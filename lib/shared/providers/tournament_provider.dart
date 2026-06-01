import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/player_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/models/tournament_prediction_model.dart';
import 'package:wcpredict/core/models/tournament_results_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Earliest non-cancelled match kickoff (DB function). Used to determine
// whether tournament predictions are still editable. Cached aggressively
// since this only shifts on schedule changes.
// ---------------------------------------------------------------------------
final tournamentOpeningKickoffProvider = FutureProvider<DateTime?>((ref) async {
  final raw = await supabase.rpc('tournament_opening_kickoff');
  if (raw == null) return null;
  return DateTime.parse(raw as String);
});

/// Computed lock state — true once the opening match kickoff is in the past.
final tournamentLockedProvider = Provider<bool>((ref) {
  final kickoff = ref.watch(tournamentOpeningKickoffProvider).valueOrNull;
  if (kickoff == null) return false;
  return DateTime.now().isAfter(kickoff);
});

// ---------------------------------------------------------------------------
// Current user's tournament prediction (null if not submitted yet)
// ---------------------------------------------------------------------------
final myTournamentPredictionProvider =
    FutureProvider<TournamentPredictionModel?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final data = await supabase
      .from('tournament_predictions')
      .select()
      .eq('user_id', userId)
      .maybeSingle();

  if (data == null) return null;
  return TournamentPredictionModel.fromJson(data);
});

// ---------------------------------------------------------------------------
// Singleton tournament results row (null until the admin posts the result)
// ---------------------------------------------------------------------------
final tournamentResultsProvider =
    FutureProvider<TournamentResultsModel?>((ref) async {
  final data = await supabase
      .from('tournament_results')
      .select()
      .eq('id', true)
      .maybeSingle();
  if (data == null) return null;
  return TournamentResultsModel.fromJson(data);
});

// ---------------------------------------------------------------------------
// Tournament-prediction picker support.
//
// Pickers do **not** load entire tables. Each list is a paginated search
// (up to 50 rows) bound to the user's current query string. Empty query
// returns the first 50 alphabetically — enough to browse on first open
// without scrolling through 1200+ rows or tripping Supabase's `max_rows`.
//
// Test-fixture team IDs (99_000+) are still excluded from the production
// UI. Match IDs use a different range (>= 100_000) and are not relevant
// here.
// ---------------------------------------------------------------------------

const int _pickerLimit = 50;
const int _testIdFloor = 99000;

/// Search teams by name. Pass `''` for the first page.
final teamSearchProvider =
    FutureProvider.family<List<TeamModel>, String>((ref, query) async {
  final trimmed = query.trim();
  var q = supabase
      .from('teams')
      .select()
      // Exclude regression-test fixtures (IDs 99_000+).
      .lt('id', _testIdFloor);
  if (trimmed.isNotEmpty) {
    q = q.ilike('name', '%$trimmed%');
  }
  final data =
      await q.order('name', ascending: true).limit(_pickerLimit);
  return (data as List)
      .map((e) => TeamModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Single team lookup — for rendering the currently picked label.
final teamByIdProvider =
    FutureProvider.family<TeamModel?, int>((ref, id) async {
  final data = await supabase
      .from('teams')
      .select()
      .eq('id', id)
      .maybeSingle();
  if (data == null) return null;
  return TeamModel.fromJson(data);
});

/// Player search row — bundles the player with the joined team so the
/// picker can show "Messi · Argentina" without a second round-trip.
class PlayerSearchHit {
  const PlayerSearchHit({required this.player, this.team});
  final PlayerModel player;
  final TeamModel? team;
}

/// Search players by name. Pass `''` for the first page.
final playerSearchProvider =
    FutureProvider.family<List<PlayerSearchHit>, String>((ref, query) async {
  final trimmed = query.trim();
  var q = supabase
      .from('players')
      .select('*, team:teams!team_id(*)')
      .lt('team_id', _testIdFloor);
  if (trimmed.isNotEmpty) {
    q = q.ilike('name', '%$trimmed%');
  }
  final data =
      await q.order('name', ascending: true).limit(_pickerLimit);
  return (data as List).map((row) {
    final m = row as Map<String, dynamic>;
    final teamJson = m['team'] as Map<String, dynamic>?;
    return PlayerSearchHit(
      player: PlayerModel.fromJson(m),
      team: teamJson == null ? null : TeamModel.fromJson(teamJson),
    );
  }).toList();
});

/// Single player lookup — for rendering the currently picked label.
final playerByIdProvider =
    FutureProvider.family<PlayerSearchHit?, int>((ref, id) async {
  final data = await supabase
      .from('players')
      .select('*, team:teams!team_id(*)')
      .eq('id', id)
      .maybeSingle();
  if (data == null) return null;
  final teamJson = data['team'] as Map<String, dynamic>?;
  return PlayerSearchHit(
    player: PlayerModel.fromJson(data),
    team: teamJson == null ? null : TeamModel.fromJson(teamJson),
  );
});
