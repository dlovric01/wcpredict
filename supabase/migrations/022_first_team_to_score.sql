-- ============================================================
-- Migration 022: First team to score (optional, +2 pts)
-- ============================================================
-- rules.md adds an optional third pick alongside the score and
-- goalscorer:
--   First team to score = 2 pts
--
-- The pick is the team_id (FK → teams) and is independent + additive.
-- It is awarded when the predicted team matches the team that scored
-- the first regular-time goal (minute <= 90, type='goal', non-OG, no
-- shootout kicks).
--
-- UI rules (mirror the goalscorer):
--   * 0-0 prediction      → first-team pick is not allowed.
--   * Team predicted to   → cannot pick that team as first to score.
--     score 0 goals
--   * Team not on match   → cannot pick.
--
-- Max base per match is now 5 + 2 + 8 = 15.
-- points_earned = (points_match + points_first_team + points_goalscorer) * multiplier.
-- ============================================================

-- ============================================================
-- Step 1: Schema
-- ============================================================
alter table public.predictions
  add column if not exists predicted_first_team_id int references public.teams on delete set null,
  add column if not exists points_first_team       int;

-- Replace the scoreless constraint to cover the new pick as well.
alter table public.predictions
  drop constraint if exists no_scorer_on_scoreless;

alter table public.predictions
  add constraint no_picks_on_scoreless check (
    not (predicted_team1 = 0 and predicted_team2 = 0
         and (predicted_scorer_id is not null
              or predicted_first_team_id is not null))
  );

-- ============================================================
-- Step 2: Lock trigger — watch the new column too
-- ============================================================
drop trigger if exists predictions_lock_check on public.predictions;

create trigger predictions_lock_check
  before insert
     or update of predicted_team1,
                  predicted_team2,
                  predicted_first_team_id,
                  predicted_scorer_id
  on public.predictions
  for each row
  execute function public.check_prediction_lock();

-- ============================================================
-- Step 3: Replace goalscorer-only validation trigger with a
-- combined picks validation. Enforces rules.md "UI Rules" for
-- both first-team and goalscorer at the DB layer.
-- ============================================================
create or replace function public.validate_prediction_picks()
returns trigger language plpgsql as $$
declare
  v_player_team int;
  v_team1       int;
  v_team2       int;
begin
  -- Fetch match teams once.
  select m.team1_id, m.team2_id
    into v_team1, v_team2
    from public.matches m
   where m.id = new.match_id;

  -- ── First team to score ─────────────────────────────────────────
  if new.predicted_first_team_id is not null then
    if new.predicted_first_team_id is distinct from v_team1
       and new.predicted_first_team_id is distinct from v_team2 then
      raise exception 'first-team pick % is not on either match team', new.predicted_first_team_id
        using errcode = 'check_violation';
    end if;

    if new.predicted_team1 is not null and new.predicted_team2 is not null then
      if new.predicted_team1 = 0 and new.predicted_team2 = 0 then
        raise exception 'first-team pick not allowed for 0-0 prediction'
          using errcode = 'check_violation';
      end if;

      if (new.predicted_first_team_id = v_team1 and new.predicted_team1 = 0)
         or (new.predicted_first_team_id = v_team2 and new.predicted_team2 = 0) then
        raise exception 'first-team pick is predicted to score 0'
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  -- ── Goalscorer ──────────────────────────────────────────────────
  if new.predicted_scorer_id is not null then
    select p.team_id into v_player_team
      from public.players p
     where p.id = new.predicted_scorer_id;

    if v_player_team is null then
      raise exception 'goalscorer player % not found', new.predicted_scorer_id
        using errcode = 'check_violation';
    end if;

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
  end if;

  return new;
end;
$$;

drop trigger if exists predictions_validate_scorer on public.predictions;
drop trigger if exists predictions_validate_picks  on public.predictions;
create trigger predictions_validate_picks
  before insert
     or update of predicted_team1,
                  predicted_team2,
                  predicted_first_team_id,
                  predicted_scorer_id
  on public.predictions
  for each row
  execute function public.validate_prediction_picks();

-- Old function no longer referenced.
drop function if exists public.validate_prediction_scorer();

-- ============================================================
-- Step 4: Rewrite compute_match_scoring to include first-team
-- ============================================================
create or replace function public.compute_match_scoring(p_match_id int)
returns void language plpgsql security definer as $$
declare
  v_match         public.matches;
  v_ft1           int;
  v_ft2           int;
  v_first_team_id int;
begin
  select * into v_match from public.matches where id = p_match_id;
  if not found or v_match.status != 'final' then return; end if;

  v_ft1 := v_match.score_ft_team1;
  v_ft2 := v_match.score_ft_team2;

  -- First scoring team in regulation: earliest non-OG, non-shootout goal
  -- at minute <= 90. NULL when the match was 0-0 at FT (no goals to award).
  select team_id into v_first_team_id
    from public.match_events
   where match_id = p_match_id
     and type = 'goal'
     and (detail is null or detail not in ('own_goal'))
     and minute is not null
     and minute <= 90
   order by minute asc, id asc
   limit 1;

  update public.predictions pr set
    -- Match result: mutually exclusive. Highest matching category wins.
    -- Order: exact ⊃ goal_diff (|GD|≥2) ⊃ outcome.
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
    -- First team to score: independent + additive. Awarded only when
    -- the user explicitly picked a team AND that team scored first in
    -- regulation. No implicit award for 0-0 / null pick.
    points_first_team = case
      when pr.predicted_first_team_id is null then 0
      when pr.predicted_first_team_id = v_first_team_id then 2
      else 0
    end,
    -- Goalscorer: independent + additive. Regular time only.
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
    points_earned = (coalesce(points_match,       0)
                   + coalesce(points_first_team,  0)
                   + coalesce(points_goalscorer,  0))
                  * multiplier
  where match_id = p_match_id;

  refresh materialized view concurrently public.group_standings;
end;
$$;

-- ============================================================
-- Step 5: Recompute every finalized match so historical rows
-- reflect the new points_earned formula (points_first_team
-- defaults to 0 for legacy rows → totals unchanged unless a
-- user later edits a prediction, which is impossible post-lock).
-- ============================================================
do $$
declare
  v_match_id int;
begin
  for v_match_id in
    select id from public.matches where status = 'final'
  loop
    perform public.compute_match_scoring(v_match_id);
  end loop;
end$$;
