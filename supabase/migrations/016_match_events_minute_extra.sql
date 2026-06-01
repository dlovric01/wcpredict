-- ============================================================
-- Migration 016: Store stoppage time extra minutes on match_events
-- ============================================================
-- api-sports.io stores stoppage time goals as elapsed=90, extra=N.
-- We now persist extra alongside elapsed so the UI can display
-- "90+13'" instead of just "90'" for late stoppage time events.
-- The scoring rule is unchanged: minute <= 90 (= elapsed) determines
-- regular time, since elapsed is always capped at the period boundary.
-- ============================================================

alter table public.match_events
  add column if not exists minute_extra int;

comment on column public.match_events.minute_extra is
  'Stoppage time addition (e.g. 3 for "90+3"). Null when not in stoppage time. '
  'Sourced from api-sports.io time.extra field.';
