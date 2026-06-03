-- ============================================================
-- Migration 036: Per-match lineups
-- ============================================================
-- Resolves: Teams tab "Substitutes" section showed every non-starter
-- player on the team (often 15-25 reserves), because `players` is a
-- global per-team roster, not a per-match matchday squad.
--
-- api-sports.io `/fixtures/lineups` returns:
--   • startXI: exactly 11
--   • substitutes: ~7-15 (the actual matchday bench, never the whole squad)
-- We need a join table that records this per-match shape, so the Teams
-- tab can iterate (starters, subs) for THIS fixture instead of mining
-- the global players table.
--
-- Global `players` stays as-is (canonical roster, populated by
-- poll_fixtures + poll_lineups). It still backs the goalscorer picker,
-- which needs the full squad pre-match. `players.is_starter` / `.grid`
-- columns are now legacy / unused by the Teams tab but kept for
-- compatibility — re-tasking them would break the existing
-- PlayerModel JSON contract.
-- ============================================================

create table if not exists public.match_lineups (
  match_id   int     not null references public.matches(id) on delete cascade,
  team_id    int     not null references public.teams(id)   on delete cascade,
  player_id  int     not null references public.players(id) on delete cascade,
  is_starter boolean not null,
  grid       text,
  primary key (match_id, player_id)
);

create index if not exists match_lineups_match_team_idx
  on public.match_lineups (match_id, team_id);

alter table public.match_lineups enable row level security;

-- Any signed-in user can read lineups (they're public information
-- and shown on every match detail screen). Writes are service-role only
-- (poll_lineups edge function + dev_seed); RLS denies everything else
-- because no INSERT/UPDATE/DELETE policy is defined.
drop policy if exists "match_lineups_read" on public.match_lineups;
create policy "match_lineups_read" on public.match_lineups
  for select to authenticated
  using (true);
