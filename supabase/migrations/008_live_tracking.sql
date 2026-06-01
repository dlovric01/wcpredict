-- ============================================================
-- WC2026 Prediction App — Live tracking + lineup grid
-- Migration 006
-- ============================================================

-- Add grid position and starter flag to players.
-- grid: API-Football "row:col" string, e.g. "2:3" — null for substitutes.
-- is_starter: true = starting XI, false = named substitute.
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS grid       text,
  ADD COLUMN IF NOT EXISTS is_starter bool NOT NULL DEFAULT true;

-- Add formation columns to matches so the pitch view can show "4-3-3" etc.
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS formation_team1 text,
  ADD COLUMN IF NOT EXISTS formation_team2 text;

-- ============================================================
-- Restore cron to every minute for live score polling.
-- Migration 005 slowed it to 10 min; live tracking needs 1 min.
-- ============================================================
SELECT cron.unschedule('poll-match-results')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'poll-match-results');

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
