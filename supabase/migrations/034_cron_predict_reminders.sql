-- ============================================================
-- Migration 034: pg_cron schedule for notify_predict_reminders
-- ============================================================
-- Fires the edge function every minute. The function self-gates on
-- (kickoff between now+29min and now+31min) AND
-- (user not in prediction_reminders_sent for this match) AND
-- (user has no prediction yet), so a single matched user is pushed
-- exactly once.
--
-- Bearer token is the project anon key — same pattern as 004 and 005.
-- The function uses the service-role key from its env to query
-- auth.users and the reminders log.
-- ============================================================

select cron.schedule(
  'notify-predict-reminders',
  '* * * * *',
  $$
  select net.http_post(
    url     := 'https://txziwjxvfprjilfyibol.supabase.co/functions/v1/notify_predict_reminders',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer REDACTED-ANON-JWT'
    ),
    body    := '{}'::jsonb
  );
  $$
);
