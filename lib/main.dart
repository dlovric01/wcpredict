import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/supabase_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: WcPredictApp()));
}
