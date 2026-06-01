# World Cup Prediction App - Rules & Scoring

## Overview

Players earn points by predicting match results, goalscorers, and tournament outcomes.

All predictions are optional.

Predictions may be edited until they are locked.

---

# Match Result Scoring

Match result points are mutually exclusive.

Award only the highest matching category.

| Condition                       | Points |
| ------------------------------- | ------ |
| Exact Score                     | 5      |
| Correct Goal Difference         | 3      |
| Correct Outcome (Win/Loss/Draw) | 2      |
| Incorrect Prediction            | 0      |

Examples:

| Prediction | Result | Points |
| ---------- | ------ | ------ |
| 2-1        | 2-1    | 5      |
| 3-1        | 4-2    | 3      |
| 2-1        | 1-0    | 2      |
| 1-1        | 2-2    | 2      |
| 0-2        | 1-1    | 0      |

---

# First Team to Score

Players may optionally pick which team scores the first goal in regular time.

| Condition                                | Points |
| ---------------------------------------- | ------ |
| Picked team scores the first regular-time goal | 2 |
| Otherwise                                | 0      |

Rules:

* One first-team pick per match.
* The pick is independent of the match-result and goalscorer points (additive).
* Own goals do not count toward "first goal".
* Shootout kicks do not count.
* Goals after the 90-minute mark (extra time) do not count.
* The pick is locked at kickoff alongside the other predictions.

---
# Goalscorer Prediction

Players may optionally select one goalscorer per match.

| Condition                                | Points |
| ---------------------------------------- | ------ |
| Selected player scores at least one goal | 8      |
| Otherwise                                | 0      |

Rules:

* One goalscorer prediction per match.
* The selected player does not need to score first.
* The selected player does not need to start the match.
* Own goals do not count.
* Official FIFA goalscorer data is the source of truth.
* Goalscorer points are independent from match result points.

---

# Maximum Match Score

| Category           | Points |
| ------------------ | ------ |
| Exact Score        | 5      |
| First Team to Score | 2     |
| Goalscorer         | 8      |

Maximum possible score per match:

15 Points

---

# Prediction Rules

All predictions are optional.

A player may submit:

* Match result prediction only
* First-team-to-score prediction only
* Goalscorer prediction only
* Any combination of the three
* Neither prediction

Examples:

| Match | First Team | Goalscorer | Valid |
| ----- | ---------- | ---------- | ----- |
| Yes   | Yes        | Yes        | Yes   |
| Yes   | No         | Yes        | Yes   |
| No    | Yes        | No         | Yes   |
| No    | No         | No         | Yes   |

---

# First-Team & Goalscorer UI Rules

First-team-to-score and goalscorer selection become available only after a score prediction is selected.

First-team chips:

* Both chips are visible whenever the predicted score is non-zero.
* A chip is selectable only when that team's predicted score is greater than zero (otherwise it is dimmed).
* Selection is optional — neither chip is preselected.

Available goalscorers depend on the predicted score:

* If only Team A is predicted to score, show Team A players only.
* If only Team B is predicted to score, show Team B players only.
* If both teams are predicted to score, show players from both teams.
* If predicted score is 0-0, goalscorer selection is unavailable.

---

# Match Evaluation

All predictions are evaluated using the score after regular time only.

Included:

* 90 minutes
* Stoppage time

Ignored:

* Extra time
* Penalty shootouts

Example:

Prediction:
1-1

Actual Match:

* 1-1 after 90 minutes
* 2-1 after extra time

The prediction is evaluated against the 1-1 result.

---

# Group Stage

Group stage matches use the standard scoring system.

No boosters are available.

---

# Knockout Stage Boosters

Each player receives one booster per knockout round.

Manual boosters are available for:

| Round        | Multiplier |
| ------------ | ---------- |
| Round of 32  | 2x         |
| Round of 16  | 3x         |
| Quarterfinal | 4x         |
| Semifinal    | 5x         |

Rules:

* One booster per round.
* Booster may be applied to one match only.
* Booster must be selected before kickoff.
* Unused boosters expire when the round ends.
* Only one booster can be active on a prediction.

---

# Automatic Multipliers

The final two matches receive automatic multipliers.

No manual booster selection is available.

| Match             | Multiplier |
| ----------------- | ---------- |
| Third Place Match | 5x         |
| Final             | 6x         |

These multipliers are automatically applied to all predictions.

---

# Tournament Predictions

Tournament predictions must be submitted before the opening match of the tournament.

After the tournament begins, these predictions are locked.

## World Cup Winner

Predict the team that will win the FIFA World Cup.

| Condition                | Points |
| ------------------------ | ------ |
| Correct World Cup Winner | 75     |

Notes:

* Official FIFA tournament winner is used.
* Prediction must be submitted before the tournament starts.

---

## Golden Boot Winner

Predict the player who finishes the tournament as the Golden Boot winner.

| Condition                  | Points |
| -------------------------- | ------ |
| Correct Golden Boot Winner | 50     |

Notes:

* Official FIFA Golden Boot results are used.
* Prediction must be submitted before the tournament starts.

---

# Tournament Prediction Total

| Prediction         | Points |
| ------------------ | ------ |
| World Cup Winner   | 75     |
| Golden Boot Winner | 50     |

Maximum tournament prediction bonus:

125 Points

---

# Points Calculation

## Match Predictions

```text
points_match       = 0, 2, 3, or 5

points_first_team  = 0 or 2

points_goalscorer  = 0 or 8

points_base =
points_match + points_first_team + points_goalscorer

points_earned =
points_base × multiplier
```

Examples:

```text
Exact Score (5)
+
First Team to Score (2)
+
Goalscorer (8)

= 15 points
```

```text
Exact Score (5)
+
First Team to Score (2)
+
Goalscorer (8)
+
Final Multiplier (6x)

15 × 6 = 90 points
```

---

## Tournament Predictions

Tournament prediction points are added directly to the player's total score.

Examples:

```text
Correct World Cup Winner
= 75 points
```

```text
Correct Golden Boot Winner
= 50 points
```

```text
Correct World Cup Winner
+
Correct Golden Boot Winner

= 125 points
```

---

# Official Data

All scoring uses official FIFA data.

This includes:

* Match results
* Full-time scores
* Goalscorers
* Own goal attribution
* Tournament winner
* Golden Boot winner

If FIFA later updates official records, scoring should be recalculated using the updated data.

---

# New Players

Players may join the competition at any time.

New players start with 0 points and only receive points for future matches.

---

# Prediction Locking

Predictions remain editable until they are locked.

## Match Predictions

The following lock at kickoff:

* Match result prediction
* First-team-to-score prediction
* Goalscorer prediction
* Booster selection

No further changes are allowed after kickoff.

## Tournament Predictions

The following lock at the start of the opening match:

* World Cup Winner
* Golden Boot Winner

No further changes are allowed after the tournament begins.

