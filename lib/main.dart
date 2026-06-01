import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'app.dart';
import 'core/logger.dart';
import 'core/provider_observer.dart';
import 'core/supabase_client.dart';

/// Optional debug-only auto-login. Set via:
///   --dart-define=DEV_AUTOLOGIN_USER=alice
/// The app boots straight into the authenticated state as that test
/// user, skipping the sign-in screen entirely. Useful for simulator
/// drives where CLI cannot tap the dummy-login button.
const _kDevAutoLoginUser = String.fromEnvironment('DEV_AUTOLOGIN_USER');

Future<void> _devAutoLogin() async {
  if (!kDebugMode || _kDevAutoLoginUser.isEmpty) return;
  if (supabase.auth.currentSession != null) return;
  final email = '$_kDevAutoLoginUser@wctest.invalid';
  const password = 'TestPass99!';
  try {
    try {
      await supabase.auth
          .signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      if (e.statusCode == '400' || e.statusCode == '401') {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'display_name': _kDevAutoLoginUser},
        );
        if (supabase.auth.currentSession == null) {
          await supabase.auth
              .signInWithPassword(email: email, password: password);
        }
      } else {
        rethrow;
      }
    }
    talker.info('Dev auto-login succeeded as $_kDevAutoLoginUser');
  } catch (e, st) {
    talker.handle(e, st, 'Dev auto-login failed');
  }
}
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
      await _devAutoLogin();
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
