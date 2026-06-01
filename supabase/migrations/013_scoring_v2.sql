-- ============================================================
-- Migration 013: Scoring v2
-- ============================================================
-- Replaces the old 3-category scoring (score/first_team/scorer)
-- with a new cumulative 4-category model:
--   outcome(2) + goal_diff(3) + exact(3) + scorer(5) = 13 base max
--   multiplied by a per-prediction multiplier.
-- Removes predicted_first_team_id and related columns/logic.
-- ============================================================

-- ============================================================
-- Step 1: Recreate predictions_lock_check trigger
-- Drop old trigger (watched predicted_first_team_id which we're removing)
-- and recreate it without that column.
-- ============================================================
drop trigger if exists predictions_lock_check on public.predictions;

create trigger predictions_lock_check
  before insert
     or update of predicted_team1,
                  predicted_team2,
                  predicted_scorer_id
  on public.predictions
  for each row
  execute function public.check_prediction_lock();

-- ============================================================
-- Step 2: Alter predictions table
-- ============================================================
-- Remove old scoring constraint (references columns being dropped)
alter table public.predictions
  drop constraint if exists no_scorer_on_scoreless;

-- Drop old columns
alter table public.predictions
  drop column if exists predicted_first_team_id,
  drop column if exists points_first_team,
  drop column if exists points_score;

-- Add new scoring columns
alter table public.predictions
  add column if not exists points_outcome   int,
  add column if not exists points_goal_diff int,
  add column if not exists points_exact     int,
  add column if not exists multiplier       int not null default 1;

-- Restore the 0-0 constraint (now scorer-only, first_team removed)
alter table public.predictions
  add constraint no_scorer_on_scoreless check (
    not (predicted_team1 = 0 and predicted_team2 = 0
         and predicted_scorer_id is not null)
  );

-- ============================================================
-- Step 3: Rewrite compute_match_scoring
-- ============================================================
create or replace function public.compute_match_scoring(p_match_id int)
returns void language plpgsql security definer as $$
declare
  v_match   public.matches;
  v_ft1     int;
  v_ft2     int;
  v_has_et  bool;
begin
  select * into v_match from public.matches where id = p_match_id;
  if not found or v_match.status != 'final' then return; end if;

  v_ft1    := v_match.score_ft_team1;
  v_ft2    := v_match.score_ft_team2;
  -- ET flag: if score_et_team1 is set, this match went to extra time
  v_has_et := v_match.score_et_team1 is not null;

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
    -- Goalscorer: predicted player scored ≥1 non-own-goal
    -- If match had ET, only count goals at minute <= 90
    points_scorer = case
      when pr.predicted_scorer_id is null then 0
      when exists (
        select 1 from public.match_events me
        where me.match_id = p_match_id
          and me.type = 'goal'
          and me.player_id = pr.predicted_scorer_id
          and (me.detail is null or me.detail not in ('own_goal'))
          and (not v_has_et or me.minute <= 90)
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

-- ============================================================
-- Step 4: Recreate group_standings materialized view
-- New columns: outcome_count, goal_diff_count, scorer_count,
-- earliest_submission. Removed: correct_result_count.
-- Cancelled matches excluded via status = 'final' filter.
-- ============================================================
drop materialized view if exists public.group_standings;

create materialized view public.group_standings as
select
  gm.group_id,
  p.user_id,
  p.display_name,
  coalesce(sum(pr.points_earned), 0)           as total_points,
  count(*) filter (
    where m.status = 'final' and pr.points_exact    = 3
  )                                             as exact_count,
  count(*) filter (
    where m.status = 'final' and pr.points_outcome  = 2
  )                                             as outcome_count,
  count(*) filter (
    where m.status = 'final' and pr.points_goal_diff = 3
  )                                             as goal_diff_count,
  count(*) filter (
    where m.status = 'final' and pr.points_scorer   = 5
  )                                             as scorer_count,
  min(pr.created_at)                            as earliest_submission
from public.group_members gm
join public.profiles p on p.user_id = gm.user_id
left join public.predictions pr on pr.user_id = gm.user_id
left join public.matches m
  on m.id = pr.match_id
group by gm.group_id, p.user_id, p.display_name;

create unique index group_standings_pk
  on public.group_standings (group_id, user_id);

-- Initial population (non-concurrent since view was just created)
refresh materialized view public.group_standings;
