class PredictionModel {
  final String id;
  final String userId;
  final int matchId;
  final int? predictedTeam1;
  final int? predictedTeam2;
  final int? predictedFirstTeamId;
  final int? predictedScorerId;
  final int? pointsScore;
  final int? pointsFirstTeam;
  final int? pointsScorer;
  final int? pointsEarned;
  final DateTime? lockedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PredictionModel({
    required this.id,
    required this.userId,
    required this.matchId,
    this.predictedTeam1,
    this.predictedTeam2,
    this.predictedFirstTeamId,
    this.predictedScorerId,
    this.pointsScore,
    this.pointsFirstTeam,
    this.pointsScorer,
    this.pointsEarned,
    this.lockedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory PredictionModel.fromJson(Map<String, dynamic> json) {
    return PredictionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      matchId: (json['match_id'] as num).toInt(),
      predictedTeam1: (json['predicted_team1'] as num?)?.toInt(),
      predictedTeam2: (json['predicted_team2'] as num?)?.toInt(),
      predictedFirstTeamId: (json['predicted_first_team_id'] as num?)?.toInt(),
      predictedScorerId: (json['predicted_scorer_id'] as num?)?.toInt(),
      pointsScore: (json['points_score'] as num?)?.toInt(),
      pointsFirstTeam: (json['points_first_team'] as num?)?.toInt(),
      pointsScorer: (json['points_scorer'] as num?)?.toInt(),
      pointsEarned: (json['points_earned'] as num?)?.toInt(),
      lockedAt: json['locked_at'] != null
          ? DateTime.parse(json['locked_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'match_id': matchId,
        'predicted_team1': predictedTeam1,
        'predicted_team2': predictedTeam2,
        'predicted_first_team_id': predictedFirstTeamId,
        'predicted_scorer_id': predictedScorerId,
        'points_score': pointsScore,
        'points_first_team': pointsFirstTeam,
        'points_scorer': pointsScorer,
        'points_earned': pointsEarned,
        'locked_at': lockedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}
