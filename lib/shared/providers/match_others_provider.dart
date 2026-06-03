import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/features/matches/live_scoring.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';

/// Profile of every group-mate of the current user across **all** their
/// groups, deduplicated by `user_id`. Excludes the current user — the
/// Others tab is, by name, about everyone else.
///
/// Two round-trips because there's no direct FK between
/// `group_members.user_id` and `profiles.user_id` (both reference
/// `auth.users`), so PostgREST refuses to embed the join. Mirrors the
/// existing `groupMembersProvider` pattern.
final myGroupmatesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];

  // Step 1: user_ids of every group-mate, deduplicated.
  // RLS on group_members already restricts to my groups.
  final memberRows = await supabase
      .from('group_members')
      .select('user_id');
  final ids = <String>{};
  for (final row in memberRows as List) {
    final uid = (row as Map<String, dynamic>)['user_id'] as String?;
    if (uid != null && uid != me) ids.add(uid);
  }
  if (ids.isEmpty) return const [];

  // Step 2: profile rows for those ids.
  final profileRows = await supabase
      .from('profiles')
      .select()
      .inFilter('user_id', ids.toList());
  return (profileRows as List)
      .map((e) => ProfileModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// All locked predictions for [matchId], keyed by user_id. RLS limits
/// callers to predictions for users in their own groups (or themselves),
/// which is exactly what the Others tab needs.
final matchPredictionsByUserProvider = FutureProvider.autoDispose
    .family<Map<String, PredictionModel>, int>((ref, matchId) async {
  // User-scoped — clear on sign-in/out so account B never sees A's cache.
  ref.watch(currentUserIdProvider);
  final data = await supabase
      .from('predictions')
      .select()
      .eq('match_id', matchId)
      .not('locked_at', 'is', null);
  final out = <String, PredictionModel>{};
  for (final row in (data as List)) {
    final pred = PredictionModel.fromJson(row as Map<String, dynamic>);
    out[pred.userId] = pred;
  }
  return out;
});

/// Per-user booster rows for [matchId], keyed by user_id. Knockout-only;
/// for non-booster rounds this comes back empty and the multiplier
/// resolution falls through to [MatchModel.autoMultiplier].
final matchBoostersByUserProvider = FutureProvider.autoDispose
    .family<Map<String, RoundBoosterModel>, int>((ref, matchId) async {
  ref.watch(currentUserIdProvider);
  final data = await supabase
      .from('round_boosters')
      .select()
      .eq('match_id', matchId);
  final out = <String, RoundBoosterModel>{};
  for (final row in (data as List)) {
    final b = RoundBoosterModel.fromJson(row as Map<String, dynamic>);
    out[b.userId] = b;
  }
  return out;
});

/// A single row rendered on the OTHERS tab — a group-mate, their
/// (optional) prediction, and the live (or final) points they would
/// score if the match ended right now.
class OthersRow {
  final ProfileModel profile;
  final PredictionModel? prediction;
  final LiveScore? score;

  const OthersRow({
    required this.profile,
    required this.prediction,
    required this.score,
  });

  bool get hasPrediction => prediction != null;

  int get pointsTotal => score?.total ?? 0;
}

/// The OTHERS tab data — one row per group-mate, sorted by current
/// (live or final) points descending, name ascending as tie-breaker.
///
/// Watches the live match overlay + the events stream so a Realtime
/// score update or new goal event rebuilds this provider (and its
/// consumers re-sort) without an explicit invalidate.
final othersForMatchProvider = FutureProvider.autoDispose
    .family<List<OthersRow>, int>((ref, matchId) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];

  final profiles = await ref.watch(myGroupmatesProvider.future);
  if (profiles.isEmpty) return const [];

  final baseline = await ref.watch(matchByIdProvider(matchId).future);
  final overlay = ref.watch(liveMatchProvider(matchId));
  final match = mergeWithLive(baseline, overlay);

  final predictions =
      await ref.watch(matchPredictionsByUserProvider(matchId).future);
  final events =
      await ref.watch(matchEventsStreamProvider(matchId).future);
  final boosters =
      await ref.watch(matchBoostersByUserProvider(matchId).future);

  return buildOthersRows(
    match: match,
    profiles: profiles,
    predictionsByUser: predictions,
    boostersByUser: boosters,
    events: events,
  );
});

/// Pure helper that assembles + sorts the OTHERS rows from already-fetched
/// inputs. Exposed so it can be unit-tested without a Supabase round-trip.
///
/// Only group-mates **with a locked prediction** for this match become rows
/// — the OTHERS tab is a competition view, not a roll-call of everyone in
/// your groups. Each kept row is scored via [computeLiveScore] using the
/// per-user effective multiplier (booster row wins, else the match's
/// `autoMultiplier`: 1 for group stage, 5 for 3rd-place, 6 for Final).
///
/// Sort: points descending, then display name ascending (case-insensitive)
/// for stable ordering when totals tie.
List<OthersRow> buildOthersRows({
  required MatchModel match,
  required Iterable<ProfileModel> profiles,
  required Map<String, PredictionModel> predictionsByUser,
  required Map<String, RoundBoosterModel> boostersByUser,
  required List<MatchEventModel> events,
}) {
  final autoMultiplier = match.autoMultiplier;
  final rows = <OthersRow>[];
  for (final profile in profiles) {
    final pred = predictionsByUser[profile.userId];
    if (pred == null) continue; // Predictors only — drop non-participants.
    final multiplier =
        boostersByUser[profile.userId]?.multiplier ?? autoMultiplier;
    final score = computeLiveScore(
      match: match,
      prediction: pred,
      events: events,
      multiplier: multiplier,
    );
    rows.add(OthersRow(profile: profile, prediction: pred, score: score));
  }
  rows.sort((a, b) {
    final cmp = b.pointsTotal.compareTo(a.pointsTotal);
    if (cmp != 0) return cmp;
    final an = (a.profile.displayName ?? '').toLowerCase();
    final bn = (b.profile.displayName ?? '').toLowerCase();
    return an.compareTo(bn);
  });
  return rows;
}
