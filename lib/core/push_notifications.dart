import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:wcpredict/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'logger.dart';
import 'supabase_client.dart';

/// Global singleton — initialised in `main.dart` so `AuthRepository`
/// (which does not have a Riverpod ref) can call into the lifecycle
/// hooks directly. Same pattern as `talker` from `logger.dart`.
PushNotifications? pushNotifications;

/// Background-isolate entry point for FCM messages.
///
/// MUST be a top-level (or static) function with `@pragma('vm:entry-point')`
/// — `FirebaseMessaging.onBackgroundMessage` calls it from a fresh isolate
/// with no inherited state.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Background sends fire automatically; we only need to ensure Firebase is
  // initialised in this isolate. Nothing else to do here — the OS shows the
  // notification, and a tap routes through the foreground handler.
  await Firebase.initializeApp();
}

/// Wraps `firebase_messaging` and `firebase_core` behind an interface the
/// rest of the app can call without importing the Firebase plugins
/// directly. Lets the unit tests inject a fake.
abstract class FcmGateway {
  Future<void> initializeFirebase();
  Future<NotificationSettings> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Future<void> deleteToken();
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
  void setBackgroundMessageHandler(
      Future<void> Function(RemoteMessage) handler);
}

/// Production gateway — delegates to the real Firebase SDK.
class _RealFcmGateway implements FcmGateway {
  @override
  Future<void> initializeFirebase() =>
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  @override
  Future<NotificationSettings> requestPermission() =>
      FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() =>
      FirebaseMessaging.instance.getInitialMessage();

  @override
  void setBackgroundMessageHandler(
      Future<void> Function(RemoteMessage) handler) {
    FirebaseMessaging.onBackgroundMessage(handler);
  }
}

/// Lifecycle hub for push notifications.
///
/// Responsibilities:
///   * Initialise Firebase (idempotent — safe to call from `main`).
///   * Request iOS permission once, on first successful sign-in.
///   * Register the FCM token in `device_tokens` after sign-in and
///     re-register on token-refresh events.
///   * Delete the local token on sign-out.
///   * Wire foreground / cold-start / background-tap message handlers
///     to deep-link via the app's GoRouter.
class PushNotifications {
  PushNotifications({
    FcmGateway? gateway,
    GoRouter? router,
  })  : _fcm = gateway ?? _RealFcmGateway(),
        _router = router;

  final FcmGateway _fcm;
  final GoRouter? _router;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openSub;
  bool _initialized = false;

  /// Initialise Firebase and wire the global background handler.
  ///
  /// Idempotent. Silently swallows initialisation failures (logs them
  /// via Talker) so a missing `GoogleService-Info.plist` doesn't crash
  /// the app boot — push reminders are non-essential.
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      await _fcm.initializeFirebase();
      _fcm.setBackgroundMessageHandler(_firebaseBackgroundHandler);
      _wireHandlers();
      _initialized = true;
      return true;
    } catch (e, st) {
      talker.handle(e, st, 'Firebase init failed — push reminders disabled');
      return false;
    }
  }

  /// Register the current device's FCM token against [userId].
  ///
  /// Safe to call repeatedly; the upsert keys on (user_id, token).
  /// No-op if Firebase isn't initialised yet or if no token comes back.
  Future<void> registerForUser(String userId) async {
    if (!_initialized) return;
    try {
      await _fcm.requestPermission();
      final token = await _fcm.getToken();
      if (token == null || token.isEmpty) return;
      await _upsertToken(userId, token);

      // Replace any prior refresh subscription so we don't leak.
      await _tokenSub?.cancel();
      _tokenSub = _fcm.onTokenRefresh.listen((newToken) {
        // Use the most recent supabase session user-id, not the captured
        // one — token refresh can fire after a sign-out/sign-in cycle.
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) _upsertToken(uid, newToken);
      });

      // Surface a cold-start tap if one is queued.
      final initial = await _fcm.getInitialMessage();
      if (initial != null) _handleTap(initial);
    } catch (e, st) {
      talker.handle(e, st, 'registerForUser failed');
    }
  }

  /// Delete the current device's token from `device_tokens` and from FCM.
  ///
  /// Called from sign-out so the next sign-in (possibly as a different
  /// account on the same device) doesn't inherit the previous user's
  /// notification subscription.
  Future<void> unregisterForCurrentDevice() async {
    if (!_initialized) return;
    String? token;
    try {
      token = await _fcm.getToken();
    } catch (e, st) {
      talker.handle(e, st, 'getToken before unregister failed');
    }

    try {
      final userId = supabase.auth.currentUser?.id;
      if (token != null && userId != null) {
        await supabase
            .from('device_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('token', token);
      }
    } catch (e, st) {
      talker.handle(e, st, 'device_tokens delete failed');
    }

    try {
      await _fcm.deleteToken();
    } catch (e, st) {
      talker.handle(e, st, 'fcm deleteToken failed');
    }

    await _tokenSub?.cancel();
    _tokenSub = null;
  }

  /// Stops all handler subscriptions. Mainly for tests.
  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openSub?.cancel();
    _tokenSub = null;
    _foregroundSub = null;
    _openSub = null;
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<void> _upsertToken(String userId, String token) async {
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    await supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': platform,
    }, onConflict: 'user_id,token');
  }

  void _wireHandlers() {
    _foregroundSub?.cancel();
    _openSub?.cancel();

    _foregroundSub = _fcm.onMessage.listen((message) {
      // We deliberately do NOT auto-route on foreground arrival — the user
      // is already actively using the app. The system will not show an
      // OS-level banner here (iOS suppresses by default). Logging is enough
      // for the diagnostic FAB; if we ever want an in-app banner this is
      // where it'd hook in.
      final title = message.notification?.title;
      if (title != null) {
        talker.info('Foreground push: $title');
      }
    });

    _openSub = _fcm.onMessageOpenedApp.listen(_handleTap);
  }

  void _handleTap(RemoteMessage message) {
    final router = _router;
    if (router == null) return;
    final link = message.data['deep_link'] as String?;
    if (link == null || link.isEmpty) return;
    try {
      router.push(link);
    } catch (e, st) {
      talker.handle(e, st, 'Deep-link nav failed: $link');
    }
  }
}
