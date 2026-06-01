// Pure-Dart unit tests for PredictionModel.
//
// Covers:
//   * JSON round-trip with all fields populated
//   * JSON round-trip with sparse / partial input
//   * Computed getters (basePoints, isExact/isGoalDiff/isOutcome,
//     firstTeamHit, goalscorerHit)
//
// No Flutter or Supabase dependencies — runs in milliseconds.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/prediction_model.dart';

void main() {
  group('PredictionModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final json = <String, dynamic>{
        'id': '11111111-2222-3333-4444-555555555555',
        'user_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'match_id': 99203,
        'predicted_team1': 2,
        'predicted_team2': 1,
        'predicted_first_team_id': 99001,
        'predicted_scorer_id': 99101,
        'points_match': 5,
        'points_first_team': 2,
        'points_goalscorer': 8,
        'multiplier': 4,
        'points_earned': 60, // (5 + 2 + 8) * 4
        'locked_at': '2026-06-01T12:00:00.000Z',
        'created_at': '2026-05-30T08:30:00.000Z',
        'updated_at': '2026-05-31T09:45:00.000Z',
      };

      final p = PredictionModel.fromJson(json);

      expect(p.id, json['id']);
      expect(p.userId, json['user_id']);
      expect(p.matchId, 99203);
      expect(p.predictedTeam1, 2);
      expect(p.predictedTeam2, 1);
      expect(p.predictedFirstTeamId, 99001);
      expect(p.predictedScorerId, 99101);
      expect(p.pointsMatch, 5);
      expect(p.pointsFirstTeam, 2);
      expect(p.pointsGoalscorer, 8);
      expect(p.multiplier, 4);
      expect(p.pointsEarned, 60);
      expect(p.lockedAt?.toUtc().toIso8601String(),
          '2026-06-01T12:00:00.000Z');
      expect(p.createdAt?.toUtc().toIso8601String(),
          '2026-05-30T08:30:00.000Z');
      expect(p.updatedAt?.toUtc().toIso8601String(),
          '2026-05-31T09:45:00.000Z');

      // toJson preserves every column the DB cares about.
      final round = p.toJson();
      expect(round['predicted_first_team_id'], 99001);
      expect(round['points_first_team'], 2);
      expect(round['points_goalscorer'], 8);
      expect(round['points_match'], 5);
      expect(round['points_earned'], 60);
      expect(round['predicted_scorer_id'], 99101);
    });

    test('tolerates nullable scoring fields (pre-FT row)', () {
      final p = PredictionModel.fromJson({
        'id': 'x',
        'user_id': 'u',
        'match_id': 1,
        'predicted_team1': 0,
        'predicted_team2': 0,
        // first-team / scorer absent, all points columns null
      });

      expect(p.predictedFirstTeamId, isNull);
      expect(p.predictedScorerId, isNull);
      expect(p.pointsMatch, isNull);
      expect(p.pointsFirstTeam, isNull);
      expect(p.pointsGoalscorer, isNull);
      expect(p.multiplier, isNull);
      expect(p.pointsEarned, isNull);
      expect(p.basePoints, 0); // null → 0
    });

    test('parses numerics from doubles (defensive)', () {
      // Supabase sometimes returns ints as JS numbers; ensure .toInt() path works.
      final p = PredictionModel.fromJson({
        'id': 'x',
        'user_id': 'u',
        'match_id': 1.0,
        'predicted_team1': 3.0,
        'predicted_team2': 2.0,
        'predicted_first_team_id': 99001.0,
        'predicted_scorer_id': 99101.0,
        'points_match': 5.0,
        'points_first_team': 2.0,
        'points_goalscorer': 8.0,
        'multiplier': 1.0,
        'points_earned': 15.0,
      });

      expect(p.matchId, 1);
      expect(p.predictedTeam1, 3);
      expect(p.predictedFirstTeamId, 99001);
      expect(p.predictedScorerId, 99101);
      expect(p.pointsFirstTeam, 2);
      expect(p.pointsGoalscorer, 8);
      expect(p.pointsEarned, 15);
    });
  });

  group('PredictionModel computed getters', () {
    PredictionModel makePred({
      int? pm,
      int? pft,
      int? pgs,
    }) =>
        PredictionModel(
          id: 'x',
          userId: 'u',
          matchId: 1,
          pointsMatch: pm,
          pointsFirstTeam: pft,
          pointsGoalscorer: pgs,
        );

    test('basePoints sums all three categories', () {
      expect(makePred(pm: 5, pft: 2, pgs: 8).basePoints, 15);
      expect(makePred(pm: 2, pft: 0, pgs: 0).basePoints, 2);
      expect(makePred(pm: 0, pft: 2, pgs: 0).basePoints, 2);
      expect(makePred(pm: 0, pft: 0, pgs: 8).basePoints, 8);
      expect(makePred().basePoints, 0);
    });

    test('isExact / isGoalDiff / isOutcome are mutually exclusive', () {
      final exact = makePred(pm: 5);
      expect(exact.isExact, isTrue);
      expect(exact.isGoalDiff, isFalse);
      expect(exact.isOutcome, isFalse);

      final gd = makePred(pm: 3);
      expect(gd.isExact, isFalse);
      expect(gd.isGoalDiff, isTrue);
      expect(gd.isOutcome, isFalse);

      final outcome = makePred(pm: 2);
      expect(outcome.isExact, isFalse);
      expect(outcome.isGoalDiff, isFalse);
      expect(outcome.isOutcome, isTrue);

      final miss = makePred(pm: 0);
      expect(miss.isExact, isFalse);
      expect(miss.isGoalDiff, isFalse);
      expect(miss.isOutcome, isFalse);
    });

    test('firstTeamHit fires only at exactly 2 pts', () {
      expect(makePred(pft: 2).firstTeamHit, isTrue);
      expect(makePred(pft: 0).firstTeamHit, isFalse);
      expect(makePred(pft: null).firstTeamHit, isFalse);
    });

    test('goalscorerHit fires only at exactly 8 pts', () {
      expect(makePred(pgs: 8).goalscorerHit, isTrue);
      expect(makePred(pgs: 0).goalscorerHit, isFalse);
      expect(makePred(pgs: null).goalscorerHit, isFalse);
    });
  });
}
