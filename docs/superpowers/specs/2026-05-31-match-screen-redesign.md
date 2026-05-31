# Match Screen Redesign

**Date:** 2026-05-31  
**Status:** Approved

---

## Problem

The current match detail screen uses a `DraggableScrollableSheet` (bottom modal) for prediction entry. The modal contains a fixed score picker at the top and a scrollable list (first scorer + goalscorer picker) below — scroll-inside-a-draggable-sheet, which conflicts with the sheet drag gesture. The screen also lacks clear structure for the multiple concerns it needs to handle: match context, prediction, lineups, and events.

---

## Solution

Replace the single-scroll screen + modal with a **tabbed full-screen layout**. Three tabs, always the same names, content adapts per match state. The `predict_modal.dart` file is deleted entirely.

---

## Tab Structure

### Always visible (above tabs)
A **hero card** pinned above the tab bar at all times:
- Both team flags, names, codes
- Kickoff time (scheduled) or live score with HT score below (live/final)  
- Status chip top-right: `KO HH:MM` (scheduled) / `● LIVE` pulsing (live) / `FT` (final)

### Tab 1 — OVERVIEW

| State | Content |
|---|---|
| Scheduled | Match info card (venue, group/round, kickoff date+time) + prediction summary card (your current pick, or a CTA linking to the Predict tab if none submitted) |
| Live | Events timeline: goals, cards, subs in reverse-chronological order with minute, scorer, team, running score |
| Final | Same events timeline as live |

### Tab 2 — PREDICT

| State | Content |
|---|---|
| Scheduled (unlocked) | Score picker → First team to score (segmented button) → Goalscorer search + player chips → pinned Save/Update button |
| Live / Final (locked) | Locked banner ("Predictions locked · match has started") + result comparison card (Actual vs You scores side by side) + points verdict pill. For final: full points breakdown by category. |

The Predict tab is the **default tab** when navigating to a match that has no prediction yet and is still scheduled. For all other states the default tab is Overview.

### Tab 3 — TEAMS

Same content regardless of match state:
- Formation string (e.g. 4-3-3) shown per team
- Formation pitch visualisation (existing `_FormationPitch` widget, reused)
- Player dots colour-coded by position (GK amber, DEF cobalt, MID green, FWD coral)
- Substitutes list below the pitch
- If no lineups available yet: empty state ("Lineups not yet announced")

---

## Predict Tab — Form Detail

Score picker:
- Team flag above each score box
- Large tappable number box (64 dp); tap to increment, `−` / `+` buttons row below
- Clamp 0–20
- Both pickers visible at once, no scroll required

First team to score:
- `SegmentedButton` with team 1 | team 2
- Hidden when score is 0–0 (both zero → first scorer irrelevant)
- Auto-cleared when score resets to 0–0

Goalscorer:
- Text field (search/filter)
- Player chips in a `Wrap` — team 1 players first, then team 2, with a team name label above each group
- One chip selected at a time; tapping selected chip deselects
- Hidden when score is 0–0

Save button:
- Pinned at the bottom (outside scroll)
- Disabled while `_saving` or locked
- Label: "Save Prediction" (new) / "Update Prediction" (existing)
- On success: invalidate `myPredictionProvider(matchId)`, switch tab to Overview, haptic

---

## File Changes

### New file
`lib/features/matches/match_detail_screen.dart` — full replacement. The tabbed screen is implemented here. All private widgets stay in this file.

### Deleted file
`lib/features/matches/predict_modal.dart` — removed entirely. `showPredictModal` no longer exists.

### Updated files
- `lib/features/matches/match_detail_screen.dart` — entire file replaced
- All callsites of `showPredictModal` removed (currently only called from within `match_detail_screen.dart` itself — no other callers)

### Unchanged
- `lib/features/matches/live_events_widget.dart` — reused as-is on Overview tab for live/final
- `lib/shared/providers/predictions_provider.dart` — unchanged
- `lib/shared/providers/match_detail_provider.dart` — unchanged
- `lib/shared/widgets/verdict_pill.dart` — reused on Predict tab locked state
- All models, providers, Supabase queries — unchanged

---

## Default Tab Logic

```
// myPredictionProvider is AsyncValue — resolve before setting initial tab
// While loading: default Overview (index 0)
// On data:
//   !match.isLocked && prediction == null → Predict (index 1)
//   all other cases                       → Overview (index 0)
```

Tab index is set once in `initState` after the first non-loading value arrives from `myPredictionProvider`. It is never reset after that — the user controls the tab freely.

---

## State Transitions

- The tab bar and hero card are stateless — they read from the same `matchByIdProvider` and `myPredictionProvider` that already exist.
- No new providers needed.
- After save: `ref.invalidate(myPredictionProvider(matchId))` + `ref.invalidate(matchByIdProvider(matchId))` — existing pattern.
- Live updates: existing `matchLiveStateProvider` Realtime subscription continues to drive the hero score.

---

## Acceptance Criteria

1. No scroll-inside-scroll anywhere on the screen.
2. Prediction form is fully usable on the Predict tab for scheduled matches.
3. Locked state (live/final) shows result comparison and points on Predict tab.
4. Overview tab shows match info + prediction summary for scheduled; events timeline for live/final.
5. Teams tab shows formation pitch and players in all states; shows empty state if no lineups.
6. Default tab is Predict when match is scheduled and user has no prediction; Overview otherwise.
7. Save/Update works identically to current implementation (same Supabase upsert, same invalidation).
8. `predict_modal.dart` is deleted; no references to `showPredictModal` remain.
9. `flutter analyze` passes with no new warnings.
