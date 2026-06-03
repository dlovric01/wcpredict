-- ============================================================
-- Migration 033: Predict-reminder idempotency log
-- ============================================================
-- The notify_predict_reminders edge function fires every minute and
-- selects matches with kickoff in [now+29min, now+31min]. Without an
-- idempotency log a user would get up to 3 pushes for the same match
-- across the overlapping cron ticks.
--
-- Inserting (user_id, match_id) here BEFORE building the FCM payload
-- gates the next tick from re-sending. We accept the trade-off that a
-- crashed handler may drop one push rather than risk duplicates — one
-- missed reminder is acceptable, three duplicates are not.
-- ============================================================

create table if not exists public.prediction_reminders_sent (
  user_id  uuid        not null references auth.users on delete cascade,
  match_id int         not null references public.matches on delete cascade,
  sent_at  timestamptz not null default now(),
  primary key (user_id, match_id)
);

-- Edge function reads + writes via the service-role key (bypasses RLS).
-- Clients have no reason to read or write this table directly. RLS is
-- still enabled with no policies → all anon/authenticated access denied.
alter table public.prediction_reminders_sent enable row level security;
