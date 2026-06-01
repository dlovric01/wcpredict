class MatchEventModel {
  final int id;
  final int matchId;
  final int? minute;
  /// Stoppage time addition from api-sports.io `time.extra`.
  /// Non-null when the event occurred during stoppage time (e.g. 3 for "90+3").
  final int? minuteExtra;
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
    this.minuteExtra,
    this.type,
    this.teamId,
    this.playerId,
    this.playerName,
    this.detail,
    this.createdAt,
    this.teamCode,
  });

  /// Display string for the minute, e.g. "90+13'" or "45'".
  String get minuteLabel {
    if (minute == null) return '—';
    if (minuteExtra != null && minuteExtra! > 0) {
      return '$minute+$minuteExtra\'';
    }
    return '$minute\'';
  }

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
      minuteExtra: (json['minute_extra'] as num?)?.toInt(),
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
        'minute_extra': minuteExtra,
        'type': type,
        'team_id': teamId,
        'player_id': playerId,
        'player_name': playerName,
        'detail': detail,
        'created_at': createdAt?.toIso8601String(),
      };
}
