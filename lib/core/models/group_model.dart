class GroupModel {
  final String id;
  final String name;
  final String ownerId;
  final String? inviteCode;
  final DateTime? createdAt;

  /// Total members in this group, populated by `myGroupsProvider` via a
  /// batched count query. Null when the value is not known at
  /// construction time (e.g. parsing a stand-alone row outside the
  /// groups-list flow).
  final int? memberCount;

  const GroupModel({
    required this.id,
    required this.name,
    required this.ownerId,
    this.inviteCode,
    this.createdAt,
    this.memberCount,
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
      memberCount: (json['member_count'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'owner_id': ownerId,
        'invite_code': inviteCode,
        'created_at': createdAt?.toIso8601String(),
        if (memberCount != null) 'member_count': memberCount,
      };

  GroupModel copyWith({int? memberCount}) => GroupModel(
        id: id,
        name: name,
        ownerId: ownerId,
        inviteCode: inviteCode,
        createdAt: createdAt,
        memberCount: memberCount ?? this.memberCount,
      );
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
