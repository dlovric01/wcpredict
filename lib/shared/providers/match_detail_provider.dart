import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/models/player_model.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';

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

/// Matchday squad for a single fixture — what api-sports.io
/// `/fixtures/lineups` returned for THIS fixture (11 starters + bench).
///
/// Distinct from `match.team1.players` / `match.team2.players`, which
/// expose the full season-long roster (~25-35 per team) used by the
/// goalscorer picker. The Teams tab uses this provider exclusively so
/// non-matchday reserves never show up in the "Substitutes" section.
///
/// Returns an empty list when `match_lineups` has no rows for the
/// fixture yet (pre-poll_lineups or for matches outside the 45-min
/// window). Callers should gate with `teamsTabLineupReady(match)`
/// before showing the roster UI.
final matchLineupProvider =
    FutureProvider.autoDispose.family<List<PlayerModel>, int>((ref, matchId) async {
  final rows = await supabase
      .from('match_lineups')
      .select('is_starter, grid, players(id, team_id, name, position, jersey_number)')
      .eq('match_id', matchId);
  return rows
      .map((row) {
        final p = row['players'] as Map<String, dynamic>?;
        if (p == null) return null;
        return PlayerModel(
          id: (p['id'] as num).toInt(),
          teamId: (p['team_id'] as num).toInt(),
          name: p['name'] as String,
          position: p['position'] as String?,
          jerseyNumber: (p['jersey_number'] as num?)?.toInt(),
          grid: row['grid'] as String?,
          isStarter: (row['is_starter'] as bool?) ?? true,
        );
      })
      .whereType<PlayerModel>()
      .toList();
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

/// Match-event timeline. Realtime push during the live window, plain
/// one-shot fetch otherwise.
///
/// Why the gate: holding a websocket open for every detail-view of a
/// finished match would burn through the Supabase free-plan
/// 200-concurrent-connection cap once users start browsing past
/// results. A final match's events never change again (modulo manual
/// VAR corrections, which are rare), so a single SELECT is enough.
///
/// Subscribes ONLY when the match is `status == 'live'` or within
/// `[kickoff - 5 min .. kickoff + 3 h]`. Anything else (final,
/// cancelled, far-future scheduled, missing from cache) gets a
/// one-shot fetch.
///
/// `clockTickerProvider` (30 s) is watched so a scheduled match
/// crossing into its window transparently upgrades from one-shot to
/// streaming without the user closing and re-opening the screen.
final matchEventsStreamProvider = StreamProvider.family
    .autoDispose<List<MatchEventModel>, int>((ref, matchId) async* {
  final now = ref.watch(clockTickerProvider).valueOrNull ?? DateTime.now();
  final matches = ref.watch(allMatchesProvider).valueOrNull;

  MatchModel? match;
  if (matches != null) {
    for (final m in matches) {
      if (m.id == matchId) {
        match = m;
        break;
      }
    }
  }

  bool needsRealtime = false;
  if (match != null) {
    if (match.status == 'live') {
      needsRealtime = true;
    } else if (match.status != 'final' && match.status != 'cancelled') {
      final k = match.kickoffTime;
      if (k != null) {
        final open  = k.subtract(const Duration(minutes: 5));
        final close = k.add(const Duration(hours: 3));
        if (now.isAfter(open) && now.isBefore(close)) needsRealtime = true;
      }
    }
  }

  List<MatchEventModel> sortEvents(Iterable<MatchEventModel> events) {
    // Sort client-side ascending by minute. The stream's .order()
    // only applies to the initial fetch; subsequent realtime upserts
    // append in insertion order, which is wrong for out-of-order
    // goals (VAR overturns, delayed event ingestion).
    final list = events.toList()
      ..sort((a, b) {
        final am = a.minute ?? 0;
        final bm = b.minute ?? 0;
        if (am != bm) return am.compareTo(bm);
        return (a.minuteExtra ?? 0).compareTo(b.minuteExtra ?? 0);
      });
    return list;
  }

  if (!needsRealtime) {
    final rows = await supabase
        .from('match_events')
        .select()
        .eq('match_id', matchId)
        .order('minute');
    yield sortEvents(
      (rows as List).map((e) => MatchEventModel.fromJson(e as Map<String, dynamic>)),
    );
    return;
  }

  yield* supabase
      .from('match_events')
      .stream(primaryKey: ['id'])
      .eq('match_id', matchId)
      .map((rows) => sortEvents(rows.map(MatchEventModel.fromJson)));
});
