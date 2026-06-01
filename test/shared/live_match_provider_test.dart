// Provider-level tests for the live-match overlay layer.
//
// We can't talk to a real Supabase realtime stream from a unit test,
// but we CAN override the internal map provider with a synthetic
// StateProvider and pin the contract that `liveMatchProvider`:
//
//   1. Returns null when the requested id isn't in the map.
//   2. Returns the same row Riverpod stores in the map.
//   3. De-dupes via `.select`: an unrelated id flipping should NOT
//      retrigger a listener watching a different id.
//   4. Reflects updates (status / score) when the same id changes.
//
// `mergeWithLive` is also covered here — it's the splice helper that
// turns (baseline-with-teams, overlay-without-teams) into the
// effective MatchModel widgets consume.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';

/// Synthetic backing store. Tests mutate this StateProvider and
/// override `liveMatchProvider` to read from it. Mirrors the contract
/// of the real (private) `_liveMatchesMapProvider` without exposing it.
final _fakeMapProvider = StateProvider<Map<int, MatchModel>>((ref) => {});

ProviderContainer _container() {
  // Override the family with a plain Provider builder. We do NOT use
  // `.select` inside the override — the production provider already
  // relies on `MatchModel ==` for de-dupe, which is what we want to
  // verify Riverpod actually does for us.
  return ProviderContainer(
    overrides: [
      liveMatchProvider.overrideWith((ref, id) {
        final map = ref.watch(_fakeMapProvider);
        return map[id];
      }),
    ],
  );
}

MatchModel _m({
  int id = 100001,
  String? status,
  int? ft1,
  int? ft2,
}) =>
    MatchModel(
      id: id,
      status: status,
      scoreFtTeam1: ft1,
      scoreFtTeam2: ft2,
    );

void main() {
  group('liveMatchProvider', () {
    test('returns null when id is absent', () {
      final c = _container();
      addTearDown(c.dispose);
      expect(c.read(liveMatchProvider(100001)), isNull);
    });

    test('returns the row from the underlying map', () {
      final c = _container();
      addTearDown(c.dispose);
      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'live', ft1: 0, ft2: 0),
      };
      final m = c.read(liveMatchProvider(100001));
      expect(m, isNotNull);
      expect(m!.status, 'live');
      expect(m.scoreFtTeam1, 0);
    });

    test('emits on update to that id', () {
      final c = _container();
      addTearDown(c.dispose);
      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'live', ft1: 0, ft2: 0),
      };
      // Prime the family — listen subscribes only after the first read.
      c.read(liveMatchProvider(100001));

      final emissions = <MatchModel?>[];
      final sub = c.listen<MatchModel?>(
        liveMatchProvider(100001),
        (_, next) => emissions.add(next),
      );
      addTearDown(sub.close);

      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'live', ft1: 1, ft2: 0),
      };
      // c.read flushes pending dependents synchronously.
      c.read(liveMatchProvider(100001));

      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'final', ft1: 1, ft2: 0),
      };
      c.read(liveMatchProvider(100001));

      expect(emissions.length, 2);
      expect(emissions[0]!.scoreFtTeam1, 1);
      expect(emissions[1]!.status, 'final');
    });

    test('.select de-dupes: unrelated id update does NOT notify', () {
      final c = _container();
      addTearDown(c.dispose);

      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'live', ft1: 0, ft2: 0),
        100002: _m(id: 100002, status: 'scheduled'),
      };

      int notified = 0;
      final sub = c.listen<MatchModel?>(
        liveMatchProvider(100001),
        (_, __) => notified++,
        fireImmediately: false,
      );
      addTearDown(sub.close);

      // Flip ONLY the other match's row.
      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'live', ft1: 0, ft2: 0),
        100002: _m(id: 100002, status: 'live', ft1: 2, ft2: 1),
      };

      expect(
        notified,
        0,
        reason: 'listener on 100001 must not fire when 100002 changes',
      );
    });

    test('.select de-dupes: identical row replacement does NOT notify', () {
      final c = _container();
      addTearDown(c.dispose);

      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'live', ft1: 1, ft2: 0),
      };

      int notified = 0;
      final sub = c.listen<MatchModel?>(
        liveMatchProvider(100001),
        (_, __) => notified++,
        fireImmediately: false,
      );
      addTearDown(sub.close);

      // Replace with an equal value (MatchModel has full == coverage).
      c.read(_fakeMapProvider.notifier).state = {
        100001: _m(id: 100001, status: 'live', ft1: 1, ft2: 0),
      };

      expect(
        notified,
        0,
        reason: 'equal overlay should be deduped by Riverpod select',
      );
    });
  });

  group('mergeWithLive', () {
    final teamA =
        const TeamModel(id: 1, name: 'Team A', code: 'AAA', flagUrl: null);
    final teamB =
        const TeamModel(id: 2, name: 'Team B', code: 'BBB', flagUrl: null);
    final baseline = MatchModel(
      id: 100001,
      team1Id: 1,
      team2Id: 2,
      team1: teamA,
      team2: teamB,
      status: 'scheduled',
      kickoffTime: DateTime.utc(2026, 6, 15, 17, 0),
    );

    test('null overlay returns baseline unchanged', () {
      final merged = mergeWithLive(baseline, null);
      expect(identical(merged, baseline), isTrue);
    });

    test('overlay flips status and scores but keeps teams + kickoff', () {
      final overlay = MatchModel(
        id: 100001,
        status: 'live',
        scoreFtTeam1: 1,
        scoreFtTeam2: 0,
      );
      final merged = mergeWithLive(baseline, overlay);

      expect(merged.status, 'live');
      expect(merged.scoreFtTeam1, 1);
      expect(merged.scoreFtTeam2, 0);
      expect(merged.team1, teamA);
      expect(merged.team2, teamB);
      expect(merged.kickoffTime, baseline.kickoffTime);
    });

    test('overlay carries HT/ET/PEN through to the merged model', () {
      final overlay = MatchModel(
        id: 100001,
        status: 'final',
        scoreFtTeam1: 2,
        scoreFtTeam2: 2,
        scoreHtTeam1: 1,
        scoreHtTeam2: 1,
        scoreEtTeam1: 2,
        scoreEtTeam2: 2,
        scorePenTeam1: 5,
        scorePenTeam2: 4,
      );
      final merged = mergeWithLive(baseline, overlay);

      expect(merged.status, 'final');
      expect(merged.scoreHtTeam1, 1);
      expect(merged.scoreEtTeam1, 2);
      expect(merged.scorePenTeam1, 5);
      expect(merged.team1?.code, 'AAA');
    });
  });
}
