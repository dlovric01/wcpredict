import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wcpredict/core/logger.dart';
import 'package:wcpredict/core/legal_urls.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/providers/groups_provider.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Fetches the current user's profile row.
final _myProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final data = await supabase
      .from('profiles')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
  return data;
});

/// Aggregates prediction stats for the current user.
final _myStatsProvider = FutureProvider<_PredictionStats>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const _PredictionStats();

  final preds = (await supabase
          .from('predictions')
          .select()
          .eq('user_id', userId) as List)
      .map((e) => PredictionModel.fromJson(e as Map<String, dynamic>))
      .toList();

  final totalPoints = preds.fold<int>(
    0,
    (sum, p) => sum + (p.pointsEarned ?? 0),
  );

  final exactCount = preds.where((p) => p.isExact).length;
  final goalDiffCount = preds.where((p) => p.isGoalDiff).length;
  final outcomeCount = preds.where((p) => p.isOutcome).length;
  final firstTeamHits = preds.where((p) => p.firstTeamHit).length;
  final goalscorerHits = preds.where((p) => p.goalscorerHit).length;

  return _PredictionStats(
    totalPoints: totalPoints,
    exactCount: exactCount,
    outcomeCount: outcomeCount,
    goalDiffCount: goalDiffCount,
    firstTeamHits: firstTeamHits,
    goalscorerHits: goalscorerHits,
    predictionCount: preds.length,
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
    final groupsAsync = ref.watch(myGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_myProfileProvider);
          ref.invalidate(_myStatsProvider);
          ref.invalidate(myGroupsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Header card ───────────────────────────────────────────────
            Card(
              color: AppColors.surfaceHigh,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.cardRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: profileAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error loading profile: $e'),
                  data: (profile) => _ProfileHeader(profile: profile),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Stats card ────────────────────────────────────────────────
            statsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error loading stats: $e'),
              data: (stats) => _StatsSection(stats: stats),
            ),
            const SizedBox(height: 16),

            // ── Tournament picks ──────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
              child: ListTile(
                leading: const Icon(Icons.emoji_events_outlined,
                    color: AppColors.secondary),
                title: const Text('Tournament picks'),
                subtitle: const Text('World Cup Winner +75 · Golden Boot +50'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/tournament'),
              ),
            ),
            const SizedBox(height: 16),

            // ── Groups section ────────────────────────────────────────────
            groupsAsync.maybeWhen(
              data: (groups) => groups.isEmpty
                  ? const SizedBox.shrink()
                  : Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.cardRadius,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              'My Groups',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          for (final g in groups)
                            ListTile(
                              title: Text(g.name),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/groups/${g.id}'),
                            ),
                        ],
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // ── Settings section ──────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.cardRadius,
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Theme'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Dark mode',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.lock_outline, size: 16),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('How scoring works'),
                    subtitle: const Text('Rules, multipliers & tournament picks'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/rules'),
                  ),
                  if (kDebugMode)
                    ListTile(
                      leading: const Icon(Icons.terminal_outlined),
                      title: const Text('View logs'),
                      subtitle: const Text('Errors & debug info'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TalkerScreen(talker: talker),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Legal & support ───────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.cardRadius,
              ),
              child: Column(
                children: [
                  _LegalTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy policy',
                    url: kPrivacyPolicyUrl,
                  ),
                  _LegalTile(
                    icon: Icons.description_outlined,
                    title: 'Terms of use',
                    url: kTermsOfUseUrl,
                  ),
                  _LegalTile(
                    icon: Icons.help_outline,
                    title: 'Support',
                    subtitle: 'Get help or contact us',
                    url: kSupportUrl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Dev tools — debug builds only ─────────────────────────────
            if (kDebugMode) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined,
                    color: AppColors.secondary),
                title: const Text('Live Simulator'),
                subtitle: const Text('Test realtime pipeline end-to-end'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.onSurfaceMuted),
                onTap: () => context.push('/dev/simulate'),
              ),
              const SizedBox(height: 8),
            ],

            // ── Sign out ──────────────────────────────────────────────────
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                foregroundColor: AppColors.error,
              ),
              onPressed: () => _confirmSignOut(context, ref),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // No useRootNavigator — AlertDialog blocks the whole screen regardless,
      // and using the branch navigator ensures Navigator.pop works correctly.
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your magic link to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Sign out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // SignOutScope.local clears SharedPreferences immediately without a
      // network call — always succeeds regardless of connectivity.
      await supabase.auth.signOut(scope: SignOutScope.local);
      // GoRouter's GoRouterRefreshStream listens to onAuthStateChange and
      // redirects to /sign-in automatically — no explicit navigation needed.
    } catch (e) {
      talker.error('Sign out error', e);
    }
  }
}

