import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/features/matches/live_scoring.dart';

const _t1 = TeamModel(id: 10, name: 'Alpha', code: 'ALP');
const _t2 = TeamModel(id: 20, name: 'Bravo', code: 'BRV');

MatchModel _match({
  int s1 = 0,
  int s2 = 0,
  String? round,
  String status = 'live',
}) =>
    MatchModel(
      id: 1,
      team1Id: _t1.id,
      team2Id: _t2.id,
      team1: _t1,
      team2: _t2,
      status: status,
      scoreFtTeam1: s1,
      scoreFtTeam2: s2,
      round: round,
    );

PredictionModel _pred({
  int? pt1,
  int? pt2,
  int? firstTeamId,
  int? scorerId,
}) =>
    PredictionModel(
      id: 'p',
      userId: 'u',
      matchId: 1,
      predictedTeam1: pt1,
      predictedTeam2: pt2,
      predictedFirstTeamId: firstTeamId,
      predictedScorerId: scorerId,
    );

MatchEventModel _goal({
  required int id,
  required int minute,
  int? extra,
  required int teamId,
  int? playerId,
  String? detail,
}) =>
    MatchEventModel(
      id: id,
      matchId: 1,
      minute: minute,
      minuteExtra: extra,
      type: 'goal',
      teamId: teamId,
      playerId: playerId,
      detail: detail,
    );

