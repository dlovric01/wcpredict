/// User prediction for a single match.
///
/// Match-result scoring (rules.md) is **mutually exclusive** — `pointsMatch`
/// holds the single awarded value:
///
/// | Outcome                          | `pointsMatch` |
/// |----------------------------------|---------------|
/// | Exact final score                | `5`           |
/// | Correct goal difference (|GD|≥2) | `3`           |
/// | Correct outcome (W/D/L)          | `2`           |
/// | Wrong / no prediction            | `0`           |
///
/// First-team and goalscorer are independent and additive:
///   `pointsFirstTeam`  is `0` or `2`
///   `pointsGoalscorer` is `0` or `8`
/// `pointsBase = pointsMatch + pointsFirstTeam + pointsGoalscorer` (0..15);
/// `pointsEarned = pointsBase * multiplier`.
class PredictionModel {
  final String id;
  final String userId;
  final int matchId;
  final int? predictedTeam1;
  final int? predictedTeam2;
  final int? predictedFirstTeamId;
  final int? predictedScorerId;
  // Scoring (computed at FT — rules.md)
  final int? pointsMatch;       // 0 | 2 | 3 | 5
  final int? pointsFirstTeam;   // 0 | 2
  final int? pointsGoalscorer;  // 0 | 8
  final int? multiplier;        // 1..6
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
    this.pointsMatch,
    this.pointsFirstTeam,
    this.pointsGoalscorer,
    this.multiplier,
    this.pointsEarned,
    this.lockedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Sum of match + first-team + goalscorer points before multiplier (0..15).
  int get basePoints =>
      (pointsMatch ?? 0) + (pointsFirstTeam ?? 0) + (pointsGoalscorer ?? 0);

  /// True when the match-result category awarded was exact (5 pts).
  bool get isExact => (pointsMatch ?? 0) == 5;

  /// True when the awarded category was goal-difference (3 pts).
  bool get isGoalDiff => (pointsMatch ?? 0) == 3;

  /// True when the awarded category was outcome-only (2 pts).
  bool get isOutcome => (pointsMatch ?? 0) == 2;

  /// True when the goalscorer prediction was correct (8 pts).
  bool get goalscorerHit => (pointsGoalscorer ?? 0) == 8;

  /// True when the first-team-to-score prediction was correct (2 pts).
  bool get firstTeamHit => (pointsFirstTeam ?? 0) == 2;

  factory PredictionModel.fromJson(Map<String, dynamic> json) {
    return PredictionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      matchId: (json['match_id'] as num).toInt(),
      predictedTeam1: (json['predicted_team1'] as num?)?.toInt(),
      predictedTeam2: (json['predicted_team2'] as num?)?.toInt(),
      predictedFirstTeamId: (json['predicted_first_team_id'] as num?)?.toInt(),
      predictedScorerId: (json['predicted_scorer_id'] as num?)?.toInt(),
      pointsMatch: (json['points_match'] as num?)?.toInt(),
      pointsFirstTeam: (json['points_first_team'] as num?)?.toInt(),
      pointsGoalscorer: (json['points_goalscorer'] as num?)?.toInt(),
      multiplier: (json['multiplier'] as num?)?.toInt(),
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
        'points_match': pointsMatch,
        'points_first_team': pointsFirstTeam,
        'points_goalscorer': pointsGoalscorer,
        'multiplier': multiplier,
        'points_earned': pointsEarned,
        'locked_at': lockedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}
