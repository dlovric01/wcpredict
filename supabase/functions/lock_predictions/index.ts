import { corsHeaders } from '../_shared/cors.ts';
import { supabaseAdmin } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const now = new Date().toISOString();

    // Get match IDs that have kicked off
    const { data: kickedOff, error: matchErr } = await supabaseAdmin
      .from('matches')
      .select('id')
      .lte('kickoff_time', now)
      .in('status', ['scheduled', 'live', 'final']);

    if (matchErr) throw new Error(matchErr.message);
    if (!kickedOff || kickedOff.length === 0) {
      return new Response(JSON.stringify({ ok: true, locked: 0 }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const ids = kickedOff.map((m: any) => m.id);

    const { data: lockedRows, error: lockErr } = await supabaseAdmin
      .from('predictions')
      .update({ locked_at: now })
      .in('match_id', ids)
      .is('locked_at', null)
      .select('id');

    if (lockErr) throw new Error(lockErr.message);

    return new Response(
      JSON.stringify({ ok: true, locked: lockedRows?.length ?? 0 }),
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
