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
}
