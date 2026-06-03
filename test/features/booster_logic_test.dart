// Unit tests for `lib/features/matches/booster_logic.dart`.
//
// These cover every transition in the active-round state machine:
//   - empty / non-knockout lists
//   - R32 gated on every group-stage match being final
//   - R16 / QF / SF gated on the previous knockout round being fully final
//   - "all matches in the round are locked" hides the card again
//   - mixed-status rounds where SOME matches are still pre-kickoff surface
//     the card even though others kicked off
//
// `MatchModel.isLocked` reads wall-clock `DateTime.now()` as a fallback, so
// every kickoff in this file is far in the future / past to avoid timer
// flake. We never assert against the wall-clock leap.

import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/features/matches/booster_logic.dart';

final _farFuture = DateTime.now().add(const Duration(days: 30));
final _farPast = DateTime.now().subtract(const Duration(days: 30));

MatchModel _m({
  required int id,
  required String round,
  required String status,
  DateTime? kickoff,
}) =>
    MatchModel(
      id: id,
      round: round,
      status: status,
      kickoffTime: kickoff ?? _farFuture,
    );

// ─── Group-stage shorthand ──────────────────────────────────────────────────
// A group of two Matchday rows (each "Matchday N") with the supplied status.
List<MatchModel> _group({required String status}) => [
      _m(id: 1, round: 'Matchday 1', status: status, kickoff: _farPast),
      _m(id: 2, round: 'Matchday 2', status: status, kickoff: _farPast),
      _m(id: 3, round: 'Matchday 3', status: status, kickoff: _farPast),
    ];

// All R32 matches scheduled in the future (pre-kickoff).
List<MatchModel> _r32Open() => List.generate(
      16,
      (i) => _m(id: 100 + i, round: 'R32', status: 'scheduled'),
    );

// All R32 matches finalised — used to gate R16 et al.
List<MatchModel> _r32Final() => List.generate(
      16,
      (i) => _m(
        id: 100 + i,
        round: 'R32',
        status: 'final',
        kickoff: _farPast,
      ),
    );

