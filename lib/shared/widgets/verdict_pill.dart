import 'package:flutter/material.dart';

import 'package:wcpredict/core/theme/app_colors.dart';

/// Verdict type for a finished match prediction under the rules.md scoring
/// model where match result is mutually exclusive.
enum Verdict {
  exact,    // points_match == 5
  goalDiff, // points_match == 3  (|GD| ≥ 2, non-exact)
  outcome,  // points_match == 2
  miss,     // points_match == 0
  pending,  // match not finished yet
}

/// Derives the [Verdict] from the single mutually-exclusive `points_match`
/// value. Note that goalscorer is independent — it's surfaced separately
/// via [VerdictPill.goalscorerHit].
Verdict _deriveVerdict({int? points, int? pointsMatch}) {
  if (points == null) return Verdict.pending;
  switch (pointsMatch ?? 0) {
    case 5:
      return Verdict.exact;
    case 3:
      return Verdict.goalDiff;
    case 2:
      return Verdict.outcome;
    default:
      return Verdict.miss;
  }
}

/// A compact pill chip showing prediction outcome under the rules.md scoring.
///
/// Examples:
///   EXACT ×4 +52   (emerald, QF booster)
///   GOAL DIFF +3   (teal)
///   OUTCOME +2     (amber)
///   MISS +0        (muted)
class VerdictPill extends StatelessWidget {
  const VerdictPill({
    super.key,
    required this.points,
    this.pointsMatch,
    this.pointsFirstTeam,
    this.pointsGoalscorer,
    this.multiplier,
  });

  /// Total points earned (null = not yet scored).
  final int? points;

  /// Mutually exclusive match-result award: 0 | 2 | 3 | 5.
  final int? pointsMatch;

  /// First-team-to-score award: 0 | 2.
  final int? pointsFirstTeam;

  /// Goalscorer award: 0 | 8.
  final int? pointsGoalscorer;

  /// The multiplier applied to this prediction (default 1).
  final int? multiplier;

  bool get _goalscorerHit => (pointsGoalscorer ?? 0) >= 8;
  bool get _firstTeamHit => (pointsFirstTeam ?? 0) >= 2;

  @override
  Widget build(BuildContext context) {
    final verdict = _deriveVerdict(
      points: points,
      pointsMatch: pointsMatch,
    );
    if (verdict == Verdict.pending) return const SizedBox.shrink();

    final m = multiplier ?? 1;
    final multiplierSuffix = m > 1 ? ' ×$m' : '';
    final firstTeamSuffix = _firstTeamHit ? ' • 1ST' : '';
    final goalscorerSuffix = _goalscorerHit ? ' • GS' : '';
    final pointsSuffix = ' +${points ?? 0}';
    final bonusSuffix = '$multiplierSuffix$firstTeamSuffix$goalscorerSuffix';
    final anyBonusHit = _firstTeamHit || _goalscorerHit;

    final (label, bg, fg) = switch (verdict) {
      Verdict.exact => (
          'EXACT$bonusSuffix$pointsSuffix',
          AppColors.primaryContainer,
          AppColors.onPrimaryContainer,
        ),
      Verdict.goalDiff => (
          'GOAL DIFF$bonusSuffix$pointsSuffix',
          AppColors.secondaryContainer,
          AppColors.onSecondaryContainer,
        ),
      Verdict.outcome => (
          'OUTCOME$bonusSuffix$pointsSuffix',
          AppColors.secondaryContainer,
          AppColors.onSecondaryContainer,
        ),
      Verdict.miss => (
          // Match prediction missed — but first-team and/or goalscorer
          // can still award points independently.
          anyBonusHit
              ? 'BONUS$bonusSuffix$pointsSuffix'
              : 'MISS +0',
          anyBonusHit
              ? AppColors.secondaryContainer
              : AppColors.surfaceHighest,
          anyBonusHit
              ? AppColors.onSecondaryContainer
              : AppColors.onSurfaceMuted,
        ),
      Verdict.pending => ('', AppColors.surfaceHighest, AppColors.onSurfaceMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}
