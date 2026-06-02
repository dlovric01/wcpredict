/// Canonical scoring & multiplier constants for the prediction game.
///
/// Single source of truth referenced by:
///   • `MatchModel.autoMultiplier` / `boosterMultiplier` getters
///   • `RulesScreen` and contextual info sheets
///   • The SQL scoring engine (mirrored in migrations 017 / 022 / 026)
///
/// Tests in `test/core/scoring_rules_test.dart` lock cross-file invariants
/// — e.g. the sum of category maxima equals `kPointsMaxBase`, and the
/// model's per-round multipliers match the values declared here.
library;

// ─── Per-match point categories ──────────────────────────────────────────────

/// Exact final score (e.g. predict 2-1, actual 2-1).
const int kPointsExact = 5;

/// Correct goal difference with |GD| ≥ 2 (e.g. predict 3-1, actual 4-2).
const int kPointsGoalDiff = 3;

/// Correct outcome only — win / draw / loss matches, but score does not.
const int kPointsOutcome = 2;

/// First-team-to-score bonus when the picked team scores the first
/// regular-time non-own-goal (minute ≤ 90).
const int kPointsFirstTeam = 2;

/// Goalscorer bonus when the selected player scores ≥1 non-own-goal in
/// regulation time.
const int kPointsGoalscorer = 8;

/// Maximum base points per match (before any multiplier).
///   exact + first-team + goalscorer
const int kPointsMaxBase =
    kPointsExact + kPointsFirstTeam + kPointsGoalscorer; // 15

// ─── Tournament-level bonuses ────────────────────────────────────────────────

/// Awarded for correctly predicting the World Cup winner.
const int kPointsWorldCupWinner = 75;

/// Awarded for correctly predicting the Golden Boot winner.
const int kPointsGoldenBoot = 50;

/// Maximum tournament-prediction bonus across the tournament.
const int kPointsMaxTournament =
    kPointsWorldCupWinner + kPointsGoldenBoot; // 125

// ─── Multipliers ─────────────────────────────────────────────────────────────

/// Manual round boosters (one applicable match per knockout round).
const Map<String, int> kBoosterMultipliers = {
  'R32': 2,
  'R16': 3,
  'QF': 4,
  'SF': 5,
};

/// Automatic multipliers — applied to every prediction in these rounds.
const Map<String, int> kAutoMultipliers = {
  '3rd': 5,
  'Final': 6,
};
