import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/group_model.dart';
import 'package:wcpredict/core/models/group_standing_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/supabase_client.dart';

/// Groups the current user belongs to.
final myGroupsProvider = FutureProvider<List<GroupModel>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];
  final data = await supabase
      .from('groups')
      .select('*, group_members!inner(user_id)')
      .eq('group_members.user_id', user.id)
      .order('created_at');
  return (data as List)
      .map((e) => GroupModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Leaderboard for a specific group, sorted by total_points descending.
final groupStandingsProvider =
    FutureProvider.family<List<GroupStandingModel>, String>((ref, groupId) async {
  final data = await supabase
      .from('group_standings')
      .select()
      .eq('group_id', groupId)
      .order('total_points', ascending: false);
  return (data as List)
      .map((e) => GroupStandingModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Profile of every member in a group.
final groupMembersProvider =
    FutureProvider.family<List<ProfileModel>, String>((ref, groupId) async {
  final data = await supabase
      .from('group_members')
      .select('profiles(*)')
      .eq('group_id', groupId);
  return (data as List)
      .map((e) =>
          ProfileModel.fromJson((e['profiles'] ?? e) as Map<String, dynamic>))
      .toList();
});
