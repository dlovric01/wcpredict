class GroupStandingModel {
  final String groupId;
  final String userId;
  final String? displayName;
  final int totalPoints;
  final int exactCount;
  final int correctResultCount;

  const GroupStandingModel({
    required this.groupId,
    required this.userId,
    this.displayName,
    required this.totalPoints,
    required this.exactCount,
    required this.correctResultCount,
  });

  factory GroupStandingModel.fromJson(Map<String, dynamic> json) {
    return GroupStandingModel(
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      totalPoints: (json['total_points'] as num).toInt(),
      exactCount: (json['exact_count'] as num).toInt(),
      correctResultCount: (json['correct_result_count'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'user_id': userId,
        'display_name': displayName,
        'total_points': totalPoints,
        'exact_count': exactCount,
        'correct_result_count': correctResultCount,
      };
}
