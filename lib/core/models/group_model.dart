class GroupModel {
  final String id;
  final String name;
  final String ownerId;
  final String? inviteCode;
  final DateTime? createdAt;

  const GroupModel({
    required this.id,
    required this.name,
    required this.ownerId,
    this.inviteCode,
    this.createdAt,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      inviteCode: json['invite_code'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'owner_id': ownerId,
        'invite_code': inviteCode,
        'created_at': createdAt?.toIso8601String(),
      };
}

class GroupMemberModel {
  final String groupId;
  final String userId;
  final DateTime? joinedAt;

  const GroupMemberModel({
    required this.groupId,
    required this.userId,
    this.joinedAt,
  });

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'user_id': userId,
        'joined_at': joinedAt?.toIso8601String(),
      };
}
