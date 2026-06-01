import { corsHeaders } from '../_shared/cors.ts';
import { supabaseAdmin } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const url = new URL(req.url);
    const table = url.searchParams.get('table');

    // ── Single table dump ──────────────────────────────────────────────────────
    if (table) {
      const { data, error } = await supabaseAdmin.from(table).select('*').limit(200);
      return new Response(JSON.stringify({ table, count: data?.length ?? 0, error, rows: data }, null, 2), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Full DB audit ──────────────────────────────────────────────────────────
    const [
      teams,
      players,
      matches,
      predictions,
      matchEvents,
      groups,
      groupMembers,
      profiles,
      roundBoosters,
    ] = await Promise.all([
      supabaseAdmin.from('teams').select('id, name, code', { count: 'exact' }),
      supabaseAdmin.from('players').select('id, name, team_id', { count: 'exact' }),
      supabaseAdmin.from('matches').select('id, round, status, kickoff_time, team1_id, team2_id', { count: 'exact' }),
      supabaseAdmin.from('predictions').select('id, user_id, match_id, predicted_team1, predicted_team2, points_earned, locked_at', { count: 'exact' }),
      supabaseAdmin.from('match_events').select('id, match_id, minute, minute_extra, type, player_name', { count: 'exact' }),
      supabaseAdmin.from('groups').select('id, name, owner_id', { count: 'exact' }),
      supabaseAdmin.from('group_members').select('group_id, user_id', { count: 'exact' }),
      supabaseAdmin.from('profiles').select('user_id, display_name', { count: 'exact' }),
      supabaseAdmin.from('round_boosters').select('*', { count: 'exact' }),
    ]);

    return new Response(JSON.stringify({
      summary: {
        teams:         teams.count,
        players:       players.count,
        matches:       matches.count,
        predictions:   predictions.count,
        match_events:  matchEvents.count,
        groups:        groups.count,
        group_members: groupMembers.count,
        profiles:      profiles.count,
        round_boosters: roundBoosters.count,
      },
      // Show ALL rows for small tables, samples for large
      teams:         teams.data,
      players:       players.data?.slice(0, 20),
      matches:       matches.data,
      predictions:   predictions.data,
      match_events:  matchEvents.data?.slice(0, 30),
      groups:        groups.data,
      group_members: groupMembers.data,
      profiles:      profiles.data,
      round_boosters: roundBoosters.data,
    }, null, 2), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
