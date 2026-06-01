import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Current user's prediction for a specific match (null if none yet)
// ---------------------------------------------------------------------------
final myPredictionProvider =
    FutureProvider.family<PredictionModel?, int>((ref, matchId) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final data = await supabase
      .from('predictions')
      .select()
      .eq('user_id', userId)
      .eq('match_id', matchId)
      .maybeSingle();

  if (data == null) return null;
  return PredictionModel.fromJson(data);
});

// ---------------------------------------------------------------------------
// All of the current user's predictions (lightweight — only match_id and locked_at)
// ---------------------------------------------------------------------------
final myAllPredictionsProvider = FutureProvider<List<PredictionModel>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  final data = await supabase
      .from('predictions')
      .select('id, user_id, match_id, locked_at')
      .eq('user_id', userId);
  return (data as List)
      .map((e) => PredictionModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
