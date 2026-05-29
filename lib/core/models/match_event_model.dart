class MatchEventModel {
  final int id;
  final int matchId;
  final int? minute;
  final String? type;
  final int? teamId;
  final int? playerId;
  final String? playerName;
  final String? detail;
  final DateTime? createdAt;

  /// Display code for the team (populated via a join; not a DB column).
  final String? teamCode;

  const MatchEventModel({
    required this.id,
    required this.matchId,
    this.minute,
    this.type,
    this.teamId,
    this.playerId,
    this.playerName,
    this.detail,
    this.createdAt,
    this.teamCode,
  });

  factory MatchEventModel.fromJson(Map<String, dynamic> json) {
    String? resolveTeamCode() {
      final team = json['team'];
      if (team is Map<String, dynamic>) {
        return team['code'] as String?;
      }
      return null;
    }

    return MatchEventModel(
      id: (json['id'] as num).toInt(),
      matchId: (json['match_id'] as num).toInt(),
      minute: (json['minute'] as num?)?.toInt(),
      type: json['type'] as String?,
      teamId: (json['team_id'] as num?)?.toInt(),
      playerId: (json['player_id'] as num?)?.toInt(),
      playerName: json['player_name'] as String?,
      detail: json['detail'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      teamCode: resolveTeamCode(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'match_id': matchId,
        'minute': minute,
        'type': type,
        'team_id': teamId,
        'player_id': playerId,
        'player_name': playerName,
        'detail': detail,
        'created_at': createdAt?.toIso8601String(),
      };
}
