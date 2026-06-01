class PlayerModel {
  final int id;
  final int teamId;
  final String name;
  final String? position;
  final int? jerseyNumber;
  /// API-Football grid position within the formation, e.g. "2:3" (row:col).
  /// Row 1 = goalkeeper. Higher rows = more attacking.
  /// Null for substitutes or when lineup hasn't been fetched yet.
  final String? grid;
  /// True if this player is in the starting XI; false = named substitute.
  final bool isStarter;

  const PlayerModel({
    required this.id,
    required this.teamId,
    required this.name,
    this.position,
    this.jerseyNumber,
    this.grid,
    this.isStarter = true,
  });

  factory PlayerModel.fromJson(Map<String, dynamic> json) {
    return PlayerModel(
      id: (json['id'] as num).toInt(),
      teamId: (json['team_id'] as num).toInt(),
      name: json['name'] as String,
      position: json['position'] as String?,
      jerseyNumber: (json['jersey_number'] as num?)?.toInt(),
      grid: json['grid'] as String?,
      isStarter: (json['is_starter'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'team_id': teamId,
        'name': name,
        'position': position,
        'jersey_number': jerseyNumber,
        'grid': grid,
        'is_starter': isStarter,
      };
}
