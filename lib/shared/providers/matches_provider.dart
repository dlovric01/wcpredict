import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Live realtime layer
// ---------------------------------------------------------------------------
//
// The matches table is public (RLS read-anyone). We open a single websocket
// subscription per app session and fan out per-match updates via
// [liveMatchProvider.family] with [.select], so a score change only rebuilds
// the one card/widget that watches that match — the list ScrollView and any
// sibling cards stay untouched.
//
// The "baseline" lists (allMatchesProvider, upcomingUnpredictedProvider,
// recentResultsProvider) do a one-shot fetch joining teams + players. They
// no longer watch the change ticker, so a score update during play does NOT
// trigger a full list refetch. Pull-to-refresh and explicit invalidation
// remain the only paths that re-issue the join query.

/// Wall-clock pulse, emits every 30 seconds. Watched by widgets that
/// render the live minute (`_LiveMinutePill`, `_CardMinuteLabel`) so
/// a single timer drives every minute pill in the tree instead of
/// one per widget. 30 s is fast enough for a minute-granularity
/// display while halving the rebuild cost vs a 10 s tick.
///
/// Acts as a fallback only — when the api-sports broadcast minute
/// is fresh (`currentPeriod` populated), widgets show that value
/// directly and the ticker just keeps the wall-clock view current
/// between poll cycles.
final clockTickerProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  );
});

/// True when the app should hold a Supabase Realtime websocket open
/// for the `matches` table. The websocket counts against the free
/// plan's 200-concurrent-connection cap and the 2M-msg/mo budget,
/// so we only open it when something is actually live or imminent.
///
/// Open when ANY match is either:
///   * `status == 'live'` (regardless of wall-clock), OR
///   * within `[kickoff - 5 min .. kickoff + 3 h]` (covers warm-up,
///     90' regulation, ET, penalty shootout, and the final-flag
///     window where `poll_live_matches` is still writing).
///
/// Re-evaluated on every `clockTickerProvider` emit (30 s). Returns a
/// bool that only triggers downstream rebuilds when the gate actually
/// flips — so dependents don't churn every 30 s.
/// Pure decision: should the realtime websocket be open right now?
///
/// Exposed for unit tests; the production caller (`_realtimeGateProvider`)
/// wires this to the actual `clockTickerProvider` + `allMatchesProvider`
/// inputs.
@visibleForTesting
bool shouldOpenRealtimeSocket(List<MatchModel> matches, DateTime now) {
  for (final m in matches) {
    if (m.status == 'live') return true;
    final k = m.kickoffTime;
    if (k == null) continue;
    final open  = k.subtract(const Duration(minutes: 5));
    final close = k.add(const Duration(hours: 3));
    if (now.isAfter(open) && now.isBefore(close)) return true;
  }
  return false;
}

final _realtimeGateProvider = Provider<bool>((ref) {
  final now = ref.watch(clockTickerProvider).valueOrNull ?? DateTime.now();
  final matches = ref.watch(allMatchesProvider).valueOrNull;
  if (matches == null) return false;
  return shouldOpenRealtimeSocket(matches, now);
});

/// Single websocket subscription to the `matches` table, gated on
/// `_realtimeGateProvider`. When no match is live or imminent the
/// stream is replaced with `Stream.value(emptyMap)`, the old socket
/// closes, and the app holds zero realtime connections — critical
/// for fitting ~200 concurrent users into the free plan's
/// 200-connection cap.
///
/// When the gate flips open (5 min before a kickoff), a new
/// subscription is created scoped via `.stream()`'s single-filter
/// slot to a rolling 6-hour-past lower bound on `kickoff_time`.
/// Finalised group-stage fixtures from days ago stay out of the
/// publication entirely.
///
/// `supabase_flutter`'s `.stream()` builder accepts only a single
/// chained filter; the test-fixture exclusion (`id < 100000`) is
/// applied client-side after the snapshot arrives.
///
/// Internal — consumers should use [liveMatchProvider] which fans
/// out per-id with `.select` to avoid spurious rebuilds.
final _liveMatchesMapProvider = StreamProvider<Map<int, MatchModel>>((ref) {
  final gateOpen = ref.watch(_realtimeGateProvider);
  if (!gateOpen) {
    return Stream.value(const <int, MatchModel>{});
  }
  final windowStart = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 6))
      .toIso8601String();
  return supabase
      .from('matches')
      .stream(primaryKey: ['id'])
      .gte('kickoff_time', windowStart)
      .map((rows) {
    final out = <int, MatchModel>{};
    for (final r in rows) {
      final id = (r['id'] as num).toInt();
      // Regression-test fixtures (id < 100000) are excluded
      // client-side — `.stream()` only allows a single filter and
      // we spend it on the kickoff-time window above.
      if (id < 100000) continue;
      out[id] = MatchModel.fromJson(r);
    }
    return out;
  });
});

/// Latest realtime row for a single match. Returns null until the
/// stream has delivered its first snapshot or for matches outside the
/// subscription.
///
/// Watching this with no `.select` is fine — Riverpod compares the
/// returned `MatchModel?` with `==` (full-field equality on
/// MatchModel), so unchanged rows dedupe automatically and listening
/// widgets only rebuild on a real status/score change.
final liveMatchProvider = Provider.family<MatchModel?, int>((ref, id) {
  return ref.watch(
    _liveMatchesMapProvider.select((async) => async.valueOrNull?[id]),
  );
});

