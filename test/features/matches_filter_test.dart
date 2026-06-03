// Unit tests for `lib/features/matches/matches_filter.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/features/matches/matches_filter.dart';

MatchModel _m(int id, DateTime? kickoff) =>
    MatchModel(id: id, kickoffTime: kickoff);

void main() {
  group('buildDayWindow', () {
    test('default radius 3 → 7 days, today at index 3', () {
      final today = DateTime(2026, 6, 15);
      final window = buildDayWindow(today);
      expect(window, hasLength(7));
      expect(window[3], today);
      expect(window[0], DateTime(2026, 6, 12));
      expect(window[6], DateTime(2026, 6, 18));
    });

    test('custom radius', () {
      final today = DateTime(2026, 6, 15);
      final window = buildDayWindow(today, radius: 2);
      expect(window, hasLength(5));
      expect(window[2], today);
    });

    test('window crosses month boundary', () {
      final today = DateTime(2026, 6, 30);
      final window = buildDayWindow(today, radius: 2);
      expect(window, [
        DateTime(2026, 6, 28),
        DateTime(2026, 6, 29),
        DateTime(2026, 6, 30),
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 2),
      ]);
    });

    test('strips time-of-day from today so chips are local midnight', () {
      final today = DateTime(2026, 6, 15, 23, 47, 12);
      final window = buildDayWindow(today, radius: 1);
      // All three entries should be local midnight on their respective days.
      for (final d in window) {
        expect(d.hour, 0);
        expect(d.minute, 0);
        expect(d.second, 0);
      }
      expect(window[1], DateTime(2026, 6, 15));
    });
  });

  group('filterMatchesByDay', () {
    final day = DateTime(2026, 6, 15);

    test('null day returns input unchanged', () {
      final matches = [_m(1, DateTime(2026, 6, 15, 18))];
      expect(filterMatchesByDay(matches, null), same(matches));
    });

    test('matches on the requested day pass', () {
      final matches = [
        _m(1, DateTime(2026, 6, 15, 0, 0)),
        _m(2, DateTime(2026, 6, 15, 12, 0)),
        _m(3, DateTime(2026, 6, 15, 23, 59)),
      ];
      expect(filterMatchesByDay(matches, day).map((m) => m.id), [1, 2, 3]);
    });

    test('matches on adjacent days are dropped', () {
      final matches = [
        _m(1, DateTime(2026, 6, 14, 23, 59)),
        _m(2, DateTime(2026, 6, 15, 12, 0)),
        _m(3, DateTime(2026, 6, 16, 0, 0)),
      ];
      expect(filterMatchesByDay(matches, day).map((m) => m.id), [2]);
    });

    test('matches with null kickoffTime are dropped when filtering', () {
      final matches = [
        _m(1, null),
        _m(2, DateTime(2026, 6, 15, 18)),
      ];
      expect(filterMatchesByDay(matches, day).map((m) => m.id), [2]);
    });

    test('matches with null kickoffTime are KEPT when day is null (ALL)', () {
      final matches = [
        _m(1, null),
        _m(2, DateTime(2026, 6, 15, 18)),
      ];
      expect(filterMatchesByDay(matches, null), hasLength(2));
    });

    test('empty input returns empty output', () {
      expect(filterMatchesByDay(const [], day), isEmpty);
      expect(filterMatchesByDay(const [], null), isEmpty);
    });

    test('UTC kickoff that maps to a different local date is filtered '
        'by the LOCAL date', () {
      // Build the match with a UTC instant whose local conversion lands
      // on the same day the test asks for. Using `DateTime.utc` + the
      // helper's `toLocal` ensures we exercise the timezone branch.
      final utc = DateTime.utc(2026, 6, 15, 18, 0);
      final local = utc.toLocal();
      final matches = [_m(1, utc)];
      expect(
        filterMatchesByDay(matches, DateTime(local.year, local.month, local.day)),
        hasLength(1),
      );
    });
  });

  group('isSameLocalDay', () {
    test('same wall-clock date returns true regardless of time', () {
      expect(
        isSameLocalDay(
          DateTime(2026, 6, 15, 0, 0),
          DateTime(2026, 6, 15, 23, 59),
        ),
        isTrue,
      );
    });

    test('different calendar dates return false', () {
      expect(
        isSameLocalDay(
          DateTime(2026, 6, 15, 23, 59),
          DateTime(2026, 6, 16, 0, 0),
        ),
        isFalse,
      );
    });

    test('crosses month boundary', () {
      expect(
        isSameLocalDay(
          DateTime(2026, 6, 30, 12),
          DateTime(2026, 7, 1, 12),
        ),
        isFalse,
      );
    });
  });
}
