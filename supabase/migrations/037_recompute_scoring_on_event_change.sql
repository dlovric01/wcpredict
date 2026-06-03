-- ============================================================
-- Migration 037: Recompute scoring on match_events INSERT too
-- ============================================================
-- The legacy `match_event_deleted` trigger (migration 001) fires
-- `compute_match_scoring()` per row whenever a match_events row is
-- deleted while the match is `status='final'`. That is correct for
-- a genuine VAR-disallowed goal (a single goal row vanishes and the
-- prediction bonuses must re-evaluate), but it is **destructive**
-- when DELETE is the first half of an idempotent refresh:
--
--   DELETE FROM match_events WHERE match_id = X;   -- fires per row;
--                                                  -- last recompute
--                                                  -- sees 0 events
--   INSERT INTO match_events (…);                  -- no trigger →
--                                                  -- scoring stays
--                                                  -- at 0 bonuses
--
-- Real-world impact: poll_live_matches Phase B used to do exactly
-- this sequence (`status='final'` then `upsertEvents` = delete-
-- then-insert), silently zeroing `points_first_team` and
-- `points_goalscorer` for every prediction on the affected match,
-- with no self-healing path (the match leaves the active poll set).
--
-- Two fixes layer here:
--   1. poll_live_matches Phase B now refreshes events BEFORE
--      flipping status — the destructive delete runs while status
--      is 'live'/'scheduled', where this trigger short-circuits.
--   2. **This migration** makes the trigger fire on INSERT too,
--      so any future caller (manual VAR re-sync, ad-hoc backfill,
--      one-off SQL fix) that touches events while status='final'
--      always re-arms scoring with the latest event set as the
--      LAST operation in their delete-then-insert refresh.
--
-- Cost: 2N recomputes per refresh (one per delete + one per
-- insert). For a max ~30-event match that's ~60 invocations,
-- each running compute_match_scoring + concurrent MV refresh.
-- Within tolerance for the cadence (manual / once at FT).
--
-- The legitimate VAR path is unchanged: a bare DELETE without a
-- following INSERT still triggers a recompute with the remaining
-- events, correctly stripping the disallowed bonus.
-- ============================================================

drop trigger if exists match_event_deleted on public.match_events;
drop function if exists public.trigger_recompute_on_event_delete();

create or replace function public.trigger_recompute_on_event_change()
returns trigger language plpgsql security definer as $$
declare
  v_match_id int;
  v_status   text;
begin
  -- For INSERT new is set; for DELETE old is set. UPDATE is not
  -- bound here (no UPDATE trigger declared) but coalesce keeps it
  -- defensible if one is added later.
  v_match_id := coalesce(new.match_id, old.match_id);
  if v_match_id is null then
    return null;
  end if;

  select status into v_status from public.matches where id = v_match_id;
  if v_status = 'final' then
    perform public.compute_match_scoring(v_match_id);
  end if;
  return null;
end;
$$;

create trigger match_events_recompute_scoring
  after insert or delete on public.match_events
  for each row
  execute function public.trigger_recompute_on_event_change();
