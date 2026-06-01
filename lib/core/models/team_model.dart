import 'package:flutter/foundation.dart' show listEquals;

import 'player_model.dart';

class TeamModel {
  final int id;
  final String name;
  final String code;
  final String? flagUrl;
  final String? groupLetter;
  final List<PlayerModel>? players;

  const TeamModel({
    required this.id,
    required this.name,
    required this.code,
    this.flagUrl,
    this.groupLetter,
    this.players,
  });

  factory TeamModel.fromJson(Map<String, dynamic> json) {
    final rawPlayers = json['players'];
    return TeamModel(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      code: (json['code'] as String?) ?? '',
      flagUrl: json['flag_url'] as String?,
      groupLetter: json['group_letter'] as String?,
      players: rawPlayers is List
          ? rawPlayers
              .map((p) => PlayerModel.fromJson(p as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'flag_url': flagUrl,
        'group_letter': groupLetter,
      };

  // Value equality. `players` uses `listEquals` so a re-fetch that
  // returns the same lineup compares equal even though the inner List
  // is a new instance.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamModel &&
          id == other.id &&
          name == other.name &&
          code == other.code &&
          flagUrl == other.flagUrl &&
          groupLetter == other.groupLetter &&
          listEquals(players, other.players);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        code,
        flagUrl,
        groupLetter,
        players == null ? null : Object.hashAll(players!),
      );
}
