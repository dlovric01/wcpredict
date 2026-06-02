import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/providers/groups_provider.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';
import 'package:wcpredict/shared/utils/score_format.dart';

// ---------------------------------------------------------------------------

class UserPredictionsScreen extends ConsumerWidget {
  const UserPredictionsScreen({
    super.key,
    required this.userId,
    required this.displayName,
    required this.totalPoints,
    required this.exactCount,
    required this.outcomeCount,
    required this.goalDiffCount,
    required this.scorerCount,
    required this.firstTeamCount,
  });

  final String userId;
  final String displayName;
  final int totalPoints;
  final int exactCount;
  final int outcomeCount;
  final int goalDiffCount;
  final int scorerCount;
  final int firstTeamCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predsAsync = ref.watch(userPredictionsProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayName),
            Text(
              'Predictions',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: predsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (rows) {
          final completed =
              rows.where((r) => r.match.status == 'final').toList();
          final upcoming =
              rows.where((r) => r.match.status != 'final').toList();

          if (rows.isEmpty) {
            return Column(
              children: [
                _SummaryHeader(
                  totalPoints: totalPoints,
                  exactCount: exactCount,
                  outcomeCount: outcomeCount,
                  goalDiffCount: goalDiffCount,
                  scorerCount: scorerCount,
                  firstTeamCount: firstTeamCount,
                  predictionCount: 0,
                ),
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.how_to_vote_outlined,
                            size: 40, color: AppColors.onSurfaceMuted),
                        SizedBox(height: 12),
                        Text(
                          'No predictions yet',
                          style: TextStyle(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _SummaryHeader(
                  totalPoints: totalPoints,
                  exactCount: exactCount,
                  outcomeCount: outcomeCount,
                  goalDiffCount: goalDiffCount,
                  scorerCount: scorerCount,
                  firstTeamCount: firstTeamCount,
                  predictionCount: rows.length,
                ),
              ),
              if (completed.isNotEmpty) ...[
                _SectionHeader(
                    label: 'Completed', count: completed.length),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _PredictionTile(
                      prediction: completed[i].prediction,
                      match: completed[i].match,
                    ),
                    childCount: completed.length,
                  ),
                ),
              ],
              if (upcoming.isNotEmpty) ...[
                _SectionHeader(
                    label: 'Upcoming', count: upcoming.length),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _PredictionTile(
                      prediction: upcoming[i].prediction,
                      match: upcoming[i].match,
                    ),
                    childCount: upcoming.length,
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary header
// ---------------------------------------------------------------------------

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.totalPoints,
    required this.exactCount,
    required this.outcomeCount,
    required this.goalDiffCount,
    required this.scorerCount,
    required this.firstTeamCount,
    required this.predictionCount,
  });

  final int totalPoints;
  final int exactCount;
  final int outcomeCount;
  final int goalDiffCount;
  final int scorerCount;
  final int firstTeamCount;
  final int predictionCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$totalPoints',
                style: textTheme.displaySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'total pts',
                style: textTheme.labelSmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Container(width: 1, height: 48, color: AppColors.outline),
          const SizedBox(width: 24),
          Expanded(
            child: Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                _StatChip(
                    label: 'Predictions',
                    value: predictionCount,
                    color: AppColors.onSurfaceVariant),
                _StatChip(
                    label: 'Exact',
                    value: exactCount,
                    color: AppColors.primary),
                _StatChip(
                    label: 'Outcomes',
                    value: outcomeCount,
                    color: AppColors.onSurfaceVariant),
                _StatChip(
                    label: 'Scorers',
                    value: scorerCount,
                    color: AppColors.secondary),
                _StatChip(
                    label: '1st team',
                    value: firstTeamCount,
                    color: AppColors.tertiary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: textTheme.titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label,
            style: textTheme.labelSmall
                ?.copyWith(color: AppColors.onSurfaceMuted)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceHighest,
                borderRadius: AppRadii.pillRadius,
              ),
              child: Text(
                '$count',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Prediction tile
// ---------------------------------------------------------------------------

class _PredictionTile extends StatelessWidget {
  const _PredictionTile(
      {required this.prediction, required this.match});
  final PredictionModel prediction;
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final isFinal = match.status == 'final';
    final isLive = match.status == 'live';

    final earned = prediction.pointsEarned;
    final pointColor = isFinal
        ? earned == null
            ? AppColors.onSurfaceMuted
            : earned >= 8
                ? AppColors.gold
                : earned >= 5
                    ? AppColors.primary
                    : earned >= 1
                        ? AppColors.secondary
                        : AppColors.onSurfaceMuted
        : AppColors.onSurfaceMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
        child: InkWell(
          borderRadius: AppRadii.cardRadius,
          onTap: () => context.push('/matches/${match.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Match header row ──────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _MatchHeader(match: match, isLive: isLive),
                    ),
                    if (isFinal && earned != null) ...[
                      const SizedBox(width: 8),
                      _PointsBadge(points: earned, color: pointColor),
                    ] else if (!isFinal) ...[
                      const SizedBox(width: 8),
                      _StatusBadge(status: match.status),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // ── Scores row ────────────────────────────────────────────
                Row(
                  children: [
                    _ScoreBlock(
                      label: 'Predicted',
                      score1: prediction.predictedTeam1,
                      score2: prediction.predictedTeam2,
                      highlight: false,
                    ),
                    if (isFinal) ...[
                      const SizedBox(width: 20),
                      _ScoreBlock(
                        label: 'Actual',
                        score1: match.scoreFtTeam1,
                        score2: match.scoreFtTeam2,
                        highlight: true,
                      ),
                    ],
                  ],
                ),
                // ── Points breakdown ──────────────────────────────────────
                if (isFinal) ...[
                  const SizedBox(height: 10),
                  _PointsBreakdown(prediction: prediction),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.match, required this.isLive});
  final MatchModel match;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final t1 = match.team1;
    final t2 = match.team2;
    final kickoff = match.kickoffTime;
    final dateStr = kickoff != null
        ? DateFormat('d MMM · HH:mm').format(kickoff.toLocal())
        : '';

    return Row(
      children: [
        if (t1 != null) ...[
          TeamFlag(team: t1, size: 22),
          const SizedBox(width: 6),
          Text(t1.code,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('vs',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.onSurfaceMuted)),
        ),
        if (t2 != null) ...[
          Text(t2.code,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          TeamFlag(team: t2, size: 22),
        ],
        const SizedBox(width: 8),
        Text(
          dateStr,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.label,
    required this.score1,
    required this.score2,
    required this.highlight,
  });
  final String label;
  final int? score1;
  final int? score2;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scoreText = (score1 != null && score2 != null)
        ? formatScore(score1, score2)
        : '—';
    final scoreColor =
        highlight ? AppColors.onSurface : AppColors.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: textTheme.labelSmall
                ?.copyWith(color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 2),
        Text(
          scoreText,
          style: textTheme.titleMedium?.copyWith(
            color: scoreColor,
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PointsBreakdown extends StatelessWidget {
  const _PointsBreakdown({required this.prediction});
  final PredictionModel prediction;

  @override
  Widget build(BuildContext context) {
    final m = prediction.multiplier ?? 1;
    final pm = prediction.pointsMatch ?? 0;
    // Match result is mutually exclusive — surface the single category that
    // was awarded (or "Miss" when none matched).
    final String matchLabel;
    final int matchMax;
    switch (pm) {
      case 5:
        matchLabel = 'Exact';
        matchMax = 5;
      case 3:
        matchLabel = 'Goal diff';
        matchMax = 3;
      case 2:
        matchLabel = 'Outcome';
        matchMax = 2;
      default:
        matchLabel = 'Miss';
        matchMax = 5; // dimmest state — show full bar for context
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _BreakdownChip(
          label: matchLabel,
          points: pm,
          max: matchMax,
        ),
        _BreakdownChip(
          label: 'First team',
          points: prediction.pointsFirstTeam ?? 0,
          max: 2,
        ),
        _BreakdownChip(
          label: 'Goalscorer',
          points: prediction.pointsGoalscorer ?? 0,
          max: 8,
        ),
        if (m > 1)
          _BreakdownChip(
            label: '×$m booster',
            points: m,
            max: m,
            isMultiplier: true,
          ),
      ],
    );
  }
}

class _BreakdownChip extends StatelessWidget {
  const _BreakdownChip(
      {required this.label, required this.points, required this.max,
       this.isMultiplier = false});
  final String label;
  final int points;
  final int max;
  final bool isMultiplier;

  @override
  Widget build(BuildContext context) {
    final hit = points > 0;
    final color = hit ? AppColors.primary : AppColors.onSurfaceMuted;
    final bgColor = hit
        ? AppColors.primaryContainer.withValues(alpha: 0.5)
        : AppColors.surfaceHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppRadii.pillRadius,
        border: Border.all(
          color: hit ? AppColors.primary.withValues(alpha: 0.4) : AppColors.outline,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hit ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isMultiplier ? label : '$label · ${points}pt${points != 1 ? 's' : ''}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight:
                      hit ? FontWeight.w600 : FontWeight.normal,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({required this.points, required this.color});
  final int points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$points',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
        Text(
          'pts',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.onSurfaceMuted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    if (status != 'live') return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.15),
        borderRadius: AppRadii.pillRadius,
      ),
      child: Text(
        'LIVE',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.live,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
