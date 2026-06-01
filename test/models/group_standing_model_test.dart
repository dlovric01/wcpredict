// GroupStandingModel — view-row mirror with totals, tiebreaker counts,
// and earliest submission. All counts default to 0 when the view returns
// null (rare but defensive).
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/group_standing_model.dart';

void main() {
  group('GroupStandingModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final s = GroupStandingModel.fromJson({
        'group_id': 'g-uuid',
        'user_id': 'u-uuid',
        'display_name': 'Alice',
        'total_points': 175,
        'match_points': 50,
        'tournament_points': 125,
        'exact_count': 3,
        'scorer_count': 1,
        'first_team_count': 4,
        'goal_diff_count': 2,
        'outcome_count': 4,
        'earliest_submission': '2026-06-01T08:00:00.000Z',
      });
      expect(s.groupId, 'g-uuid');
      expect(s.userId, 'u-uuid');
      expect(s.displayName, 'Alice');
      expect(s.totalPoints, 175);
      expect(s.matchPoints, 50);
      expect(s.tournamentPoints, 125);
      expect(s.exactCount, 3);
      expect(s.scorerCount, 1);
      expect(s.firstTeamCount, 4);
      expect(s.goalDiffCount, 2);
      expect(s.outcomeCount, 4);
      expect(s.earliestSubmission?.toUtc().toIso8601String(),
          '2026-06-01T08:00:00.000Z');

      final j = s.toJson();
      expect(j['total_points'], 175);
      expect(j['exact_count'], 3);
      expect(j['scorer_count'], 1);
      expect(j['first_team_count'], 4);
      expect(j['goal_diff_count'], 2);
      expect(j['outcome_count'], 4);
    });

    test('all count + point fields default to 0 when missing', () {
      // Empty standing — user just joined a group, hasn't predicted yet.
      // The MV LEFT JOINs, so all aggregate fields can come back null.
      final s = GroupStandingModel.fromJson({
        'group_id': 'g',
        'user_id': 'u',
      });
      expect(s.totalPoints, 0);
      expect(s.matchPoints, 0);
      expect(s.tournamentPoints, 0);
      expect(s.exactCount, 0);
      expect(s.scorerCount, 0);
      expect(s.firstTeamCount, 0);
      expect(s.goalDiffCount, 0);
      expect(s.outcomeCount, 0);
      expect(s.displayName, isNull);
      expect(s.earliestSubmission, isNull);
    });

    test('displayName tolerates null', () {
      final s = GroupStandingModel.fromJson({
        'group_id': 'g',
        'user_id': 'u',
        'display_name': null,
        'total_points': 10,
      });
      expect(s.displayName, isNull);
      expect(s.totalPoints, 10);
    });

    test('parses numerics from doubles', () {
      final s = GroupStandingModel.fromJson({
        'group_id': 'g',
        'user_id': 'u',
        'total_points': 175.0,
        'exact_count': 3.0,
        'scorer_count': 1.0,
        'first_team_count': 2.0,
      });
      expect(s.totalPoints, 175);
      expect(s.exactCount, 3);
      expect(s.scorerCount, 1);
      expect(s.firstTeamCount, 2);
    });
  });
}
