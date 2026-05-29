-- ============================================================
-- WC2026 Prediction App — Update cron schedules
-- Migration 005
--
-- Changes from migration 004:
--   - poll-live-matches → poll-match-results, every 10 min
--   - poll-lineups stays every minute (self-gates internally)
--   - lock-predictions every 30 min (kickoff times are known)
--   - poll-fixtures daily unchanged
-- ============================================================

-- Remove old jobs before recreating
SELECT cron.unschedule('poll-live-matches') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'poll-live-matches'
);
SELECT cron.unschedule('lock-predictions') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'lock-predictions'
);

-- poll-match-results: every 10 minutes
-- Checks for FT matches not yet final in DB; self-gates if no match could be finished
SELECT cron.schedule(
  'poll-match-results',
  '*/10 * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://txziwjxvfprjilfyibol.supabase.co/functions/v1/poll_live_matches',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer REDACTED-ANON-JWT'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- lock-predictions: every 30 minutes (kickoff times are fixed and known in advance)
SELECT cron.schedule(
  'lock-predictions',
  '*/30 * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://txziwjxvfprjilfyibol.supabase.co/functions/v1/lock_predictions',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer REDACTED-ANON-JWT'
    ),
    body    := '{}'::jsonb
  );
  $$
);
