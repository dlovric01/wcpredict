import 'package:flutter/material.dart';

import 'package:wcpredict/core/scoring_rules.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';

/// Logical sections of the rules surface. Used as deep-link anchors so info
/// buttons on contextual screens can scroll the user directly to the section
/// most relevant to where they came from.
enum RuleSection {
  matchScoring,
  firstTeam,
  goalscorer,
  multipliers,
  tournament,
  locking,
}

/// Single canonical rules screen. Renders every scoring rule using values
/// from [scoring_rules.dart] so that displayed numbers are guaranteed to
/// agree with the engine.
///
/// `anchor` (optional) scrolls the section into view after first layout.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, this.anchor});

  final RuleSection? anchor;

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final Map<RuleSection, GlobalKey> _keys = {
    for (final s in RuleSection.values) s: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    final anchor = widget.anchor;
    if (anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[anchor]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: 0.05,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Rules & Scoring'),
        backgroundColor: AppColors.surfaceBase,
        foregroundColor: AppColors.onSurface,
        surfaceTintColor: AppColors.surfaceBase,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _IntroCard(),
            const SizedBox(height: AppSpacing.md),
            _MatchScoringCard(sectionKey: _keys[RuleSection.matchScoring]!),
            const SizedBox(height: AppSpacing.md),
            _FirstTeamCard(sectionKey: _keys[RuleSection.firstTeam]!),
            const SizedBox(height: AppSpacing.md),
            _GoalscorerCard(sectionKey: _keys[RuleSection.goalscorer]!),
            const SizedBox(height: AppSpacing.md),
            const _MaxBaseCard(),
            const SizedBox(height: AppSpacing.md),
            _MultipliersCard(sectionKey: _keys[RuleSection.multipliers]!),
            const SizedBox(height: AppSpacing.md),
            _TournamentCard(sectionKey: _keys[RuleSection.tournament]!),
            const SizedBox(height: AppSpacing.md),
            _LockingCard(sectionKey: _keys[RuleSection.locking]!),
          ],
        ),
      ),
    );
  }
}

// ─── Shared section scaffolding ──────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.accent = AppColors.primary,
    this.sectionKey,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Key? sectionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: sectionKey,
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Two-column row used in every scoring table. `label` left, `points`
/// right with a coloured pill.
class _PointsRow extends StatelessWidget {
  const _PointsRow({
    required this.label,
    required this.points,
    this.accent = AppColors.primary,
    this.subtitle,
  });

