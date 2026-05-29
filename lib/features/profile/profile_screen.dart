import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Fetches the current user's profile row.
final _myProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return null;
  final data = await supabase
      .from('profiles')
      .select()
      .eq('user_id', user.id)
      .maybeSingle();
  return data;
});

/// Aggregates prediction stats for the current user.
final _myStatsProvider = FutureProvider<_PredictionStats>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return const _PredictionStats();

  final data = await supabase
      .from('predictions')
      .select()
      .eq('user_id', user.id);

  final preds = (data as List)
      .map((e) => PredictionModel.fromJson(e as Map<String, dynamic>))
      .toList();

  final totalPoints = preds.fold<int>(
    0,
    (sum, p) => sum + (p.pointsEarned ?? 0),
  );

  final exactCount = preds.where((p) {
    final scorePoints = p.pointsScore ?? 0;
    // 'Exact score' — awarded max score-related points
    // Heuristic: pointsScore == 3 (common exact-score award)
    return scorePoints >= 3;
  }).length;

  final correctResultCount = preds.where((p) {
    return (p.pointsScore ?? 0) > 0;
  }).length;

  return _PredictionStats(
    totalPoints: totalPoints,
    exactCount: exactCount,
    correctResultCount: correctResultCount,
  );
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_myProfileProvider);
    final statsAsync = ref.watch(_myStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_myProfileProvider);
          ref.invalidate(_myStatsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Avatar + name ──────────────────────────────────────────
            profileAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading profile: $e'),
              data: (profile) => _ProfileHeader(profile: profile),
            ),
            const SizedBox(height: 24),

            // ── Stats ──────────────────────────────────────────────────
            statsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error loading stats: $e'),
              data: (stats) => _StatsSection(stats: stats),
            ),
            const SizedBox(height: 32),

            // ── Sign out ───────────────────────────────────────────────
            _SignOutButton(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header — avatar + editable display name
// ---------------------------------------------------------------------------
class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({this.profile});

  final Map<String, dynamic>? profile;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  bool _saving = false;

  String get _displayName =>
      (widget.profile?['display_name'] as String?) ??
      supabase.auth.currentUser?.email ??
      'User';

  String get _initials {
    final parts = _displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return _displayName.isNotEmpty
        ? _displayName[0].toUpperCase()
        : '?';
  }

  Future<void> _editName(BuildContext context) async {
    final controller =
        TextEditingController(text: _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Your name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      await supabase.from('profiles').upsert(
        {'user_id': user.id, 'display_name': result},
        onConflict: 'user_id',
      );
      ref.invalidate(_myProfileProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor:
                  Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            _initials,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 8),
            if (_saving)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => _editName(context),
                tooltip: 'Edit name',
              ),
          ],
        ),
        Text(
          supabase.auth.currentUser?.email ?? '',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stats section
// ---------------------------------------------------------------------------
class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.stats});

  final _PredictionStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stats',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'Total Points',
                    value: '${stats.totalPoints}',
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _StatCell(
                    label: 'Exact Scores',
                    value: '${stats.exactCount}',
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _StatCell(
                    label: 'Correct Results',
                    value: '${stats.correctResultCount}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sign-out button
// ---------------------------------------------------------------------------
class _SignOutButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.logout, color: Colors.red),
      label: const Text('Sign out', style: TextStyle(color: Colors.red)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
      ),
      onPressed: () async {
        final repo = ref.read(authRepositoryProvider);
        await repo.signOut();
        if (context.mounted) {
          context.go('/sign-in');
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------
class _PredictionStats {
  const _PredictionStats({
    this.totalPoints = 0,
    this.exactCount = 0,
    this.correctResultCount = 0,
  });

  final int totalPoints;
  final int exactCount;
  final int correctResultCount;
}
