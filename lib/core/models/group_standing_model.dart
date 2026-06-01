/// One row per (group, user) in the `group_standings` materialized view.
///
/// `totalPoints` = `matchPoints + tournamentPoints`. The `*Count` columns
/// are tiebreakers, applied in order:
/// exact → scorer → firstTeam → goalDiff → outcome → earliestSubmission.
class GroupStandingModel {
  final String groupId;
  final String userId;
  final String? displayName;
  final int totalPoints;
  final int matchPoints;
  final int tournamentPoints;
  final int exactCount;
  final int scorerCount;
  final int firstTeamCount;
  final int goalDiffCount;
  final int outcomeCount;
  final DateTime? earliestSubmission;

  const GroupStandingModel({
    required this.groupId,
    required this.userId,
    this.displayName,
    required this.totalPoints,
    required this.matchPoints,
    required this.tournamentPoints,
    required this.exactCount,
    required this.scorerCount,
    required this.firstTeamCount,
    required this.goalDiffCount,
    required this.outcomeCount,
    this.earliestSubmission,
  });

  factory GroupStandingModel.fromJson(Map<String, dynamic> json) {
    return GroupStandingModel(
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      totalPoints: (json['total_points'] as num? ?? 0).toInt(),
      matchPoints: (json['match_points'] as num? ?? 0).toInt(),
      tournamentPoints: (json['tournament_points'] as num? ?? 0).toInt(),
      exactCount: (json['exact_count'] as num? ?? 0).toInt(),
      scorerCount: (json['scorer_count'] as num? ?? 0).toInt(),
      firstTeamCount: (json['first_team_count'] as num? ?? 0).toInt(),
      goalDiffCount: (json['goal_diff_count'] as num? ?? 0).toInt(),
      outcomeCount: (json['outcome_count'] as num? ?? 0).toInt(),
      earliestSubmission: json['earliest_submission'] != null
          ? DateTime.parse(json['earliest_submission'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'user_id': userId,
        'display_name': displayName,
        'total_points': totalPoints,
        'match_points': matchPoints,
        'tournament_points': tournamentPoints,
        'exact_count': exactCount,
        'scorer_count': scorerCount,
        'first_team_count': firstTeamCount,
        'goal_diff_count': goalDiffCount,
        'outcome_count': outcomeCount,
        'earliest_submission': earliestSubmission?.toIso8601String(),
      };
}
