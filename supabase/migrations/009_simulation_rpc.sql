-- ============================================================
-- WC2026 Prediction App — Live simulation RPC
-- Migration 007
--
-- A SECURITY DEFINER function lets the Flutter app drive the
-- simulation without needing write access to matches/match_events.
-- All logic runs as the DB owner, bypassing RLS.
-- ============================================================

create or replace function public.simulate_live_match(step_num int)
returns jsonb
language plpgsql
security definer          -- bypasses RLS; runs as DB owner
set search_path = public
as $$
declare
  v_match_id  int  := 999001;
  v_team1_id  int  := 13;   -- Argentina
  v_team2_id  int  := 17;   -- Brazil
begin
  case step_num

    -- ── Step 0: create match as scheduled ──────────────────────────────
    when 0 then
      insert into public.matches
        (id, round, group_letter, team1_id, team2_id, kickoff_time, status)
      values
        (v_match_id, 'Matchday 1', 'D', v_team1_id, v_team2_id,
         now() - interval '35 minutes', 'scheduled')
      on conflict (id) do update set
        status       = 'scheduled',
        score_ft_team1 = null,
        score_ft_team2 = null,
        updated_at   = now();

      -- clear any leftover events from a previous simulation run
      delete from public.match_events where match_id = v_match_id;

      return jsonb_build_object('ok', true, 'step', 0, 'desc', 'match created');

    -- ── Step 1: kick off ────────────────────────────────────────────────
    when 1 then
      update public.matches set
        status         = 'live',
        score_ft_team1 = 0,
        score_ft_team2 = 0,
        updated_at     = now()
      where id = v_match_id;

      return jsonb_build_object('ok', true, 'step', 1, 'desc', 'kicked off 0-0');

    -- ── Step 2: Argentina goal — Messi 23' ──────────────────────────────
    when 2 then
      update public.matches set
        score_ft_team1 = 1,
        updated_at     = now()
      where id = v_match_id;

      insert into public.match_events (match_id, minute, type, team_id, player_name)
      values (v_match_id, 23, 'goal', v_team1_id, 'L. Messi');

      return jsonb_build_object('ok', true, 'step', 2, 'desc', 'ARG 1-0 Messi 23''');

    -- ── Step 3: yellow card — V. Jr. 31' ────────────────────────────────
    when 3 then
      insert into public.match_events (match_id, minute, type, team_id, player_name, detail)
      values (v_match_id, 31, 'card', v_team2_id, 'V. Jr.', 'yellow');

      return jsonb_build_object('ok', true, 'step', 3, 'desc', 'yellow card V. Jr. 31''');

    -- ── Step 4: Brazil equalise — Rodrygo 55' ───────────────────────────
    when 4 then
      update public.matches set
        score_ft_team2 = 1,
        updated_at     = now()
      where id = v_match_id;

      insert into public.match_events (match_id, minute, type, team_id, player_name)
      values (v_match_id, 55, 'goal', v_team2_id, 'Rodrygo');

      return jsonb_build_object('ok', true, 'step', 4, 'desc', 'ARG 1-1 Rodrygo 55''');

    -- ── Step 5: Argentina winner — Álvarez 88' ──────────────────────────
    when 5 then
      update public.matches set
        score_ft_team1 = 2,
        updated_at     = now()
      where id = v_match_id;

      insert into public.match_events (match_id, minute, type, team_id, player_name)
      values (v_match_id, 88, 'goal', v_team1_id, 'J. Álvarez');

      return jsonb_build_object('ok', true, 'step', 5, 'desc', 'ARG 2-1 Álvarez 88''');

    -- ── Step 6: full time — DB trigger fires compute_match_scoring() ────
    when 6 then
      update public.matches set
        status         = 'final',
        score_ft_team1 = 2,
        score_ft_team2 = 1,
        score_ht_team1 = 1,
        score_ht_team2 = 0,
        updated_at     = now()
      where id = v_match_id;

      return jsonb_build_object('ok', true, 'step', 6, 'desc', 'full time ARG 2-1 BRA');

    -- ── Step 99: cleanup ────────────────────────────────────────────────
    when 99 then
      delete from public.match_events where match_id = v_match_id;
      delete from public.matches       where id      = v_match_id;

      return jsonb_build_object('ok', true, 'step', 99, 'desc', 'cleaned up');

    else
      return jsonb_build_object('ok', false, 'error', 'unknown step ' || step_num);
  end case;
end;
$$;

-- Any authenticated user can call this function (RLS is bypassed inside it).
grant execute on function public.simulate_live_match(int) to authenticated;
