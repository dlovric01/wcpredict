-- ============================================================
-- Migration 031: Drop dev_seed_helpers
-- ============================================================
-- Reverts the helpers introduced (and applied) by 030_dev_seed_helpers.sql.
-- They were added for an in-flight backend-seed plan that we pivoted away
-- from in favour of a frontend-only mock (lib/shared/providers/mock_groups.dart).
-- Functions are service-role-only and unused, but we drop them so the
-- schema surface stays minimal.
--
-- Idempotent: `drop function if exists` so a fresh `supabase db reset`
-- (which skips the deleted 030 file) succeeds even though there is
-- nothing to drop.
-- ============================================================

drop function if exists public.dev_seed_locked_prediction(uuid, int, int, int, int, int);
drop function if exists public.dev_seed_tournament_pick(uuid, int, int);
