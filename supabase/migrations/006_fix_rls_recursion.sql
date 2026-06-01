-- ============================================================
-- Migration 006: Fix infinite recursion in group_members RLS
-- ============================================================
--
-- Root cause: group_members_read evaluated `SELECT FROM group_members`
-- inside a policy ON group_members → infinite recursion.
-- The same recursion was triggered transitively by predictions_group_read
-- and groups_members_read (both JOIN group_members), which caused ALL
-- SELECT queries on predictions and groups to fail with:
--   "infinite recursion detected in policy for relation group_members"
--
-- Fix: introduce a SECURITY DEFINER helper that reads group_members
-- without triggering RLS (runs as the function owner, bypassing policies),
-- then rewrite all affected policies to use it.

-- ── Step 1: SECURITY DEFINER helper ──────────────────────────────────────────
-- Running as function owner (no RLS on the read inside) breaks the cycle.

CREATE OR REPLACE FUNCTION public.is_group_member(
  _group_id uuid,
  _user_id  uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM group_members
    WHERE group_id = _group_id
      AND user_id  = _user_id
  );
$$;

-- ── Step 2: Fix group_members_read ───────────────────────────────────────────
DROP POLICY IF EXISTS "group_members_read" ON public.group_members;

CREATE POLICY "group_members_read" ON public.group_members
  FOR SELECT USING (
    -- Always see your own rows (no recursion — direct column comparison).
    user_id = auth.uid()
    -- See all rows for any group you belong to (SECURITY DEFINER → no recursion).
    OR public.is_group_member(group_id, auth.uid())
  );

-- ── Step 3: Fix groups_members_read ──────────────────────────────────────────
-- Original used EXISTS(SELECT FROM group_members) directly → triggered broken policy.
DROP POLICY IF EXISTS "groups_members_read" ON public.groups;

CREATE POLICY "groups_members_read" ON public.groups
  FOR SELECT USING (
    public.is_group_member(id, auth.uid())
  );

-- ── Step 4: Fix predictions_group_read ───────────────────────────────────────
-- Original joined group_members twice → triggered group_members_read recursion.
-- Now the fixed group_members_read is safe, but use is_group_member for clarity.
DROP POLICY IF EXISTS "predictions_group_read" ON public.predictions;

CREATE POLICY "predictions_group_read" ON public.predictions
  FOR SELECT USING (
    locked_at IS NOT NULL
    AND EXISTS (
      -- Find any group the viewer belongs to, then check if the prediction
      -- owner is also in that group (SECURITY DEFINER call avoids recursion).
      SELECT 1 FROM group_members gm
      WHERE gm.user_id = auth.uid()
        AND public.is_group_member(gm.group_id, predictions.user_id)
    )
  );
