// MatchModel — focuses on the `isLocked` computed getter that drives the
// prediction-form lock state across every screen. The two independent lock
// conditions (non-scheduled status, past kickoff) and the null-kickoff
// fallback are the load-bearing branches.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';

void main() {
  group('MatchModel.isLocked', () {
    MatchModel makeMatch({String? status, DateTime? kickoffTime}) =>
        MatchModel(id: 1, status: status, kickoffTime: kickoffTime);

    final farFuture = DateTime.now().add(const Duration(days: 7));
    final farPast = DateTime.now().subtract(const Duration(days: 7));

    test('scheduled + future kickoff → unlocked', () {
      expect(makeMatch(status: 'scheduled', kickoffTime: farFuture).isLocked, isFalse);
    });

    test('scheduled + past kickoff → locked (wall-clock fallback)', () {
      expect(makeMatch(status: 'scheduled', kickoffTime: farPast).isLocked, isTrue);
    });

    test('live status locks regardless of kickoff time', () {
      expect(makeMatch(status: 'live', kickoffTime: farFuture).isLocked, isTrue);
    });

    test('final status locks regardless of kickoff time', () {
      expect(makeMatch(status: 'final', kickoffTime: farFuture).isLocked, isTrue);
    });

    test('cancelled status locks regardless of kickoff time', () {
      expect(makeMatch(status: 'cancelled', kickoffTime: farFuture).isLocked, isTrue);
    });

    test('null kickoff with scheduled status → unlocked', () {
      // Knockout placeholder matches have no kickoff yet.
      expect(makeMatch(status: 'scheduled', kickoffTime: null).isLocked, isFalse);
    });

    test('null kickoff with live status → locked (status wins)', () {
      expect(makeMatch(status: 'live', kickoffTime: null).isLocked, isTrue);
    });

    test('captured-at-kickoff instant → locked (clock advances past it)', () {
      // `isLocked` calls `DateTime.now().isAfter(kickoffTime)`. By the time
      // .isAfter executes, the clock has moved at least one microsecond past
      // the captured timestamp, so the match is already locked. This is the
      // realistic behaviour — a UI build that started at exactly kickoff
      // shows "locked" before the user can tap submit, which is exactly the
      // behaviour we want at the boundary.
      //
      // The DB-side guard uses `kickoff_time <= now()` which is inclusive
      // by construction, so the two layers agree at the boundary.
      final now = DateTime.now();
      expect(makeMatch(status: 'scheduled', kickoffTime: now).isLocked,
          isTrue);
    });

    test('one second after kickoff → locked', () {
      final justPast =
          DateTime.now().subtract(const Duration(seconds: 1));
      expect(makeMatch(status: 'scheduled', kickoffTime: justPast).isLocked,
          isTrue);
    });

    test('one second before kickoff → unlocked', () {
      final justAhead =
          DateTime.now().add(const Duration(seconds: 1));
      expect(makeMatch(status: 'scheduled', kickoffTime: justAhead).isLocked,
          isFalse);
    });
  });

  group('MatchModel.fromJson', () {
    test('parses round, teams, scores and nested team objects', () {
      final m = MatchModel.fromJson({
        'id': 99203,
        'round': 'QF',
        'group_letter': null,
        'team1_id': 99001,
        'team2_id': 99002,
        'kickoff_time': '2026-06-14T15:00:00.000Z',
        'status': 'scheduled',
        'score_ft_team1': null,
        'score_ft_team2': null,
        'team1': {
          'id': 99001,
          'name': 'Alpha',
          'code': 'ALP',
        },
        'team2': {
          'id': 99002,
          'name': 'Bravo',
          'code': 'BRV',
        },
      });

      expect(m.id, 99203);
      expect(m.round, 'QF');
      expect(m.team1Id, 99001);
      expect(m.team2Id, 99002);
      expect(m.team1?.name, 'Alpha');
      expect(m.team2?.name, 'Bravo');
      expect(m.isKnockout, isTrue);
      expect(m.isBoosterRound, isTrue);
      expect(m.autoMultiplier, 1);
      expect(m.boosterMultiplier, 4);
    });
  });

  group('MatchModel.autoMultiplier / boosterMultiplier', () {
    test('3rd place match → autoMultiplier 5, no booster', () {
      final m = MatchModel(id: 1, round: '3rd');
      expect(m.autoMultiplier, 5);
      expect(m.boosterMultiplier, 1);
      expect(m.isBoosterRound, isFalse);
    });

    test('Final → autoMultiplier 6, no booster', () {
      final m = MatchModel(id: 1, round: 'Final');
      expect(m.autoMultiplier, 6);
      expect(m.boosterMultiplier, 1);
      expect(m.isBoosterRound, isFalse);
    });

    test('R32/R16/QF/SF → no auto multiplier, booster ladder 2/3/4/5', () {
      for (final entry in const {
        'R32': 2,
        'R16': 3,
        'QF': 4,
        'SF': 5,
      }.entries) {
        final m = MatchModel(id: 1, round: entry.key);
        expect(m.autoMultiplier, 1, reason: '${entry.key} has no auto');
        expect(m.boosterMultiplier, entry.value,
            reason: '${entry.key} boost = ${entry.value}');
        expect(m.isBoosterRound, isTrue, reason: '${entry.key} allows booster');
      }
    });

    test('Group-stage round → no auto, no booster', () {
      final m = MatchModel(id: 1, round: 'Matchday 1');
      expect(m.autoMultiplier, 1);
      expect(m.boosterMultiplier, 1);
      expect(m.isBoosterRound, isFalse);
      expect(m.isKnockout, isFalse);
    });
  });
}
