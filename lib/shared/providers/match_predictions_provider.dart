// Powers the unified PREDICTIONS tab on the match detail screen.
//
// One ranked row per participant (the current user + every group-mate
// across all their groups, deduped). Self is always pinned at index 0
// regardless of points so "where do I stand?" is one glance, not a
// scan. Opponents fan out below by total points desc, name asc as
// stable tiebreaker.
//
// The provider chain watches three live streams:
//   • [liveMatchProvider]            — Realtime score / status overlay
//   • [matchEventsStreamProvider]    — Realtime goal/card/sub stream
//   • [matchPredictionsByUserProvider] — RLS-filtered locked predictions
// so a goal landing on the wire rebuilds + re-sorts the list without
// explicit invalidation.

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

/// Self + group-mate profiles for the prediction list. Self is split
/// out so the row builder can always pin it at the top, even when the
/// user has no group-mates yet (e.g. solo account viewing a match).
class PredictionParticipants {
  final ProfileModel? self;
  final List<ProfileModel> others;
  const PredictionParticipants({required this.self, required this.others});

  static const empty = PredictionParticipants(self: null, others: []);
}

/// Resolves the participant set for the PREDICTIONS tab: the current
/// user + every group-mate across all their groups, deduplicated.
///
/// Two round-trips because there's no direct FK between
/// `group_members.user_id` and `profiles.user_id` (both reference
/// `auth.users`), so PostgREST refuses to embed the join.
final predictionParticipantsProvider =
    FutureProvider<PredictionParticipants>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return PredictionParticipants.empty;

  // Step 1: user_ids of every group member visible to me (RLS already
  // limits group_members to my groups). Include self so a user in zero
  // groups still gets their own row.
  final memberRows = await supabase.from('group_members').select('user_id');
  final ids = <String>{me};
  for (final row in memberRows as List) {
    final uid = (row as Map<String, dynamic>)['user_id'] as String?;
    if (uid != null) ids.add(uid);
  }

  // Step 2: profile rows for those ids. Split self out of the result.
  final profileRows = await supabase
      .from('profiles')
      .select()
      .inFilter('user_id', ids.toList());

  ProfileModel? self;
  final others = <ProfileModel>[];
  for (final r in profileRows as List) {
    final profile = ProfileModel.fromJson(r as Map<String, dynamic>);
    if (profile.userId == me) {
      self = profile;
    } else {
      others.add(profile);
    }
  }
  return PredictionParticipants(self: self, others: others);
});

/// All locked predictions for [matchId], keyed by user_id. RLS limits
/// callers to predictions for users in their own groups (or themselves),
/// and the `locked_at IS NOT NULL` filter is the no-spoiler safeguard
/// for pre-kickoff opponent picks.
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

/// One row on the PREDICTIONS tab — a participant (self or group-mate),
/// their (optional) prediction, and the live (or final) points they
/// would score if the match ended right now.
class PredictionRow {
  final ProfileModel profile;
  final PredictionModel? prediction;
  final LiveScore? score;

  /// True when this row represents the currently-signed-in user. Drives
  /// pinned-at-top placement and the always-reveal-my-own-picks rule.
  final bool isSelf;

  const PredictionRow({
    required this.profile,
    required this.prediction,
    required this.score,
    this.isSelf = false,
  });

  bool get hasPrediction => prediction != null;

  int get pointsTotal => score?.total ?? 0;
}

/// The PREDICTIONS tab data — self pinned at index 0, then group-mates
/// with a locked prediction sorted by current (live or final) points
/// descending, name ascending as tie-breaker.
///
/// Watches the live match overlay + the events stream so a Realtime
/// score update or new goal event rebuilds this provider (and its
/// consumers re-sort) without an explicit invalidate.
final predictionsForMatchProvider = FutureProvider.autoDispose
    .family<List<PredictionRow>, int>((ref, matchId) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const [];

  final participants =
      await ref.watch(predictionParticipantsProvider.future);

  final baseline = await ref.watch(matchByIdProvider(matchId).future);
  final overlay = ref.watch(liveMatchProvider(matchId));
  final match = mergeWithLive(baseline, overlay);

  final predictions =
      await ref.watch(matchPredictionsByUserProvider(matchId).future);
  final events =
      await ref.watch(matchEventsStreamProvider(matchId).future);
  final boosters =
      await ref.watch(matchBoostersByUserProvider(matchId).future);

  return buildPredictionRows(
    match: match,
    selfProfile: participants.self,
    otherProfiles: participants.others,
    predictionsByUser: predictions,
    boostersByUser: boosters,
    events: events,
  );
});

/// Pure helper that assembles + sorts the PREDICTIONS rows from
/// already-fetched inputs. Exposed so it can be unit-tested without a
/// Supabase round-trip.
///
/// Contract:
///   * Self is **always** included when [selfProfile] is non-null — even
///     when they have no locked prediction for this match — and is
///     pinned at index 0 of the returned list regardless of points.
///   * Other participants appear only when they have a locked prediction
///     for the match (the tab is a competition view, not a roll-call of
///     every group-mate).
///   * Each kept row is scored via [computeLiveScore] using the per-user
///     effective multiplier (booster row wins, else the match's
///     `autoMultiplier`: 1 for group stage, 5 for 3rd-place, 6 for Final).
///   * Sort order for others: points descending, then display name
///     ascending (case-insensitive) for stable ordering when totals tie.
List<PredictionRow> buildPredictionRows({
  required MatchModel match,
  required ProfileModel? selfProfile,
  required Iterable<ProfileModel> otherProfiles,
  required Map<String, PredictionModel> predictionsByUser,
  required Map<String, RoundBoosterModel> boostersByUser,
  required List<MatchEventModel> events,
}) {
  final autoMultiplier = match.autoMultiplier;

  PredictionRow scoreRowFor(ProfileModel profile, {required bool isSelf}) {
    final pred = predictionsByUser[profile.userId];
    LiveScore? score;
    if (pred != null) {
      final multiplier =
          boostersByUser[profile.userId]?.multiplier ?? autoMultiplier;
      score = computeLiveScore(
        match: match,
        prediction: pred,
        events: events,
        multiplier: multiplier,
      );
    }
    return PredictionRow(
      profile: profile,
      prediction: pred,
      score: score,
      isSelf: isSelf,
    );
  }

  final others = <PredictionRow>[];
  for (final profile in otherProfiles) {
    if (predictionsByUser[profile.userId] == null) continue;
    others.add(scoreRowFor(profile, isSelf: false));
  }
  others.sort((a, b) {
    final cmp = b.pointsTotal.compareTo(a.pointsTotal);
    if (cmp != 0) return cmp;
    final an = (a.profile.displayName ?? '').toLowerCase();
    final bn = (b.profile.displayName ?? '').toLowerCase();
    return an.compareTo(bn);
  });

  if (selfProfile == null) return others;
  final selfRow = scoreRowFor(selfProfile, isSelf: true);
  return [selfRow, ...others];
}
