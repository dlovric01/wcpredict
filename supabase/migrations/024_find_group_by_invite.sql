-- ============================================================
-- Migration 024: find_group_by_invite RPC
-- ============================================================
-- The `groups_members_read` RLS policy in 002 only lets a user SELECT
-- groups they already belong to. The join-by-code flow needs the
-- opposite: look up a group by its invite code BEFORE the caller is a
-- member. Without this, `select * from groups where invite_code = ?`
-- runs by a non-member returns zero rows and the UI reports "Group not
-- found" even when the code is valid.
--
-- A SECURITY DEFINER function bypasses RLS for the lookup, but only
-- returns the minimum needed (id + name) — never the invite_code itself
-- or any owner metadata — so it cannot be abused to enumerate groups.
-- ============================================================

create or replace function public.find_group_by_invite(p_code text)
returns table(id uuid, name text)
language sql
security definer
stable
set search_path = public
as $$
  select g.id, g.name
  from public.groups g
  where upper(g.invite_code) = upper(trim(p_code))
  limit 1;
$$;

revoke all on function public.find_group_by_invite(text) from public;
grant execute on function public.find_group_by_invite(text) to authenticated;
