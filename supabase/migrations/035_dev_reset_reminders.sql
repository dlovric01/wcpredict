-- ============================================================
-- Migration 035: dev_reset_reminders() RPC
-- ============================================================
-- The in-app simulation screen (`/dev/simulate`, kDebugMode-gated)
-- exposes a "Reset reminders log" button so a developer can re-test
-- the predict-reminder flow on the same match without having to
-- service-role into the DB.
--
-- Mirrors the gating from migration 027: the RPC may run only when
-- the caller's JWT email belongs to a known dev domain
-- (`@wcpredict.dev` for seeded dev users, `@wctest.invalid` for the
-- regression suite, service-role for direct backend calls). Real
-- users hitting the endpoint by hand get a 42501 permission error.
-- ============================================================

create or replace function public.dev_reset_reminders()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text;
  v_role    text;
  v_user_id uuid;
  v_deleted int;
begin
  v_role    := auth.role();
  v_email   := coalesce((auth.jwt() ->> 'email')::text, '');
  v_user_id := auth.uid();

  if v_user_id is null and v_role <> 'service_role' then
    raise exception 'dev_reset_reminders requires an authenticated caller'
      using errcode = '42501';
  end if;

  if not (
    v_role = 'service_role'
    or v_email ~* '@wctest\.invalid$'
    or v_email ~* '@wcpredict\.dev$'
  ) then
    raise exception
      'dev_reset_reminders is restricted to dev/test accounts'
      using errcode = '42501';
  end if;

  delete from public.prediction_reminders_sent
   where user_id = v_user_id;
  get diagnostics v_deleted = row_count;

  return v_deleted;
end;
$$;

revoke all on function public.dev_reset_reminders() from public;
grant execute on function public.dev_reset_reminders() to authenticated;
