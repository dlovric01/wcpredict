import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/route_observer.dart';
import 'core/supabase_client.dart';
import 'router_redirect.dart';
import 'features/auth/auth_callback_screen.dart';
import 'features/auth/social_sign_in_screen.dart';
import 'features/dev/simulation_screen.dart';
import 'features/groups/group_detail_screen.dart';
import 'features/groups/groups_list_screen.dart';
import 'features/groups/user_predictions_screen.dart';
import 'features/matches/match_detail_screen.dart';
import 'features/matches/matches_list_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/tournament/tournament_predictions_screen.dart';
import 'shared/widgets/app_shell.dart';

/// Bridges a [Stream] to a [Listenable] for [GoRouter.refreshListenable].
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// _publicRoutes + redirect logic live in router_redirect.dart for testability.

final appRouter = GoRouter(
  initialLocation: '/matches',
  observers: [AppRouteObserver()],
  refreshListenable: GoRouterRefreshStream(
    supabase.auth.onAuthStateChange,
  ),
  redirect: (BuildContext context, GoRouterState state) => computeAuthRedirect(
    loggedIn: supabase.auth.currentUser != null,
    location: state.matchedLocation,
  ),
  routes: [
    // ── Public routes (outside the shell) ───────────────────────────────────
    GoRoute(
      path: '/',
      builder: (_, __) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: '/sign-in',
      builder: (_, __) => const SocialSignInScreen(),
    ),
    GoRoute(
      path: '/auth/callback',
      builder: (_, __) => const AuthCallbackScreen(),
    ),

    // ── Detail routes (above the shell, with back button) ───────────────────
    GoRoute(
      path: '/matches/:matchId',
      builder: (_, state) =>
          MatchDetailScreen(matchId: int.parse(state.pathParameters['matchId']!)),
    ),
    GoRoute(
      path: '/dev/simulate',
      builder: (_, __) => const SimulationScreen(),
    ),
    GoRoute(
      path: '/tournament',
      builder: (_, __) => const TournamentPredictionsScreen(),
    ),
    GoRoute(
      path: '/groups/:groupId',
      builder: (_, state) =>
          GroupDetailScreen(groupId: state.pathParameters['groupId']!),
    ),
    GoRoute(
      path: '/members/:userId',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>;
        return UserPredictionsScreen(
          userId: state.pathParameters['userId']!,
          displayName: extra['displayName'] as String,
          totalPoints: extra['totalPoints'] as int,
          exactCount: extra['exactCount'] as int,
          outcomeCount: extra['outcomeCount'] as int? ?? 0,
          goalDiffCount: extra['goalDiffCount'] as int? ?? 0,
          scorerCount: extra['scorerCount'] as int? ?? 0,
          firstTeamCount: extra['firstTeamCount'] as int? ?? 0,
        );
      },
    ),

    // ── Shell with persistent bottom nav ────────────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/matches',
              builder: (_, __) => const MatchesListScreen(),
            ),
          ],
        ),

        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/groups',
              builder: (_, __) => const GroupsListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, __) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
