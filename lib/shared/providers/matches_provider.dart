import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';

/// All matches ordered by kickoff_time, with team objects joined.
final allMatchesProvider = FutureProvider<List<MatchModel>>((ref) async {
  final data = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .order('kickoff_time');
  return (data as List)
      .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Up to 5 upcoming scheduled matches the current user hasn't predicted yet.
final upcomingUnpredictedProvider = FutureProvider<List<MatchModel>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final matches = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .eq('status', 'scheduled')
      .order('kickoff_time')
      .limit(20);

  final matchList = matches as List;
  if (matchList.isEmpty) return [];

  final matchIds = matchList.map((e) => e['id'] as int).toList();

  final preds = await supabase
      .from('predictions')
      .select('match_id')
      .eq('user_id', user.id)
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
  final user = supabase.auth.currentUser;

  final matches = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*), team2:teams!team2_id(*)')
      .eq('status', 'final')
      .order('kickoff_time', ascending: false)
      .limit(3);

  final matchList = matches as List;

  if (user == null) {
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
      .eq('user_id', user.id)
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
