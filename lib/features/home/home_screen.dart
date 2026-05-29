import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import 'package:wcpredict/core/supabase_client.dart';

// ---------------------------------------------------------------------------
// Data providers
// ---------------------------------------------------------------------------

/// Upcoming scheduled matches where the current user has no prediction yet.
final _upcomingProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  // Fetch the match IDs this user already predicted.
  final predicted = await supabase
      .from('predictions')
      .select('match_id')
      .eq('user_id', user.id);

  final predictedIds =
      (predicted as List).map((p) => p['match_id'] as int).toSet();

  // Build filter query — .not() must be chained before .order()/.limit().
  var baseQuery = supabase
      .from('matches')
      .select(
        'id, kickoff_time, '
        'team1:teams!team1_id(name, code, flag_url), '
        'team2:teams!team2_id(name, code, flag_url)',
      )
      .eq('status', 'scheduled');

  if (predictedIds.isNotEmpty) {
    baseQuery = baseQuery.not(
      'id',
      'in',
      '(${predictedIds.join(',')})',
    );
  }

  final rows = await baseQuery.order('kickoff_time').limit(5);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// Last 3 finished matches with the user's prediction & points.
final _recentResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final rows = await supabase
      .from('matches')
      .select(
        'id, kickoff_time, score_ft_team1, score_ft_team2, '
        'team1:teams!team1_id(name, code, flag_url), '
        'team2:teams!team2_id(name, code, flag_url), '
        'predictions!inner(predicted_team1, predicted_team2, points_earned)',
      )
      .eq('status', 'finished')
      .eq('predictions.user_id', user.id)
      .order('kickoff_time', ascending: false)
      .limit(3);

  return List<Map<String, dynamic>>.from(rows as List);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WC 2026'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await supabase.auth.signOut();
            },
          ),
        ],
      ),
      bottomNavigationBar: const _BottomNav(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_upcomingProvider);
          ref.invalidate(_recentResultsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: const [
            _SectionHeader('Upcoming predictions'),
            _UpcomingList(),
            SizedBox(height: 8),
            _SectionHeader('Recent results'),
            _RecentResultsList(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation
// ---------------------------------------------------------------------------

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  static const _items = [
    (icon: Icons.home_outlined, label: 'Home', path: '/home'),
    (icon: Icons.calendar_month_outlined, label: 'Fixtures', path: '/fixtures'),
    (icon: Icons.group_outlined, label: 'Groups', path: '/groups'),
    (icon: Icons.sports_soccer_outlined, label: 'Bracket', path: '/bracket'),
    (icon: Icons.person_outlined, label: 'Profile', path: '/profile'),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _items.indexWhere((i) => i.path == loc);
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _currentIndex(context),
      onDestinationSelected: (i) => context.go(_items[i].path),
      destinations: [
        for (final item in _items)
          NavigationDestination(
            icon: Icon(item.icon),
            label: item.label,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming predictions list
// ---------------------------------------------------------------------------

class _UpcomingList extends ConsumerWidget {
  const _UpcomingList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_upcomingProvider);

    return async.when(
      loading: () => _ShimmerList(count: 3),
      error: (e, _) => _ErrorTile('Could not load upcoming matches'),
      data: (matches) {
        if (matches.isEmpty) {
          return const _EmptyTile(
            icon: Icons.check_circle_outline,
            message: "You're all caught up — no pending predictions.",
          );
        }
        return Column(
          children: [
            for (final m in matches) _UpcomingMatchCard(match: m),
          ],
        );
      },
    );
  }
}

class _UpcomingMatchCard extends StatelessWidget {
  const _UpcomingMatchCard({required this.match});

  final Map<String, dynamic> match;

  @override
  Widget build(BuildContext context) {
    final team1 = match['team1'] as Map<String, dynamic>? ?? {};
    final team2 = match['team2'] as Map<String, dynamic>? ?? {};
    final kickoff = DateTime.parse(match['kickoff_time'] as String).toLocal();
    final fmt = DateFormat('EEE d MMM • HH:mm');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/matches/${match['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  team1['name'] as String? ?? '—',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Text('vs',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      fmt.format(kickoff),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                              color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  team2['name'] as String? ?? '—',
                  style: Theme.of(context).textTheme.titleSmall,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_outlined, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent results list
// ---------------------------------------------------------------------------

class _RecentResultsList extends ConsumerWidget {
  const _RecentResultsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recentResultsProvider);

    return async.when(
      loading: () => _ShimmerList(count: 2),
      error: (e, _) => _ErrorTile('Could not load recent results'),
      data: (matches) {
        if (matches.isEmpty) {
          return const _EmptyTile(
            icon: Icons.history_outlined,
            message: 'No finished matches yet.',
          );
        }
        return Column(
          children: [
            for (final m in matches) _ResultCard(match: m),
          ],
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.match});

  final Map<String, dynamic> match;

  @override
  Widget build(BuildContext context) {
    final team1 = match['team1'] as Map<String, dynamic>? ?? {};
    final team2 = match['team2'] as Map<String, dynamic>? ?? {};
    final prediction = (match['predictions'] is List
        ? (match['predictions'] as List).firstOrNull
        : match['predictions']) as Map<String, dynamic>?;

    final ftScore =
        '${match['score_ft_team1'] ?? '?'} – ${match['score_ft_team2'] ?? '?'}';
    final myScore = prediction != null
        ? '${prediction['predicted_team1']} – ${prediction['predicted_team2']}'
        : '—';
    final points = prediction?['points_earned'] as int?;

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/matches/${match['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${team1['name'] ?? '—'} vs ${team2['name'] ?? '—'}',
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Result: $ftScore   |   My guess: $myScore',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
              if (points != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: points > 0
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$points pts',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: points > 0
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surface;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined,
              color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}
