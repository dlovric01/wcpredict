-- ============================================================
-- WC2026 Prediction App — Fix first-team-to-score null handling
-- Migration 006
-- ============================================================
-- Bug: the null+null case for points_first_team was gated on
-- v_first_team_id IS NULL (derived from match_events), not on the
-- actual FT score being 0-0. A match with goals but no events
-- inserted would incorrectly award 2 pts to any prediction that
-- left predicted_first_team_id = null.
--
-- Fix: anchor the "predicted scoreless draw" bonus on the actual
-- FT score columns (v_ft1 = 0 and v_ft2 = 0). That way the bonus
-- is only awarded when the match was verifiably goalless, regardless
-- of whether match_events rows exist.
-- ============================================================

create or replace function public.compute_match_scoring(p_match_id int)
returns void language plpgsql security definer as $$
declare
  v_match public.matches;
  v_ft1   int;
  v_ft2   int;
  v_first_team_id int;
begin
  -- Fetch final match state
  select * into v_match from public.matches where id = p_match_id;
  if not found or v_match.status != 'final' then return; end if;

  v_ft1 := v_match.score_ft_team1;
  v_ft2 := v_match.score_ft_team2;

  -- Determine first scoring team from match_events (goals only, not shootouts, not own goals)
  select team_id into v_first_team_id
  from public.match_events
  where match_id = p_match_id
    and type = 'goal'
    and (detail is null or detail not in ('own_goal'))
    and minute <= 120
  order by minute asc, id asc
  limit 1;

  -- Update each prediction for this match
  update public.predictions pr set
    points_score = case
      when pr.predicted_team1 = v_ft1 and pr.predicted_team2 = v_ft2 then 3
      -- Correct result direction (including draw)
      when (pr.predicted_team1 > pr.predicted_team2 and v_ft1 > v_ft2) or
           (pr.predicted_team1 < pr.predicted_team2 and v_ft1 < v_ft2) or
           (pr.predicted_team1 = pr.predicted_team2 and v_ft1 = v_ft2) then 1
      else 0
    end,
    points_first_team = case
      -- Predicted no goals (null) AND match was truly 0-0 at FT
      when pr.predicted_first_team_id is null and v_ft1 = 0 and v_ft2 = 0 then 2
      when pr.predicted_first_team_id = v_first_team_id then 2
      else 0
    end,
    points_scorer = case
      when pr.predicted_scorer_id is null then 0
      -- Check there is a non-own-goal goal by this player in this match (minutes 1-120)
      when exists (
        select 1 from public.match_events me
        where me.match_id = p_match_id
          and me.type = 'goal'
          and me.player_id = pr.predicted_scorer_id
          and (me.detail is null or me.detail not in ('own_goal'))
          and me.minute <= 120
      ) then 3
      else 0
    end
  where pr.match_id = p_match_id;

  -- Compute total
  update public.predictions set
    points_earned = coalesce(points_score, 0)
                  + coalesce(points_first_team, 0)
                  + coalesce(points_scorer, 0)
  where match_id = p_match_id;

  -- Refresh materialized view for all groups that have members with predictions on this match
  refresh materialized view concurrently public.group_standings;
end;
$$;