void main() {
  group('computeLiveScore — match result', () {
    test('null prediction sides → 0', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(),
        events: const [],
        multiplier: 1,
      );
      expect(score.pointsMatch, 0);
    });

    test('exact score → 5', () {
      final score = computeLiveScore(
        match: _match(s1: 2, s2: 1),
        prediction: _pred(pt1: 2, pt2: 1),
        events: const [],
        multiplier: 1,
      );
      expect(score.pointsMatch, 5);
    });

    test('goal diff with |GD|>=2 → 3', () {
      // predicted 3-1 (GD 2), actual 4-2 (GD 2)
      final score = computeLiveScore(
        match: _match(s1: 4, s2: 2),
        prediction: _pred(pt1: 3, pt2: 1),
        events: const [],
        multiplier: 1,
      );
      expect(score.pointsMatch, 3);
    });

    test('goal diff |GD|=1 falls back to outcome → 2', () {
      // predicted 2-1 (GD 1), actual 3-2 (GD 1) — outcome match wins,
      // goal diff threshold is >=2.
      final score = computeLiveScore(
        match: _match(s1: 3, s2: 2),
        prediction: _pred(pt1: 2, pt2: 1),
        events: const [],
        multiplier: 1,
      );
      expect(score.pointsMatch, 2);
    });

    test('correct draw → 2', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 1),
        prediction: _pred(pt1: 2, pt2: 2),
        events: const [],
        multiplier: 1,
      );
      expect(score.pointsMatch, 2);
    });

    test('wrong outcome → 0', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 2),
        prediction: _pred(pt1: 2, pt2: 1),
        events: const [],
        multiplier: 1,
      );
      expect(score.pointsMatch, 0);
    });
  });

  group('computeLiveScore — first team to score', () {
    test('no pick → 0', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0),
        events: [_goal(id: 1, minute: 5, teamId: _t1.id)],
        multiplier: 1,
      );
      expect(score.pointsFirstTeam, 0);
    });

    test('correct first team → 2', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0, firstTeamId: _t1.id),
        events: [_goal(id: 1, minute: 12, teamId: _t1.id)],
        multiplier: 1,
      );
      expect(score.pointsFirstTeam, 2);
    });

    test('wrong first team → 0', () {
      final score = computeLiveScore(
        match: _match(s1: 0, s2: 1),
        prediction: _pred(pt1: 0, pt2: 1, firstTeamId: _t1.id),
        events: [_goal(id: 1, minute: 12, teamId: _t2.id)],
        multiplier: 1,
      );
      expect(score.pointsFirstTeam, 0);
    });

    test('own goal does not count as first team', () {
      // Team 2 scores an OG (credits team 1 on scoreboard) but the
      // pick is team 1 — should NOT award.
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0, firstTeamId: _t1.id),
        events: [
          _goal(id: 1, minute: 8, teamId: _t1.id, detail: 'own_goal'),
          _goal(id: 2, minute: 70, teamId: _t2.id),
        ],
        multiplier: 1,
      );
      // Earliest non-OG goal is team 2's minute 70 → mismatch.
      expect(score.pointsFirstTeam, 0);
    });

    test('extra-time goal does not award first team', () {
      // Only ET goals (minute 91+) — no regulation goals at all.
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0, firstTeamId: _t1.id),
        events: [_goal(id: 1, minute: 91, teamId: _t1.id)],
        multiplier: 1,
      );
      expect(score.pointsFirstTeam, 0);
    });

    test('earliest tie → lowest id wins', () {
      // Two simultaneous (impossible-but-possible-with-data-glitches)
      // goal events on minute 5 — SQL uses `order by minute asc, id asc`.
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 1),
        prediction: _pred(pt1: 1, pt2: 1, firstTeamId: _t2.id),
        events: [
          _goal(id: 2, minute: 5, teamId: _t2.id),
          _goal(id: 1, minute: 5, teamId: _t1.id),
        ],
        multiplier: 1,
      );
      // id 1 (team 1) wins the tie → team 2 pick is wrong.
      expect(score.pointsFirstTeam, 0);
    });
  });

  group('computeLiveScore — goalscorer', () {
    test('no pick → 0', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0),
        events: [_goal(id: 1, minute: 12, teamId: _t1.id, playerId: 99)],
        multiplier: 1,
      );
      expect(score.pointsGoalscorer, 0);
    });

    test('correct goalscorer → 8', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0, scorerId: 99),
        events: [_goal(id: 1, minute: 12, teamId: _t1.id, playerId: 99)],
        multiplier: 1,
      );
      expect(score.pointsGoalscorer, 8);
    });

    test('own goal by the picked player → 0', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0, scorerId: 99),
        events: [
          _goal(
              id: 1,
              minute: 12,
              teamId: _t1.id,
              playerId: 99,
              detail: 'own_goal'),
        ],
        multiplier: 1,
      );
      expect(score.pointsGoalscorer, 0);
    });

    test('extra-time goal by picked player → 0', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 1, pt2: 0, scorerId: 99),
        events: [_goal(id: 1, minute: 95, teamId: _t1.id, playerId: 99)],
        multiplier: 1,
      );
      expect(score.pointsGoalscorer, 0);
    });
  });

  group('computeLiveScore — totals & multipliers', () {
    test('base = sum of categories', () {
      final score = computeLiveScore(
        match: _match(s1: 2, s2: 1),
        prediction: _pred(
          pt1: 2,
          pt2: 1,
          firstTeamId: _t1.id,
          scorerId: 99,
        ),
        events: [_goal(id: 1, minute: 3, teamId: _t1.id, playerId: 99)],
        multiplier: 1,
      );
      expect(score.pointsMatch, 5);
      expect(score.pointsFirstTeam, 2);
      expect(score.pointsGoalscorer, 8);
      expect(score.base, 15);
      expect(score.total, 15);
    });

    test('multiplier applies only to total', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0, round: 'Final'),
        prediction: _pred(
          pt1: 1,
          pt2: 0,
          firstTeamId: _t1.id,
        ),
        events: [_goal(id: 1, minute: 50, teamId: _t1.id)],
        multiplier: 6,
      );
      expect(score.base, 7); // 5 exact + 2 first team
      expect(score.total, 42); // 7 × 6 Final auto-multiplier
    });

    test('zero base × any multiplier = 0', () {
      final score = computeLiveScore(
        match: _match(s1: 1, s2: 0),
        prediction: _pred(pt1: 0, pt2: 2),
        events: const [],
        multiplier: 3,
      );
      expect(score.total, 0);
    });
  });
}
