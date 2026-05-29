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
    const windowStart = new Date(now.getTime() + 25 * 60 * 1000).toISOString();
    const windowEnd   = new Date(now.getTime() + 35 * 60 * 1000).toISOString();

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

    for (const match of upcoming) {
      const res = await fetch(`${BASE}/fixtures/lineups?fixture=${match.id}`, {
        headers: { 'x-apisports-key': key },
      });
      if (!res.ok) continue;
      const json = await res.json();
      const lineups = json.response as any[];

      const playerRows: object[] = [];
      for (const lineup of lineups) {
        const teamId = lineup.team.id;
        for (const entry of [...lineup.startXI, ...lineup.substitutes]) {
          const p = entry.player;
          if (!p?.id) continue;
          playerRows.push({
            id: p.id,
            team_id: teamId,
            name: p.name,
            position: mapPos(p.pos),
            jersey_number: p.number ?? null,
          });
        }
      }

      if (playerRows.length > 0) {
        const { error } = await supabaseAdmin
          .from('players')
          .upsert(playerRows, { onConflict: 'id', ignoreDuplicates: false });
        if (!error) playersUpserted += playerRows.length;
      }
    }

    return new Response(
      JSON.stringify({ ok: true, matches: upcoming.length, players_upserted: playersUpserted }),
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
