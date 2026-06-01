import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/logger.dart';
import 'core/provider_observer.dart';
import 'core/supabase_client.dart';
void main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Route all Flutter framework + platform errors → Talker.
      FlutterError.onError = (details) {
        talker.handle(details.exception, details.stack, 'Flutter framework error');
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        talker.handle(error, stack, 'PlatformDispatcher error');
        return true; // treated as handled — prevents crash dialog in release
      };

      await initSupabase();
      runApp(
        ProviderScope(
          observers: const [AppProviderObserver()],
          child: const WcPredictApp(),
        ),
      );
    },
    (error, stack) {
      talker.handle(error, stack, 'Unhandled async error');
    },
  );
}
