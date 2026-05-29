class ProfileModel {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? createdAt;

  const ProfileModel({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.createdAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'created_at': createdAt?.toIso8601String(),
      };
}
