import { corsHeaders } from '../_shared/cors.ts';
import { supabaseAdmin } from '../_shared/supabase.ts';
import {
  type ApiEventRow,
  type DbEventRow,
  diffEvents,
} from '../_shared/event_diff.ts';

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

// Sync stored match_events for `matchId` against the api-sports.io
// events endpoint using a signature-based diff.
//
// Returns:
//   { ok: true,  inserted: N }  — N rows newly inserted this call.
//                                 Steady-state polls (no goals/cards/
//                                 subs since last poll) return N=0
//                                 and emit ZERO CDC writes — the
//                                 critical optimisation for staying
//                                 under the Supabase free-plan
//                                 realtime-message budget.
//   { ok: false, inserted: 0 }  — API fetch or DB write failed; caller
//                                 MUST treat this as transient and
//                                 retry on the next cron tick.
//
// `ok` exists specifically so finalisation can refuse to flip a match
// to `final` when the events fetch failed. Setting `status='final'`
// fires `trigger_compute_scoring()`, which uses match_events to award
// the goalscorer and first-team bonuses. Finalising blindly would
// lock in 0 bonuses with no self-healing path (the match is no longer
// in this function's `activeMatches` filter).
//
// VAR semantics are preserved: a row that vanishes from the API
// response is DELETEd here; the migration-037 trigger fires per row
// and re-runs compute_match_scoring with the new event set.
async function upsertEvents(
  matchId: number,
  key: string,
): Promise<{ ok: boolean; inserted: number }> {
  const res = await fetch(`${BASE}/fixtures/events?fixture=${matchId}`, {
    headers: { 'x-apisports-key': key },
  });
  if (!res.ok) return { ok: false, inserted: 0 };
  const json = await res.json();
  const apiEvents = (json.response ?? []) as any[];

  const incoming: ApiEventRow[] = apiEvents
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
      type: mapEventType(e.type, e.comments ?? null)!,
      team_id: e.team?.id ?? null,
      player_id: e.player?.id ?? null,
      player_name: e.player?.name ?? null,
      detail: mapEventDetail(e.type, e.detail ?? ''),
    }));

  // Load existing rows for this match so we can diff. Excluding `id`
  // would force two round-trips; PostgREST select is cheap.
  const { data: existingRaw, error: selErr } = await supabaseAdmin
    .from('match_events')
    .select('id, match_id, minute, minute_extra, type, team_id, player_id, player_name, detail')
    .eq('match_id', matchId);
  if (selErr) return { ok: false, inserted: 0 };
  const existing = (existingRaw ?? []) as DbEventRow[];

  const { toInsert, toDelete } = diffEvents(existing, incoming);

  // Steady-state short-circuit: nothing changed since last poll. NO
  // writes → no CDC fan-out to realtime subscribers.
  if (toInsert.length === 0 && toDelete.length === 0) {
    return { ok: true, inserted: 0 };
  }

  // VAR-style removal first. The migration-037 trigger short-circuits
  // unless status='final', so during live play this is a pure DB op;
  // post-final it correctly re-runs scoring against the remaining set.
  if (toDelete.length > 0) {
    const { error: delErr } = await supabaseAdmin
      .from('match_events')
      .delete()
      .in('id', toDelete);
    if (delErr) return { ok: false, inserted: 0 };
  }

  if (toInsert.length > 0) {
    const { error: insErr } = await supabaseAdmin
      .from('match_events')
      .insert(toInsert);
    if (insErr) return { ok: false, inserted: 0 };
  }

  return { ok: true, inserted: toInsert.length };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const now = new Date();

    // ── Find all matches that have kicked off but are not yet final/cancelled.
    const { data: activeMatches } = await supabaseAdmin
      .from('matches')
      .select('id, kickoff_time, status, score_ft_team1, score_ft_team2, current_minute, current_minute_extra, current_period')
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

        // Build the incoming row from api-sports.io (Pro plan provides
        // status.elapsed / extra / short on every live fixture). Lets
        // the Flutter client render "67'" / "HT" / "ET" / "PEN" from
        // source instead of guessing via the kickoff-time heuristic.
        //
        //   status.elapsed → current_minute
        //   status.extra   → current_minute_extra (stoppage)
        //   status.short   → current_period (1H / HT / 2H / ET / BT / P)
        const next = {
          status: 'live' as const,
          score_ft_team1: f.goals.home ?? null,
          score_ft_team2: f.goals.away ?? null,
          current_minute:       f.fixture.status?.elapsed ?? null,
          current_minute_extra: f.fixture.status?.extra   ?? null,
          current_period:       f.fixture.status?.short   ?? null,
        };

        // Skip the UPDATE entirely when nothing user-visible changed.
        // Postgres CDC would otherwise fan an unchanged row out to
        // every Realtime subscriber — pure noise that eats the free
        // plan's 2M-msg/mo budget. Steady-state HT polls (15+ minutes
        // of pinned `elapsed`/`extra`/`period`), suspended matches,
        // and any sub-minute re-poll all become true no-ops.
        const unchanged =
          match.status === next.status &&
          match.score_ft_team1 === next.score_ft_team1 &&
          match.score_ft_team2 === next.score_ft_team2 &&
          match.current_minute === next.current_minute &&
          match.current_minute_extra === next.current_minute_extra &&
          match.current_period === next.current_period;

        if (!unchanged) {
          const { error } = await supabaseAdmin
            .from('matches')
            .update({ ...next, updated_at: now.toISOString() })
            .eq('id', match.id);
          if (error) continue;
          liveUpdated++;
        }

        // Refresh events on every cycle regardless of whether the
        // matches row moved: upsertEvents does its own signature diff
        // and short-circuits when nothing changed. Safe under the
        // migration-037 trigger because the surgical DELETE here only
        // fires for events actually removed from the API response.
        const ev = await upsertEvents(match.id, key);
        eventsInserted += ev.inserted;
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

          // ── Ordering matters ───────────────────────────────────────────────
          // We MUST refresh events BEFORE flipping `status` to 'final'.
          //
          // Setting `status='final'` fires `trigger_compute_scoring()` which
          // awards points_first_team and points_goalscorer from match_events.
          // The legacy migration-001 `match_event_deleted` trigger then fires
          // per-row on the delete-half of upsertEvents and recomputes against
          // a progressively shrinking event set. If upsertEvents ran *after*
          // the status flip, the final recompute would land at 0 events ⇒
          // every prediction permanently loses its first-team + goalscorer
          // bonuses, with no path to self-heal (status='final' excludes the
          // match from later poll cycles).
          //
          // Refreshing first keeps the destructive delete inside the
          // 'scheduled'/'live' window where the per-row trigger is a no-op,
          // and the subsequent status flip runs scoring exactly once against
          // the authoritative event list.
          const ev = await upsertEvents(match.id, key);
          if (!ev.ok) {
            // Events fetch/insert failed — leave the match in its current
            // pre-final state so the next cron tick retries the whole flip.
            continue;
          }
          eventsInserted += ev.inserted;

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
              // Match is over — clear the live ticker fields so the
              // detail screen doesn't keep showing a stale minute.
              current_minute:       null,
              current_minute_extra: null,
              current_period:       null,
              updated_at: now.toISOString(),
            })
            .eq('id', match.id);

          if (!error) finalized++;
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
