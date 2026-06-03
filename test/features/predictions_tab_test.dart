import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/shared/providers/match_predictions_provider.dart';

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
  group('buildPredictionRows', () {
    // ── Self pinning ──────────────────────────────────────────────────────────

    test('self is always at index 0 regardless of points', () {
      // Alice (self) misses entirely (0 pts); Bob nails exact (5 pts).
      // Without pinning, Bob would lead the list. With pinning, Alice
      // (self) sits at index 0.
      final rows = buildPredictionRows(
        match: _match(s1: 1, s2: 0),
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: [_profile('bob', 'Bob')],
        predictionsByUser: {
          'alice': _pred(userId: 'alice', pt1: 0, pt2: 3),
          'bob': _pred(userId: 'bob', pt1: 1, pt2: 0),
        },
        boostersByUser: const {},
        events: const [],
      );
      expect(rows, hasLength(2));
      expect(rows[0].isSelf, isTrue);
      expect(rows[0].profile.userId, 'alice');
      expect(rows[0].pointsTotal, 0);
      expect(rows[1].isSelf, isFalse);
      expect(rows[1].profile.userId, 'bob');
      expect(rows[1].pointsTotal, 5);
    });

    test('self is included even without a prediction', () {
      // Self never predicted, group-mate did. The row builder still emits
      // a self row (the UI uses it to render a "didn't predict" placeholder)
      // and others fan out below.
      final rows = buildPredictionRows(
        match: _match(s1: 1, s2: 0),
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: [_profile('bob', 'Bob')],
        predictionsByUser: {
          'bob': _pred(userId: 'bob', pt1: 1, pt2: 0),
        },
        boostersByUser: const {},
        events: const [],
      );
      expect(rows, hasLength(2));
      expect(rows[0].isSelf, isTrue);
      expect(rows[0].profile.userId, 'alice');
      expect(rows[0].prediction, isNull);
      expect(rows[0].score, isNull);
      expect(rows[0].pointsTotal, 0);
      expect(rows[1].isSelf, isFalse);
      expect(rows[1].profile.userId, 'bob');
    });

    test('self is the only row when no others have predicted', () {
      final rows = buildPredictionRows(
        match: _match(s1: 2, s2: 1),
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: [
          _profile('bob', 'Bob'),
          _profile('carol', 'Carol'),
        ],
        predictionsByUser: {
          'alice': _pred(userId: 'alice', pt1: 2, pt2: 1),
        },
        boostersByUser: const {},
        events: const [],
      );
      expect(rows, hasLength(1));
      expect(rows.single.isSelf, isTrue);
      expect(rows.single.pointsTotal, 5);
    });

    test('returns empty when selfProfile is null and others have no preds', () {
      // Edge case: signed-out viewer (defensive — provider short-circuits
      // earlier, but the builder must still be safe).
      final rows = buildPredictionRows(
        match: _match(),
        selfProfile: null,
        otherProfiles: [_profile('bob', 'Bob')],
        predictionsByUser: const {},
        boostersByUser: const {},
        events: const [],
      );
      expect(rows, isEmpty);
    });

    test('null selfProfile + others with preds still returns others', () {
      final rows = buildPredictionRows(
        match: _match(s1: 1, s2: 0),
        selfProfile: null,
        otherProfiles: [_profile('bob', 'Bob')],
        predictionsByUser: {
          'bob': _pred(userId: 'bob', pt1: 1, pt2: 0),
        },
        boostersByUser: const {},
        events: const [],
      );
      expect(rows, hasLength(1));
      expect(rows.single.isSelf, isFalse);
      expect(rows.single.profile.userId, 'bob');
    });

    // ── Opponent ordering & filtering ─────────────────────────────────────────

    test('opponents without predictions are filtered out', () {
      final rows = buildPredictionRows(
        match: _match(),
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: [
          _profile('bob', 'Bob'),
          _profile('carol', 'Carol'),
        ],
        predictionsByUser: const {},
        boostersByUser: const {},
        events: const [],
      );
      // Self only — no opponent predictions to include.
      expect(rows, hasLength(1));
      expect(rows.single.isSelf, isTrue);
    });

    test('opponents sorted by points desc, name asc as tiebreaker', () {
      final match = _match(s1: 1, s2: 0);
      final rows = buildPredictionRows(
        match: match,
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: [
          _profile('u1', 'Carol'),
          _profile('u2', 'Dora'),
          _profile('u3', 'Bob'),
        ],
        predictionsByUser: {
          // Self: outcome 2-0 (2 pts) — to confirm self pinning regardless.
          'alice': _pred(userId: 'alice', pt1: 2, pt2: 0),
          // Carol: exact 1-0 (5 pts)
          'u1': _pred(userId: 'u1', pt1: 1, pt2: 0),
          // Dora: outcome 2-0 (2 pts)
          'u2': _pred(userId: 'u2', pt1: 2, pt2: 0),
          // Bob: outcome 3-1 (2 pts)
          'u3': _pred(userId: 'u3', pt1: 3, pt2: 1),
        },
        boostersByUser: const {},
        events: const [],
      );
      // Row 0: self (pinned)
      expect(rows[0].isSelf, isTrue);
      expect(rows[0].profile.userId, 'alice');
      // Opponents follow by points desc, name asc (Bob before Dora at 2 pts).
      expect(rows.skip(1).map((r) => r.profile.displayName).toList(),
          ['Carol', 'Bob', 'Dora']);
      expect(rows[1].pointsTotal, 5);
      expect(rows[2].pointsTotal, 2);
      expect(rows[3].pointsTotal, 2);
    });

    test('case-insensitive name tiebreak among opponents', () {
      final rows = buildPredictionRows(
        match: _match(),
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: [
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
      // All three opponents at 5 pts (exact 0-0) → sort by name regardless of case.
      expect(rows.skip(1).map((r) => r.profile.displayName).toList(),
          ['amber', 'Amelia', 'zoe']);
    });

    // ── Score parity (mirrors compute_match_scoring) ──────────────────────────

    test('per-user booster overrides auto-multiplier', () {
      final match = _match(s1: 1, s2: 0, round: 'QF');
      final rows = buildPredictionRows(
        match: match,
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: [_profile('u2', 'Bob')],
        predictionsByUser: {
          'alice': _pred(userId: 'alice', pt1: 1, pt2: 0),
          'u2': _pred(userId: 'u2', pt1: 1, pt2: 0),
        },
        boostersByUser: {
          'alice': const RoundBoosterModel(
            userId: 'alice',
            round: 'QF',
            matchId: 1,
            multiplier: 4,
          ),
        },
        events: const [],
      );
      // Both predicted exact 1-0 (5 base). Alice boosted ×4 → 20; Bob ×1 → 5.
      expect(rows[0].isSelf, isTrue);
      expect(rows[0].pointsTotal, 20);
      expect(rows[1].pointsTotal, 5);
    });

    test('Final round auto-multiplier ×6 applies when no booster', () {
      final rows = buildPredictionRows(
        match: _match(s1: 1, s2: 0, round: 'Final'),
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: const [],
        predictionsByUser: {
          'alice': _pred(userId: 'alice', pt1: 1, pt2: 0),
        },
        boostersByUser: const {},
        events: const [],
      );
      // 5 exact × 6 auto multiplier = 30
      expect(rows.single.pointsTotal, 30);
    });

    test('events feed first-team & goalscorer bonuses correctly', () {
      final match = _match(s1: 1, s2: 0);
      final rows = buildPredictionRows(
        match: match,
        selfProfile: _profile('alice', 'Alice'),
        otherProfiles: const [],
        predictionsByUser: {
          'alice': _pred(
            userId: 'alice',
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
      expect(rows.single.pointsTotal, 15);
      expect(rows.single.score!.pointsMatch, 5);
      expect(rows.single.score!.pointsFirstTeam, 2);
      expect(rows.single.score!.pointsGoalscorer, 8);
    });
  });
}
