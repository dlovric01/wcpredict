-- ============================================================
-- Migration 017: Rules.md scoring — mutually-exclusive match score + GS 8
-- ============================================================
-- rules.md (canonical) changes match-result scoring from stacked
-- (outcome 2 + goal_diff 3 + exact 3 = up to 8 base) to mutually
-- exclusive (highest matching category wins):
--   Exact Score             = 5
--   Correct Goal Difference = 3
--   Correct Outcome (W/D/L) = 2
--   Otherwise               = 0
-- And goalscorer changes from 5 to 8 (still independent + additive).
-- Max base per match remains 13 (5 + 8).
--
-- Storage: collapse points_outcome/goal_diff/exact into a single
-- `points_match` int column. Rename points_scorer → points_goalscorer.
-- One row has at most one match category set, so the materialized
-- view's tiebreaker counts become `count(*) FILTER (WHERE points_match = N)`.
--
-- Goalscorer team validation: rules.md UI rules require that the
-- selected scorer's team be predicted to score > 0 (and disallow any
-- goalscorer when the predicted score is 0-0). Enforced at the DB
-- layer via a BEFORE trigger so it survives non-UI clients.
-- ============================================================

-- ============================================================
-- Step 1: Add new columns, backfill from old, drop old columns
-- ============================================================
alter table public.predictions
  add column if not exists points_match      int,
  add column if not exists points_goalscorer int;

-- Backfill from existing v2 columns (best-effort translation)
update public.predictions set
  points_match = case
    when coalesce(points_exact,     0) > 0 then 5
    when coalesce(points_goal_diff, 0) > 0 then 3
    when coalesce(points_outcome,   0) > 0 then 2
    else 0
  end,
  points_goalscorer = case
    when coalesce(points_scorer, 0) > 0 then 8
    else 0
  end
where points_match is null
   or points_goalscorer is null;

-- Recompute points_earned with the new totals before dropping the old columns
update public.predictions set
  points_earned = (coalesce(points_match, 0) + coalesce(points_goalscorer, 0))
                  * coalesce(multiplier, 1);

-- The materialized view's count(*) FILTER expressions reference the
-- old columns, so the view must go before the columns are dropped.
-- Migration 019 recreates it with the new column set.
drop materialized view if exists public.group_standings;

-- The old constraint references columns we're about to drop
alter table public.predictions
  drop constraint if exists no_scorer_on_scoreless;

alter table public.predictions
  drop column if exists points_outcome,
  drop column if exists points_goal_diff,
  drop column if exists points_exact,
  drop column if exists points_scorer;

-- ============================================================
-- Step 2: Goalscorer validation trigger
-- ============================================================
-- Enforces rules.md "Goalscorer UI Rules" at the DB layer:
--   * 0-0 prediction + scorer            → reject
--   * Scorer on the team predicted to    → reject
--     score 0 goals (other team scores)
--   * Scorer not on either match team    → reject
-- Goalscorer without a score prediction is permitted (rules.md
-- "Prediction Rules" lists this combination as valid); team-zero
-- and team-membership checks are skipped when no score is predicted.
-- ============================================================
create or replace function public.validate_prediction_scorer()
returns trigger language plpgsql as $$
declare
  v_player_team int;
  v_team1       int;
  v_team2       int;
begin
  if new.predicted_scorer_id is null then
    return new;
  end if;

  select p.team_id into v_player_team
    from public.players p
   where p.id = new.predicted_scorer_id;

  if v_player_team is null then
    raise exception 'goalscorer player % not found', new.predicted_scorer_id
      using errcode = 'check_violation';
  end if;

  select m.team1_id, m.team2_id
    into v_team1, v_team2
    from public.matches m
   where m.id = new.match_id;

  if v_player_team is distinct from v_team1
     and v_player_team is distinct from v_team2 then
    raise exception 'goalscorer % is not on either match team', new.predicted_scorer_id
      using errcode = 'check_violation';
  end if;

  if new.predicted_team1 is not null and new.predicted_team2 is not null then
    if new.predicted_team1 = 0 and new.predicted_team2 = 0 then
      raise exception 'goalscorer not allowed for 0-0 prediction'
        using errcode = 'check_violation';
    end if;

    if (v_player_team = v_team1 and new.predicted_team1 = 0)
       or (v_player_team = v_team2 and new.predicted_team2 = 0) then
      raise exception 'goalscorer team predicted to score 0'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists predictions_validate_scorer on public.predictions;
create trigger predictions_validate_scorer
  before insert
     or update of predicted_team1,
                  predicted_team2,
                  predicted_scorer_id
  on public.predictions
  for each row
  execute function public.validate_prediction_scorer();

-- ============================================================
-- Step 3: Rewrite compute_match_scoring (mutually-exclusive match)
-- ============================================================
create or replace function public.compute_match_scoring(p_match_id int)
returns void language plpgsql security definer as $$
declare
  v_match public.matches;
  v_ft1   int;
  v_ft2   int;
begin
  select * into v_match from public.matches where id = p_match_id;
  if not found or v_match.status != 'final' then return; end if;

  v_ft1 := v_match.score_ft_team1;
  v_ft2 := v_match.score_ft_team2;

  update public.predictions pr set
    -- Match result: mutually exclusive. Award the highest matching
    -- category. Order matters: exact ⊃ goal_diff ⊃ outcome.
    --
    -- Per rules.md examples, "Correct Goal Difference" only fires when
    -- the actual margin is ≥ 2 goals. A 1-goal win or a draw with the
    -- same trivial GD (0 or ±1) falls through to the outcome bonus.
    -- This matches the examples:
    --   3-1 vs 4-2 (GD=2)  → 3
    --   2-1 vs 1-0 (GD=1)  → 2 (outcome only)
    --   1-1 vs 2-2 (GD=0)  → 2 (outcome only)
    points_match = case
      when pr.predicted_team1 is null or pr.predicted_team2 is null then 0
      when pr.predicted_team1 = v_ft1 and pr.predicted_team2 = v_ft2 then 5
      when (pr.predicted_team1 - pr.predicted_team2) = (v_ft1 - v_ft2)
       and abs(v_ft1 - v_ft2) >= 2 then 3
      when (pr.predicted_team1 > pr.predicted_team2 and v_ft1 > v_ft2) or
           (pr.predicted_team1 < pr.predicted_team2 and v_ft1 < v_ft2) or
           (pr.predicted_team1 = pr.predicted_team2 and v_ft1 = v_ft2) then 2
      else 0
    end,
    -- Goalscorer: independent + additive. Regular time only
    -- (api-sports stoppage goals are at elapsed=90, ET at >=91).
    -- type='goal' excludes shootout_kick rows.
    points_goalscorer = case
      when pr.predicted_scorer_id is null then 0
      when exists (
        select 1 from public.match_events me
        where me.match_id = p_match_id
          and me.type = 'goal'
          and me.player_id = pr.predicted_scorer_id
          and (me.detail is null or me.detail not in ('own_goal'))
          and me.minute <= 90
      ) then 8
      else 0
    end,
    -- Multiplier: auto for 3rd/Final, user booster for R32-SF, else 1.
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

  update public.predictions set
    points_earned = (coalesce(points_match, 0) + coalesce(points_goalscorer, 0))
                    * multiplier
  where match_id = p_match_id;

  refresh materialized view concurrently public.group_standings;
end;
$$;
