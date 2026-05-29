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

const ROUND_MAP: Record<string, string> = {
  'Group Stage - 1': 'Matchday 1',
  'Group Stage - 2': 'Matchday 2',
  'Group Stage - 3': 'Matchday 3',
  'Round of 32': 'R32',
  'Round of 16': 'R16',
  'Quarter-finals': 'QF',
  'Semi-finals': 'SF',
  '3rd Place Final': '3rd',
  'Final': 'Final',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const key = apiKey();

    // Fetch all WC2026 fixtures
    const res = await fetch(`${BASE}/fixtures?league=${LEAGUE}&season=${SEASON}`, {
      headers: { 'x-apisports-key': key },
    });
    if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`);
    const json = await res.json();
    if (json.errors && Object.keys(json.errors).length > 0) throw new Error(JSON.stringify(json.errors));

    const fixtures = json.response as any[];

    // Collect unique teams
    const teamsMap = new Map<number, object>();
    const matchRows: object[] = [];

    for (const f of fixtures) {
      const home = f.teams.home;
      const away = f.teams.away;

      teamsMap.set(home.id, {
        id: home.id,
        name: home.name,
        code: home.code ?? home.name.substring(0, 3).toUpperCase(),
        flag_url: home.logo,
      });
      teamsMap.set(away.id, {
        id: away.id,
        name: away.name,
        code: away.code ?? away.name.substring(0, 3).toUpperCase(),
        flag_url: away.logo,
      });

      const round = ROUND_MAP[f.league.round] ?? f.league.round;

      matchRows.push({
        id: f.fixture.id,
        round,
        group_letter: null, // populated separately via standings if needed
        team1_id: home.id,
        team2_id: away.id,
        kickoff_time: f.fixture.date,
        status: mapStatus(f.fixture.status.short),
        score_ht_team1: f.score.halftime.home,
        score_ht_team2: f.score.halftime.away,
        score_ft_team1: f.goals.home,
        score_ft_team2: f.goals.away,
        score_et_team1: f.score.extratime.home,
        score_et_team2: f.score.extratime.away,
        score_pen_team1: f.score.penalty.home,
        score_pen_team2: f.score.penalty.away,
        updated_at: new Date().toISOString(),
      });
    }

    // Upsert teams
    const teamRows = Array.from(teamsMap.values());
    if (teamRows.length > 0) {
      const { error: teamErr } = await supabaseAdmin
        .from('teams')
        .upsert(teamRows, { onConflict: 'id', ignoreDuplicates: false });
      if (teamErr) throw new Error(`teams upsert: ${teamErr.message}`);
    }

    // Upsert matches in batches of 50
    let matchesUpserted = 0;
    for (let i = 0; i < matchRows.length; i += 50) {
      const batch = matchRows.slice(i, i + 50);
      const { error: matchErr } = await supabaseAdmin
        .from('matches')
        .upsert(batch, { onConflict: 'id', ignoreDuplicates: false });
      if (matchErr) throw new Error(`matches upsert batch ${i}: ${matchErr.message}`);
      matchesUpserted += batch.length;
    }

    return new Response(
      JSON.stringify({ ok: true, teams: teamRows.length, matches: matchesUpserted }),
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
