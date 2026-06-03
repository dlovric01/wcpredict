-- ============================================================
-- Migration 038: Recompute scoring when a booster row changes
-- ============================================================
-- The lock trigger (mig 012) only fires on INSERT/UPDATE and only
-- to REJECT writes against a match past its kickoff window. It
-- does NOT propagate booster changes back into already-scored
-- predictions. Two reachable scoring drifts result:
--
--   1. DELETE booster row after the match finalised
--      → predictions.multiplier stays at the cached pre-delete value;
--        the points_earned column is inflated by the multiplier the
--        user has since removed.
--
--   2. UPDATE booster row's match_id (i.e. the "move" UX) after the
--      ORIGINAL match finalised
--      → the same drift on the old match: it still shows the boosted
--        multiplier even though the booster row no longer references it.
--
-- This migration adds AFTER DELETE + AFTER UPDATE triggers that call
-- compute_match_scoring() on every match losing a booster reference.
-- compute_match_scoring() short-circuits when status != 'final', so
-- pre-kickoff churn is a no-op.
-- ============================================================

create or replace function public.recompute_on_booster_change()
returns trigger
language plpgsql
security definer
as $$
begin
  if (tg_op = 'DELETE') then
    perform public.compute_match_scoring(old.match_id);
    return old;
  elsif (tg_op = 'UPDATE') then
    -- Only recompute the OLD match when match_id actually changed.
    -- NEW.match_id can't have been final (lock trigger forbids it),
    -- so we never need to recompute it here.
    if old.match_id is distinct from new.match_id then
      perform public.compute_match_scoring(old.match_id);
    end if;
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists round_boosters_recompute on public.round_boosters;
create trigger round_boosters_recompute
  after update or delete
  on public.round_boosters
  for each row
  execute function public.recompute_on_booster_change();

-- ============================================================
-- One-shot reconciliation: any finalised match that currently has
-- a stale prediction.multiplier (i.e. its multiplier doesn't match
-- the live booster table) will be put back in sync. Idempotent:
-- compute_match_scoring is a SET-from-canonical-state operation.
-- ============================================================
do $$
declare
  v_match_id int;
begin
  for v_match_id in
    select distinct pr.match_id
      from public.predictions pr
      join public.matches m on m.id = pr.match_id
     where m.status = 'final'
       and pr.multiplier > 1
       and not exists (
         select 1 from public.round_boosters rb
          where rb.user_id  = pr.user_id
            and rb.match_id = pr.match_id
       )
       -- Skip auto-multiplier rounds (Final ×6, 3rd ×5) — their multiplier
       -- column is correctly > 1 without a booster row.
       and m.round not in ('Final','3rd')
  loop
    perform public.compute_match_scoring(v_match_id);
  end loop;
end$$;
