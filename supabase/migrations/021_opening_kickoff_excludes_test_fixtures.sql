-- ============================================================
-- Migration 021: Filter regression-test fixtures out of opening kickoff
-- ============================================================
-- Regression tests reserve `matches.id < 100_000` (T.MATCH_FUTURE etc. in
-- the 99_2xx range). Production data uses real api-sports.io ids which
-- are always ≥ 100_000. The Flutter client already filters `id >= 100000`
-- everywhere, but `tournament_opening_kickoff()` and the lock policy did
-- not, so a leftover test fixture from a regression run could prematurely
-- lock tournament predictions for everyone.
--
-- Apply the same id filter inside the function so the lock reflects only
-- the real opening match.
-- ============================================================

create or replace function public.tournament_opening_kickoff()
returns timestamptz
language sql
stable
parallel safe
as $$
  select min(kickoff_time)
    from public.matches
   where status != 'cancelled'
     and id >= 100000;
$$;

comment on function public.tournament_opening_kickoff() is
  'Earliest non-cancelled, non-test (id >= 100000) match kickoff. '
  'Tournament predictions lock when this is in the past.';
