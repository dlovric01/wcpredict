class RoundBoosterModel {
  final String userId;
  final String round;
  final int matchId;
  final int multiplier;
  final DateTime? createdAt;

  const RoundBoosterModel({
    required this.userId,
    required this.round,
    required this.matchId,
    required this.multiplier,
    this.createdAt,
  });

  factory RoundBoosterModel.fromJson(Map<String, dynamic> json) {
    return RoundBoosterModel(
      userId: json['user_id'] as String,
      round: json['round'] as String,
      matchId: (json['match_id'] as num).toInt(),
      multiplier: (json['multiplier'] as num).toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'round': round,
        'match_id': matchId,
        'multiplier': multiplier,
        'created_at': createdAt?.toIso8601String(),
      };
}
