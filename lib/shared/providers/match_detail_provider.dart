import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/supabase_client.dart';

/// Single match by id — joins both teams with their players.
/// Single match by id — joins both teams with their players.
final matchByIdProvider = FutureProvider.autoDispose.family<MatchModel, int>((ref, id) async {
  final data = await supabase
      .from('matches')
      .select('*, team1:teams!team1_id(*, players(*)), team2:teams!team2_id(*, players(*))')
      .eq('id', id)
      .single();
  return MatchModel.fromJson(data);
});

/// Events for a match.
/// Events for a match.
final matchEventsProvider =
    FutureProvider.autoDispose.family<List<MatchEventModel>, int>((ref, matchId) async {
  final data = await supabase
      .from('match_events')
      .select()
      .eq('match_id', matchId)
      .order('minute');
  return (data as List)
      .map((e) => MatchEventModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Streams live score/status for a single match row.
/// Used by the match detail hero to update the scoreboard without refetching teams.
final matchLiveStateProvider =
    StreamProvider.family.autoDispose<Map<String, dynamic>?, int>(
  (ref, matchId) {
    return supabase
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('id', matchId)
        .map((rows) => rows.isNotEmpty ? rows.first : null);
  },
);

/// Streams match events in real-time. Falls back to FutureProvider data
/// for finished matches; live matches get push updates.
final matchEventsStreamProvider =
    StreamProvider.family.autoDispose<List<MatchEventModel>, int>(
  (ref, matchId) {
    return supabase
        .from('match_events')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('minute')
        .map((rows) => rows
            .map((e) => MatchEventModel.fromJson(e))
            .toList());
  },
);
