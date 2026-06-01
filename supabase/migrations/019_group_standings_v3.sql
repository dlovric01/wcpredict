-- ============================================================
-- Migration 019: group_standings v3 — tournament points + new counts
-- ============================================================
-- Schema changed in 017 (mutually-exclusive match score lives in
-- `points_match`) and 018 added `tournament_predictions`. Recreate
-- the materialized view to:
--   * Use `points_match` for the exact / goal_diff / outcome
--     tiebreaker counts (was points_outcome / points_goal_diff /
--     points_exact).
--   * Use `points_goalscorer` (was points_scorer) for scorer_count.
--   * Add `tournament_points` and roll it into `total_points`.
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

  -- Tiebreaker counts (mutually exclusive match categories)
  count(*) filter (
    where m.status = 'final' and pr.points_match = 5
  )                                                         as exact_count,
  count(*) filter (
    where m.status = 'final' and pr.points_match = 3
  )                                                         as goal_diff_count,
  count(*) filter (
    where m.status = 'final' and pr.points_match = 2
  )                                                         as outcome_count,
  count(*) filter (
    where m.status = 'final' and pr.points_goalscorer = 8
  )                                                         as scorer_count,

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

-- Tiebreaker ordering index for queries that already filter by group.
create index group_standings_order_idx
  on public.group_standings (
    group_id,
    total_points       desc,
    exact_count        desc,
    scorer_count       desc,
    goal_diff_count    desc,
    outcome_count      desc,
    earliest_submission asc
  );

-- Initial populate (non-concurrent: a concurrent refresh requires the
-- MV to already hold data, which it doesn't on first creation).
refresh materialized view public.group_standings;

-- Recompute every finalized match under the new rules so historical
-- predictions land on points_match / points_goalscorer with the
-- mutually-exclusive scoring. compute_match_scoring() concurrently
-- refreshes the view after each match — slow but safe.
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
