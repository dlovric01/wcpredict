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
import 'core/push_notifications.dart';
import 'router.dart' show appRouter;
import 'package:supabase_flutter/supabase_flutter.dart' as sb show AuthChangeEvent;

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
      pushNotifications = PushNotifications(router: appRouter);
      await pushNotifications!.initialize();

      // Register the existing session's user — covers the "user opens the
      // app while already signed in" path that AuthRepository's per-method
      // hooks miss (those only fire on a fresh sign-in flow).
      final restoredUid = supabase.auth.currentUser?.id;
      if (restoredUid != null) {
        // Fire-and-forget so app boot isn't blocked on FCM token fetch.
        unawaited(pushNotifications!.registerForUser(restoredUid));
      }

      // Keep token registration in lockstep with auth lifecycle for the
      // duration of the process. Covers: silent session restore after the
      // app was killed, sign-in via a path that bypassed AuthRepository,
      // and account switches.
      supabase.auth.onAuthStateChange.listen((state) {
        final uid = state.session?.user.id;
        switch (state.event) {
          case sb.AuthChangeEvent.signedIn:
          case sb.AuthChangeEvent.initialSession:
          case sb.AuthChangeEvent.tokenRefreshed:
          case sb.AuthChangeEvent.userUpdated:
            if (uid != null) {
              unawaited(pushNotifications!.registerForUser(uid));
            }
            break;
          case sb.AuthChangeEvent.signedOut:
            unawaited(pushNotifications!.unregisterForCurrentDevice());
            break;
          default:
            break;
        }
      });

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
