import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

/// Emits whenever the `matches` table changes anywhere in the cluster.
///
/// The four list providers below `ref.watch` this so the Matches /
/// Live / Home tabs refresh themselves the instant a poll_live_matches
/// run (or any other writer) flips status / score / events on a row.
/// Without it, FutureProvider lists serve their cached snapshot until
/// the user pulls to refresh.
///
/// `matches` is public data (RLS is read-anyone), so a single stream
/// covers every user.
final matchesChangeTickerProvider = StreamProvider<int>((ref) {
  var tick = 0;
  return supabase
      .from('matches')
      .stream(primaryKey: ['id'])
      .map((_) => ++tick);
});

/// All matches ordered by kickoff_time, with team objects joined.
final allMatchesProvider = FutureProvider<List<MatchModel>>((ref) async {
  ref.watch(matchesChangeTickerProvider);
  final data = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      // Exclude regression-test fixture IDs which are < 100,000
      .gte('id', 100000)
      .order('kickoff_time', ascending: true);
  return (data as List)
      .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
/// Up to 5 upcoming scheduled matches the current user hasn't predicted yet.
final upcomingUnpredictedProvider = FutureProvider<List<MatchModel>>((ref) async {
  ref.watch(matchesChangeTickerProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final matches = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      // Exclude regression-test fixture IDs which are < 100,000
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
  ref.watch(matchesChangeTickerProvider);
  final userId = ref.watch(currentUserIdProvider);

  final matches = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      // Exclude regression-test fixture IDs which are < 100,000
      .gte('id', 100000)
      .eq('status', 'final')
      .order('kickoff_time', ascending: false)
      .limit(3);

  final matchList = matches as List;

  if (userId == null) {
    return matchList
        .map((e) =>
            (MatchModel.fromJson(e as Map<String, dynamic>), null as PredictionModel?))
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

  ref.watch(matchesChangeTickerProvider);
  final now = DateTime.now();
  final todayStart =
      DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
  final todayEnd =
      DateTime(now.year, now.month, now.day, 23, 59, 59).toUtc().toIso8601String();

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

