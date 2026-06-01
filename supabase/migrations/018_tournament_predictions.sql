-- ============================================================
-- Migration 018: Tournament predictions (World Cup winner + Golden Boot)
-- ============================================================
-- rules.md introduces tournament-level predictions worth a fixed bonus:
--   World Cup Winner   = 75 pts
--   Golden Boot Winner = 50 pts
--
-- Predictions are submitted *before the opening match* and locked when
-- the earliest match kicks off. The lock is enforced by a BEFORE
-- trigger that compares now() against MIN(kickoff_time) — no cron
-- needed, no state to maintain.
--
-- Results are stored in a 1-row table `tournament_results`. Writing
-- to it fires `compute_tournament_scoring()` which assigns 75/50
-- to every matching row.
-- ============================================================

-- ============================================================
-- Helper: earliest scheduled kickoff = tournament lock cutoff
-- ============================================================
create or replace function public.tournament_opening_kickoff()
returns timestamptz
language sql
stable
parallel safe
as $$
  select min(kickoff_time)
    from public.matches
   where status != 'cancelled';
$$;

comment on function public.tournament_opening_kickoff() is
  'Earliest non-cancelled match kickoff. Tournament predictions lock when this is in the past.';

-- ============================================================
-- tournament_predictions: one row per user
-- ============================================================
create table public.tournament_predictions (
  user_id               uuid primary key references auth.users on delete cascade,
  wc_winner_team_id     int  references public.teams   on delete set null,
  golden_boot_player_id int  references public.players on delete set null,
  -- Scoring (computed when tournament_results is set)
  points_wc             int  not null default 0,
  points_golden_boot    int  not null default 0,
  points_earned         int  not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index tournament_predictions_team_idx
  on public.tournament_predictions (wc_winner_team_id);
create index tournament_predictions_player_idx
  on public.tournament_predictions (golden_boot_player_id);

create trigger tournament_predictions_updated_at
  before update on public.tournament_predictions
  for each row execute function public.set_updated_at();

-- ============================================================
-- Lock trigger: reject writes once the opening match has kicked off
-- Scope is intentionally narrow — only the prediction payload columns
-- are watched, so the scoring function (which updates points_*) is
-- unaffected.
-- ============================================================
create or replace function public.check_tournament_prediction_lock()
returns trigger language plpgsql as $$
declare
  v_opening timestamptz;
begin
  v_opening := public.tournament_opening_kickoff();
  if v_opening is not null and v_opening <= now() then
    raise exception
      'tournament predictions are locked (opening match kicked off at %)',
      v_opening
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger tournament_predictions_lock_check
  before insert
     or update of wc_winner_team_id,
                  golden_boot_player_id
  on public.tournament_predictions
  for each row
  execute function public.check_tournament_prediction_lock();

-- ============================================================
-- tournament_results: single-row sink for FIFA's official outcome
-- ============================================================
create table public.tournament_results (
  id                    boolean primary key default true check (id),
  winner_team_id        int references public.teams   on delete set null,
  golden_boot_player_id int references public.players on delete set null,
  set_at                timestamptz not null default now()
);

-- ============================================================
-- compute_tournament_scoring: fire when tournament_results changes
-- ============================================================
create or replace function public.compute_tournament_scoring()
returns trigger language plpgsql security definer as $$
begin
  update public.tournament_predictions tp set
    points_wc = case
      when new.winner_team_id is not null
       and tp.wc_winner_team_id = new.winner_team_id then 75
      else 0
    end,
    points_golden_boot = case
      when new.golden_boot_player_id is not null
       and tp.golden_boot_player_id = new.golden_boot_player_id then 50
      else 0
    end,
    points_earned =
        case when new.winner_team_id is not null
              and tp.wc_winner_team_id = new.winner_team_id then 75 else 0 end
      + case when new.golden_boot_player_id is not null
              and tp.golden_boot_player_id = new.golden_boot_player_id then 50 else 0 end,
    updated_at = now();

  refresh materialized view concurrently public.group_standings;
  return new;
end;
$$;

create trigger tournament_results_score
  after insert or update on public.tournament_results
  for each row execute function public.compute_tournament_scoring();

-- ============================================================
-- RLS
-- ============================================================
alter table public.tournament_predictions enable row level security;
alter table public.tournament_results     enable row level security;

-- tournament_predictions: owner has full read/write; group-mates can
-- read once predictions are locked (opening match has kicked off).
create policy tournament_predictions_own_rw on public.tournament_predictions
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy tournament_predictions_group_read on public.tournament_predictions
  for select
  using (
    -- Lock has fired
    (public.tournament_opening_kickoff() is not null
     and public.tournament_opening_kickoff() <= now())
    and exists (
      select 1
      from public.group_members gm_viewer
      join public.group_members gm_owner
        on gm_owner.group_id = gm_viewer.group_id
      where gm_viewer.user_id = auth.uid()
        and gm_owner.user_id  = tournament_predictions.user_id
    )
  );

-- tournament_results: world-readable, admin-write only.
create policy tournament_results_read on public.tournament_results
  for select using (true);
-- No insert/update/delete policy → only service role can write.
