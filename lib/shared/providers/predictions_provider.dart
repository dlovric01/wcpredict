import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';

// ---------------------------------------------------------------------------
// Current user's prediction for a specific match (null if none yet)
// ---------------------------------------------------------------------------
final myPredictionProvider =
    FutureProvider.family<PredictionModel?, int>((ref, matchId) async {
  final user = supabase.auth.currentUser;
  if (user == null) return null;

  final data = await supabase
      .from('predictions')
      .select()
      .eq('user_id', user.id)
      .eq('match_id', matchId)
      .maybeSingle();

  if (data == null) return null;
  return PredictionModel.fromJson(data);
});
