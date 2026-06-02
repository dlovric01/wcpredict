-- ============================================================
-- WC2026 Prediction App — Restrict simulate_live_match RPC
-- Migration 027
--
-- Migration 026 left `grant execute on simulate_live_match(int) to
-- authenticated`. With matches + match_events publicly readable
-- (002_rls_policies.sql), any signed-in user could call the RPC and
-- conjure the test fixture (match 999001, France vs Brazil) into
-- every other user's fixtures list.
--
-- The in-app simulator UI is now `kDebugMode`-gated (router + profile
-- entry) so production builds have no surface to it. This migration
-- adds the matching backend guard: the RPC may only run for callers
-- whose JWT email ends in `@wctest.invalid` — the domain used by
-- `_devQuickLogin` and the regression suite. Real users can never
-- trigger it even by hand-crafting a POST.
-- ============================================================

drop function if exists public._simulate_live_match_impl(int);

-- Rename the existing implementation so we can wrap it. The wrapper
-- keeps the original `simulate_live_match` name (callers don't move),
-- and the inner `_impl` is callable only by the wrapper (we revoke
-- public execute below).
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'simulate_live_match'
      and pg_get_function_identity_arguments(p.oid) = 'step_num integer'
  ) then
    alter function public.simulate_live_match(int)
      rename to _simulate_live_match_impl;
  end if;
end$$;

revoke all on function public._simulate_live_match_impl(int) from public;
revoke all on function public._simulate_live_match_impl(int) from authenticated;

-- Guarded entry point. `auth.jwt()` returns the verified JWT claims
-- for the caller. Trusted backend callers (service-role JWT, or
-- direct psql/pgcron connections without a JWT) bypass the check.
create or replace function public.simulate_live_match(step_num int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_role  text;
begin
  v_role  := auth.role();
  v_email := coalesce((auth.jwt() ->> 'email')::text, '');

  if not (
    v_role is null
    or v_role = 'service_role'
    or v_email ~* '@wctest\.invalid$'
  ) then
    raise exception
      'simulate_live_match is restricted to @wctest.invalid test accounts'
      using errcode = '42501';
  end if;

  return public._simulate_live_match_impl(step_num);
end;
$$;

grant execute on function public.simulate_live_match(int) to authenticated;
