import 'team_model.dart';

class MatchModel {
  final int id;
  final String? round;
  final String? groupLetter;
  final int? team1Id;
  final int? team2Id;
  final DateTime? kickoffTime;
  final String? status;
  final int? scoreFtTeam1;
  final int? scoreFtTeam2;
  final int? scoreHtTeam1;
  final int? scoreHtTeam2;
  final int? scoreEtTeam1;
  final int? scoreEtTeam2;
  final int? scorePenTeam1;
  final int? scorePenTeam2;
  final DateTime? updatedAt;

  /// Populated when the query joins the teams table.
  final TeamModel? team1;
  final TeamModel? team2;

  /// Formation strings fetched from the lineup endpoint, e.g. "4-3-3".
  final String? formationTeam1;
  final String? formationTeam2;

  const MatchModel({
    required this.id,
    this.round,
    this.groupLetter,
    this.team1Id,
    this.team2Id,
    this.kickoffTime,
    this.status,
    this.scoreFtTeam1,
    this.scoreFtTeam2,
    this.scoreHtTeam1,
    this.scoreHtTeam2,
    this.scoreEtTeam1,
    this.scoreEtTeam2,
    this.scorePenTeam1,
    this.scorePenTeam2,
    this.updatedAt,
    this.team1,
    this.team2,
    this.formationTeam1,
    this.formationTeam2,
  });

  /// Predictions are locked once the match is no longer scheduled.
  bool get isLocked {
    if (status == 'live' || status == 'final' || status == 'cancelled') return true;
    if (kickoffTime == null) return false;
    return DateTime.now().isAfter(kickoffTime!);
  }

  /// True for knockout rounds including 3rd place and Final.
  bool get isKnockout {
    final r = round;
    return r == 'R32' || r == 'R16' || r == 'QF' || r == 'SF' ||
        r == '3rd' || r == 'Final';
  }

  /// True for rounds where users can apply a manual booster (R32/R16/QF/SF).
  bool get isBoosterRound {
    final r = round;
    return r == 'R32' || r == 'R16' || r == 'QF' || r == 'SF';
  }

  /// Auto-multiplier applied regardless of user action: 5 for 3rd, 6 for Final.
  int get autoMultiplier {
    if (round == '3rd')   return 5;
    if (round == 'Final') return 6;
    return 1;
  }

  /// Maximum booster multiplier for this round (R32=2, R16=3, QF=4, SF=5, else 1).
  int get boosterMultiplier {
    switch (round) {
      case 'R32':   return 2;
      case 'R16':   return 3;
      case 'QF':    return 4;
      case 'SF':    return 5;
      default:      return 1;
    }
  }

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    TeamModel? parseTeam(dynamic raw) {
      if (raw is Map<String, dynamic>) return TeamModel.fromJson(raw);
      return null;
    }

