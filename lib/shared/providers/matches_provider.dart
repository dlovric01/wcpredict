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

/// Wall-clock pulse, emits roughly every 10 seconds. Watched by widgets
/// that render the live minute (e.g. `LiveMinuteText`) so a single timer
/// drives every minute pill in the tree instead of one per widget.
final clockTickerProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(
    const Duration(seconds: 10),
    (_) => DateTime.now(),
  );
});

/// Single websocket subscription to the `matches` table. Emits a
/// `Map<id, MatchModel>` snapshot whenever any row changes. Test
/// fixtures (`id < 100000`) are filtered out so they never appear in
/// live overlays.
///
/// Internal — consumers should use [liveMatchProvider] which fans out
/// per-id with `.select` to avoid spurious rebuilds.
final _liveMatchesMapProvider = StreamProvider<Map<int, MatchModel>>((ref) {
  return supabase
      .from('matches')
      .stream(primaryKey: ['id'])
      .map((rows) {
    final out = <int, MatchModel>{};
    for (final r in rows) {
      final id = (r['id'] as num).toInt();
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
/// with the live overlay (status + scores). Returns the baseline as-is
/// when no overlay exists.
MatchModel _merge(MatchModel base, MatchModel? overlay) {
  if (overlay == null) return base;
  return base.copyWith(
    status: overlay.status,
    scoreFtTeam1: overlay.scoreFtTeam1,
    scoreFtTeam2: overlay.scoreFtTeam2,
    scoreHtTeam1: overlay.scoreHtTeam1,
    scoreHtTeam2: overlay.scoreHtTeam2,
    scoreEtTeam1: overlay.scoreEtTeam1,
    scoreEtTeam2: overlay.scoreEtTeam2,
    scorePenTeam1: overlay.scorePenTeam1,
    scorePenTeam2: overlay.scorePenTeam2,
    updatedAt: overlay.updatedAt,
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
