import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/supabase_client.dart';

/// Single match by id — joins both teams with their players.
///
/// This is a one-shot fetch: it does NOT watch the live ticker, because
/// in-match score / status updates are delivered separately through
/// `liveMatchProvider` (in `matches_provider.dart`). The detail screen
/// merges the cached baseline with the live overlay row-by-row so the
/// hero scoreboard updates without rebuilding the whole screen.
///
/// Re-fetched only on explicit invalidate (pull-to-refresh, route
/// re-entry) or when the user re-opens this match.
final matchByIdProvider =
    FutureProvider.autoDispose.family<MatchModel, int>((ref, id) async {
  final data = await supabase
      .from('matches')
      .select(
          '*, team1:teams!team1_id(*, players(*)), team2:teams!team2_id(*, players(*))')
      .eq('id', id)
      .single();
  return MatchModel.fromJson(data);
});

/// Events for a match — non-realtime one-shot. Prefer
/// [matchEventsStreamProvider] for live timelines.
final matchEventsProvider = FutureProvider.autoDispose
    .family<List<MatchEventModel>, int>((ref, matchId) async {
  final data = await supabase
      .from('match_events')
      .select()
      .eq('match_id', matchId)
      .order('minute');
  return (data as List)
      .map((e) => MatchEventModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Streams match events in real-time. Falls back to FutureProvider data
/// for finished matches; live matches get push updates.
final matchEventsStreamProvider = StreamProvider.family
    .autoDispose<List<MatchEventModel>, int>((ref, matchId) {
  return supabase
      .from('match_events')
      .stream(primaryKey: ['id'])
      .eq('match_id', matchId)
      .map((rows) {
        // Sort client-side ascending by minute. The stream's .order()
        // only applies to the initial fetch; subsequent realtime
        // upserts append in insertion order, which is wrong for
        // out-of-order goals (VAR overturns, delayed event ingestion).
        final events = rows.map(MatchEventModel.fromJson).toList()
          ..sort((a, b) {
            final am = a.minute ?? 0;
            final bm = b.minute ?? 0;
            if (am != bm) return am.compareTo(bm);
            return (a.minuteExtra ?? 0).compareTo(b.minuteExtra ?? 0);
          });
        return events;
      });
});
