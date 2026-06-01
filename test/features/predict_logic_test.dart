// Pure-logic tests for the predict tab's lock decision + bonus-pick
// sanitisation. These mirror the real-life scenarios that matter most:
//
//   * Match goes live mid-session via Realtime → form locks instantly.
//   * Match was already locked when the user opened the page.
//   * User drops the predicted score for the team they picked as first
//     to score → that pick must clear (otherwise the DB rejects on save).
//   * User flips the score to 0-0 → both bonus picks must clear.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/features/matches/predict_logic.dart';

void main() {
  group('predictTabLocked', () {
    MatchModel makeMatch({String? status, DateTime? kickoffTime}) =>
        MatchModel(id: 1, status: status, kickoffTime: kickoffTime);

    final far = DateTime.now().add(const Duration(days: 7));
    final past = DateTime.now().subtract(const Duration(hours: 1));

    test('scheduled + future kickoff + no override → unlocked', () {
      expect(
        predictTabLocked(makeMatch(status: 'scheduled', kickoffTime: far), null),
        isFalse,
      );
    });

    test('match.isLocked=true → locked regardless of override', () {
      expect(
        predictTabLocked(
            makeMatch(status: 'final', kickoffTime: past), null),
        isTrue,
      );
      expect(
        predictTabLocked(
            makeMatch(status: 'cancelled', kickoffTime: far), null),
        isTrue,
      );
    });

    test('past kickoff with scheduled status → locked (wall-clock)', () {
      expect(
        predictTabLocked(
            makeMatch(status: 'scheduled', kickoffTime: past), null),
        isTrue,
      );
    });

    test('Realtime override status=live locks an otherwise-open form', () {
      // The cached MatchModel still says scheduled (DB poll hasn't run yet)
      // but Realtime delivered the kickoff status flip — UI must lock.
      final cached = makeMatch(status: 'scheduled', kickoffTime: far);
      expect(predictTabLocked(cached, makeMatch(status: 'live')), isTrue);
    });

    test('Realtime override status=final locks', () {
      final cached = makeMatch(status: 'scheduled', kickoffTime: far);
      expect(predictTabLocked(cached, makeMatch(status: 'final')), isTrue);
    });

    test('Realtime override status=cancelled locks', () {
      final cached = makeMatch(status: 'scheduled', kickoffTime: far);
      expect(
          predictTabLocked(cached, makeMatch(status: 'cancelled')), isTrue);
    });

    test('Realtime override status=scheduled does NOT lock', () {
      final cached = makeMatch(status: 'scheduled', kickoffTime: far);
      expect(
          predictTabLocked(cached, makeMatch(status: 'scheduled')), isFalse);
    });

    test('Realtime override with null status does not lock', () {
      final cached = makeMatch(status: 'scheduled', kickoffTime: far);
      expect(predictTabLocked(cached, makeMatch()), isFalse);
    });
  });

  group('sanitisePredictionPicks', () {
    test('0-0 score clears both picks', () {
      final r = sanitisePredictionPicks(
        score1: 0,
        score2: 0,
        firstTeamId: 99001,
        scorerId: 99101,
        team1Id: 99001,
        team2Id: 99002,
      );
      expect(r.firstTeamId, isNull);
      expect(r.scorerId, isNull);
    });

    test('first-team pick on team predicted to score 0 → cleared', () {
      // Score is 2-0; user picked team2 (the 0-scoring side) as first.
      final r = sanitisePredictionPicks(
        score1: 2,
        score2: 0,
        firstTeamId: 99002,
        scorerId: null,
        team1Id: 99001,
        team2Id: 99002,
      );
      expect(r.firstTeamId, isNull);
      expect(r.scorerId, isNull);
    });

    test('first-team pick on team predicted to score → preserved', () {
      final r = sanitisePredictionPicks(
        score1: 2,
        score2: 1,
        firstTeamId: 99001,
        scorerId: null,
        team1Id: 99001,
        team2Id: 99002,
      );
      expect(r.firstTeamId, 99001);
    });

    test('first-team pick survives when both teams predicted to score', () {
      // Score 2-2 — either team could legitimately be picked first.
      for (final picked in [99001, 99002]) {
        final r = sanitisePredictionPicks(
          score1: 2,
          score2: 2,
          firstTeamId: picked,
          scorerId: null,
          team1Id: 99001,
          team2Id: 99002,
        );
        expect(r.firstTeamId, picked, reason: 'picked=$picked must survive');
      }
    });

    test('scorerId passes through unchanged when score is non-zero', () {
      // The DB trigger validates the scorer's team; the UI doesn't have
      // that info in this helper, so it leaves scorerId alone.
      final r = sanitisePredictionPicks(
        score1: 1,
        score2: 1,
        firstTeamId: null,
        scorerId: 99101,
        team1Id: 99001,
        team2Id: 99002,
      );
      expect(r.scorerId, 99101);
    });

    test('null firstTeamId is idempotent (no-op)', () {
      final r = sanitisePredictionPicks(
        score1: 1,
        score2: 1,
        firstTeamId: null,
        scorerId: 99101,
        team1Id: 99001,
        team2Id: 99002,
      );
      expect(r.firstTeamId, isNull);
      expect(r.scorerId, 99101);
    });

    test('TBD knockout (team ids null) preserves picks if scores non-zero', () {
      // Edge case: knockout placeholder where teams aren't resolved yet.
      // The UI doesn't show first-team chips for these, but if a stale
      // pick is in memory and team ids are null, we keep them — the DB
      // will reject on save with a clearer error.
      final r = sanitisePredictionPicks(
        score1: 1,
        score2: 1,
        firstTeamId: 99001,
        scorerId: 99101,
        team1Id: null,
        team2Id: null,
      );
      expect(r.firstTeamId, 99001);
      expect(r.scorerId, 99101);
    });
  });

  group('SanitisedPicks value semantics', () {
    test('equality treats both fields', () {
      const a = SanitisedPicks(firstTeamId: 1, scorerId: 2);
      const b = SanitisedPicks(firstTeamId: 1, scorerId: 2);
      const c = SanitisedPicks(firstTeamId: 1, scorerId: 3);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes both fields for debug output', () {
      const r = SanitisedPicks(firstTeamId: 1, scorerId: 2);
      expect(r.toString(), contains('firstTeamId: 1'));
      expect(r.toString(), contains('scorerId: 2'));
    });
  });
}
