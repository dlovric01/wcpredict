// Pure-Dart mirror of the `compute_match_scoring` SQL function from
// migration 022, used by the OTHERS tab on the match detail screen to
// preview points while a match is still in play.
//
// Live preview and final settlement MUST stay in lockstep. Tests in
// `test/features/live_scoring_test.dart` lock the parity. If you touch
// either side, update both and re-run those tests.

import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/scoring_rules.dart';

/// Result of evaluating a prediction against a match's current (live) or
/// final state.
///
/// All three category points are mutually independent and additive at the
/// `base` layer. `multiplier` is applied at the very end so the same
/// formula handles unboosted group-stage matches (×1), manually-boosted
/// knockout matches, and auto-multiplied 3rd/Final matches.
class LiveScore {
  /// Match result, mutually exclusive: 0 / 2 / 3 / 5.
  final int pointsMatch;

  /// First team to score bonus: 0 / 2.
  final int pointsFirstTeam;

  /// Goalscorer bonus: 0 / 8.
  final int pointsGoalscorer;

  /// Effective multiplier for this match × user pair (booster or auto).
  final int multiplier;

  const LiveScore({
    required this.pointsMatch,
    required this.pointsFirstTeam,
    required this.pointsGoalscorer,
    required this.multiplier,
  });

  /// Sum of mutually-exclusive match category + independent bonuses
  /// (0..15) before multiplier.
  int get base => pointsMatch + pointsFirstTeam + pointsGoalscorer;

  /// Final points = `base × multiplier`. Matches `points_earned` from the
  /// SQL engine for `status = 'final'` rows.
  int get total => base * multiplier;
}

/// Compute live (or final) points for a single prediction against a
/// match's current state.
///
/// Branches mirror migration 022's `compute_match_scoring` exactly:
///
///   * `pointsMatch`: exact (5) → goal-diff with |GD|≥2 (3) → outcome (2) → 0.
///     Returns 0 when either side of the prediction is null.
///   * `pointsFirstTeam`: 2 when the earliest non-OG goal in `events` with
///     `minute <= 90` is on the predicted team; 0 when no pick or no goal
///     in regulation yet.
///   * `pointsGoalscorer`: 8 when any non-OG goal event with `minute <= 90`
///     is by `predictedScorerId`; 0 otherwise.
///   * `multiplier`: caller-resolved (booster row for R32-SF, auto for
///     3rd / Final, 1 otherwise).
///
/// For live matches the SQL function is short-circuited (`status != 'final'`),
/// so this helper IS the only source of truth pre-FT.
LiveScore computeLiveScore({
  required MatchModel match,
  required PredictionModel prediction,
  required List<MatchEventModel> events,
  required int multiplier,
}) {
  // ── Match result ──────────────────────────────────────────────────────
  final pt1 = prediction.predictedTeam1;
  final pt2 = prediction.predictedTeam2;
  final ft1 = match.scoreFtTeam1 ?? 0;
  final ft2 = match.scoreFtTeam2 ?? 0;

  int pointsMatch;
  if (pt1 == null || pt2 == null) {
    pointsMatch = 0;
  } else if (pt1 == ft1 && pt2 == ft2) {
    pointsMatch = kPointsExact; // 5
  } else if ((pt1 - pt2) == (ft1 - ft2) && (ft1 - ft2).abs() >= 2) {
    pointsMatch = kPointsGoalDiff; // 3
  } else if ((pt1 > pt2 && ft1 > ft2) ||
      (pt1 < pt2 && ft1 < ft2) ||
      (pt1 == pt2 && ft1 == ft2)) {
    pointsMatch = kPointsOutcome; // 2
  } else {
    pointsMatch = 0;
  }

  // ── First team to score ───────────────────────────────────────────────
  // Earliest non-OG, non-shootout regular-time goal. SQL `order by
  // minute asc, id asc` ties → we mirror it for parity.
  int pointsFirstTeam = 0;
  final firstTeamPick = prediction.predictedFirstTeamId;
  if (firstTeamPick != null) {
    MatchEventModel? earliest;
    for (final e in events) {
      if (e.type != 'goal') continue;
      if (e.detail == 'own_goal') continue;
      final m = e.minute;
      if (m == null || m > 90) continue;
      if (earliest == null) {
        earliest = e;
        continue;
      }
      final em = earliest.minute ?? 0;
      if (m < em || (m == em && e.id < earliest.id)) earliest = e;
    }
    if (earliest != null && earliest.teamId == firstTeamPick) {
      pointsFirstTeam = kPointsFirstTeam; // 2
    }
  }

  // ── Goalscorer ────────────────────────────────────────────────────────
  int pointsGoalscorer = 0;
  final scorerPick = prediction.predictedScorerId;
  if (scorerPick != null) {
    for (final e in events) {
      if (e.type != 'goal') continue;
      if (e.detail == 'own_goal') continue;
      final m = e.minute;
      if (m == null || m > 90) continue;
      if (e.playerId == scorerPick) {
        pointsGoalscorer = kPointsGoalscorer; // 8
        break;
      }
    }
  }

  return LiveScore(
    pointsMatch: pointsMatch,
    pointsFirstTeam: pointsFirstTeam,
    pointsGoalscorer: pointsGoalscorer,
    multiplier: multiplier,
  );
}
