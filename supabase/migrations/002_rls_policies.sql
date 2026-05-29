-- ============================================================
-- WC2026 Prediction App — Row Level Security Policies
-- Migration 002
-- ============================================================

-- Enable RLS on all user-facing tables
alter table public.profiles       enable row level security;
alter table public.groups          enable row level security;
alter table public.group_members   enable row level security;
alter table public.teams           enable row level security;
alter table public.players         enable row level security;
alter table public.matches         enable row level security;
alter table public.match_events    enable row level security;
alter table public.predictions     enable row level security;

-- ============================================================
-- PROFILES
-- ============================================================
-- Own profile: full access
create policy "profiles_own_rw" on public.profiles
  for all using (auth.uid() = user_id);

-- Others: read display_name only (SELECT only, column-level restriction via view is optional)
create policy "profiles_others_read" on public.profiles
  for select using (true);

-- ============================================================
-- GROUPS
-- ============================================================
-- Members can read groups they belong to
create policy "groups_members_read" on public.groups
  for select using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = id and gm.user_id = auth.uid()
    )
  );

-- Owner can insert/update/delete
create policy "groups_owner_write" on public.groups
  for all using (owner_id = auth.uid());

-- ============================================================
-- GROUP MEMBERS
-- ============================================================
-- Members see all rows for groups they belong to
create policy "group_members_read" on public.group_members
  for select using (
    exists (
      select 1 from public.group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
    )
  );

-- Anyone can insert themselves (joining a group via invite code)
create policy "group_members_join" on public.group_members
  for insert with check (user_id = auth.uid());

-- Users can remove themselves (leave group); owner can remove anyone
create policy "group_members_leave" on public.group_members
  for delete using (
    user_id = auth.uid()
    or exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
  );

-- ============================================================
-- TEAMS & PLAYERS (public read, service-role write)
-- ============================================================
create policy "teams_public_read" on public.teams
  for select using (true);

create policy "players_public_read" on public.players
  for select using (true);

-- ============================================================
-- MATCHES (public read, service-role write)
-- ============================================================
create policy "matches_public_read" on public.matches
  for select using (true);

-- ============================================================
-- MATCH EVENTS (public read, service-role write)
-- ============================================================
create policy "match_events_public_read" on public.match_events
  for select using (true);

-- ============================================================
-- PREDICTIONS
-- ============================================================
-- Own predictions: full access (before lock)
create policy "predictions_own_rw" on public.predictions
  for all using (user_id = auth.uid());

-- Group members can read each other's predictions once match has kicked off
-- (locked_at is set at kickoff, which is when predictions lock)
create policy "predictions_group_read" on public.predictions
  for select using (
    locked_at is not null
    and exists (
      -- viewer and prediction owner share a group
      select 1
      from public.group_members gm_viewer
      join public.group_members gm_owner
        on gm_viewer.group_id = gm_owner.group_id
      where gm_viewer.user_id = auth.uid()
        and gm_owner.user_id  = predictions.user_id
    )
  );
