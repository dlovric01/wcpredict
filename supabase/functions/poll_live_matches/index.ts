import { corsHeaders } from '../_shared/cors.ts';
import { supabaseAdmin } from '../_shared/supabase.ts';

const BASE = 'https://v3.football.api-sports.io';
const LEAGUE = 1;
const SEASON = 2026;

function apiKey(): string {
  const k = Deno.env.get('APISPORTS_KEY');
  if (!k) throw new Error('APISPORTS_KEY not set');
  return k;
}

function mapStatus(short: string): string {
  if (['FT', 'AET', 'PEN'].includes(short)) return 'final';
  if (['PST', 'CANC', 'ABD', 'WO', 'AWD'].includes(short)) return 'cancelled';
  if (['NS', 'TBD'].includes(short)) return 'scheduled';
  return 'live';
}

function mapEventType(type: string): string | null {
  if (type === 'Goal') return 'goal';
  if (type === 'Card') return 'card';
  if (type === 'subst') return 'subst';
  return null; // skip Var and other types
}

function mapEventDetail(type: string, detail: string): string | null {
  if (type === 'Goal') {
    if (detail === 'Own Goal') return 'own_goal';
    if (detail === 'Penalty') return 'penalty';
    return null; // Normal Goal — no detail needed
  }
  if (type === 'Card') {
    if (detail === 'Red Card' || detail === 'Yellow Card (2nd)') return 'red';
    return 'yellow';
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    // Gate: find today's matches that are past kickoff + 105 min (earliest they can be FT)
    const now = new Date();
    const todayStart = new Date(now);
    todayStart.setUTCHours(0, 0, 0, 0);
    const todayEnd = new Date(now);
    todayEnd.setUTCHours(23, 59, 59, 999);

    const { data: todayMatches } = await supabaseAdmin
      .from('matches')
      .select('id, kickoff_time, status')
      .gte('kickoff_time', todayStart.toISOString())
      .lte('kickoff_time', todayEnd.toISOString());

    if (!todayMatches || todayMatches.length === 0) {
      return new Response(JSON.stringify({ ok: true, skipped: true, reason: 'no_matches_today' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Check if any match could possibly be finished (kickoff + 105 min <= now)
    const couldBeFinished = todayMatches.some((m: any) => {
      const kickoff = new Date(m.kickoff_time).getTime();
      return now.getTime() >= kickoff + 105 * 60 * 1000;
    });

    if (!couldBeFinished) {
      return new Response(JSON.stringify({ ok: true, skipped: true, reason: 'matches_not_finished_yet' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Fetch all WC2026 finished fixtures from API
    const key = apiKey();
    const res = await fetch(`${BASE}/fixtures?league=${LEAGUE}&season=${SEASON}&status=FT-AET-PEN`, {
      headers: { 'x-apisports-key': key },
    });
    if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`);
    const json = await res.json();
    if (json.errors && Object.keys(json.errors).length > 0) throw new Error(JSON.stringify(json.errors));

    const finishedApi = json.response as any[];
    const finishedApiIds = new Set(finishedApi.map((f: any) => f.fixture.id));

    // Find which of today's matches are now final in API but not in DB
    const needsUpdate = todayMatches.filter((m: any) =>
      m.status !== 'final' && finishedApiIds.has(m.id)
    );

    if (needsUpdate.length === 0) {
      return new Response(JSON.stringify({ ok: true, skipped: false, updated: 0, reason: 'nothing_new_final' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    let matchesFinalized = 0;
    let eventsInserted = 0;

    for (const dbMatch of needsUpdate) {
      const f = finishedApi.find((x: any) => x.fixture.id === dbMatch.id);
      if (!f) continue;

      // Update match scores and status (triggers compute_scoring via DB trigger)
      const { error: updateErr } = await supabaseAdmin
        .from('matches')
        .update({
          status: mapStatus(f.fixture.status.short),
          score_ft_team1: f.goals.home,
          score_ft_team2: f.goals.away,
          score_ht_team1: f.score.halftime.home,
          score_ht_team2: f.score.halftime.away,
          score_et_team1: f.score.extratime.home,
          score_et_team2: f.score.extratime.away,
          score_pen_team1: f.score.penalty.home,
          score_pen_team2: f.score.penalty.away,
          updated_at: new Date().toISOString(),
        })
        .eq('id', dbMatch.id);

      if (updateErr) {
        console.error(`match ${dbMatch.id} update error:`, updateErr.message);
        continue;
      }
      matchesFinalized++;

      // Fetch events for this match
      const evRes = await fetch(`${BASE}/fixtures/events?fixture=${dbMatch.id}`, {
        headers: { 'x-apisports-key': key },
      });
      if (!evRes.ok) continue;
      const evJson = await evRes.json();
      const apiEvents = evJson.response as any[];

      // Map to DB rows, skip Var and Missed Penalty
      const eventRows = apiEvents
        .filter((e: any) => {
          const t = mapEventType(e.type);
          if (!t) return false;
          if (e.type === 'Goal' && e.detail === 'Missed Penalty') return false;
          return true;
        })
        .map((e: any) => ({
          match_id: dbMatch.id,
          minute: e.time.elapsed,
          type: mapEventType(e.type),
          team_id: e.team?.id ?? null,
          player_id: e.player?.id ?? null,
          player_name: e.player?.name ?? null,
          detail: mapEventDetail(e.type, e.detail ?? ''),
        }));

      if (eventRows.length > 0) {
        // Delete existing events for this match first (idempotent)
        await supabaseAdmin.from('match_events').delete().eq('match_id', dbMatch.id);
        const { error: evErr } = await supabaseAdmin.from('match_events').insert(eventRows);
        if (!evErr) eventsInserted += eventRows.length;
      }
    }

    return new Response(
      JSON.stringify({ ok: true, matches_finalized: matchesFinalized, events_inserted: eventsInserted }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ ok: false, error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
