import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/group_model.dart';
import 'package:wcpredict/core/models/group_standing_model.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

/// Groups the current user belongs to, with `memberCount` filled in
/// via a single batched follow-up query. Two round-trips total: one
/// to filter groups by membership, one to count members per group.
///
/// `group_members_read` RLS (migration 002) allows a member to see
/// every row for groups they belong to, so the count query returns
/// real totals — not just the caller's own membership.
final myGroupsProvider = FutureProvider<List<GroupModel>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  final data = await supabase
      .from('groups')
      .select('*, group_members!inner(user_id)')
      .eq('group_members.user_id', userId)
      .order('created_at');
  final groups = (data as List)
      .map((e) => GroupModel.fromJson(e as Map<String, dynamic>))
      .toList();
  if (groups.isEmpty) return groups;

  // Batched count fetch. Single round-trip; RLS already restricts the
  // result to groups the user can see.
  final ids = groups.map((g) => g.id).toList();
  final rows = await supabase
      .from('group_members')
      .select('group_id')
      .inFilter('group_id', ids);

  final counts = <String, int>{};
  for (final row in rows as List) {
    final gid = (row as Map<String, dynamic>)['group_id'] as String;
    counts[gid] = (counts[gid] ?? 0) + 1;
  }

  return groups
      .map((g) => g.copyWith(memberCount: counts[g.id] ?? 1))
      .toList();
});

/// Leaderboard for a specific group, sorted by total_points descending.
final groupStandingsProvider =
    FutureProvider.family<List<GroupStandingModel>, String>((ref, groupId) async {
  // RLS-scoped: data depends on whether the current user is a member,
  // so reset the cache on sign-in/out.
  ref.watch(currentUserIdProvider);
  final data = await supabase
      .from('group_standings')
      .select()
      .eq('group_id', groupId)
      .order('total_points',        ascending: false)
      .order('exact_count',         ascending: false)
      .order('scorer_count',        ascending: false)
      .order('goal_diff_count',     ascending: false)
      .order('outcome_count',       ascending: false)
      .order('earliest_submission', ascending: true);
  return (data as List)
      .map((e) => GroupStandingModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Profile of every member in a group.
final groupMembersProvider =
    FutureProvider.family<List<ProfileModel>, String>((ref, groupId) async {
  // RLS-scoped: cleared on user change so account B never sees account
  // A's cached member list.
  ref.watch(currentUserIdProvider);
  // Step 1: get user IDs for this group
  final memberData = await supabase
      .from('group_members')
      .select('user_id')
      .eq('group_id', groupId);

  final ids = (memberData as List)
      .map((e) => e['user_id'] as String)
      .toList();

  if (ids.isEmpty) return [];

  // Step 2: fetch profiles for those users
  final data = await supabase
      .from('profiles')
      .select()
      .inFilter('user_id', ids);

  return (data as List)
      .map((e) => ProfileModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Locked predictions for [userId] with match + team data, sorted by kickoff.
/// RLS ensures callers only see locked predictions for other users.
final userPredictionsProvider = FutureProvider.family<
    List<({PredictionModel prediction, MatchModel match})>, String>(
  (ref, userId) async {
    // RLS-scoped — must reset across sign-in/out transitions.
    ref.watch(currentUserIdProvider);
    final data = await supabase
        .from('predictions')
        .select(
          '*, match:matches!match_id('
          '*, team1:teams!team1_id(*, players(*)),'
          ' team2:teams!team2_id(*, players(*)))',
        )
        .eq('user_id', userId)
        .not('locked_at', 'is', null);

    final rows = (data as List).map((e) {
      final map = e as Map<String, dynamic>;
      return (
        prediction: PredictionModel.fromJson(map),
        match: MatchModel.fromJson(map['match'] as Map<String, dynamic>),
      );
    }).toList();

    rows.sort((a, b) {
      final ta = a.match.kickoffTime;
      final tb = b.match.kickoffTime;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });

    return rows;
  },
);
