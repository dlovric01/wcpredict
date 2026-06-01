// Regression cover for the cross-account data-leak bug: after sign-out
// then sign-in as a different user, user-scoped Riverpod providers kept
// serving the previous account's cached data until the process was
// killed. The fix is `currentUserIdProvider` — a stable String? key that
// every user-scoped provider must `ref.watch`, so Riverpod's dependency
// graph invalidates them whenever the user id flips.
//
// These tests pin two invariants:
//   1. The id is null when there is no user, present when there is.
//   2. Equality is by id (String), so token-refresh events that return
//      a new User instance with the same id do NOT re-fire dependents.
//      A different id (sign-out → sign-in as different account) DOES.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

User _user(String id, {String? updatedAt}) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: updatedAt,
    );

/// Test-only bridge: a [StateProvider] the test can mutate, exposed as
/// the source of truth that [currentUserProvider] reads from.
final _bridge = StateProvider<User?>((ref) => null);

/// Override list shared by tests that need to flip the user at runtime.
final _overrides = <Override>[
  currentUserProvider.overrideWith((ref) => ref.watch(_bridge)),
];

void main() {
  group('currentUserIdProvider', () {
    test('returns null when no user is signed in', () {
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);
      expect(container.read(currentUserIdProvider), isNull);
    });

    test('returns the user id when a user is present', () {
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(_user('user-a')),
      ]);
      addTearDown(container.dispose);
      expect(container.read(currentUserIdProvider), 'user-a');
    });

    test('flips when the user id changes (sign-out → sign-in as other user)',
        () {
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_bridge)),
      ]);
      addTearDown(container.dispose);

      // Starting state: signed in as user-a.
      container.read(_bridge.notifier).state = _user('user-a');
      expect(container.read(currentUserIdProvider), 'user-a');

      // Sign-out.
      container.read(_bridge.notifier).state = null;
      expect(container.read(currentUserIdProvider), isNull);

      // Sign-in as a different user.
      container.read(_bridge.notifier).state = _user('user-b');
      expect(container.read(currentUserIdProvider), 'user-b');
    });

    test('does NOT notify on token refresh that keeps the same id', () {
      // Token refresh emits a fresh User object with the same id but a
      // different `updatedAt`. The User class overrides == with a deep
      // field compare, so without the id-only projection a refresh would
      // invalidate every user-scoped provider on the screen.
      final container = ProviderContainer(overrides: _overrides);
      addTearDown(container.dispose);

      container.read(_bridge.notifier).state =
          _user('user-a', updatedAt: 't1');

      final received = <String?>[];
      container.listen<String?>(
        currentUserIdProvider,
        (_, next) => received.add(next),
        fireImmediately: true,
      );

      expect(received, ['user-a']);

      // Token refresh: same id, different User instance.
      container.read(_bridge.notifier).state =
          _user('user-a', updatedAt: 't2');

      // currentUserProvider's emitted value changed (different User
      // instance), but currentUserIdProvider's projected String is
      // identical so listeners must not fire again.
      expect(received, ['user-a']);
    });
  });
}