    return MatchModel(
      id: (json['id'] as num).toInt(),
      round: json['round'] as String?,
      groupLetter: json['group_letter'] as String?,
      team1Id: (json['team1_id'] as num?)?.toInt(),
      team2Id: (json['team2_id'] as num?)?.toInt(),
      kickoffTime: json['kickoff_time'] != null
          ? DateTime.parse(json['kickoff_time'] as String)
          : null,
      status: json['status'] as String?,
      scoreFtTeam1: (json['score_ft_team1'] as num?)?.toInt(),
      scoreFtTeam2: (json['score_ft_team2'] as num?)?.toInt(),
      scoreHtTeam1: (json['score_ht_team1'] as num?)?.toInt(),
      scoreHtTeam2: (json['score_ht_team2'] as num?)?.toInt(),
      scoreEtTeam1: (json['score_et_team1'] as num?)?.toInt(),
      scoreEtTeam2: (json['score_et_team2'] as num?)?.toInt(),
      scorePenTeam1: (json['score_pen_team1'] as num?)?.toInt(),
      scorePenTeam2: (json['score_pen_team2'] as num?)?.toInt(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      team1: parseTeam(json['team1']),
      team2: parseTeam(json['team2']),
      formationTeam1: json['formation_team1'] as String?,
      formationTeam2: json['formation_team2'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'round': round,
        'group_letter': groupLetter,
        'team1_id': team1Id,
        'team2_id': team2Id,
        'kickoff_time': kickoffTime?.toIso8601String(),
        'status': status,
        'score_ft_team1': scoreFtTeam1,
        'score_ft_team2': scoreFtTeam2,
        'score_ht_team1': scoreHtTeam1,
        'score_ht_team2': scoreHtTeam2,
        'score_et_team1': scoreEtTeam1,
        'score_et_team2': scoreEtTeam2,
        'score_pen_team1': scorePenTeam1,
        'score_pen_team2': scorePenTeam2,
        'updated_at': updatedAt?.toIso8601String(),
        'formation_team1': formationTeam1,
        'formation_team2': formationTeam2,
      };

  /// Returns a copy with the listed fields overridden. Used by the
  /// "live view" provider to splice the realtime row's status + scores
  /// onto the cached match-with-lineups without refetching the whole
  /// join.
  MatchModel copyWith({
    String? status,
    int? scoreFtTeam1,
    int? scoreFtTeam2,
    int? scoreHtTeam1,
    int? scoreHtTeam2,
    int? scoreEtTeam1,
    int? scoreEtTeam2,
    int? scorePenTeam1,
    int? scorePenTeam2,
    DateTime? updatedAt,
  }) {
    return MatchModel(
      id: id,
      round: round,
      groupLetter: groupLetter,
      team1Id: team1Id,
      team2Id: team2Id,
      kickoffTime: kickoffTime,
      status: status ?? this.status,
      scoreFtTeam1: scoreFtTeam1 ?? this.scoreFtTeam1,
      scoreFtTeam2: scoreFtTeam2 ?? this.scoreFtTeam2,
      scoreHtTeam1: scoreHtTeam1 ?? this.scoreHtTeam1,
      scoreHtTeam2: scoreHtTeam2 ?? this.scoreHtTeam2,
      scoreEtTeam1: scoreEtTeam1 ?? this.scoreEtTeam1,
      scoreEtTeam2: scoreEtTeam2 ?? this.scoreEtTeam2,
      scorePenTeam1: scorePenTeam1 ?? this.scorePenTeam1,
      scorePenTeam2: scorePenTeam2 ?? this.scorePenTeam2,
      updatedAt: updatedAt ?? this.updatedAt,
      team1: team1,
      team2: team2,
      formationTeam1: formationTeam1,
      formationTeam2: formationTeam2,
    );
  }

  // Value equality so Riverpod `.select` and ListView keys can dedupe
  // unchanged rows on every list refetch. Nested `team1` / `team2`
  // delegate to TeamModel ==, which in turn delegates to PlayerModel
  // == — so an unchanged lineup compares equal even after JSON
  // round-trip.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchModel &&
          id == other.id &&
          round == other.round &&
          groupLetter == other.groupLetter &&
          team1Id == other.team1Id &&
          team2Id == other.team2Id &&
          kickoffTime == other.kickoffTime &&
          status == other.status &&
          scoreFtTeam1 == other.scoreFtTeam1 &&
          scoreFtTeam2 == other.scoreFtTeam2 &&
          scoreHtTeam1 == other.scoreHtTeam1 &&
          scoreHtTeam2 == other.scoreHtTeam2 &&
          scoreEtTeam1 == other.scoreEtTeam1 &&
          scoreEtTeam2 == other.scoreEtTeam2 &&
          scorePenTeam1 == other.scorePenTeam1 &&
          scorePenTeam2 == other.scorePenTeam2 &&
          updatedAt == other.updatedAt &&
          team1 == other.team1 &&
          team2 == other.team2 &&
          formationTeam1 == other.formationTeam1 &&
          formationTeam2 == other.formationTeam2;

  @override
  int get hashCode => Object.hashAll([
        id,
        round,
        groupLetter,
        team1Id,
        team2Id,
        kickoffTime,
        status,
        scoreFtTeam1,
        scoreFtTeam2,
        scoreHtTeam1,
        scoreHtTeam2,
        scoreEtTeam1,
        scoreEtTeam2,
        scorePenTeam1,
        scorePenTeam2,
        updatedAt,
        team1,
        team2,
        formationTeam1,
        formationTeam2,
      ]);
}