void main() {
  group('allGroupStageFinal', () {
    test('empty list returns false', () {
      expect(allGroupStageFinal(const []), isFalse);
    });

    test('list with no group-stage matches returns false', () {
      expect(allGroupStageFinal(_r32Open()), isFalse);
    });

    test('all Matchday rounds final returns true', () {
      expect(allGroupStageFinal(_group(status: 'final')), isTrue);
    });

    test('one Matchday match still scheduled returns false', () {
      final matches = _group(status: 'final').toList()
        ..[1] = _m(
          id: 2,
          round: 'Matchday 2',
          status: 'scheduled',
          kickoff: _farFuture,
        );
      expect(allGroupStageFinal(matches), isFalse);
    });

    test('one Matchday match live returns false', () {
      final matches = _group(status: 'final').toList()
        ..[2] = _m(
          id: 3,
          round: 'Matchday 3',
          status: 'live',
          kickoff: _farPast,
        );
      expect(allGroupStageFinal(matches), isFalse);
    });

    test('legacy "Group Stage" round literal accepted', () {
      final matches = [
        _m(id: 1, round: 'Group Stage', status: 'final', kickoff: _farPast),
        _m(id: 2, round: 'Group Stage', status: 'final', kickoff: _farPast),
      ];
      expect(allGroupStageFinal(matches), isTrue);
    });

    test('mix of Matchday + Group Stage all final returns true', () {
      final matches = [
        _m(id: 1, round: 'Group Stage', status: 'final', kickoff: _farPast),
        _m(id: 2, round: 'Matchday 1', status: 'final', kickoff: _farPast),
      ];
      expect(allGroupStageFinal(matches), isTrue);
    });

    test('non-group rounds ignored entirely', () {
      // R32 rows mixed with all-final group: should still return true.
      final matches = [
        ..._group(status: 'final'),
        ..._r32Open(),
      ];
      expect(allGroupStageFinal(matches), isTrue);
    });
  });

  group('activeBoosterRound', () {
    test('empty list returns null', () {
      expect(activeBoosterRound(const []), isNull);
    });

    test('group-stage-only list returns null (no knockout rounds yet)', () {
      expect(activeBoosterRound(_group(status: 'live')), isNull);
    });

    test('R32 hidden until every group-stage match is final', () {
      final matches = [..._group(status: 'live'), ..._r32Open()];
      expect(activeBoosterRound(matches), isNull);
    });

    test('R32 surfaces once group stage is fully final', () {
      final matches = [..._group(status: 'final'), ..._r32Open()];
      expect(activeBoosterRound(matches), 'R32');
    });

    test('R32 hidden again when every R32 match has kicked off', () {
      final matches = [
        ..._group(status: 'final'),
        ...List.generate(
          16,
          (i) => _m(
            id: 100 + i,
            round: 'R32',
            status: 'live',
            kickoff: _farPast,
          ),
        ),
      ];
      expect(activeBoosterRound(matches), isNull);
    });

    test('R32 still surfaces if even ONE match is pre-kickoff', () {
      // 15 matches live, 1 still scheduled in the future.
      final r32 = [
        ...List.generate(
          15,
          (i) => _m(
            id: 100 + i,
            round: 'R32',
            status: 'live',
            kickoff: _farPast,
          ),
        ),
        _m(id: 200, round: 'R32', status: 'scheduled', kickoff: _farFuture),
      ];
      final matches = [..._group(status: 'final'), ...r32];
      expect(activeBoosterRound(matches), 'R32');
    });

    test('R16 hidden when R32 not fully final', () {
      // R32 partially final.
      final r32Mixed = [
        ...List.generate(
          15,
          (i) => _m(
            id: 100 + i,
            round: 'R32',
            status: 'final',
            kickoff: _farPast,
          ),
        ),
        _m(id: 200, round: 'R32', status: 'live', kickoff: _farPast),
      ];
      final r16 = List.generate(
        8,
        (i) => _m(id: 300 + i, round: 'R16', status: 'scheduled'),
      );
      final matches = [..._group(status: 'final'), ...r32Mixed, ...r16];
      expect(activeBoosterRound(matches), isNull);
    });

    test('R16 surfaces once R32 is fully final and R16 has open matches', () {
      final r16 = List.generate(
        8,
        (i) => _m(id: 300 + i, round: 'R16', status: 'scheduled'),
      );
      final matches = [..._group(status: 'final'), ..._r32Final(), ...r16];
      expect(activeBoosterRound(matches), 'R16');
    });

    test('R16 retires for QF once R16 is fully final and QF has open matches',
        () {
      final r16Final = List.generate(
        8,
        (i) => _m(
          id: 300 + i,
          round: 'R16',
          status: 'final',
          kickoff: _farPast,
        ),
      );
      final qf = List.generate(
        4,
        (i) => _m(id: 400 + i, round: 'QF', status: 'scheduled'),
      );
      final matches = [
        ..._group(status: 'final'),
        ..._r32Final(),
        ...r16Final,
        ...qf,
      ];
      expect(activeBoosterRound(matches), 'QF');
    });

    test('SF is the last actionable round (Final/3rd never surface)', () {
      final r16Final = List.generate(
        8,
        (i) => _m(
          id: 300 + i,
          round: 'R16',
          status: 'final',
          kickoff: _farPast,
        ),
      );
      final qfFinal = List.generate(
        4,
        (i) => _m(
          id: 400 + i,
          round: 'QF',
          status: 'final',
          kickoff: _farPast,
        ),
      );
      final sf = List.generate(
        2,
        (i) => _m(id: 500 + i, round: 'SF', status: 'scheduled'),
      );
      final matches = [
        ..._group(status: 'final'),
        ..._r32Final(),
        ...r16Final,
        ...qfFinal,
        ...sf,
        // Final and 3rd are present but never returned (auto-multiplier).
        _m(id: 600, round: 'Final', status: 'scheduled'),
        _m(id: 700, round: '3rd', status: 'scheduled'),
      ];
      expect(activeBoosterRound(matches), 'SF');
    });

    test('Final / 3rd never returned even when SF is fully final', () {
      final r16Final = List.generate(
        8,
        (i) => _m(
          id: 300 + i,
          round: 'R16',
          status: 'final',
          kickoff: _farPast,
        ),
      );
      final qfFinal = List.generate(
        4,
        (i) => _m(
          id: 400 + i,
          round: 'QF',
          status: 'final',
          kickoff: _farPast,
        ),
      );
      final sfFinal = List.generate(
        2,
        (i) => _m(
          id: 500 + i,
          round: 'SF',
          status: 'final',
          kickoff: _farPast,
        ),
      );
      final matches = [
        ..._group(status: 'final'),
        ..._r32Final(),
        ...r16Final,
        ...qfFinal,
        ...sfFinal,
        _m(id: 600, round: 'Final', status: 'scheduled'),
        _m(id: 700, round: '3rd', status: 'scheduled'),
      ];
      // SF retired, but the helper does NOT advance to Final/3rd.
      expect(activeBoosterRound(matches), isNull);
    });

    test('list missing a knockout round is skipped (no exception)', () {
      // Group + only QF present (skipping R32 + R16) — shouldn't trip the
      // "previous round fully final" check because the helper iterates and
      // `_r32`/`_r16` lookups return empty (which `.every` treats as true).
      final qf = List.generate(
        4,
        (i) => _m(id: 400 + i, round: 'QF', status: 'scheduled'),
      );
      final matches = [..._group(status: 'final'), ...qf];
      // Group is final → R32 gate passes → roundMatches for R32 is empty
      // → continue → R16 same → QF: prev R16 is empty so `.every` is true
      // → returns 'QF'.
      expect(activeBoosterRound(matches), 'QF');
    });

    test('non-knockout list with finalised group still returns null', () {
      expect(activeBoosterRound(_group(status: 'final')), isNull);
    });

    test('locked-by-wall-clock match counts as locked', () {
      // status = 'scheduled' but kickoff is in the past → MatchModel.isLocked
      // is true, so the round is treated as fully locked.
      final r32Locked = List.generate(
        16,
        (i) => _m(
          id: 100 + i,
          round: 'R32',
          status: 'scheduled',
          kickoff: _farPast,
        ),
      );
      final matches = [..._group(status: 'final'), ...r32Locked];
      expect(activeBoosterRound(matches), isNull);
    });
  });

  group('kBoosterRoundsInOrder', () {
    test('contains exactly R32 → R16 → QF → SF in bracket order', () {
      expect(kBoosterRoundsInOrder, ['R32', 'R16', 'QF', 'SF']);
    });
  });
}
