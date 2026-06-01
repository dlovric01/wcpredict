-- ============================================================
-- Migration 014: Fix goalscorer minute check in compute_match_scoring
-- ============================================================
-- The API stores goals as:
--   Regular time + stoppage: elapsed = 1-90, extra = null or N
--   Extra time:              elapsed = 91-120, extra = null or N
--   Penalty shootout:        elapsed = 120, extra = 1-N
--
-- Since the DB stores only `elapsed` (as `minute`), and the rules say
-- "regular time only (90 minutes + stoppage)", the correct check is
-- unconditionally `minute <= 90`.
--
-- Stoppage time goals are always stored at minute=90, so they are included.
-- ET goals are always at minute >= 91, so they are excluded.
-- No v_has_et conditional is needed — the minute value alone is sufficient.
-- ============================================================

create or replace function public.compute_match_scoring(p_match_id int)
returns void language plpgsql security definer as $$
declare
  v_match   public.matches;
  v_ft1     int;
  v_ft2     int;
begin
  select * into v_match from public.matches where id = p_match_id;
  if not found or v_match.status != 'final' then return; end if;

  v_ft1 := v_match.score_ft_team1;
  v_ft2 := v_match.score_ft_team2;

  update public.predictions pr set
    -- Outcome: correct W/D/L direction
    points_outcome = case
      when (pr.predicted_team1 > pr.predicted_team2 and v_ft1 > v_ft2) or
           (pr.predicted_team1 < pr.predicted_team2 and v_ft1 < v_ft2) or
           (pr.predicted_team1 = pr.predicted_team2 and v_ft1 = v_ft2) then 2
      else 0
    end,
    -- Goal difference: same margin
    points_goal_diff = case
      when (pr.predicted_team1 - pr.predicted_team2) = (v_ft1 - v_ft2) then 3
      else 0
    end,
    -- Exact: both goals correct
    points_exact = case
      when pr.predicted_team1 = v_ft1 and pr.predicted_team2 = v_ft2 then 3
      else 0
    end,
    -- Goalscorer: predicted player scored ≥1 non-own-goal in regular time.
    -- API stores elapsed minute directly; stoppage time goals are at minute=90.
    -- ET goals are at minute >= 91 and are never credited.
    points_scorer = case
      when pr.predicted_scorer_id is null then 0
      when exists (
        select 1 from public.match_events me
        where me.match_id = p_match_id
          and me.type = 'goal'
          and me.player_id = pr.predicted_scorer_id
          and (me.detail is null or me.detail not in ('own_goal'))
          and me.minute <= 90
      ) then 5
      else 0
    end,
    -- Multiplier: auto for 3rd/Final, user booster for R32-SF, else 1
    multiplier = case v_match.round
      when '3rd'   then 5
      when 'Final' then 6
      else coalesce(
        (select rb.multiplier
           from public.round_boosters rb
          where rb.user_id  = pr.user_id
            and rb.match_id = p_match_id),
        1
      )
    end
  where pr.match_id = p_match_id;

  -- Compute total: base × multiplier
  update public.predictions set
    points_earned = (
      coalesce(points_outcome,   0) +
      coalesce(points_goal_diff, 0) +
      coalesce(points_exact,     0) +
      coalesce(points_scorer,    0)
    ) * multiplier
  where match_id = p_match_id;

  refresh materialized view concurrently public.group_standings;
end;
$$;
