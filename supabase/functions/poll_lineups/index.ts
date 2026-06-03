import { corsHeaders } from '../_shared/cors.ts';
import { supabaseAdmin } from '../_shared/supabase.ts';

const BASE = 'https://v3.football.api-sports.io';

function apiKey(): string {
  const k = Deno.env.get('APISPORTS_KEY');
  if (!k) throw new Error('APISPORTS_KEY not set');
  return k;
}

function mapPos(pos: string | null): string | null {
  if (!pos) return null;
  const m: Record<string, string> = { G: 'GK', D: 'DEF', M: 'MID', F: 'FWD' };
  return m[pos] ?? pos;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const now = new Date();

    // Window: matches kicking off between now+5 min and now+45 min.
    // Lineups are typically confirmed by T-60 so T-45 is the earliest reliably
    // useful attempt; the lower bound covers cron drift after kickoff has
    // passed but before the live-events poller starts.
    const windowStart = new Date(now.getTime() +  5 * 60 * 1000).toISOString();
    const windowEnd   = new Date(now.getTime() + 45 * 60 * 1000).toISOString();

    const { data: upcoming } = await supabaseAdmin
      .from('matches')
      .select('id, team1_id, team2_id, formation_team1, formation_team2')
      .eq('status', 'scheduled')
      .gte('kickoff_time', windowStart)
      .lte('kickoff_time', windowEnd);

    if (!upcoming || upcoming.length === 0) {
      return new Response(JSON.stringify({ ok: true, skipped: true }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const key = apiKey();
    let playersUpserted = 0;
    let matchesPopulated = 0;

    for (const match of upcoming) {
      // Guard: skip when both formations are already stored. More reliable than
      // counting players (which are upserted by `id`, so a previous match's
      // lineup can leave stale rows that satisfy a count check for the wrong
      // fixture). The match row's formation columns only flip non-null once
      // this function has successfully ingested a lineup payload for *this*
      // fixture, making it a per-match idempotency marker.
      if (match.formation_team1 && match.formation_team2) {
        continue;
      }

      const res = await fetch(`${BASE}/fixtures/lineups?fixture=${match.id}`, {
        headers: { 'x-apisports-key': key },
      });
      if (!res.ok) continue;
      const json = await res.json();
      const lineups = (json.response ?? []) as any[];
      if (lineups.length === 0) continue; // not confirmed yet — retry next minute

      const playerRows: object[] = [];
      const lineupRows: object[] = [];
      const formations: Record<number, string> = {};

      for (const lineup of lineups) {
        const teamId = lineup.team.id;
        if (lineup.formation) formations[teamId] = lineup.formation;

        for (const entry of lineup.startXI ?? []) {
          const p = entry.player;
          if (!p?.id) continue;
          playerRows.push({
            id: p.id,
            team_id: teamId,
            name: p.name,
            position: mapPos(p.pos),
            jersey_number: p.number ?? null,
            grid: p.grid ?? null,
            is_starter: true,
          });
          lineupRows.push({
            match_id: match.id,
            team_id: teamId,
            player_id: p.id,
            is_starter: true,
            grid: p.grid ?? null,
          });
        }

        for (const entry of lineup.substitutes ?? []) {
          const p = entry.player;
          if (!p?.id) continue;
          playerRows.push({
            id: p.id,
            team_id: teamId,
            name: p.name,
            position: mapPos(p.pos),
            jersey_number: p.number ?? null,
            grid: null,
            is_starter: false,
          });
          lineupRows.push({
            match_id: match.id,
            team_id: teamId,
            player_id: p.id,
            is_starter: false,
            grid: null,
          });
        }
      }

      if (playerRows.length > 0) {
        const { error } = await supabaseAdmin
          .from('players')
          .upsert(playerRows, { onConflict: 'id', ignoreDuplicates: false });
        if (!error) playersUpserted += playerRows.length;
      }

      // Replace the per-match lineup atomically: delete-then-insert. The
      // matchday squad shape (11 starters + N subs) is owned by THIS
      // fixture and must not bleed across re-runs (e.g. an in-window
      // re-poll after a last-minute starter change).
      if (lineupRows.length > 0) {
        await supabaseAdmin
          .from('match_lineups')
          .delete()
          .eq('match_id', match.id);
        await supabaseAdmin
          .from('match_lineups')
          .insert(lineupRows);
      }

      // Store formations on the match row so the pitch UI can display them.
      if (Object.keys(formations).length > 0) {
        const formationUpdate: Record<string, string> = {};
        if (match.team1_id && formations[match.team1_id]) {
          formationUpdate['formation_team1'] = formations[match.team1_id];
        }
        if (match.team2_id && formations[match.team2_id]) {
          formationUpdate['formation_team2'] = formations[match.team2_id];
        }
        if (Object.keys(formationUpdate).length > 0) {
          await supabaseAdmin.from('matches').update(formationUpdate).eq('id', match.id);
        }
      }

      matchesPopulated++;
    }

    return new Response(
      JSON.stringify({ ok: true, matches: upcoming.length, matches_populated: matchesPopulated, players_upserted: playersUpserted }),
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
