import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

/// All boosters for the current user, keyed by round.
final myBoostersProvider =
    FutureProvider<Map<String, RoundBoosterModel>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return {};
  final data = await supabase
      .from('round_boosters')
      .select()
      .eq('user_id', userId);
  final list = (data as List)
      .map((e) => RoundBoosterModel.fromJson(e as Map<String, dynamic>))
      .toList();
  return {for (final b in list) b.round: b};
});

/// The booster the current user has applied to a specific match (if any).
final boosterForMatchProvider =
    FutureProvider.family<RoundBoosterModel?, int>((ref, matchId) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final data = await supabase
      .from('round_boosters')
      .select()
      .eq('user_id', userId)
      .eq('match_id', matchId)
      .maybeSingle();
  if (data == null) return null;
  return RoundBoosterModel.fromJson(data);
});
