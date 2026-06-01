import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';
import 'package:wcpredict/shared/providers/tournament_provider.dart';

/// Big, in-flow card at the top of the Matches screen. Drives the tournament
/// bonus prediction: World Cup Winner (+75) and Golden Boot (+50). Four
/// states — open/empty, open/picked, locked, resolved.
class TournamentAchievementBanner extends ConsumerWidget {
  const TournamentAchievementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predAsync = ref.watch(myTournamentPredictionProvider);
    final resultsAsync = ref.watch(tournamentResultsProvider);
    final locked = ref.watch(tournamentLockedProvider);
    final openingAsync = ref.watch(tournamentOpeningKickoffProvider);

    final pred = predAsync.valueOrNull;
    final results = resultsAsync.valueOrNull;
    final opening = openingAsync.valueOrNull;

    final resolved =
        results != null && (results.hasWinner || results.hasGoldenBoot);

    // Resolve labels via by-id providers (no full-table fetch).
    final pickedTeam = pred?.wcWinnerTeamId != null
        ? ref.watch(teamByIdProvider(pred!.wcWinnerTeamId!)).valueOrNull
        : null;
    final pickedPlayerHit = pred?.goldenBootPlayerId != null
        ? ref.watch(playerByIdProvider(pred!.goldenBootPlayerId!)).valueOrNull
        : null;
    final pickedPlayer = pickedPlayerHit?.player;
    final actualTeam = results?.winnerTeamId != null
        ? ref.watch(teamByIdProvider(results!.winnerTeamId!)).valueOrNull
        : null;
    final actualPlayerHit = results?.goldenBootPlayerId != null
        ? ref.watch(playerByIdProvider(results!.goldenBootPlayerId!)).valueOrNull
        : null;
    final actualPlayer = actualPlayerHit?.player;

    final hasPicks = pickedTeam != null || pickedPlayer != null;

    // ── State 4: resolved (results posted) ──────────────────────────────────
    if (resolved) {
      final wcHit = pred?.wcWinnerTeamId != null
          && pred?.wcWinnerTeamId == results.winnerTeamId;
      final gbHit = pred?.goldenBootPlayerId != null
          && pred?.goldenBootPlayerId == results.goldenBootPlayerId;
      final earned = pred?.pointsEarned ?? 0;

      return _BannerCard(
        accent: earned > 0 ? AppColors.primary : AppColors.onSurfaceMuted,
        icon: Icons.emoji_events,
        iconColor: earned > 0 ? AppColors.gold : AppColors.onSurfaceMuted,
        title: 'Tournament bonus',
        subtitle: earned > 0
            ? 'You earned $earned points'
            : 'Better luck next tournament',
        rightBadge: _PointsBadge(
          points: earned,
          big: true,
          positive: earned > 0,
        ),
        rows: [
          _ResolvedRow(
            label: 'Winner',
            actualName: actualTeam?.name ?? '—',
            actualFlag: actualTeam?.flagUrl,
            pickedName: pickedTeam?.name,
            hit: wcHit,
            bonus: 75,
          ),
          _ResolvedRow(
            label: 'Golden Boot',
            actualName: actualPlayer?.name ?? '—',
            pickedName: pickedPlayer?.name,
            hit: gbHit,
            bonus: 50,
          ),
        ],
      );
    }

    // ── State 3: locked, awaiting results ───────────────────────────────────
    if (locked) {
      return _BannerCard(
        accent: AppColors.locked,
        icon: Icons.lock_outline,
        iconColor: AppColors.locked,
        title: 'Tournament picks · Locked',
        subtitle: hasPicks
            ? 'Awaiting tournament results'
            : 'You missed the opening match',
        rightBadge: const _PointsBadge(points: 125, label: 'TBD'),
        rows: [
          _PickedRow(
            label: 'Winner',
            value: pickedTeam?.name ?? 'No pick',
            flagUrl: pickedTeam?.flagUrl,
            placeholder: pickedTeam == null,
            bonus: 75,
            icon: Icons.flag_outlined,
          ),
          _PickedRow(
            label: 'Golden Boot',
            value: pickedPlayer?.name ?? 'No pick',
            placeholder: pickedPlayer == null,
            bonus: 50,
            icon: Icons.sports_soccer_outlined,
          ),
        ],
      );
    }

    // ── State 2: open, picks already submitted ──────────────────────────────
    if (hasPicks) {
      final lockText = opening != null
          ? 'Locks ${DateFormat.MMMd().add_jm().format(opening.toLocal())}'
          : 'Tap to edit before kickoff';
      return _BannerCard(
        accent: AppColors.primary,
        icon: Icons.check_circle,
        iconColor: AppColors.primary,
        title: 'Your tournament picks',
        subtitle: lockText,
        rightBadge: const _PointsBadge(points: 125, label: 'max'),
        rows: [
          _PickedRow(
            label: 'Winner',
            value: pickedTeam?.name ?? 'Tap to pick',
            flagUrl: pickedTeam?.flagUrl,
            placeholder: pickedTeam == null,
            bonus: 75,
            icon: Icons.flag_outlined,
          ),
          _PickedRow(
            label: 'Golden Boot',
            value: pickedPlayer?.name ?? 'Tap to pick',
            placeholder: pickedPlayer == null,
            bonus: 50,
            icon: Icons.sports_soccer_outlined,
          ),
        ],
        footerLabel: 'Tap to edit',
      );
    }

