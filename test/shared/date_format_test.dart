// Unit tests for `lib/shared/utils/date_format.dart`.
//
// Tests pin the expected string shape so any drift (locale switch,
// AM/PM creep, missing weekday) trips a failing test rather than
// landing in the UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/shared/utils/date_format.dart';

void main() {
  // Build the timestamps in LOCAL time so the test asserts a stable
  // string regardless of the host's TZ. `toLocal()` is a no-op when
  // the source DateTime is already local.
  final fixedLocal = DateTime(2026, 6, 11, 21, 0); // Thu 11 Jun 21:00

  group('formatLockDeadline', () {
    test('renders short weekday + day + short month + 24h time', () {
      expect(formatLockDeadline(fixedLocal), 'Thu 11 Jun · 21:00');
    });

    test('zero-pads single-digit hour but not single-digit day', () {
      final t = DateTime(2026, 7, 4, 9, 5);
      expect(formatLockDeadline(t), 'Sat 4 Jul · 09:05');
    });

    test('uses 24h clock (no AM/PM creep)', () {
      final t = DateTime(2026, 6, 11, 23, 30);
      expect(formatLockDeadline(t), contains('23:30'));
      expect(formatLockDeadline(t), isNot(contains('PM')));
      expect(formatLockDeadline(t), isNot(contains('AM')));
    });
  });

  group('formatMatchKickoffVerbose', () {
    test('renders full weekday + day + full month + year + 24h time', () {
      expect(
        formatMatchKickoffVerbose(fixedLocal),
        'Thursday 11 June 2026 · 21:00',
      );
    });
  });

  group('formatMatchKickoffCompact', () {
    test('renders day + short month + 24h time without weekday', () {
      expect(formatMatchKickoffCompact(fixedLocal), '11 Jun · 21:00');
    });

    test('uses 24h clock (no AM/PM creep)', () {
      final t = DateTime(2026, 6, 11, 14, 15);
      expect(formatMatchKickoffCompact(t), '11 Jun · 14:15');
    });
  });
}
