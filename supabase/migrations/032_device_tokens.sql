-- ============================================================
-- Migration 032: Device tokens for push notifications
-- ============================================================
-- Stores FCM device tokens per user so the notify_predict_reminders
-- edge function (migration 034) knows where to deliver the 30-min
-- kickoff reminder.
--
-- A single user may have multiple devices — composite PK on
-- (user_id, token) lets us upsert idempotently from each device on
-- sign-in / on Firebase token refresh, without orphaning rows when
-- the same token rotates to a different account.
-- ============================================================

create table if not exists public.device_tokens (
  user_id    uuid        not null references auth.users on delete cascade,
  token      text        not null,
  platform   text        not null check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- Lookup by token for cleanup when the same token has migrated to a new user.
create index if not exists device_tokens_token_idx
  on public.device_tokens (token);

alter table public.device_tokens enable row level security;

-- Owner-only RW. Edge functions read with the service-role key,
-- which bypasses RLS, so no SELECT policy is needed here.
drop policy if exists "device_tokens_owner_rw" on public.device_tokens;
create policy "device_tokens_owner_rw" on public.device_tokens
  for all
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Keep updated_at fresh on every upsert so the edge function can
-- prune long-stale tokens later if quota becomes a concern.
create or replace function public.set_device_token_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists device_tokens_set_updated_at on public.device_tokens;
create trigger device_tokens_set_updated_at
  before insert or update on public.device_tokens
  for each row
  execute function public.set_device_token_updated_at();
