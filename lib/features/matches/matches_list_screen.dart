import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';
import 'package:wcpredict/shared/utils/live_minute.dart';
import 'package:wcpredict/shared/utils/score_format.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';
import 'package:wcpredict/features/matches/tournament_achievement_banner.dart';
import 'package:wcpredict/core/scoring_rules.dart';
import 'package:wcpredict/shared/providers/boosters_provider.dart';

class MatchesListScreen extends ConsumerWidget {
  const MatchesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(allMatchesProvider);
    final myPredsAsync = ref.watch(myAllPredictionsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        title: const Text('Matches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How scoring works',
            onPressed: () => context.push('/rules'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          ref.invalidate(allMatchesProvider);
          ref.invalidate(myAllPredictionsProvider);
        },
        child: matchesAsync.when(
          // The list itself never refetches on score/status changes —
          // those propagate through `liveMatchProvider` per-card. We
          // still keep skipLoadingOnReload for pull-to-refresh.
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Error: $e',
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
          data: (matches) {
            final items = _buildItems(matches);
            final predictedIds =
                myPredsAsync.valueOrNull?.map((p) => p.matchId).toSet() ??
                    const <int>{};
            // Round → matchId for the user's applied boosters. Drives both
            // the strip below the tournament banner and the green tint on
            // the affected match card. Watched here once instead of inside
            // each `_MatchCard` so a single boosters fetch covers the
            // whole list.
            final myBoosters = ref.watch(myBoostersProvider).valueOrNull ??
                const <String, RoundBoosterModel>{};
            final boostedMatchIds =
                myBoosters.values.map((b) => b.matchId).toSet();

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              // +1 for the achievement banner, +1 for the boosters strip
              itemCount: items.length + 2,
              itemBuilder: (ctx, i) {
                if (i == 0) return const TournamentAchievementBanner();
                if (i == 1) {
                  return _RoundBoostersStrip(
                    matches: matches,
                    boostersByRound: myBoosters,
                  );
                }
                final item = items[i - 2];
                if (item is _SectionHeader) {
                  return _RoundHeader(section: item);
                }
                final m = item as MatchModel;
                return _MatchCard(
                  key: ValueKey(m.id),
                  match: m,
                  isPredicted: predictedIds.contains(m.id),
                  isBoosted: boostedMatchIds.contains(m.id),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Builds a flat list of section headers + matches. Each `_SectionHeader`
  /// summarises a round (count + date range) and is followed by its matches.
  List<Object> _buildItems(List<MatchModel> matches) {
    final grouped = <String, List<MatchModel>>{};
    final order = <String>[];
    for (final m in matches) {
      final round = m.round ?? 'Unknown';
      grouped.putIfAbsent(round, () {
        order.add(round);
        return <MatchModel>[];
      }).add(m);
    }

    final items = <Object>[];
    for (final round in order) {
      final group = grouped[round]!;
      items.add(_SectionHeader.fromGroup(round, group));
      items.addAll(group);
    }
    return items;
  }
}

// ---------------------------------------------------------------------------
// Round metadata
// ---------------------------------------------------------------------------

class _SectionHeader {
  const _SectionHeader({
    required this.round,
    required this.count,
    required this.firstKickoff,
    required this.lastKickoff,
  });

  factory _SectionHeader.fromGroup(String round, List<MatchModel> matches) {
    DateTime? first;
    DateTime? last;
    for (final m in matches) {
      final t = m.kickoffTime;
      if (t == null) continue;
      if (first == null || t.isBefore(first)) first = t;
      if (last == null || t.isAfter(last)) last = t;
    }
    return _SectionHeader(
      round: round,
      count: matches.length,
      firstKickoff: first,
      lastKickoff: last,
    );
  }

  final String round;
  final int count;
  final DateTime? firstKickoff;
  final DateTime? lastKickoff;

  /// Returns the matchday number for group-stage rounds like "Matchday 12",
  /// or `null` for knockout rounds.
  int? get matchdayNumber {
    final m =
        RegExp(r'matchday\s*(\d+)', caseSensitive: false).firstMatch(round);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// Maps DB round code to a display label.
  String get label {
    final r = round.toLowerCase();
    switch (r) {
      case 'r32':
        return 'Round of 32';
      case 'r16':
        return 'Round of 16';
      case 'qf':
        return 'Quarter-finals';
      case 'sf':
        return 'Semi-finals';
      case '3rd':
        return 'Third place';
      case 'final':
        return 'Final';
      default:
        return round;
    }
  }

  /// Knockout rounds get a prestige icon instead of a number badge.
  IconData? get knockoutIcon {
    switch (round.toLowerCase()) {
      case 'r32':
      case 'r16':
        return Symbols.emoji_events;
      case 'qf':
      case 'sf':
        return Symbols.military_tech;
      case '3rd':
        return Symbols.workspace_premium;
      case 'final':
        return Symbols.crown;
      default:
        return null;
    }
  }

  /// Accent color: emerald for group stage, amber for knockout, gold-ish for Final.
  Color get accentColor {
    if (round.toLowerCase() == 'final') return AppColors.secondary;
    return matchdayNumber != null ? AppColors.primary : AppColors.secondary;
  }

  String? get dateRange {
    if (firstKickoff == null) return null;
    final f = firstKickoff!.toLocal();
    final l = (lastKickoff ?? firstKickoff!).toLocal();
    final fStr = DateFormat('d MMM').format(f);
    if (l.year == f.year && l.month == f.month && l.day == f.day) {
      return fStr;
    }
    final lStr = DateFormat('d MMM').format(l);
    return '$fStr – $lStr';
  }
}

// ---------------------------------------------------------------------------
// Round header — number badge for matchdays, icon for knockouts
// ---------------------------------------------------------------------------

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.section});
  final _SectionHeader section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFinal = section.round.toLowerCase() == 'final';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFinal ? 24 : 20, 16, 8),
      child: Row(
        children: [
          _LeadingBadge(section: section),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFinal ? section.label.toUpperCase() : section.label,
                  style: (isFinal
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                    letterSpacing: isFinal ? 1.2 : 0,
                  ),
                ),
                if (section.dateRange != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    section.dateRange!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Final doesn't get a count pill — it's always one match.
          if (!isFinal)
            _CountPill(count: section.count, accent: section.accentColor),
        ],
      ),
    );
  }
}

class _LeadingBadge extends StatelessWidget {
  const _LeadingBadge({required this.section});
  final _SectionHeader section;

