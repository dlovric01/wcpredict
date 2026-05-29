import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_callback_screen.dart';
import 'features/auth/magic_link_screen.dart';
import 'features/bracket/bracket_screen.dart';
import 'features/fixtures/fixtures_screen.dart';
import 'features/groups/create_group_screen.dart';
import 'features/groups/group_detail_screen.dart';
import 'features/groups/groups_list_screen.dart';
import 'features/groups/join_group_screen.dart';
import 'features/home/home_screen.dart';
import 'features/matches/match_detail_screen.dart';
import 'features/profile/profile_screen.dart';
import 'core/supabase_client.dart';

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

final _publicRoutes = {'/sign-in', '/auth/callback'};

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: GoRouterRefreshStream(
    supabase.auth.onAuthStateChange,
  ),
  redirect: (BuildContext context, GoRouterState state) {
    final loggedIn = supabase.auth.currentUser != null;
    final loc = state.matchedLocation;

    if (!loggedIn && !_publicRoutes.contains(loc)) return '/sign-in';
    if (loggedIn && loc == '/sign-in') return '/home';
    if (loc == '/') return loggedIn ? '/home' : '/sign-in';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: '/sign-in',
      builder: (_, __) => const MagicLinkScreen(),
    ),
    GoRoute(
      path: '/auth/callback',
      builder: (_, __) => const AuthCallbackScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/groups',
      builder: (_, __) => const GroupsListScreen(),
      routes: [
        GoRoute(
          path: 'create',
          builder: (_, __) => const CreateGroupScreen(),
        ),
        GoRoute(
          path: 'join',
          builder: (_, __) => const JoinGroupScreen(),
        ),
        GoRoute(
          path: ':groupId',
          builder: (_, state) =>
              GroupDetailScreen(groupId: state.pathParameters['groupId']!),
        ),
      ],
    ),
    GoRoute(
      path: '/fixtures',
      builder: (_, __) => const FixturesScreen(),
    ),
    GoRoute(
      path: '/matches/:matchId',
      builder: (_, state) =>
          MatchDetailScreen(matchId: int.parse(state.pathParameters['matchId']!)),
    ),
    GoRoute(
      path: '/bracket',
      builder: (_, __) => const BracketScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (_, __) => const ProfileScreen(),
    ),
  ],
);
