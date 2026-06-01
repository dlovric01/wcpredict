// Auth-redirect truth-table tests. The redirect runs on every GoRouter
// navigation including refresh on `onAuthStateChange`, so any regression
// here breaks the sign-in flow for every user.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/router_redirect.dart';

void main() {
  group('computeAuthRedirect — unauthenticated user', () {
    test('non-public route → bounce to /sign-in', () {
      expect(
        computeAuthRedirect(loggedIn: false, location: '/matches'),
        '/sign-in',
      );
      expect(
        computeAuthRedirect(loggedIn: false, location: '/groups'),
        '/sign-in',
      );
      expect(
        computeAuthRedirect(loggedIn: false, location: '/profile'),
        '/sign-in',
      );
      expect(
        computeAuthRedirect(loggedIn: false, location: '/matches/12345'),
        '/sign-in',
      );
    });

    test('public routes pass through unchanged', () {
      expect(computeAuthRedirect(loggedIn: false, location: '/sign-in'),
          isNull);
      expect(
          computeAuthRedirect(loggedIn: false, location: '/auth/callback'),
          isNull);
    });

    test('root "/" → /sign-in for unauthenticated', () {
      expect(computeAuthRedirect(loggedIn: false, location: '/'), '/sign-in');
    });
  });

  group('computeAuthRedirect — authenticated user', () {
    test('public auth routes bounce to /matches', () {
      // User shouldn't see the sign-in screen while signed in (e.g. they
      // tapped a stale magic link).
      expect(computeAuthRedirect(loggedIn: true, location: '/sign-in'),
          '/matches');
      expect(computeAuthRedirect(loggedIn: true, location: '/auth/callback'),
          '/matches');
    });

    test('root "/" → /matches for authenticated', () {
      expect(computeAuthRedirect(loggedIn: true, location: '/'), '/matches');
    });

    test('protected routes pass through unchanged', () {
      expect(computeAuthRedirect(loggedIn: true, location: '/matches'),
          isNull);
      expect(computeAuthRedirect(loggedIn: true, location: '/groups'), isNull);
      expect(computeAuthRedirect(loggedIn: true, location: '/profile'),
          isNull);
      expect(
          computeAuthRedirect(loggedIn: true, location: '/matches/12345'),
          isNull);
      expect(
          computeAuthRedirect(loggedIn: true, location: '/groups/abc-uuid'),
          isNull);
    });
  });

  group('publicRoutes set is stable', () {
    test('contains only /sign-in and /auth/callback', () {
      expect(publicRoutes, equals(<String>{'/sign-in', '/auth/callback'}));
    });
  });
}
