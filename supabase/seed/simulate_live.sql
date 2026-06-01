-- ============================================================
-- Live match simulation
-- Run each STEP block in the Supabase SQL editor while the
-- app is open with kUseMockData = false.
--
-- Teams used (real IDs from seed):
--   Argentina (id=13, Group D)
--   Brazil    (id=17, Group E)
--
-- Expected app behaviour per step is noted in comments.
-- Run CLEANUP at the end to remove all test data.
-- ============================================================

-- ============================================================
-- STEP 0 — Setup: insert the match in a scheduled state.
-- App: appears in Fixtures under "Group Stage" tab.
-- ============================================================
INSERT INTO public.matches
  (id, round, group_letter, team1_id, team2_id, kickoff_time, status)
VALUES
  (999001, 'Matchday 1', 'D', 13, 17,
   now() - interval '35 minutes',   -- kicked off 35 min ago
   'scheduled')
ON CONFLICT (id) DO UPDATE SET
  round        = EXCLUDED.round,
  team1_id     = EXCLUDED.team1_id,
  team2_id     = EXCLUDED.team2_id,
  kickoff_time = EXCLUDED.kickoff_time,
  status       = EXCLUDED.status;


-- ============================================================
-- STEP 1 — Kickoff: set status → live, score 0-0.
-- App: match appears in the home live strip immediately
--      (realtime channel fires → _liveMatchesProvider invalidated).
--      Fixtures row shows LIVE badge.
--      Match detail hero shows 0 – 0 with pulsing LIVE chip.
-- ============================================================
UPDATE public.matches SET
  status        = 'live',
  score_ft_team1 = 0,
  score_ft_team2 = 0,
  updated_at    = now()
WHERE id = 999001;


-- ============================================================
-- STEP 2 — Goal! Argentina scores at 23'.
-- App: match detail events timeline gains a new goal row
--      (matchEventsStreamProvider pushes the insert).
--      Hero score updates to 1 – 0 via matchLiveStateProvider.
-- ============================================================
UPDATE public.matches SET
  score_ft_team1 = 1,
  updated_at    = now()
WHERE id = 999001;

INSERT INTO public.match_events
  (match_id, minute, type, team_id, player_name)
VALUES
  (999001, 23, 'goal', 13, 'L. Messi');


-- ============================================================
-- STEP 3 — Yellow card for Brazil at 31'.
-- App: card event appears on the timeline with yellow badge.
-- ============================================================
INSERT INTO public.match_events
  (match_id, minute, type, team_id, player_name, detail)
VALUES
  (999001, 31, 'card', 17, 'V. Jr.', 'yellow');


-- ============================================================
-- STEP 4 — Brazil equalises at 55'.
-- App: score updates to 1 – 1 in real time.
--      New goal event pushed to timeline.
-- ============================================================
UPDATE public.matches SET
  score_ft_team2 = 1,
  updated_at    = now()
WHERE id = 999001;

INSERT INTO public.match_events
  (match_id, minute, type, team_id, player_name)
VALUES
  (999001, 55, 'goal', 17, 'Rodrygo');


-- ============================================================
-- STEP 5 — Argentina winner at 88'.
-- App: score ticks to 2 – 1.
-- ============================================================
UPDATE public.matches SET
  score_ft_team1 = 2,
  updated_at    = now()
WHERE id = 999001;

INSERT INTO public.match_events
  (match_id, minute, type, team_id, player_name)
VALUES
  (999001, 88, 'goal', 13, 'J. Álvarez');


-- ============================================================
-- STEP 6 — Full time: status → final, half-time scores stored.
-- App: LIVE chip → FT badge.
--      DB trigger fires compute_match_scoring() immediately.
--      Any user with a prediction on this match gets points.
--      group_standings materialized view refreshes.
--      Leaderboard tab in Groups shows updated totals.
-- ============================================================
UPDATE public.matches SET
  status         = 'final',
  score_ft_team1 = 2,
  score_ft_team2 = 1,
  score_ht_team1 = 1,
  score_ht_team2 = 0,
  updated_at     = now()
WHERE id = 999001;


-- ============================================================
-- CLEANUP — run after you're done testing.
-- Deletes the test match and all its events.
-- Scoring rows for this match_id are also removed via CASCADE.
-- ============================================================
DELETE FROM public.match_events WHERE match_id = 999001;
DELETE FROM public.matches       WHERE id      = 999001;
