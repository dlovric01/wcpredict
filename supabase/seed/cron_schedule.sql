-- Cron schedule for WC2026 prediction app Edge Functions
-- Requirements:
--   1. pg_cron extension enabled (Supabase dashboard → Database → Extensions → pg_cron)
--   2. pg_net extension enabled (usually on by default in Supabase)
--   3. Edge Functions deployed (supabase functions deploy ...)
--
-- TODO: Replace the two placeholder values before running:
--   txziwjxvfprjilfyibol  → your Supabase project ref (e.g. abcdefghijklmnop)
--   REDACTED-ANON-JWT     → your project's anon/public key
--
-- Run this file in the Supabase dashboard SQL editor (not via migration runner,
-- because cron.schedule() is idempotent by job name — safe to re-run).

-- Enable pg_cron if not already active (requires superuser; do this once in the dashboard)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ----------------------------------------------------------------------------
-- poll-live-matches: every minute during tournament window
-- Fetches live score updates for any match with status IN_PLAY / HT.
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'poll-live-matches',
  '* * * * *',
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

-- ----------------------------------------------------------------------------
-- poll-fixtures: daily at 04:00 UTC
-- Syncs upcoming match schedule and team data from the API.
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'poll-fixtures',
  '0 4 * * *',
  $$
  SELECT net.http_post(
    url     := 'https://txziwjxvfprjilfyibol.supabase.co/functions/v1/poll_fixtures',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer REDACTED-ANON-JWT'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- ----------------------------------------------------------------------------
-- poll-lineups: every minute
-- Function self-gates: only fetches when a match is 25-35 min away from kickoff.
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'poll-lineups',
  '* * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://txziwjxvfprjilfyibol.supabase.co/functions/v1/poll_lineups',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer REDACTED-ANON-JWT'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- ----------------------------------------------------------------------------
-- lock-predictions: every minute
-- Locks prediction rows for matches whose kickoff_time <= NOW().
-- Note: pg_cron minimum granularity is 1 minute (no 30-second intervals).
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'lock-predictions',
  '*/1 * * * *',
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
