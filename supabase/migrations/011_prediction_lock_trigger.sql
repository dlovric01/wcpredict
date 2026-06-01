-- ============================================================
-- Migration 011: Enforce prediction lock at the DB layer
-- ============================================================
--
-- Problem: the RLS policy predictions_own_rw grants full write
-- access to a user's own rows with no check on match state.
-- A user can call the API directly (bypassing UI) to insert or
-- update a prediction after a match has kicked off, and
-- compute_match_scoring() will award points for it.
--
-- Fix: a BEFORE INSERT OR UPDATE trigger that aborts writes to
-- the prediction fields whenever the match is no longer
-- schedulable (status != 'scheduled' OR kickoff_time <= now()).
--
-- Scope is intentionally narrow — only the four prediction
-- payload columns are watched. Writes to locked_at,
-- points_score, points_first_team, points_scorer, points_earned,
-- updated_at, etc. pass through unaffected, so lock_predictions
-- and compute_match_scoring continue to work.
-- ============================================================

CREATE OR REPLACE FUNCTION public.check_prediction_lock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_status       text;
  v_kickoff_time timestamptz;
BEGIN
  SELECT status, kickoff_time
    INTO v_status, v_kickoff_time
    FROM public.matches
   WHERE id = NEW.match_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'match % does not exist', NEW.match_id;
  END IF;

  -- Reject if match is no longer in its pre-kickoff window.
  -- Two independent conditions, either is sufficient to lock:
  --   1. Status has advanced past 'scheduled' (live / final / cancelled).
  --   2. Wall clock has passed the scheduled kickoff time.
  IF v_status != 'scheduled' OR
     (v_kickoff_time IS NOT NULL AND v_kickoff_time <= now())
  THEN
    RAISE EXCEPTION
      'predictions are locked for match % (status=%, kickoff=%)',
      NEW.match_id, v_status, v_kickoff_time
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- Fire on INSERT and on UPDATE of only the prediction payload columns.
-- Updates to points, locked_at, updated_at are excluded from the trigger
-- so the scoring function and lock function are unaffected.
CREATE TRIGGER predictions_lock_check
  BEFORE INSERT
     OR UPDATE OF predicted_team1,
                  predicted_team2,
                  predicted_first_team_id,
                  predicted_scorer_id
  ON public.predictions
  FOR EACH ROW
  EXECUTE FUNCTION public.check_prediction_lock();