    // ── State 1: open, no picks yet → big CTA ───────────────────────────────
    final lockText = opening != null
        ? 'Closes ${DateFormat.MMMd().add_jm().format(opening.toLocal())}'
        : 'Closes at the opening match';
    return _CtaBanner(
      lockText: lockText,
      onTap: () => context.push('/tournament'),
    );
  }
}

// ─── Standalone CTA banner for the "nothing picked" state ────────────────────
// Visual: gradient-tinted card with trophy icon, prominent title, big button.

class _CtaBanner extends StatelessWidget {
  const _CtaBanner({required this.lockText, required this.onTap});
  final String lockText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
        child: InkWell(
          borderRadius: AppRadii.cardRadius,
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: AppRadii.cardRadius,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1F2A48),
                  Color(0xFF1A2138),
                ],
              ),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.emoji_events,
                        color: AppColors.gold,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tournament picks',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Worth up to +125 bonus points',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Bonus breakdown
                Row(
                  children: [
                    Expanded(
                      child: _BonusTile(
                        icon: Icons.flag,
                        label: 'Winner',
                        value: '+75',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BonusTile(
                        icon: Icons.sports_soccer,
                        label: 'Golden Boot',
                        value: '+50',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Big CTA button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('SUBMIT YOUR PICKS'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule, size: 12, color: AppColors.onSurfaceMuted),
                    const SizedBox(width: 4),
                    Text(
                      lockText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BonusTile extends StatelessWidget {
  const _BonusTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared card for states 2/3/4 (picks submitted / locked / resolved) ──────

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.accent,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.rightBadge,
    required this.rows,
    this.footerLabel,
  });

  final Color accent;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget rightBadge;
  final List<Widget> rows;
  final String? footerLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
        child: InkWell(
          borderRadius: AppRadii.cardRadius,
          onTap: () => GoRouterAccessor.push(context, '/tournament'),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: AppRadii.cardRadius,
              border: Border(
                left: BorderSide(color: accent, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: iconColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    rightBadge,
                  ],
                ),
                const SizedBox(height: 10),
                for (final r in rows) ...[
                  r,
                  const SizedBox(height: 4),
                ],
                if (footerLabel != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        footerLabel!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right,
                          size: 14, color: AppColors.primary),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bonus chip with optional "label" prefix ─────────────────────────────────

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({
    required this.points,
    this.label,
    this.big = false,
    this.positive = true,
  });

  final int points;
  final String? label;
  final bool big;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = positive ? AppColors.primaryContainer : AppColors.surfaceHighest;
    final fg = positive ? AppColors.onPrimaryContainer : AppColors.onSurfaceMuted;
    final text = label != null ? '$label +$points' : '+$points';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 12 : 10,
        vertical: big ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: (big ? theme.textTheme.titleSmall : theme.textTheme.labelSmall)
            ?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── A row in the submitted/locked state ─────────────────────────────────────

class _PickedRow extends StatelessWidget {
  const _PickedRow({
    required this.label,
    required this.value,
    required this.bonus,
    required this.icon,
    this.flagUrl,
    this.placeholder = false,
  });

  final String label;
  final String value;
  final int bonus;
  final IconData icon;
  final String? flagUrl;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = placeholder
        ? AppColors.onSurfaceMuted
        : AppColors.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 8),
          if (flagUrl != null) ...[
            CachedNetworkImage(
              imageUrl: flagUrl!,
              width: 22,
              height: 15,
              fit: BoxFit.cover,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: placeholder ? FontWeight.w500 : FontWeight.w700,
                    fontStyle: placeholder ? FontStyle.italic : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '+$bonus',
            style: theme.textTheme.labelMedium?.copyWith(
              color: placeholder ? AppColors.onSurfaceMuted : AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── A row in the resolved state — shows actual + user's pick + hit/miss ────

class _ResolvedRow extends StatelessWidget {
  const _ResolvedRow({
    required this.label,
    required this.actualName,
    required this.hit,
    required this.bonus,
    this.actualFlag,
    this.pickedName,
  });

  final String label;
  final String actualName;
  final String? actualFlag;
  final String? pickedName;
  final bool hit;
  final int bonus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = hit ? AppColors.primary : AppColors.onSurfaceMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hit ? AppColors.primary.withValues(alpha: 0.3) : AppColors.outline,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hit ? Icons.check_circle : Icons.cancel_outlined,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 8),
          if (actualFlag != null) ...[
            CachedNetworkImage(
              imageUrl: actualFlag!,
              width: 22,
              height: 15,
              fit: BoxFit.cover,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(text: actualName),
                      if (pickedName != null && !hit)
                        TextSpan(
                          text: '  · picked $pickedName',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.onSurfaceMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            hit ? '+$bonus' : '+0',
            style: theme.textTheme.titleSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// Helper so the _BannerCard's onTap doesn't require importing go_router here.
// (Simplifies callers — the InkWell needs *some* router access.)
class GoRouterAccessor {
  static void push(BuildContext context, String path) {
    context.push(path);
  }
}
