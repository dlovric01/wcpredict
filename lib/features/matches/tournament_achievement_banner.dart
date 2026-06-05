import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wcpredict/shared/utils/date_format.dart';

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
    final hasPicks = pickedTeam != null || pickedPlayer != null;

    // ── State 4: resolved (results posted) ──────────────────────────────────
    if (resolved) {
      final earned = pred?.pointsEarned ?? 0;
      final won = earned > 0;
      return _CompactPill(
        icon: Icons.emoji_events,
        iconColor: won ? AppColors.gold : AppColors.onSurfaceMuted,
        middle: Text(
          'Tournament bonus',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurface,
              ),
        ),
        trailing: _PointsBadge(points: earned, positive: won),
        onTap: () => context.push('/tournament'),
      );
    }

    // ── State 3: locked, awaiting results ──────────────────────────────────
    // Compact pill: picks frozen, results pending. Tap routes to /tournament
    // for the full breakdown.
    if (locked) {
      final theme = Theme.of(context);
      return _CompactPill(
        icon: Icons.lock_outline,
        iconColor: AppColors.locked,
        middle: hasPicks
            ? _PicksLine(
                teamName: pickedTeam?.name,
                teamFlagUrl: pickedTeam?.flagUrl,
                playerName: pickedPlayer?.name,
                style: theme.textTheme.bodyMedium,
              )
            : Text(
                'No tournament picks',
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
              ),
        trailing: Text(
          'TBD',
          style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceMuted,
                letterSpacing: 0.5,
              ),
        ),
        onTap: () => context.push('/tournament'),
      );
    }

    // ── State 2: open, picks already submitted ─────────────────────────────
    // Also compact — once committed there's no reason to occupy a full card
    // in the matches list. The "Edit" hint signals the picks are still
    // editable; the big CTA banner only renders in State 1 (no picks yet).
    if (hasPicks) {
      return _CompactPill(
        icon: Icons.check_circle,
        iconColor: AppColors.primary,
        middle: _PicksLine(
          teamName: pickedTeam?.name,
          teamFlagUrl: pickedTeam?.flagUrl,
          playerName: pickedPlayer?.name,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        trailing: Text(
          'Edit',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
              ),
        ),
        onTap: () => context.push('/tournament'),
      );
    }

    // ── State 1: open, no picks yet → big CTA ───────────────────────────────
    final lockText = opening != null
        ? 'Closes ${formatLockDeadline(opening)}'
        : 'Closes at the opening match';
    return _CtaBanner(
      lockText: lockText,
      onTap: () => context.push('/tournament'),
    );
  }
}

// ─── Compact pill — used for states 2 (picked), 3 (locked), 4 (resolved) ───
// Single row, ~52 px tall. State-specific differences are injected via
// `icon` / `iconColor` (status glyph), `middle` (the picks line or a plain
// label), and `trailing` (an "Edit" / "TBD" hint or a points badge). The
// big CTA banner in `_CtaBanner` only renders for state 1 (no picks yet).

class _CompactPill extends StatelessWidget {
  const _CompactPill({
    required this.icon,
    required this.iconColor,
    required this.middle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Widget middle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
        child: InkWell(
          borderRadius: AppRadii.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: middle),
                const SizedBox(width: AppSpacing.sm),
                trailing,
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline row "[flag] Team · Player" with each segment truncating
/// independently when the row is narrow.
class _PicksLine extends StatelessWidget {
  const _PicksLine({
    required this.teamName,
    required this.teamFlagUrl,
    required this.playerName,
    required this.style,
  });

  final String? teamName;
  final String? teamFlagUrl;
  final String? playerName;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    if (teamName != null) {
      segments.add(_TeamSegment(name: teamName!, flagUrl: teamFlagUrl, style: style));
    }
    if (playerName != null) {
      if (segments.isNotEmpty) {
        segments.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '·',
            style: style?.copyWith(color: AppColors.onSurfaceMuted),
          ),
        ));
      }
      segments.add(Flexible(
        child: Text(
          playerName!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(color: AppColors.onSurface),
        ),
      ));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: segments,
    );
  }
}

class _TeamSegment extends StatelessWidget {
  const _TeamSegment({
    required this.name,
    required this.flagUrl,
    required this.style,
  });

  final String name;
  final String? flagUrl;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flagUrl != null && flagUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: CachedNetworkImage(
                imageUrl: flagUrl!,
                width: 18,
                height: 13,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(width: 18, height: 13),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: AppColors.onSurface),
            ),
          ),
        ],
      ),
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
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: AppColors.gold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Tournament picks',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '+125 pts',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lockText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// ─── Bonus chip ─────────────────────────────────────────────────────────────

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({
    required this.points,
    this.positive = true,
  });

  final int points;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = positive ? AppColors.primaryContainer : AppColors.surfaceHighest;
    final fg = positive ? AppColors.onPrimaryContainer : AppColors.onSurfaceMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '+$points',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

