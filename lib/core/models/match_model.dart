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
  });

  /// Predictions are locked once the match is no longer scheduled.
  bool get isLocked {
    if (status == 'live' || status == 'final') return true;
    if (kickoffTime == null) return false;
    return DateTime.now().isAfter(kickoffTime!);
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
      };
}