// ---------------------------------------------------------------------------
// Profile header — avatar + tap-to-edit display name
// ---------------------------------------------------------------------------

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({this.profile});

  final Map<String, dynamic>? profile;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  String get _displayName {
    final explicit = widget.profile?['display_name'] as String?;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final email = supabase.auth.currentUser?.email ?? '';
    final atIdx = email.indexOf('@');
    return atIdx > 0
        ? email.substring(0, atIdx)
        : (email.isNotEmpty ? email : 'User');
  }

  String get _initial =>
      _displayName.isNotEmpty ? _displayName.trim()[0].toUpperCase() : '?';

  String? get _avatarUrl {
    final url = widget.profile?['avatar_url'] as String?;
    return (url == null || url.isEmpty) ? null : url;
  }

  Future<void> _editName() {
    return _EditNameDialog.show(context, widget.profile);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final avatarUrl = _avatarUrl;

    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: avatarUrl == null
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            image: avatarUrl != null
                ? DecorationImage(
                    image: NetworkImage(avatarUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: avatarUrl == null
              ? Center(
                  child: Text(
                    _initial,
                    style: tt.displaySmall?.copyWith(color: AppColors.onPrimary),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        // Name — tap to edit. Padding gives a comfortable hit target.
        InkWell(
          onTap: _editName,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _displayName,
                    style: tt.headlineSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          supabase.auth.currentUser?.email ?? '',
          style: tt.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit name dialog (static helper)
// ---------------------------------------------------------------------------

class _EditNameDialog extends ConsumerStatefulWidget {
  const _EditNameDialog({this.profile});

  final Map<String, dynamic>? profile;

  static Future<void> show(
    BuildContext context,
    Map<String, dynamic>? profile,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EditNameDialog(profile: profile),
    );
  }

  @override
  ConsumerState<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends ConsumerState<_EditNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: (widget.profile?['display_name'] as String?) ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await supabase.from('profiles').upsert(
        {'user_id': user.id, 'display_name': name},
        onConflict: 'user_id',
      );
      ref.invalidate(_myProfileProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit display name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Your name'),
        textCapitalization: TextCapitalization.words,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
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
    final tt = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Stats', style: tt.titleMedium),
            const SizedBox(height: 16),
            Text(
              '${stats.totalPoints}',
              style: tt.displaySmall?.copyWith(
                color: AppColors.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              'total points',
              style: tt.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const Divider(height: 24),
            _StatRow(
              icon: Icons.gps_fixed,
              label: 'Exact scores',
              value: '${stats.exactCount}',
            ),
            _StatRow(
              icon: Icons.show_chart,
              label: 'Correct outcomes',
              value: '${stats.outcomeCount}',
            ),
            _StatRow(
              icon: Icons.compare_arrows,
              label: 'Correct goal diff',
              value: '${stats.goalDiffCount}',
            ),
            _StatRow(
              icon: Icons.flag,
              label: 'First-team hits',
              value: '${stats.firstTeamHits}',
            ),
            _StatRow(
              icon: Icons.sports_soccer,
              label: 'Goalscorer hits',
              value: '${stats.goalscorerHits}',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.tertiary),
          const SizedBox(width: 10),
          Text(label, style: tt.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: tt.titleMedium?.copyWith(
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
    this.outcomeCount = 0,
    this.goalDiffCount = 0,
    this.firstTeamHits = 0,
    this.goalscorerHits = 0,
    this.predictionCount = 0,
  });

  final int totalPoints;
  final int exactCount;
  final int outcomeCount;
  final int goalDiffCount;
  final int firstTeamHits;
  final int goalscorerHits;
  final int predictionCount;
}

// ---------------------------------------------------------------------------
// Legal tile — opens a public URL in the system browser via url_launcher.
//
// Surfacing the same URLs that App Store Connect points at gives reviewers
// (and users) an in-app path to the same policy text. The URLs themselves
// live in `lib/core/legal_urls.dart` so ASC and the app cannot drift.
// ---------------------------------------------------------------------------

class _LegalTile extends StatelessWidget {
  const _LegalTile({
    required this.icon,
    required this.title,
    required this.url,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String url;
  final String? subtitle;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(url);
    // `externalApplication` opens Safari/Chrome rather than an embedded
    // webview — Apple specifically prefers this for legal pages so the
    // user can verify the domain in the address bar.
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _open(context),
    );
  }
}
