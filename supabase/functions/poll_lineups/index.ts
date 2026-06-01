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

    // Window: matches kicking off between now+5 min and now+55 min.
    // Wide enough to retry every minute for ~50 minutes; lineups are typically
    // confirmed by T-60 so T-55 is the earliest useful attempt.
    const windowStart = new Date(now.getTime() +  5 * 60 * 1000).toISOString();
    const windowEnd   = new Date(now.getTime() + 55 * 60 * 1000).toISOString();

    const { data: upcoming } = await supabaseAdmin
      .from('matches')
      .select('id, team1_id, team2_id')
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
      // Guard: if both teams already have starting-XI players with grid positions,
      // the lineup for this match is already populated — skip to save API quota.
      const { count } = await supabaseAdmin
        .from('players')
        .select('id', { count: 'exact', head: true })
        .in('team_id', [match.team1_id, match.team2_id].filter(Boolean))
        .eq('is_starter', true)
        .not('grid', 'is', null);

      if ((count ?? 0) >= 18) {
        // Both XIs already stored (11 × 2 = 22 minimum, 18 is a safe threshold)
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
        }
      }

      if (playerRows.length > 0) {
        const { error } = await supabaseAdmin
          .from('players')
          .upsert(playerRows, { onConflict: 'id', ignoreDuplicates: false });
        if (!error) playersUpserted += playerRows.length;
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
