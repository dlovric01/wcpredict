// Pure unit tests for the realtime-socket gate that protects the
// free-plan 200-concurrent-connection cap by closing the websocket
// when no match is live or imminent.

import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';

MatchModel _m({
  int id = 100001,
  String? status,
  DateTime? kickoffTime,
}) =>
    MatchModel(id: id, status: status, kickoffTime: kickoffTime);

void main() {
  final now = DateTime.utc(2026, 6, 12, 12, 0, 0);

  group('shouldOpenRealtimeSocket — empty + degenerate inputs', () {
    test('empty matches list → gate closed', () {
      expect(shouldOpenRealtimeSocket(const [], now), isFalse);
    });

    test('all matches null kickoff + status null → gate closed', () {
      expect(
        shouldOpenRealtimeSocket(
          [_m(id: 1), _m(id: 2, kickoffTime: null)],
          now,
        ),
        isFalse,
      );
    });
  });

  group('shouldOpenRealtimeSocket — live status', () {
    test('any match status=live → gate open (ignores kickoff)', () {
      expect(
        shouldOpenRealtimeSocket([_m(status: 'live')], now),
        isTrue,
      );
    });

    test('live status wins even with kickoff far in the past', () {
      expect(
        shouldOpenRealtimeSocket(
          [_m(status: 'live', kickoffTime: now.subtract(const Duration(days: 5)))],
          now,
        ),
        isTrue,
      );
    });

    test('live status wins even with kickoff far in the future (cron lag)', () {
      expect(
        shouldOpenRealtimeSocket(
          [_m(status: 'live', kickoffTime: now.add(const Duration(hours: 6)))],
          now,
        ),
        isTrue,
      );
    });
  });

  group('shouldOpenRealtimeSocket — kickoff window', () {
    test('kickoff 10 min in future → gate closed (outside 5-min lead)', () {
      expect(
        shouldOpenRealtimeSocket(
          [_m(kickoffTime: now.add(const Duration(minutes: 10)))],
          now,
        ),
        isFalse,
      );
    });

    test('kickoff 4 min in future → gate open (inside 5-min lead)', () {
      expect(
        shouldOpenRealtimeSocket(
          [_m(kickoffTime: now.add(const Duration(minutes: 4)))],
          now,
        ),
        isTrue,
      );
    });

    test('kickoff at current time → gate open', () {
      // Open edge: now == kickoff -5min..kickoff+3h, kickoff itself is
      // inside the window.
      expect(
        shouldOpenRealtimeSocket(
          [_m(kickoffTime: now)],
          now.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('kickoff 2h45m ago → gate open (inside 3h trailing window)', () {
      expect(
        shouldOpenRealtimeSocket(
          [_m(kickoffTime: now.subtract(const Duration(hours: 2, minutes: 45)))],
          now,
        ),
        isTrue,
      );
    });

    test('kickoff 3h05m ago → gate closed (past trailing window)', () {
      expect(
        shouldOpenRealtimeSocket(
          [_m(kickoffTime: now.subtract(const Duration(hours: 3, minutes: 5)))],
          now,
        ),
        isFalse,
      );
    });

    test('kickoff exactly 5 min in future is OUT (boundary excluded)', () {
      // open = kickoff - 5m; now == open means !isAfter(open).
      final kickoff = now.add(const Duration(minutes: 5));
      expect(
        shouldOpenRealtimeSocket([_m(kickoffTime: kickoff)], now),
        isFalse,
      );
    });

    test('kickoff exactly 3 h ago is OUT (boundary excluded)', () {
      // close = kickoff + 3h; now == close means !isBefore(close).
      final kickoff = now.subtract(const Duration(hours: 3));
      expect(
        shouldOpenRealtimeSocket([_m(kickoffTime: kickoff)], now),
        isFalse,
      );
    });
  });

  group('shouldOpenRealtimeSocket — mixed lists', () {
    test('many scheduled matches, none in window → gate closed', () {
      final far = [
        _m(id: 1, kickoffTime: now.add(const Duration(days: 1))),
        _m(id: 2, kickoffTime: now.add(const Duration(days: 2))),
        _m(id: 3, kickoffTime: now.subtract(const Duration(days: 1))),
      ];
      expect(shouldOpenRealtimeSocket(far, now), isFalse);
    });

    test('one match in window among many out → gate open', () {
      final mixed = [
        _m(id: 1, kickoffTime: now.subtract(const Duration(days: 1))),
        _m(id: 2, kickoffTime: now.add(const Duration(minutes: 2))), // in
        _m(id: 3, kickoffTime: now.add(const Duration(days: 2))),
      ];
      expect(shouldOpenRealtimeSocket(mixed, now), isTrue);
    });

    test('final / cancelled matches with past kickoff do NOT open gate', () {
      final past = [
        _m(id: 1, status: 'final',     kickoffTime: now.subtract(const Duration(days: 1))),
        _m(id: 2, status: 'cancelled', kickoffTime: now.subtract(const Duration(hours: 4))),
      ];
      expect(shouldOpenRealtimeSocket(past, now), isFalse);
    });

    test('final match still inside trailing window → gate open', () {
      // Edge case: poll_live_matches just flipped status to final but
      // we're still inside the +3h window. Want the gate to stay open
      // briefly so the FT score change is delivered to listening clients.
      final justFinaled = [
        _m(id: 1, status: 'final', kickoffTime: now.subtract(const Duration(hours: 2))),
      ];
      expect(shouldOpenRealtimeSocket(justFinaled, now), isTrue);
    });
  });
}
