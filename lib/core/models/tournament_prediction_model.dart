/// One row per user. Filled in before the opening match kicks off; locked
/// thereafter by the `check_tournament_prediction_lock` DB trigger.
///
/// Scoring (rules.md):
///   World Cup winner   — 75 pts
///   Golden Boot winner — 50 pts
///   Max combined bonus — 125 pts
///
/// `pointsEarned` is the sum of `pointsWc + pointsGoldenBoot` and is filled
/// in when `tournament_results` is set; the bonus is added directly to the
/// player's overall total in `group_standings.total_points`.
class TournamentPredictionModel {
  final String userId;
  final int? wcWinnerTeamId;
  final int? goldenBootPlayerId;
  final int pointsWc;
  final int pointsGoldenBoot;
  final int pointsEarned;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TournamentPredictionModel({
    required this.userId,
    this.wcWinnerTeamId,
    this.goldenBootPlayerId,
    this.pointsWc = 0,
    this.pointsGoldenBoot = 0,
    this.pointsEarned = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory TournamentPredictionModel.fromJson(Map<String, dynamic> json) {
    return TournamentPredictionModel(
      userId: json['user_id'] as String,
      wcWinnerTeamId: (json['wc_winner_team_id'] as num?)?.toInt(),
      goldenBootPlayerId: (json['golden_boot_player_id'] as num?)?.toInt(),
      pointsWc: (json['points_wc'] as num? ?? 0).toInt(),
      pointsGoldenBoot: (json['points_golden_boot'] as num? ?? 0).toInt(),
      pointsEarned: (json['points_earned'] as num? ?? 0).toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'wc_winner_team_id': wcWinnerTeamId,
        'golden_boot_player_id': goldenBootPlayerId,
        'points_wc': pointsWc,
        'points_golden_boot': pointsGoldenBoot,
        'points_earned': pointsEarned,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}
