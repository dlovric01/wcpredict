-- ============================================================
-- Migration 012: Knockout Boosters
-- ============================================================
-- Users apply a score multiplier to one match per knockout round
-- before kickoff. R32=2×, R16=3×, QF=4×, SF=5×.
-- 3rd place (5×) and Final (6×) use auto-multipliers (no user action).
-- ============================================================

create table public.round_boosters (
  user_id    uuid not null references auth.users on delete cascade,
  round      text not null,
  match_id   int  not null references public.matches on delete cascade,
  multiplier int  not null,
  created_at timestamptz not null default now(),
  primary key (user_id, round),
  constraint round_boosters_valid_round check (round in ('R32','R16','QF','SF')),
  constraint round_boosters_valid_multiplier check (
    (round = 'R32' and multiplier = 2) or
    (round = 'R16' and multiplier = 3) or
    (round = 'QF'  and multiplier = 4) or
    (round = 'SF'  and multiplier = 5)
  )
);

create index round_boosters_match_idx on public.round_boosters (match_id);

alter table public.round_boosters enable row level security;

-- Owner: full read/write of own booster rows
create policy round_boosters_own_rw on public.round_boosters
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Group members can read a booster once its match has kicked off
create policy round_boosters_group_read on public.round_boosters
  for select
  using (
    (
      select m.status != 'scheduled' or m.kickoff_time <= now()
      from public.matches m
      where m.id = round_boosters.match_id
    )
    and exists (
      select 1
      from public.group_members gm_viewer
      join public.group_members gm_owner
        on gm_owner.group_id = gm_viewer.group_id
      where gm_viewer.user_id = auth.uid()
        and gm_owner.user_id  = round_boosters.user_id
    )
  );

-- ============================================================
-- Lock trigger: reject booster if match is past its pre-kickoff window
-- Also enforces booster.round == match.round
-- ============================================================
create or replace function public.check_booster_lock()
returns trigger
language plpgsql
as $$
declare
  v_status       text;
  v_kickoff_time timestamptz;
  v_round        text;
begin
  select status, kickoff_time, round
    into v_status, v_kickoff_time, v_round
    from public.matches
   where id = new.match_id;

  if not found then
    raise exception 'match % does not exist', new.match_id;
  end if;

  -- Booster round must match the match's round
  if v_round != new.round then
    raise exception
      'booster round % does not match match round %',
      new.round, v_round
      using errcode = 'check_violation';
  end if;

  -- Reject if match is no longer in its pre-kickoff window
  if v_status != 'scheduled' or
     (v_kickoff_time is not null and v_kickoff_time <= now())
  then
    raise exception
      'booster cannot be applied to match % (status=%, kickoff=%)',
      new.match_id, v_status, v_kickoff_time
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger round_boosters_lock_check
  before insert or update
  on public.round_boosters
  for each row
  execute function public.check_booster_lock();
