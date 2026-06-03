import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/shared/providers/match_others_provider.dart';

const _t1 = TeamModel(id: 10, name: 'Alpha', code: 'ALP');
const _t2 = TeamModel(id: 20, name: 'Bravo', code: 'BRV');

MatchModel _match({
  int s1 = 0,
  int s2 = 0,
  String status = 'live',
  String? round,
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
  required String userId,
  int? pt1,
  int? pt2,
  int? firstTeamId,
  int? scorerId,
}) =>
    PredictionModel(
      id: 'p-$userId',
      userId: userId,
      matchId: 1,
      predictedTeam1: pt1,
      predictedTeam2: pt2,
      predictedFirstTeamId: firstTeamId,
      predictedScorerId: scorerId,
    );

ProfileModel _profile(String userId, String displayName) =>
    ProfileModel(userId: userId, displayName: displayName);

MatchEventModel _goal({
  required int id,
  required int minute,
  required int teamId,
  int? playerId,
  String? detail,
}) =>
    MatchEventModel(
      id: id,
      matchId: 1,
      minute: minute,
      type: 'goal',
      teamId: teamId,
      playerId: playerId,
      detail: detail,
    );

void main() {
  group('buildOthersRows', () {
    test('profiles without predictions are filtered out', () {
      // Under the predictors-only contract, group-mates with no locked
      // prediction for this match should NOT appear on the OTHERS tab.
      final rows = buildOthersRows(
        match: _match(),
        profiles: [
          _profile('u1', 'Alice'),
          _profile('u2', 'Bob'),
        ],
        predictionsByUser: const {},
        boostersByUser: const {},
        events: const [],
      );
      expect(rows, isEmpty);
    });

    test('sorted by points desc, name asc as tiebreaker', () {
      final match = _match(s1: 1, s2: 0);
      final rows = buildOthersRows(
        match: match,
        profiles: [
          _profile('u1', 'Carol'),
          _profile('u2', 'Alice'),
          _profile('u3', 'Bob'),
        ],
        predictionsByUser: {
          // Carol: exact 1-0 (5 pts)
          'u1': _pred(userId: 'u1', pt1: 1, pt2: 0),
          // Alice: outcome match 2-0 (2 pts)
          'u2': _pred(userId: 'u2', pt1: 2, pt2: 0),
          // Bob: outcome match 3-1 (2 pts)
          'u3': _pred(userId: 'u3', pt1: 3, pt2: 1),
        },
        boostersByUser: const {},
        events: const [],
      );
      expect(rows.map((r) => r.profile.displayName).toList(),
          ['Carol', 'Alice', 'Bob']);
      expect(rows[0].pointsTotal, 5);
      expect(rows[1].pointsTotal, 2);
      expect(rows[2].pointsTotal, 2);
    });

    test('per-user booster overrides auto-multiplier', () {
      // QF round → auto multiplier = 1 (no auto). Booster row applies ×4.
      final match = _match(s1: 1, s2: 0, round: 'QF');
      final rows = buildOthersRows(
        match: match,
        profiles: [
          _profile('u1', 'Alice'),
          _profile('u2', 'Bob'),
        ],
        predictionsByUser: {
          'u1': _pred(userId: 'u1', pt1: 1, pt2: 0),
          'u2': _pred(userId: 'u2', pt1: 1, pt2: 0),
        },
        boostersByUser: {
          'u1': const RoundBoosterModel(
            userId: 'u1',
            round: 'QF',
            matchId: 1,
            multiplier: 4,
          ),
        },
        events: const [],
      );
      // Both predicted exact 1-0 → base 5.
      // Alice boosted → 5 × 4 = 20; Bob no booster → 5 × 1 = 5.
      final alice = rows.firstWhere((r) => r.profile.displayName == 'Alice');
      final bob = rows.firstWhere((r) => r.profile.displayName == 'Bob');
      expect(alice.pointsTotal, 20);
      expect(bob.pointsTotal, 5);
      // Higher points wins the sort.
      expect(rows.first.profile.displayName, 'Alice');
    });

    test('Final round auto-multiplier ×6 applies when no booster', () {
      final match = _match(s1: 1, s2: 0, round: 'Final');
      final rows = buildOthersRows(
        match: match,
        profiles: [_profile('u1', 'Alice')],
        predictionsByUser: {
          'u1': _pred(userId: 'u1', pt1: 1, pt2: 0),
        },
        boostersByUser: const {},
        events: const [],
      );
      expect(rows.first.pointsTotal, 30); // 5 × 6
    });

    test('events feed first-team & goalscorer bonuses correctly', () {
      final match = _match(s1: 1, s2: 0);
      final rows = buildOthersRows(
        match: match,
        profiles: [_profile('u1', 'Alice')],
        predictionsByUser: {
          'u1': _pred(
            userId: 'u1',
            pt1: 1,
            pt2: 0,
            firstTeamId: _t1.id,
            scorerId: 77,
          ),
        },
        boostersByUser: const {},
        events: [_goal(id: 1, minute: 12, teamId: _t1.id, playerId: 77)],
      );
      // 5 exact + 2 first team + 8 goalscorer = 15
      expect(rows.first.pointsTotal, 15);
      expect(rows.first.score!.pointsMatch, 5);
      expect(rows.first.score!.pointsFirstTeam, 2);
      expect(rows.first.score!.pointsGoalscorer, 8);
    });

    test('only predictors are returned; non-predictors are dropped', () {
      final match = _match(s1: 2, s2: 1);
      final rows = buildOthersRows(
        match: match,
        profiles: [
          _profile('u1', 'NoPred'),
          _profile('u2', 'WithPred'),
        ],
        predictionsByUser: {
          // exact = 5
          'u2': _pred(userId: 'u2', pt1: 2, pt2: 1),
        },
        boostersByUser: const {},
        events: const [],
      );
      expect(rows, hasLength(1));
      expect(rows.single.profile.displayName, 'WithPred');
      expect(rows.single.pointsTotal, 5);
      expect(rows.single.hasPrediction, isTrue);
    });

    test('case-insensitive name tiebreak (among predictors)', () {
      final match = _match();
      final rows = buildOthersRows(
        match: match,
        profiles: [
          _profile('u1', 'zoe'),
          _profile('u2', 'Amelia'),
          _profile('u3', 'amber'),
        ],
        predictionsByUser: {
          'u1': _pred(userId: 'u1', pt1: 0, pt2: 0),
          'u2': _pred(userId: 'u2', pt1: 0, pt2: 0),
          'u3': _pred(userId: 'u3', pt1: 0, pt2: 0),
        },
        boostersByUser: const {},
        events: const [],
      );
      // All three score exact 0-0 (5 pts each) → sort by name.
      expect(rows.map((r) => r.profile.displayName).toList(),
          ['amber', 'Amelia', 'zoe']);
    });
  });
}
