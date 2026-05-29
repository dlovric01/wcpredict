import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/supabase_client.dart';

/// Single match by id — joins both teams with their players
final matchByIdProvider = FutureProvider.family<MatchModel, int>((ref, id) async {
  final data = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*, players(*)), team2:teams!team2_id(*, players(*))')
      .eq('id', id)
      .single();
  return MatchModel.fromJson(data);
});

/// Events for a finished match
final matchEventsProvider =
    FutureProvider.family<List<MatchEventModel>, int>((ref, matchId) async {
  final data = await supabase
      .from('match_events')
      .select()
      .eq('match_id', matchId)
      .order('minute');
  return (data as List)
      .map((e) => MatchEventModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
