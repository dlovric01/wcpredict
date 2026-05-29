-- ============================================================
-- WC2026 Prediction App — Initial Schema
-- Migration 001
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ============================================================
-- PROFILES
-- ============================================================
create table public.profiles (
  user_id   uuid primary key references auth.users on delete cascade,
  display_name text not null,
  avatar_url   text,
  created_at   timestamptz not null default now()
);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- GROUPS
-- ============================================================
create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  owner_id    uuid not null references auth.users on delete cascade,
  invite_code text not null unique,
  created_at  timestamptz not null default now()
);

create index groups_invite_code_idx on public.groups (invite_code);

-- ============================================================
-- GROUP MEMBERS
-- ============================================================
create table public.group_members (
  group_id  uuid not null references public.groups on delete cascade,
  user_id   uuid not null references auth.users on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_idx on public.group_members (user_id);

-- ============================================================
-- TEAMS
-- ============================================================
create table public.teams (
  id           int primary key,   -- BALLDONTLIE team id
  name         text not null,
  code         text not null,     -- 3-letter code e.g. MEX
  flag_url     text,
  group_letter text               -- 'A'..'L', null for TBD knockout placeholders
);

-- ============================================================
-- PLAYERS
-- ============================================================
create table public.players (
  id             int primary key,   -- BALLDONTLIE player id
  team_id        int references public.teams on delete set null,
  name           text not null,
  position       text,              -- 'GK' | 'DEF' | 'MID' | 'FWD'
  jersey_number  int
);

create index players_team_idx on public.players (team_id);

-- ============================================================
-- MATCHES
-- ============================================================
create table public.matches (
  id              int primary key,  -- BALLDONTLIE match id
  round           text not null,    -- 'Matchday 1', 'R32', 'R16', 'QF', 'SF', 'Final'
  group_letter    text,             -- null for knockout rounds
  team1_id        int references public.teams,
  team2_id        int references public.teams,
  kickoff_time    timestamptz not null,
  status          text not null default 'scheduled'
                  check (status in ('scheduled','live','final','cancelled')),
  score_ht_team1  int,
  score_ht_team2  int,
  score_ft_team1  int,
  score_ft_team2  int,
  score_et_team1  int,
  score_et_team2  int,
  score_pen_team1 int,
  score_pen_team2 int,
  updated_at      timestamptz
);

create index matches_kickoff_idx on public.matches (kickoff_time);
create index matches_status_idx  on public.matches (status);

-- ============================================================
-- MATCH EVENTS
-- ============================================================
create table public.match_events (
  id          bigserial primary key,
  match_id    int not null references public.matches on delete cascade,
  minute      int,
  type        text not null check (type in ('goal','card','subst','shootout_kick')),
  team_id     int references public.teams,
  player_id   int references public.players on delete set null,
  player_name text,
  detail      text,               -- 'penalty', 'own_goal', etc.
  created_at  timestamptz not null default now()
);

create index match_events_match_idx on public.match_events (match_id);

-- ============================================================
-- PREDICTIONS
-- ============================================================
create table public.predictions (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references auth.users on delete cascade,
  match_id                int  not null references public.matches on delete cascade,
  -- Category 1: exact final score (90' FT before ET/pens)
  predicted_team1         int,
  predicted_team2         int,
  -- Category 2: first team to score (null = predicted 0-0)
  predicted_first_team_id int references public.teams on delete set null,
  -- Category 3: goalscorer (null = skipped)
  predicted_scorer_id     int references public.players on delete set null,
  -- Scoring (computed at FT)
  points_score            int,
  points_first_team       int,
  points_scorer           int,
  points_earned           int,    -- sum of the three above
  locked_at               timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (user_id, match_id),
  -- DB invariant: 0-0 prediction must have null first-team and null scorer
  constraint no_scorer_on_scoreless check (
    not (predicted_team1 = 0 and predicted_team2 = 0 and
         (predicted_first_team_id is not null or predicted_scorer_id is not null))
  )
);

create index predictions_user_idx  on public.predictions (user_id);
create index predictions_match_idx on public.predictions (match_id);

-- Auto-update updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger predictions_updated_at
  before update on public.predictions
  for each row execute function public.set_updated_at();

-- ============================================================
-- GROUP STANDINGS  (materialized view refreshed per match final)
-- ============================================================
create materialized view public.group_standings as
select
  gm.group_id,
  p.user_id,
  p.display_name,
  coalesce(sum(pr.points_earned), 0) as total_points,
  count(*) filter (
    where pr.predicted_team1 = m.score_ft_team1
      and pr.predicted_team2 = m.score_ft_team2
      and m.status = 'final'
  ) as exact_count,
  count(*) filter (
    where m.status = 'final'
      and (
        (pr.predicted_team1 > pr.predicted_team2 and m.score_ft_team1 > m.score_ft_team2) or
        (pr.predicted_team1 < pr.predicted_team2 and m.score_ft_team1 < m.score_ft_team2) or
        (pr.predicted_team1 = pr.predicted_team2 and m.score_ft_team1 = m.score_ft_team2)
      )
  ) as correct_result_count
from public.group_members gm
join public.profiles p on p.user_id = gm.user_id
left join public.predictions pr on pr.user_id = gm.user_id
left join public.matches m on m.id = pr.match_id
group by gm.group_id, p.user_id, p.display_name;

create unique index group_standings_pk on public.group_standings (group_id, user_id);

-- ============================================================
-- SCORING FUNCTION  (called by compute_scoring Edge Function)
-- ============================================================
-- Point values: exact score = 3, correct result = 1, first team = 2, goalscorer = 3
-- These are intentionally in SQL constants so they're easy to adjust.
create or replace function public.compute_match_scoring(p_match_id int)
returns void language plpgsql security definer as $$
declare
  v_match public.matches;
  v_ft1   int;
  v_ft2   int;
  v_first_team_id int;
begin
  -- Fetch final match state
  select * into v_match from public.matches where id = p_match_id;
  if not found or v_match.status != 'final' then return; end if;

  v_ft1 := v_match.score_ft_team1;
  v_ft2 := v_match.score_ft_team2;

  -- Determine first scoring team from match_events (goals only, not shootouts, not own goals for scorer credit)
  select team_id into v_first_team_id
  from public.match_events
  where match_id = p_match_id
    and type = 'goal'
    and (detail is null or detail not in ('own_goal'))
    and minute <= 120
  order by minute asc, id asc
  limit 1;

  -- Update each prediction for this match
  update public.predictions pr set
    points_score = case
      when pr.predicted_team1 = v_ft1 and pr.predicted_team2 = v_ft2 then 3
      -- Correct result direction (including draw)
      when (pr.predicted_team1 > pr.predicted_team2 and v_ft1 > v_ft2) or
           (pr.predicted_team1 < pr.predicted_team2 and v_ft1 < v_ft2) or
           (pr.predicted_team1 = pr.predicted_team2 and v_ft1 = v_ft2) then 1
      else 0
    end,
    points_first_team = case
      -- Both null = predicted scoreless draw; if match is indeed scoreless, award
      when pr.predicted_first_team_id is null and v_first_team_id is null then 2
      when pr.predicted_first_team_id = v_first_team_id then 2
      else 0
    end,
    points_scorer = case
      when pr.predicted_scorer_id is null then 0
      -- Check there is a non-own-goal goal by this player in this match (minutes 1-120)
      when exists (
        select 1 from public.match_events me
        where me.match_id = p_match_id
          and me.type = 'goal'
          and me.player_id = pr.predicted_scorer_id
          and (me.detail is null or me.detail not in ('own_goal'))
          and me.minute <= 120
      ) then 3
      else 0
    end
  where pr.match_id = p_match_id;

  -- Compute total
  update public.predictions set
    points_earned = coalesce(points_score, 0)
                  + coalesce(points_first_team, 0)
                  + coalesce(points_scorer, 0)
  where match_id = p_match_id;

  -- Refresh materialized view for all groups that have members with predictions on this match
  refresh materialized view concurrently public.group_standings;
end;
$$;

-- ============================================================
-- TRIGGER: auto-score when match transitions to 'final'
-- ============================================================
create or replace function public.trigger_compute_scoring()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'final' and (old.status is null or old.status != 'final') then
    perform public.compute_match_scoring(new.id);
  end if;
  return new;
end;
$$;

create trigger match_status_final
  after update of status on public.matches
  for each row execute function public.trigger_compute_scoring();

-- Also handle event deletion (VAR disallowed goal): re-run scoring
create or replace function public.trigger_recompute_on_event_delete()
returns trigger language plpgsql security definer as $$
declare
  v_status text;
begin
  select status into v_status from public.matches where id = old.match_id;
  if v_status = 'final' then
    perform public.compute_match_scoring(old.match_id);
  end if;
  return old;
end;
$$;

create trigger match_event_deleted
  after delete on public.match_events
  for each row execute function public.trigger_recompute_on_event_delete();