/// "Effective" match: the cached baseline (with teams joined) merged
/// with the live overlay (status + scores + broadcast minute). When
/// `overlay` is null returns the baseline unchanged.
///
/// Unlike `MatchModel.copyWith`, this function takes the overlay's
/// values *directly* for live broadcast fields — including null. That
/// matters because `current_minute` legitimately transitions back to
/// null when poll_live_matches finalises a match, where copyWith's
/// `?? this.field` would keep showing a stale "88'" forever.
MatchModel _merge(MatchModel base, MatchModel? overlay) {
  if (overlay == null) return base;
  return MatchModel(
    id: base.id,
    round: base.round,
    groupLetter: base.groupLetter,
    team1Id: base.team1Id,
    team2Id: base.team2Id,
    kickoffTime: base.kickoffTime,
    status: overlay.status ?? base.status,
    scoreFtTeam1: overlay.scoreFtTeam1 ?? base.scoreFtTeam1,
    scoreFtTeam2: overlay.scoreFtTeam2 ?? base.scoreFtTeam2,
    scoreHtTeam1: overlay.scoreHtTeam1 ?? base.scoreHtTeam1,
    scoreHtTeam2: overlay.scoreHtTeam2 ?? base.scoreHtTeam2,
    scoreEtTeam1: overlay.scoreEtTeam1 ?? base.scoreEtTeam1,
    scoreEtTeam2: overlay.scoreEtTeam2 ?? base.scoreEtTeam2,
    scorePenTeam1: overlay.scorePenTeam1 ?? base.scorePenTeam1,
    scorePenTeam2: overlay.scorePenTeam2 ?? base.scorePenTeam2,
    // Live broadcast fields — overlay wins absolutely so a null
    // clears the cached "88'" when the match transitions to final.
    currentMinute: overlay.currentMinute,
    currentMinuteExtra: overlay.currentMinuteExtra,
    currentPeriod: overlay.currentPeriod,
    updatedAt: overlay.updatedAt ?? base.updatedAt,
    team1: base.team1,
    team2: base.team2,
    formationTeam1: base.formationTeam1,
    formationTeam2: base.formationTeam2,
  );
}

/// Convenience for callers that have a baseline match in hand and want
/// the live-merged copy. Exposed so widgets (`_MatchCard`, hero score)
/// can do the splice in one line.
MatchModel mergeWithLive(MatchModel baseline, MatchModel? overlay) =>
    _merge(baseline, overlay);

// ---------------------------------------------------------------------------
// Baseline list providers (one-shot fetch + join, no live ticker watch)
// ---------------------------------------------------------------------------

/// All matches ordered by kickoff_time, with team objects joined.
/// Refreshes on explicit invalidate / pull-to-refresh. In-match score
/// changes propagate via [liveMatchProvider], not a full refetch — so
/// the list ScrollView and its un-affected cards never rebuild.
final allMatchesProvider = FutureProvider<List<MatchModel>>((ref) async {
  final data = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .gte('id', 100000)
      .order('kickoff_time', ascending: true);
  return (data as List)
      .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Up to 5 upcoming scheduled matches the current user hasn't predicted yet.
final upcomingUnpredictedProvider =
    FutureProvider<List<MatchModel>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final matches = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .gte('id', 100000)
      .eq('status', 'scheduled')
      .order('kickoff_time', ascending: true)
      .limit(20);

  final matchList = matches as List;
  if (matchList.isEmpty) return [];

  final matchIds = matchList.map((e) => e['id'] as int).toList();

  final preds = await supabase
      .from('predictions')
      .select('match_id')
      .eq('user_id', userId)
      .inFilter('match_id', matchIds);

  final predictedIds =
      Set<int>.from((preds as List).map((e) => e['match_id'] as int));

  return matchList
      .where((e) => !predictedIds.contains(e['id'] as int))
      .take(5)
      .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Last 3 finalised matches with the current user's prediction (nullable).
final recentResultsProvider =
    FutureProvider<List<(MatchModel, PredictionModel?)>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);

  final matches = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .gte('id', 100000)
      .eq('status', 'final')
      .order('kickoff_time', ascending: false)
      .limit(3);

  final matchList = matches as List;

  if (userId == null) {
    return matchList
        .map((e) => (
              MatchModel.fromJson(e as Map<String, dynamic>),
              null as PredictionModel?
            ))
        .toList();
  }

  final ids = matchList.map((e) => e['id'] as int).toList();
  if (ids.isEmpty) return [];

  final preds = await supabase
      .from('predictions')
      .select()
      .eq('user_id', userId)
      .inFilter('match_id', ids);

  final predMap = Map<int, PredictionModel>.fromEntries(
    (preds as List).map((p) {
      final pm = PredictionModel.fromJson(p as Map<String, dynamic>);
      return MapEntry(pm.matchId, pm);
    }),
  );

  return matchList.map((e) {
    final m = MatchModel.fromJson(e as Map<String, dynamic>);
    return (m, predMap[m.id]);
  }).toList();
});

/// Live tab data: in-play matches, today's scheduled, and 3 most-recent finals.
/// Sorted: live first, then scheduled by kickoff asc, then finals by kickoff desc.
final liveMatchesProvider = FutureProvider<List<MatchModel>>((ref) async {
  final now = DateTime.now();
  final todayStart =
      DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59)
      .toUtc()
      .toIso8601String();

  final liveData = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .gte('id', 100000)
      .eq('status', 'live')
      .order('kickoff_time', ascending: true);

  final todayData = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .gte('id', 100000)
      .eq('status', 'scheduled')
      .gte('kickoff_time', todayStart)
      .lte('kickoff_time', todayEnd)
      .order('kickoff_time', ascending: true);

  final recentData = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .gte('id', 100000)
      .eq('status', 'final')
      .order('kickoff_time', ascending: false)
      .limit(3);

  MatchModel parseMatch(dynamic e) =>
      MatchModel.fromJson(e as Map<String, dynamic>);

  return [
    ...(liveData as List).map(parseMatch),
    ...(todayData as List).map(parseMatch),
    ...(recentData as List).map(parseMatch),
  ];
});