  final String label;
  final int points;
  final Color accent;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sign = points >= 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: AppRadii.pillRadius,
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Text(
              '$sign$points pts',
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-column row for multipliers. Similar to [_PointsRow] but with an
/// "×N" pill instead of a "+N pts" pill.
class _MultiplierRow extends StatelessWidget {
  const _MultiplierRow({
    required this.label,
    required this.multiplier,
    this.accent = AppColors.secondary,
  });

  final String label;
  final int multiplier;
  final Color accent;


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: AppRadii.pillRadius,
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Text(
              '×$multiplier',
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '•  ',
            style: TextStyle(color: AppColors.onSurfaceMuted),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Cards ───────────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: AppColors.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardRadius,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sports_soccer,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'How it works',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Predict each match before kickoff. Earn points when your '
              'picks come true. Boost individual knockout matches for big '
              'swings on the leaderboard.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchScoringCard extends StatelessWidget {
  const _MatchScoringCard({required this.sectionKey});
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      sectionKey: sectionKey,
      title: 'Match score',
      icon: Icons.scoreboard_outlined,
      child: Column(
        children: [
          const _PointsRow(
            label: 'Exact score',
            subtitle: 'Predict 2-1, actual 2-1',
            points: kPointsExact,
          ),
          const _PointsRow(
            label: 'Goal difference',
            subtitle: 'Same margin, |GD| ≥ 2 (e.g. 3-1 vs 4-2)',
            points: kPointsGoalDiff,
            accent: AppColors.secondary,
          ),
          const _PointsRow(
            label: 'Outcome',
            subtitle: 'Right winner / draw, wrong margin',
            points: kPointsOutcome,
            accent: AppColors.tertiary,
          ),
          const _PointsRow(
            label: 'Wrong',
            points: 0,
            accent: AppColors.onSurfaceMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Only the highest matching category is awarded — they do not stack.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}

class _FirstTeamCard extends StatelessWidget {
  const _FirstTeamCard({required this.sectionKey});
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      sectionKey: sectionKey,
      title: 'First team to score',
      icon: Icons.bolt_outlined,
      accent: AppColors.secondary,
      child: Column(
        children: const [
          _PointsRow(
            label: 'Correct pick',
            subtitle: 'Picked team scores first regular-time goal',
            points: kPointsFirstTeam,
            accent: AppColors.secondary,
          ),
          SizedBox(height: AppSpacing.xs),
          _Bullet('Own goals do not count.'),
          _Bullet('Goals after 90′ (extra time, penalties) do not count.'),
          _Bullet(
            'The pick is independent of your score prediction — it stacks.',
          ),
          _Bullet('Available only when at least one team is predicted to score.'),
        ],
      ),
    );
  }
}

class _GoalscorerCard extends StatelessWidget {
  const _GoalscorerCard({required this.sectionKey});
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      sectionKey: sectionKey,
      title: 'Goalscorer',
      icon: Icons.sports_score_outlined,
      accent: AppColors.tertiary,
      child: Column(
        children: const [
          _PointsRow(
            label: 'Player scored',
            subtitle: 'At least one non-OG goal in regulation time',
            points: kPointsGoalscorer,
            accent: AppColors.tertiary,
          ),
          SizedBox(height: AppSpacing.xs),
          _Bullet('Own goals do not count.'),
          _Bullet('The player does not need to start the match.'),
          _Bullet('The player does not need to score first.'),
          _Bullet('Stacks with match-score and first-team awards.'),
        ],
      ),
    );
  }
}

class _MaxBaseCard extends StatelessWidget {
  const _MaxBaseCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events_outlined,
                    color: AppColors.gold, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Max per match (no multiplier)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _SumLine(
              entries: const [
                ('Exact', kPointsExact),
                ('First team', kPointsFirstTeam),
                ('Goalscorer', kPointsGoalscorer),
              ],
              total: kPointsMaxBase,
              accent: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SumLine extends StatelessWidget {
  const _SumLine({
    required this.entries,
    required this.total,
    required this.accent,
  });
  final List<(String, int)> entries;
  final int total;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final (label, pts) = entries[i];
      parts.add(_chip('$label · $pts', accent));
      if (i < entries.length - 1) {
        parts.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '+',
            style: TextStyle(color: AppColors.onSurfaceMuted),
          ),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: parts,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '= $total points',
          style: theme.textTheme.titleLarge?.copyWith(
            color: accent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color accent) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          borderRadius: AppRadii.pillRadius,
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
}

class _MultipliersCard extends StatelessWidget {
  const _MultipliersCard({required this.sectionKey});
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      sectionKey: sectionKey,
      title: 'Multipliers',
      icon: Icons.bolt,
      accent: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group stage',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const _Bullet('No multipliers — base points only.'),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Knockout boosters · optional',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final entry in kBoosterMultipliers.entries)
            _MultiplierRow(
              label: _roundFullName(entry.key),
              multiplier: entry.value,
              accent: AppColors.secondary,
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One booster per round. Pick one match before kickoff. Unused '
            'boosters expire when the round ends.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Automatic multipliers',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final entry in kAutoMultipliers.entries)
            _MultiplierRow(
              label: _roundFullName(entry.key),
              multiplier: entry.value,
              accent: AppColors.primary,
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Applied to everyone\u2019s predictions — no booster needed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.sectionKey});
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      sectionKey: sectionKey,
      title: 'Tournament picks',
      icon: Icons.emoji_events_outlined,
      accent: AppColors.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PointsRow(
            label: 'World Cup winner',
            points: kPointsWorldCupWinner,
            accent: AppColors.gold,
          ),
          const _PointsRow(
            label: 'Golden Boot',
            points: kPointsGoldenBoot,
            accent: AppColors.gold,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Maximum tournament bonus: $kPointsMaxTournament points.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _Bullet(
            'Picks must be submitted before the opening match kicks off.',
          ),
          const _Bullet('Points are added directly to your total.'),
        ],
      ),
    );
  }
}

class _LockingCard extends StatelessWidget {
  const _LockingCard({required this.sectionKey});
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      sectionKey: sectionKey,
      title: 'When picks lock',
      icon: Icons.lock_outline,
      accent: AppColors.onSurfaceVariant,
      child: Column(
        children: const [
          _Bullet(
            'Score, first-team, goalscorer & booster lock at the match\u2019s '
            'kickoff.',
          ),
          _Bullet(
            'Tournament picks (World Cup winner & Golden Boot) lock at the '
            'opening match of the tournament.',
          ),
          _Bullet(
            'After lock you can\u2019t edit, but you can see what other group '
            'members predicted.',
          ),
        ],
      ),
    );
  }
}

String _roundFullName(String round) {
  switch (round) {
    case 'R32':
      return 'Round of 32';
    case 'R16':
      return 'Round of 16';
    case 'QF':
      return 'Quarter-finals';
    case 'SF':
      return 'Semi-finals';
    case '3rd':
      return '3rd-place match';
    case 'Final':
      return 'Final';
    default:
      return round;
  }
}
