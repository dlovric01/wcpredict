/// Single-row table mirror. Set by an admin when the tournament concludes.
/// Writing/updating triggers `compute_tournament_scoring()` which awards
/// the 75/50 bonuses to every matching prediction.
class TournamentResultsModel {
  final int? winnerTeamId;
  final int? goldenBootPlayerId;
  final DateTime? setAt;

  const TournamentResultsModel({
    this.winnerTeamId,
    this.goldenBootPlayerId,
    this.setAt,
  });

  bool get hasWinner => winnerTeamId != null;
  bool get hasGoldenBoot => goldenBootPlayerId != null;
  bool get isFinalised => hasWinner || hasGoldenBoot;

  factory TournamentResultsModel.fromJson(Map<String, dynamic> json) {
    return TournamentResultsModel(
      winnerTeamId: (json['winner_team_id'] as num?)?.toInt(),
      goldenBootPlayerId: (json['golden_boot_player_id'] as num?)?.toInt(),
      setAt: json['set_at'] != null
          ? DateTime.parse(json['set_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'winner_team_id': winnerTeamId,
        'golden_boot_player_id': goldenBootPlayerId,
        'set_at': setAt?.toIso8601String(),
      };
}
