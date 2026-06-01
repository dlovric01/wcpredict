-- ============================================================
-- Migration 023: group_standings v4 — add first_team_count tiebreaker
-- ============================================================
-- Migration 022 added the "first team to score" prediction (+2 pts).
-- The leaderboard tiebreakers in 019 didn't account for it, so a user
-- with more first-team hits would tie behind one with the same total
-- but fewer first-team hits and one extra goal-diff. Insert
-- first_team_count between scorer_count and goal_diff_count so the
-- order is:
--   total_points
--   → exact_count          (5)
--   → scorer_count         (8)
--   → first_team_count     (2)   -- NEW
--   → goal_diff_count      (3)
--   → outcome_count        (2)
--   → earliest_submission
-- ============================================================

drop materialized view if exists public.group_standings;

create materialized view public.group_standings as
select
  gm.group_id,
  p.user_id,
  p.display_name,

  -- Match points + tournament bonus
  coalesce(sum(pr.points_earned), 0)
    + coalesce(tp.points_earned, 0)                         as total_points,
  coalesce(sum(pr.points_earned), 0)                        as match_points,
  coalesce(tp.points_earned, 0)                             as tournament_points,

  -- Tiebreaker counts
  count(*) filter (
    where m.status = 'final' and pr.points_match = 5
  )                                                         as exact_count,
  count(*) filter (
    where m.status = 'final' and pr.points_goalscorer = 8
  )                                                         as scorer_count,
  count(*) filter (
    where m.status = 'final' and pr.points_first_team = 2
  )                                                         as first_team_count,
  count(*) filter (
    where m.status = 'final' and pr.points_match = 3
  )                                                         as goal_diff_count,
  count(*) filter (
    where m.status = 'final' and pr.points_match = 2
  )                                                         as outcome_count,

  min(pr.created_at)                                        as earliest_submission
from public.group_members gm
join public.profiles p
  on p.user_id = gm.user_id
left join public.predictions pr
  on pr.user_id = gm.user_id
left join public.matches m
  on m.id = pr.match_id
left join public.tournament_predictions tp
  on tp.user_id = gm.user_id
group by gm.group_id, p.user_id, p.display_name, tp.points_earned;

create unique index group_standings_pk
  on public.group_standings (group_id, user_id);

-- Tiebreaker ordering index (matches the documented sort order).
create index group_standings_order_idx
  on public.group_standings (
    group_id,
    total_points       desc,
    exact_count        desc,
    scorer_count       desc,
    first_team_count   desc,
    goal_diff_count    desc,
    outcome_count      desc,
    earliest_submission asc
  );

-- Initial populate (non-concurrent on first creation).
refresh materialized view public.group_standings;
