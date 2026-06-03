import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/push_notifications.dart';

/// Fake gateway captures every call and exposes synthetic stream
/// controllers for the message + token-refresh streams.
class FakeFcmGateway implements FcmGateway {
  int initCount = 0;
  int permissionCount = 0;
  int deleteCount = 0;
  Future<void> Function(RemoteMessage)? backgroundHandler;
  String? currentToken;

  final tokenRefreshCtrl = StreamController<String>.broadcast();
  final onMessageCtrl = StreamController<RemoteMessage>.broadcast();
  final onOpenedCtrl = StreamController<RemoteMessage>.broadcast();
  RemoteMessage? initialMessage;
  Exception? initError;

  @override
  Future<void> initializeFirebase() async {
    initCount++;
    if (initError != null) throw initError!;
  }

  @override
  Future<NotificationSettings> requestPermission() async {
    permissionCount++;
    // Returning a real NotificationSettings is fiddly across versions;
    // tests don't introspect the result, so cast a minimal stub.
    return _fakeSettings;
  }

  @override
  Future<String?> getToken() async => currentToken;

  @override
  Stream<String> get onTokenRefresh => tokenRefreshCtrl.stream;

  @override
  Future<void> deleteToken() async {
    deleteCount++;
    currentToken = null;
  }

  @override
  Stream<RemoteMessage> get onMessage => onMessageCtrl.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => onOpenedCtrl.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;

  @override
  void setBackgroundMessageHandler(
      Future<void> Function(RemoteMessage) handler) {
    backgroundHandler = handler;
  }
}

// `NotificationSettings` requires multiple enum args; we don't read it
// so this fixed instance via the default constructor is fine for tests.
final NotificationSettings _fakeSettings = const NotificationSettings(
  authorizationStatus: AuthorizationStatus.authorized,
  alert: AppleNotificationSetting.enabled,
  announcement: AppleNotificationSetting.notSupported,
  badge: AppleNotificationSetting.enabled,
  carPlay: AppleNotificationSetting.notSupported,
  lockScreen: AppleNotificationSetting.enabled,
  notificationCenter: AppleNotificationSetting.enabled,
  showPreviews: AppleShowPreviewSetting.always,
  timeSensitive: AppleNotificationSetting.notSupported,
  criticalAlert: AppleNotificationSetting.notSupported,
  sound: AppleNotificationSetting.enabled,
  providesAppNotificationSettings: AppleNotificationSetting.notSupported,
);

void main() {
  group('PushNotifications.initialize', () {
    test('first call initialises Firebase and wires background handler',
        () async {
      final fake = FakeFcmGateway();
      final push = PushNotifications(gateway: fake);

      final ok = await push.initialize();
      expect(ok, isTrue);
      expect(fake.initCount, 1);
      expect(fake.backgroundHandler, isNotNull);
    });

    test('second call is a no-op (idempotent)', () async {
      final fake = FakeFcmGateway();
      final push = PushNotifications(gateway: fake);

      await push.initialize();
      await push.initialize();
      expect(fake.initCount, 1);
    });

    test('returns false and swallows when Firebase init throws', () async {
      final fake = FakeFcmGateway()..initError = Exception('no config');
      final push = PushNotifications(gateway: fake);

      final ok = await push.initialize();
      expect(ok, isFalse);
    });
  });

  group('PushNotifications.registerForUser', () {
    test('skips Supabase writes when Firebase is not initialised', () async {
      final fake = FakeFcmGateway()..currentToken = 'abc';
      final push = PushNotifications(gateway: fake);

      // Did not call initialize() — register must be a guarded no-op.
      await push.registerForUser('user-1');
      expect(fake.permissionCount, 0);
    });

    test('requests permission once after init even with no token', () async {
      final fake = FakeFcmGateway(); // no token
      final push = PushNotifications(gateway: fake);

      await push.initialize();
      await push.registerForUser('user-1');

      expect(fake.permissionCount, 1);
    });
  });

  group('PushNotifications.unregisterForCurrentDevice', () {
    test('deletes FCM token after init', () async {
      final fake = FakeFcmGateway()..currentToken = 'abc';
      final push = PushNotifications(gateway: fake);
      await push.initialize();

      await push.unregisterForCurrentDevice();
      expect(fake.deleteCount, 1);
    });

    test('no-op when not initialised', () async {
      final fake = FakeFcmGateway()..currentToken = 'abc';
      final push = PushNotifications(gateway: fake);

      await push.unregisterForCurrentDevice();
      expect(fake.deleteCount, 0);
    });
  });
}
