-- ============================================================
-- Migration 025: dev_cron_status() diagnostic RPC
-- ============================================================
-- Read-only view onto cron.job for production diagnostics (the cron
-- schema is not exposed via PostgREST, so the app/dev tooling needs a
-- SECURITY DEFINER wrapper to introspect what's scheduled).
--
-- Returns one row per job — only fields safe to read by any
-- authenticated client (no http auth headers, no command bodies).
-- ============================================================

create or replace function public.dev_cron_status()
returns table(
  jobname  text,
  schedule text,
  active   boolean,
  last_run timestamptz,
  last_status text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    j.jobname,
    j.schedule,
    j.active,
    (
      select max(d.start_time)
      from cron.job_run_details d
      where d.jobid = j.jobid
    ) as last_run,
    (
      select d.status
      from cron.job_run_details d
      where d.jobid = j.jobid
      order by d.start_time desc
      limit 1
    ) as last_status
  from cron.job j
  order by j.jobname;
$$;

revoke all on function public.dev_cron_status() from public;
grant execute on function public.dev_cron_status() to authenticated, anon;
