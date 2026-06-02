// Pure unit tests for `formatLiveMinute` — the helper that turns a
// MatchModel + wall-clock `now` into a user-visible minute label
// ("4'", "HT", "90+2'", …) for the live ticker.
//
// Every interesting edge case is locked down here so a behaviour
// change is forced through a test update. Together with the widget
// consumer (`_LiveMinutePill` / `_CardMinuteLabel`), these tests are
// the single source of truth for what the live ticker can display.

import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/shared/utils/live_minute.dart';

MatchModel _live({
  required DateTime kickoff,
  String status = 'live',
  int? scoreEt1,
  int? scoreEt2,
}) =>
    MatchModel(
      id: 1,
      status: status,
      kickoffTime: kickoff,
      scoreEtTeam1: scoreEt1,
      scoreEtTeam2: scoreEt2,
    );

void main() {
  // Anchor "now" so every test is deterministic.
  final now = DateTime.utc(2026, 6, 15, 18, 0, 0);
  DateTime kickoffMinutesAgo(double m) =>
      now.subtract(Duration(milliseconds: (m * 60000).round()));

  group('formatLiveMinute — non-live statuses return null', () {
    for (final status in const ['scheduled', 'final', 'cancelled', null]) {
      test('status=$status → null', () {
        final m = _live(kickoff: kickoffMinutesAgo(30), status: status ?? '');
        // Force null status case via empty string vs real null.
        final mNull = status == null
            ? MatchModel(id: 1, kickoffTime: kickoffMinutesAgo(30))
            : m;
        expect(formatLiveMinute(mNull, now), isNull);
      });
    }
  });

  test('no kickoff_time → null', () {
    final m = MatchModel(id: 1, status: 'live');
    expect(formatLiveMinute(m, now), isNull);
  });

  test('kickoff is in the future → null (clock drift safeguard)', () {
    final m = _live(kickoff: now.add(const Duration(minutes: 10)));
    expect(formatLiveMinute(m, now), isNull);
  });

  test('elapsed exactly 0 → null (avoid showing "0\'")', () {
    final m = _live(kickoff: now);
    expect(formatLiveMinute(m, now), isNull);
  });

  group('first half (1\' .. 45\')', () {
    test('1 second elapsed → "1\'"', () {
      final m = _live(
        kickoff: now.subtract(const Duration(seconds: 1)),
      );
      expect(formatLiveMinute(m, now), "1'");
    });

    test('4 minutes elapsed → "4\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(4)), now),
        "4'",
      );
    });

    test('44 minutes elapsed → "44\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(44)), now),
        "44'",
      );
    });

    test('exactly 45 minutes elapsed → "45\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(45)), now),
        "45'",
      );
    });
  });

  group('first-half stoppage (45+X)', () {
    test('45.3 min → "45+1\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(45.3)), now),
        "45+1'",
      );
    });

    test('46.5 min → "45+2\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(46.5)), now),
        "45+2'",
      );
    });
  });

  group('halftime window (47..60 elapsed)', () {
    test('47 min → "HT"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(47)), now),
        'HT',
      );
    });

    test('59 min → "HT"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(59)), now),
        'HT',
      );
    });
  });

  group('second half (46\' .. 90\')', () {
    test('60 min elapsed → "46\'" (15-min break subtracted)', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(60)), now),
        "46'",
      );
    });

    test('82 min elapsed → "67\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(82)), now),
        "67'",
      );
    });

    test('103 min elapsed → "88\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(103)), now),
        "88'",
      );
    });

    test('exactly 105 min elapsed → "90\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(105)), now),
        "90'",
      );
    });
  });

  group('second-half stoppage (90+X)', () {
    test('105.5 min → "90+1\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(105.5)), now),
        "90+1'",
      );
    });

    test('106.5 min → "90+2\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(106.5)), now),
        "90+2'",
      );
    });
  });

  group('extended stoppage past 92 (no ET fields → keep "90+X")', () {
    test('108 min, no ET set → "90+3\'"', () {
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(108)), now),
        "90+3'",
      );
    });

    test('cap at 90+15 even for very long delays', () {
      // 200 min elapsed with no ET set: stoppage cap kicks in.
      expect(
        formatLiveMinute(_live(kickoff: kickoffMinutesAgo(200)), now),
        "90+15'",
      );
    });
  });

  group('extra time (ET fields populated)', () {
    test('110 min elapsed + ET set → "95\'"', () {
      expect(
        formatLiveMinute(
          _live(kickoff: kickoffMinutesAgo(110), scoreEt1: 0, scoreEt2: 0),
          now,
        ),
        "95'",
      );
    });

    test('135 min elapsed + ET set → "120\'" (capped)', () {
      expect(
        formatLiveMinute(
          _live(kickoff: kickoffMinutesAgo(135), scoreEt1: 1, scoreEt2: 0),
          now,
        ),
        "120'",
      );
    });

    test('200 min elapsed + ET set → still "120\'" (capped)', () {
      expect(
        formatLiveMinute(
          _live(kickoff: kickoffMinutesAgo(200), scoreEt1: 2, scoreEt2: 2),
          now,
        ),
        "120'",
      );
    });

    test('only scoreEtTeam1 set is enough to promote to ET', () {
      expect(
        formatLiveMinute(
          _live(kickoff: kickoffMinutesAgo(110), scoreEt1: 1),
          now,
        ),
        "95'",
      );
    });

    test('only scoreEtTeam2 set is enough to promote to ET', () {
      expect(
        formatLiveMinute(
          _live(kickoff: kickoffMinutesAgo(115), scoreEt2: 0),
          now,
        ),
        "100'",
      );
    });
  });
  // ── api-sports broadcast minute (Pro plan) — wins over wall-clock ──
  group('api-sports broadcast minute takes priority', () {
    MatchModel apiLive({
      required String period,
      int? minute,
      int? extra,
      // Wall-clock kickoff deliberately set to a value that would
      // produce a *different* label, to prove the api value wins.
      Duration kickoffOffset = const Duration(minutes: 9),
    }) =>
        MatchModel(
          id: 1,
          status: 'live',
          kickoffTime: now.subtract(kickoffOffset),
          currentPeriod: period,
          currentMinute: minute,
          currentMinuteExtra: extra,
        );

    test('1H minute 23 → "23\'" (wall-clock would say "9\'")', () {
      expect(
        formatLiveMinute(apiLive(period: '1H', minute: 23), now),
        "23'",
      );
    });

    test('2H minute 67 → "67\'"', () {
      expect(
        formatLiveMinute(apiLive(period: '2H', minute: 67), now),
        "67'",
      );
    });

    test('1H stoppage minute=45 extra=3 → "45+3\'"', () {
      expect(
        formatLiveMinute(apiLive(period: '1H', minute: 45, extra: 3), now),
        "45+3'",
      );
    });

    test('2H stoppage minute=90 extra=5 → "90+5\'"', () {
      expect(
        formatLiveMinute(apiLive(period: '2H', minute: 90, extra: 5), now),
        "90+5'",
      );
    });

    test('HT period → "HT"', () {
      expect(formatLiveMinute(apiLive(period: 'HT'), now), 'HT');
    });

    test('ET period with minute 105 → "105\'"', () {
      expect(
        formatLiveMinute(apiLive(period: 'ET', minute: 105), now),
        "105'",
      );
    });

    test('BT period (break before ET) → "BT"', () {
      expect(formatLiveMinute(apiLive(period: 'BT'), now), 'BT');
    });

    test('P period (penalty shootout) → "PEN"', () {
      expect(formatLiveMinute(apiLive(period: 'P'), now), 'PEN');
    });

    test('PEN period alias → "PEN"', () {
      expect(formatLiveMinute(apiLive(period: 'PEN'), now), 'PEN');
    });

    test('INT period (interrupted) → "INT"', () {
      expect(formatLiveMinute(apiLive(period: 'INT'), now), 'INT');
    });

    test('unknown period with minute → falls back to minute label', () {
      expect(
        formatLiveMinute(apiLive(period: 'XYZ', minute: 42), now),
        "42'",
      );
    });

    test('empty currentPeriod string → falls back to wall-clock', () {
      // Empty string is treated as absent (defensive: db could write '').
      final m = MatchModel(
        id: 1,
        status: 'live',
        kickoffTime: now.subtract(const Duration(minutes: 4)),
        currentPeriod: '',
      );
      expect(formatLiveMinute(m, now), "4'");
    });

    test('null currentPeriod with broadcast minute set → falls back', () {
      // currentMinute alone (without period) is ambiguous; we keep
      // wall-clock derivation as the source of truth in that case.
      final m = MatchModel(
        id: 1,
        status: 'live',
        kickoffTime: now.subtract(const Duration(minutes: 4)),
        currentMinute: 99,
      );
      expect(formatLiveMinute(m, now), "4'");
    });
  });
}
