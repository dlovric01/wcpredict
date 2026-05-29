class PlayerModel {
  final int id;
  final int teamId;
  final String name;
  final String? position;
  final int? jerseyNumber;

  const PlayerModel({
    required this.id,
    required this.teamId,
    required this.name,
    this.position,
    this.jerseyNumber,
  });

  factory PlayerModel.fromJson(Map<String, dynamic> json) {
    return PlayerModel(
      id: (json['id'] as num).toInt(),
      teamId: (json['team_id'] as num).toInt(),
      name: json['name'] as String,
      position: json['position'] as String?,
      jerseyNumber: (json['jersey_number'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'team_id': teamId,
        'name': name,
        'position': position,
        'jersey_number': jerseyNumber,
      };
}