  @override
  Widget build(BuildContext context) {
    final isFinal = section.round.toLowerCase() == 'final';
    final number = section.matchdayNumber;
    final accent = section.accentColor;
    final size = isFinal ? 44.0 : 36.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isFinal ? 0.18 : 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: isFinal ? 0.7 : 0.4),
          width: isFinal ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: number != null
          ? Text(
              '$number',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          : Icon(
              section.knockoutIcon ?? Symbols.sports_soccer,
              color: accent,
              size: isFinal ? 24 : 20,
              fill: 1,
            ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.accent});
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: AppRadii.pillRadius,
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: AppColors.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Match card
//
// The outer card (kickoff time column, team flags + codes, predict button
// silhouette) is a plain StatelessWidget — it never rebuilds on a score
// tick. The live state (score, LIVE pill, minute, predict-vs-checkmark
// chip) lives inside the [_LiveCardCenter] / [_LiveAction] consumers,
// each of which subscribes to its own slice of [liveMatchProvider] +
// [clockTickerProvider].
// ---------------------------------------------------------------------------

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    super.key,
    required this.match,
    required this.isPredicted,
    required this.isBoosted,
  });

  final MatchModel match;
  final bool isPredicted;
  final bool isBoosted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Boosted cards get a tinted background + a soft green stroke so a
    // glance at the list shows the user where their multiplier sits.
    // We keep the existing live-ticker subtree intact; only the outer
    // surface chrome reacts to `isBoosted`.
    final cardColor = isBoosted
        ? AppColors.primaryContainer.withValues(alpha: 0.25)
        : AppColors.surfaceHigh;
    final cardBorder = isBoosted
        ? Border.all(
            color: AppColors.primary.withValues(alpha: 0.45),
            width: 1.5,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: AppRadii.cardRadius,
            border: cardBorder,
          ),
          child: InkWell(
            onTap: () => context.push('/matches/${match.id}'),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  _LiveTimeColumn(match: match),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _LiveTeamsBlock(match: match, theme: theme),
                  ),
                  if (isBoosted) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.bolt,
                      size: 18,
                      color: AppColors.primary.withValues(alpha: 0.9),
                    ),
                  ],
                  const SizedBox(width: 10),
                  _LiveAction(match: match, isPredicted: isPredicted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LiveTimeColumn — leading time / day. Color flips with status, so it
// subscribes to overlay's status (not score).
// ---------------------------------------------------------------------------

class _LiveTimeColumn extends ConsumerWidget {
  const _LiveTimeColumn({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlayStatus = ref.watch(
      liveMatchProvider(match.id).select((m) => m?.status),
    );
    final status = overlayStatus ?? match.status;
    final isLive = status == 'live';
    final isFinal = status == 'final' || status == 'finished';

    final kickoff = match.kickoffTime?.toLocal();
    if (kickoff == null) {
      return const SizedBox(
        width: 48,
        child: Text(
          'TBC',
          style: TextStyle(
            color: AppColors.onSurfaceMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    final timeStr = DateFormat('HH:mm').format(kickoff);
    final dayStr = DateFormat('EEE').format(kickoff).toUpperCase();

    final color = isLive
        ? AppColors.live
        : (isFinal ? AppColors.onSurfaceMuted : AppColors.onSurface);

    return SizedBox(
      width: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dayStr,
            style: const TextStyle(
              color: AppColors.onSurfaceMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LiveTeamsBlock — team codes + flags + live-aware score separator.
//
// Subscribes to the merged overlay so a score tick rebuilds only this
// row of the card (and a status flip recolors the divider).
// ---------------------------------------------------------------------------

class _LiveTeamsBlock extends ConsumerWidget {
  const _LiveTeamsBlock({required this.match, required this.theme});
  final MatchModel match;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(liveMatchProvider(match.id));
    final m = mergeWithLive(match, overlay);
    final isLive = m.status == 'live';
    final isFinal = m.status == 'final' || m.status == 'finished';

    // Score column logic — match the detail screen's hero:
    //   * final          → full-time number (with (et) / (p) prefix when relevant)
    //   * live + HT set  → "ft–ft  HT ht1-ht2" (running + half-time)
    //   * live (pre-HT)  → running score
    //   * else           → "vs"
    final String scoreText;
    final bool showScore;
    if (isFinal) {
      scoreText = _finalScoreLabel(m);
      showScore = true;
    } else if (isLive) {
      scoreText = formatScore(m.scoreFtTeam1, m.scoreFtTeam2);
      showScore = true;
    } else {
      scoreText = 'vs';
      showScore = false;
    }

    final separatorColor = isLive
        ? AppColors.live
        : (isFinal ? AppColors.onSurface : AppColors.onSurfaceMuted);

    final t1 = m.team1 ?? match.team1;
    final t2 = m.team2 ?? match.team2;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (t1 != null) ...[
                TeamFlag(team: t1, size: 24),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  t1?.code ?? '?',
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                scoreText,
                style: TextStyle(
                  color: separatorColor,
                  fontSize: showScore ? 16 : 12,
                  fontWeight: showScore ? FontWeight.w800 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (isLive && m.scoreHtTeam1 != null && m.scoreHtTeam2 != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    formatLabeledScore('HT', m.scoreHtTeam1, m.scoreHtTeam2),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.onSurfaceMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  t2?.code ?? '?',
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
              if (t2 != null) ...[
                const SizedBox(width: 8),
                TeamFlag(team: t2, size: 24),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _LiveAction — trailing pill ("LIVE 23'", "Predict", checkmark, or nothing).
//
// Watches the overlay status + the global clock ticker (only when live).
// Status flip → swap pill; minute tick → only the minute Text rebuilds
// via the inner [_CardMinuteLabel].
// ---------------------------------------------------------------------------

class _LiveAction extends ConsumerWidget {
  const _LiveAction({required this.match, required this.isPredicted});
  final MatchModel match;
  final bool isPredicted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(liveMatchProvider(match.id));
    final m = mergeWithLive(match, overlay);
    final isLive = m.status == 'live';
    final isFinal = m.status == 'final' || m.status == 'finished';
    final isCancelled = m.status == 'cancelled';

    if (isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.live.withValues(alpha: 0.15),
          borderRadius: AppRadii.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.live,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'LIVE',
              style: TextStyle(
                color: AppColors.live,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            // Live minute pill — isolated consumer so the 10 s tick only
            // rebuilds the inner Text, not the surrounding pill.
            _CardMinuteLabel(match: m),
          ],
        ),
      );
    }
    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighest,
          borderRadius: AppRadii.pillRadius,
        ),
        child: const Text(
          'CANC',
          style: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    if (isFinal) {
      // Final matches: keep the trailing column clean — the score lives
      // in the middle, no action pill. Predicted matches get a quiet
      // checkmark for confirmation.
      if (isPredicted) {
        return const Icon(
          Symbols.check_circle,
          size: 22,
          color: AppColors.primary,
          fill: 1,
        );
      }
      return const SizedBox(width: 0);
    }
    // Scheduled, not yet started.
    if (!m.isLocked && !isPredicted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: AppRadii.pillRadius,
        ),
        child: const Text(
          'Predict',
          style: TextStyle(
            color: AppColors.onPrimaryContainer,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (!m.isLocked && isPredicted) {
      return const Icon(
        Symbols.check_circle,
        size: 22,
        color: AppColors.primary,
        fill: 1,
      );
    }
    return const SizedBox(width: 0);
  }
}

/// Minute Text inside the LIVE pill of a list card. Watches the global
/// clock ticker so only this Text rebuilds every 10 seconds.
class _CardMinuteLabel extends ConsumerWidget {
  const _CardMinuteLabel({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockTickerProvider).valueOrNull ?? DateTime.now();
    final label = formatLiveMinute(match, now);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.live,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Human-readable score for a match that's reached `final` status.
///
/// Rules:
/// - Penalties: render `(p) X–Y` to flag the shootout result.
/// - Extra time: render `(et) X–Y` using the post-ET score.
/// - Otherwise: the standard 90-minute full-time score.
///
/// Stays compact for the list-card centre column; the detail-screen
/// hero gets a richer multi-line presentation in match_detail_screen.
String _finalScoreLabel(MatchModel m) {
  if (m.scorePenTeam1 != null && m.scorePenTeam2 != null) {
    return '(p) ${formatScore(m.scorePenTeam1, m.scorePenTeam2)}';
  }
  if (m.scoreEtTeam1 != null && m.scoreEtTeam2 != null) {
    return '(et) ${formatScore(m.scoreEtTeam1, m.scoreEtTeam2)}';
  }
  return formatScore(m.scoreFtTeam1, m.scoreFtTeam2);
}

// ---------------------------------------------------------------------------
// Active-round booster card — pinned beneath the tournament banner.
//
// Shows ONE card for the round the user can act on right now. The active
// round is the earliest knockout round where:
//   1. The previous bracket stage has fully finalised (so the bracket is
//      filled in and team names are real, not TBD placeholders), and
//   2. At least one match in this round is still pre-kickoff (so the
//      booster can still be applied or moved before the lock trigger
//      fires DB-side).
//
// Until R32 starts the card is hidden — knockout teams aren't determined
// until the group stage is final. Once R16 starts the R32 card retires
// (no more boosters can land there) and R16 takes its place. The Final
// and 3rd-place rounds use auto-multipliers, so we never surface a
// booster card for them.
// ---------------------------------------------------------------------------

/// Returns the round the booster card should surface, or null when no
/// round is actionable. Pure — exported only via this file's private
/// scope, but kept top-level so unit tests can target it directly later.
String? _activeBoosterRound(List<MatchModel> matches) {
  const knockoutOrder = ['R32', 'R16', 'QF', 'SF'];
  for (var i = 0; i < knockoutOrder.length; i++) {
    final round = knockoutOrder[i];
    final roundMatches = matches.where((m) => m.round == round).toList();
    if (roundMatches.isEmpty) continue;

    // Previous stage must have fully finalised so the bracket teams are
    // real. R32's gate is the group stage; later rounds gate on the
    // previous knockout round.
    final prevRoundFinal = i == 0
        ? _allGroupStageFinal(matches)
        : matches
            .where((m) => m.round == knockoutOrder[i - 1])
            .every((m) => m.status == 'final');
    if (!prevRoundFinal) continue;

    // At least one match in THIS round must still be pre-kickoff.
    final hasUnlocked = roundMatches.any((m) => !m.isLocked);
    if (!hasUnlocked) continue;

    return round;
  }
  return null;
}

bool _allGroupStageFinal(List<MatchModel> matches) {
  final group = matches.where((m) {
    final r = m.round ?? '';
    return r.startsWith('Matchday') || r == 'Group Stage';
  }).toList();
  if (group.isEmpty) return false;
  return group.every((m) => m.status == 'final');
}

class _RoundBoostersStrip extends StatelessWidget {
  const _RoundBoostersStrip({
    required this.matches,
    required this.boostersByRound,
  });

  final List<MatchModel> matches;
  final Map<String, RoundBoosterModel> boostersByRound;

  @override
  Widget build(BuildContext context) {
    final round = _activeBoosterRound(matches);
    if (round == null) return const SizedBox.shrink();

    final multiplier = kBoosterMultipliers[round]!;
    final booster = boostersByRound[round];
    final appliedMatch = booster == null
        ? null
        : matches.cast<MatchModel?>().firstWhere(
              (m) => m?.id == booster.matchId,
              orElse: () => null,
            );
    final applied = appliedMatch != null;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: applied
              ? () => context.push('/matches/${appliedMatch.id}')
              : null,
          borderRadius: AppRadii.cardRadius,
          child: Ink(
            decoration: BoxDecoration(
              color: applied
                  ? AppColors.primaryContainer.withValues(alpha: 0.25)
                  : AppColors.surfaceHigh,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(
                color: applied
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : AppColors.outline,
                width: applied ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  // Round + multiplier badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: applied
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : AppColors.surfaceHighest,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: applied
                            ? AppColors.primary.withValues(alpha: 0.6)
                            : AppColors.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 14,
                          color: applied
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$round ×$multiplier',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: applied
                                ? AppColors.primary
                                : AppColors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          applied
                              ? '${appliedMatch.team1?.code ?? '???'} vs ${appliedMatch.team2?.code ?? '???'}'
                              : 'No match boosted yet',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          applied
                              ? 'Booster applied · tap to open the match'
                              : 'Tap a $round match to apply this round\'s booster',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (applied)
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.onSurfaceMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
