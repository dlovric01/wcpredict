-- ============================================================
-- Migration 020: Add WHERE clause to compute_tournament_scoring
-- ============================================================
-- Supabase enables sql_safe_updates which rejects UPDATEs without a
-- WHERE clause. The previous version of this function in 018 updated
-- every row implicitly, which trips that check when the trigger fires.
-- Add an explicit `WHERE TRUE` to make the intent (touch all rows)
-- pass the safety filter.
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
    updated_at = now()
  where true;

  refresh materialized view concurrently public.group_standings;
  return new;
end;
$$;
