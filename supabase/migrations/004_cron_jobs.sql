-- ============================================================
-- WC2026 Prediction App — pg_cron schedules
-- Migration 004
-- pg_cron and pg_net are pre-enabled on Supabase free tier.
-- cron.schedule() is idempotent: upserts by job name.
-- ============================================================

-- Every minute: poll live match scores (function self-gates to daily window)
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

-- Daily 04:00 UTC: sync full fixture list (handles knockout bracket resolution)
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

-- Every minute: fetch lineups for matches kicking off in 25-35 min
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

-- Every minute: lock predictions for matches that have kicked off
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
