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

function mapEventType(type: string, comments: string | null): string | null {
  if (type === 'Goal') {
    // Penalty shootout kicks have comments="Penalty Shootout" from the API.
    // Store as 'shootout_kick' — never credited as a goalscorer prediction.
    if (comments === 'Penalty Shootout') return 'shootout_kick';
    return 'goal';
  }
  if (type === 'Card') return 'card';
  if (type === 'subst') return 'subst';
  return null;
}

function mapEventDetail(type: string, detail: string): string | null {
  if (type === 'Goal') {
    if (detail === 'Own Goal') return 'own_goal';
    if (detail === 'Penalty') return 'penalty';
    return null;
  }
  if (type === 'Card') {
    if (detail === 'Red Card' || detail === 'Yellow Card (2nd)') return 'red';
    return 'yellow';
  }
  return null;
}

async function upsertEvents(matchId: number, key: string): Promise<number> {
  const res = await fetch(`${BASE}/fixtures/events?fixture=${matchId}`, {
    headers: { 'x-apisports-key': key },
  });
  if (!res.ok) return 0;
  const json = await res.json();
  const apiEvents = (json.response ?? []) as any[];

  const rows = apiEvents
    .filter((e: any) => {
      const t = mapEventType(e.type, e.comments ?? null);
      if (!t) return false;
      // Missed penalties in shootout are already 'shootout_kick' — drop them (no points)
      if (e.type === 'Goal' && e.detail === 'Missed Penalty') return false;
      return true;
    })
    .map((e: any) => ({
      match_id: matchId,
      minute:       e.time.elapsed,
      minute_extra: e.time.extra ?? null,
      type: mapEventType(e.type, e.comments ?? null),
      team_id: e.team?.id ?? null,
      player_id: e.player?.id ?? null,
      player_name: e.player?.name ?? null,
      detail: mapEventDetail(e.type, e.detail ?? ''),
    }));

  if (rows.length === 0) return 0;

  // Delete then re-insert for idempotency — keeps event order stable.
  await supabaseAdmin.from('match_events').delete().eq('match_id', matchId);
  const { error } = await supabaseAdmin.from('match_events').insert(rows);
  return error ? 0 : rows.length;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const now = new Date();

    // ── Find all matches that have kicked off but are not yet final/cancelled.
    const { data: activeMatches } = await supabaseAdmin
      .from('matches')
      .select('id, kickoff_time, status')
      .lte('kickoff_time', now.toISOString())
      .not('status', 'in', '("final","cancelled")');

    if (!activeMatches || activeMatches.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, skipped: true, reason: 'no_active_matches' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const key = apiKey();
    let liveUpdated = 0;
    let finalized = 0;
    let eventsInserted = 0;

    // ── Phase A: poll /fixtures?live=all — updates in-progress scores + events ──
    const liveRes = await fetch(
      `${BASE}/fixtures?live=all&league=${LEAGUE}&season=${SEASON}`,
      { headers: { 'x-apisports-key': key } },
    );

    if (liveRes.ok) {
      const liveJson = await liveRes.json();
      const liveFixtures = (liveJson.response ?? []) as any[];
      const liveById = new Map<number, any>(liveFixtures.map((f: any) => [f.fixture.id, f]));

      for (const match of activeMatches) {
        const f = liveById.get(match.id);
        if (!f) continue;

        const { error } = await supabaseAdmin
          .from('matches')
          .update({
            status: 'live',
            score_ft_team1: f.goals.home,
            score_ft_team2: f.goals.away,
            updated_at: now.toISOString(),
          })
          .eq('id', match.id);

        if (!error) {
          liveUpdated++;
          // Fetch events so the timeline stays current during the match.
          eventsInserted += await upsertEvents(match.id, key);
        }
      }
    }

    // ── Phase B: finalise matches that could be done (kickoff + 105 min elapsed) ──
    const couldBeFinished = activeMatches.some(
      (m: any) => now.getTime() >= new Date(m.kickoff_time).getTime() + 105 * 60 * 1000,
    );

    if (couldBeFinished) {
      const ftRes = await fetch(
        `${BASE}/fixtures?league=${LEAGUE}&season=${SEASON}&status=FT-AET-PEN`,
        { headers: { 'x-apisports-key': key } },
      );

      if (ftRes.ok) {
        const ftJson = await ftRes.json();
        const ftFixtures = (ftJson.response ?? []) as any[];
        const ftById = new Map<number, any>(ftFixtures.map((f: any) => [f.fixture.id, f]));

        for (const match of activeMatches) {
          const f = ftById.get(match.id);
          if (!f) continue;
          if (match.status === 'final') continue; // already done

          const { error } = await supabaseAdmin
            .from('matches')
            .update({
              // Setting status='final' fires the DB trigger → compute_match_scoring()
              status: mapStatus(f.fixture.status.short),
              // score_ft = 90-min result (fulltime), NOT goals which includes ET.
              // Scoring rules are based on 90' direction; ET/pens are tracked separately.
              score_ft_team1: f.score.fulltime?.home ?? f.goals.home,
              score_ft_team2: f.score.fulltime?.away ?? f.goals.away,
              score_ht_team1: f.score.halftime?.home ?? null,
              score_ht_team2: f.score.halftime?.away ?? null,
              score_et_team1: f.score.extratime?.home ?? null,
              score_et_team2: f.score.extratime?.away ?? null,
              score_pen_team1: f.score.penalty?.home ?? null,
              score_pen_team2: f.score.penalty?.away ?? null,
              updated_at: now.toISOString(),
            })
            .eq('id', match.id);

          if (!error) {
            finalized++;
            eventsInserted += await upsertEvents(match.id, key);
          }
        }
      }
    }

    return new Response(
      JSON.stringify({ ok: true, live_updated: liveUpdated, finalized, events_inserted: eventsInserted }),
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
