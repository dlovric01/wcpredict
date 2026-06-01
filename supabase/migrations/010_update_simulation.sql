-- ============================================================
-- WC2026 Prediction App — Updated live simulation RPC
-- Migration 010
--
-- Uses real DB team IDs: France (2) vs Brazil (6)
-- Includes lineup inserts (pitch renders with player dots)
-- Adds substitution event
-- Steps mirror exactly what poll_live_matches writes to the DB
-- so the simulation validates the full realtime pipeline.
-- ============================================================

create or replace function public.simulate_live_match(step_num int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match_id  int := 999001;
  v_fra_id    int := 2;   -- France  (real DB id from poll_fixtures)
  v_bra_id    int := 6;   -- Brazil  (real DB id from poll_fixtures)
begin
  case step_num

    -- ── Step 0: create match + insert lineup data ───────────────────────
    when 0 then
      -- Upsert the test match
      insert into public.matches
        (id, round, group_letter, team1_id, team2_id, kickoff_time, status)
      values
        (v_match_id, 'Matchday 1', 'A', v_fra_id, v_bra_id,
         now() - interval '35 minutes', 'scheduled')
      on conflict (id) do update set
        status         = 'scheduled',
        score_ft_team1 = null,
        score_ft_team2 = null,
        formation_team1 = null,
        formation_team2 = null,
        updated_at     = now();

      -- Clear leftover events
      delete from public.match_events where match_id = v_match_id;

      -- ── France 4-3-3 starting XI ─────────────────────────────────────
      insert into public.players (id, team_id, name, position, jersey_number, grid, is_starter) values
        (9001, v_fra_id, 'M. Maignan',      'GK',  16, '1:1', true),
        (9002, v_fra_id, 'B. Pavard',        'DEF',  2, '2:1', true),
        (9003, v_fra_id, 'D. Upamecano',     'DEF',  4, '2:2', true),
        (9004, v_fra_id, 'I. Konaté',        'DEF',  5, '2:3', true),
        (9005, v_fra_id, 'T. Hernandez',     'DEF', 22, '2:4', true),
        (9006, v_fra_id, 'A. Tchouaméni',    'MID',  8, '3:1', true),
        (9007, v_fra_id, 'E. Camavinga',     'MID', 10, '3:2', true),
        (9008, v_fra_id, 'A. Griezmann',     'MID',  7, '3:3', true),
        (9009, v_fra_id, 'O. Dembélé',       'FWD', 11, '4:1', true),
        (9010, v_fra_id, 'K. Mbappé',        'FWD',  9, '4:2', true),
        (9011, v_fra_id, 'M. Thuram',        'FWD', 15, '4:3', true),
        -- Substitutes
        (9012, v_fra_id, 'O. Giroud',        'FWD', 18, null,  false),
        (9013, v_fra_id, 'Y. Fofana',        'MID', 14, null,  false),
        (9014, v_fra_id, 'S. Theo',          'DEF',  3, null,  false)
      on conflict (id) do update set
        team_id      = excluded.team_id,
        name         = excluded.name,
        position     = excluded.position,
        jersey_number = excluded.jersey_number,
        grid         = excluded.grid,
        is_starter   = excluded.is_starter;

      -- ── Brazil 4-3-3 starting XI ─────────────────────────────────────
      insert into public.players (id, team_id, name, position, jersey_number, grid, is_starter) values
        (9021, v_bra_id, 'Ederson',           'GK',   1, '1:1', true),
        (9022, v_bra_id, 'Danilo',            'DEF',  2, '2:1', true),
        (9023, v_bra_id, 'Marquinhos',        'DEF',  4, '2:2', true),
        (9024, v_bra_id, 'G. Magalhães',      'DEF', 24, '2:3', true),
        (9025, v_bra_id, 'Guilherme Arana',   'DEF', 22, '2:4', true),
        (9026, v_bra_id, 'Gerson',            'MID',  8, '3:1', true),
        (9027, v_bra_id, 'B. Guimarães',      'MID', 16, '3:2', true),
        (9028, v_bra_id, 'L. Paquetá',        'MID', 10, '3:3', true),
        (9029, v_bra_id, 'Rodrygo',           'FWD', 11, '4:1', true),
        (9030, v_bra_id, 'Vinícius Jr.',      'FWD',  7, '4:2', true),
        (9031, v_bra_id, 'Raphinha',          'FWD', 21, '4:3', true),
        -- Substitutes
        (9032, v_bra_id, 'Weverton',          'GK',  23, null,  false),
        (9033, v_bra_id, 'Endrick',           'FWD', 19, null,  false),
        (9034, v_bra_id, 'Andreas Pereira',   'MID', 18, null,  false)
      on conflict (id) do update set
        team_id      = excluded.team_id,
        name         = excluded.name,
        position     = excluded.position,
        jersey_number = excluded.jersey_number,
        grid         = excluded.grid,
        is_starter   = excluded.is_starter;

      -- Write formations onto the match row
      update public.matches set
        formation_team1 = '4-3-3',
        formation_team2 = '4-3-3'
      where id = v_match_id;

      return jsonb_build_object('ok', true, 'step', 0,
        'desc', 'FRA vs BRA created — lineups inserted, pitch ready');

    -- ── Step 1: kick off ────────────────────────────────────────────────
    when 1 then
      update public.matches set
        status         = 'live',
        score_ft_team1 = 0,
        score_ft_team2 = 0,
        updated_at     = now()
      where id = v_match_id;
      return jsonb_build_object('ok', true, 'step', 1, 'desc', 'kicked off 0-0');

    -- ── Step 2: Brazil goal — Vinícius Jr. 23' ──────────────────────────
    when 2 then
      update public.matches set score_ft_team2 = 1, updated_at = now()
      where id = v_match_id;
      insert into public.match_events (match_id, minute, type, team_id, player_id, player_name)
      values (v_match_id, 23, 'goal', v_bra_id, 9030, 'Vinícius Jr.');
      return jsonb_build_object('ok', true, 'step', 2, 'desc', 'FRA 0-1 BRA  Vinícius Jr. 23''');

    -- ── Step 3: yellow card — Tchouaméni 31' ────────────────────────────
    when 3 then
      insert into public.match_events (match_id, minute, type, team_id, player_id, player_name, detail)
      values (v_match_id, 31, 'card', v_fra_id, 9006, 'A. Tchouaméni', 'yellow');
      return jsonb_build_object('ok', true, 'step', 3, 'desc', 'yellow card Tchouaméni 31''');

    -- ── Step 4: substitution — Dembélé off / Giroud on (HT, 46') ────────
    when 4 then
      insert into public.match_events (match_id, minute, type, team_id, player_id, player_name, detail)
      values (v_match_id, 46, 'subst', v_fra_id, 9009, 'O. Dembélé', 'O. Giroud');
      return jsonb_build_object('ok', true, 'step', 4, 'desc', 'sub: Dembélé → Giroud 46''');

    -- ── Step 5: France equalise — Mbappé 67' ────────────────────────────
    when 5 then
      update public.matches set score_ft_team1 = 1, updated_at = now()
      where id = v_match_id;
      insert into public.match_events (match_id, minute, type, team_id, player_id, player_name)
      values (v_match_id, 67, 'goal', v_fra_id, 9010, 'K. Mbappé');
      return jsonb_build_object('ok', true, 'step', 5, 'desc', 'FRA 1-1 BRA  Mbappé 67''');

    -- ── Step 6: France winner — Mbappé pen 88' ──────────────────────────
    when 6 then
      update public.matches set score_ft_team1 = 2, updated_at = now()
      where id = v_match_id;
      insert into public.match_events (match_id, minute, type, team_id, player_id, player_name, detail)
      values (v_match_id, 88, 'goal', v_fra_id, 9010, 'K. Mbappé', 'penalty');
      return jsonb_build_object('ok', true, 'step', 6, 'desc', 'FRA 2-1 BRA  Mbappé pen 88''');

    -- ── Step 7: full time ────────────────────────────────────────────────
    -- Mirrors exactly what poll_live_matches writes on finalization.
    -- status='final' fires compute_match_scoring() DB trigger.
    -- score_ft uses fulltime (90-min) score — validated against real API response.
    when 7 then
      update public.matches set
        status         = 'final',
        score_ft_team1 = 2,   -- 90-min FT (same as goals for non-ET game)
        score_ft_team2 = 1,
        score_ht_team1 = 0,
        score_ht_team2 = 1,
        updated_at     = now()
      where id = v_match_id;
      return jsonb_build_object('ok', true, 'step', 7,
        'desc', 'FT FRA 2-1 BRA — scoring trigger fired');

    -- ── Step 99: cleanup ────────────────────────────────────────────────
    when 99 then
      delete from public.match_events where match_id = v_match_id;
      delete from public.matches       where id      = v_match_id;
      delete from public.players       where id between 9001 and 9034;
      return jsonb_build_object('ok', true, 'step', 99, 'desc', 'cleaned up');

    else
      return jsonb_build_object('ok', false, 'error', 'unknown step ' || step_num);
  end case;
end;
$$;

grant execute on function public.simulate_live_match(int) to authenticated;
