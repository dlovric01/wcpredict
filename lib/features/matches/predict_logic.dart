// Pure logic for the predict tab — extracted so it can be unit-tested
// without spinning up a widget tree.
//
// Two responsibilities:
//   1. `predictTabLocked` — decides whether the predict form should render
//      its locked card based on the match model + a (potentially fresher)
//      live-streamed status row.
//   2. `sanitisePredictionPicks` — enforces the client-side mirror of the
//      DB validation triggers: a 0-0 prediction has no bonus picks, and a
//      first-team pick on a 0-scoring team is dropped.
//
// Mirrors the server-side rules from migration 022.

import 'package:wcpredict/core/models/match_model.dart';

/// Returns `true` when the predict form must render in its locked state.
///
/// A match is locked when either:
///   * The (cached) [match] is already locked — kickoff passed, status
///     advanced past `scheduled`, or status is `cancelled`.
///   * The live-streamed overlay row ([liveOverlay]) reports a non-scheduled
///     status. This handles the mid-session race where Realtime delivers
///     `status='live'` before the next match query refresh.
bool predictTabLocked(MatchModel match, MatchModel? liveOverlay) {
  if (match.isLocked) return true;
  final s = liveOverlay?.status;
  return s == 'live' || s == 'final' || s == 'cancelled';
}

/// Result of [sanitisePredictionPicks]. The score fields are pass-through;
/// the bonus picks may be cleared.
class SanitisedPicks {
  const SanitisedPicks({
    required this.firstTeamId,
    required this.scorerId,
  });

  final int? firstTeamId;
  final int? scorerId;

  @override
  bool operator ==(Object other) =>
      other is SanitisedPicks &&
      other.firstTeamId == firstTeamId &&
      other.scorerId == scorerId;

  @override
  int get hashCode => Object.hash(firstTeamId, scorerId);

  @override
  String toString() =>
      'SanitisedPicks(firstTeamId: $firstTeamId, scorerId: $scorerId)';
}

/// Drops bonus picks that would be rejected by the DB validation trigger:
///   * 0-0 score → both bonus picks cleared.
///   * `firstTeamId` matches a team whose predicted score is 0 → cleared.
///
/// Goalscorer's "scorer's team predicted to score 0" is enforced only by
/// the server (the UI doesn't track the scorer's team here — it lives in
/// the player roster). The DB trigger handles that case.
SanitisedPicks sanitisePredictionPicks({
  required int score1,
  required int score2,
  required int? firstTeamId,
  required int? scorerId,
  required int? team1Id,
  required int? team2Id,
}) {
  if (score1 == 0 && score2 == 0) {
    return const SanitisedPicks(firstTeamId: null, scorerId: null);
  }
  int? sanitisedFirstTeam = firstTeamId;
  if (sanitisedFirstTeam != null) {
    if (sanitisedFirstTeam == team1Id && score1 == 0) sanitisedFirstTeam = null;
    if (sanitisedFirstTeam == team2Id && score2 == 0) sanitisedFirstTeam = null;
  }
  return SanitisedPicks(firstTeamId: sanitisedFirstTeam, scorerId: scorerId);
}
