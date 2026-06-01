// First-team-to-score picker. Two side-by-side team chips that toggle
// on tap. Chip is disabled (dimmed, no gesture) when that team's
// predicted score is 0 — mirrors the DB validation trigger so users
// can't even attempt an invalid save.
//
// Extracted from `match_detail_screen.dart` so it can be widget-tested
// in isolation. The parent screen owns the selection state and feeds
// it back via [onPick].

import 'package:flutter/material.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';

/// Two-chip row letting the user pick which team scores first. Both chips
/// are visible whenever the predicted score is non-zero; a chip is only
/// tappable when its team has a predicted score > 0.
class FirstTeamPicker extends StatelessWidget {
  const FirstTeamPicker({
    super.key,
    required this.match,
    required this.selectedTeamId,
    required this.score1,
    required this.score2,
    required this.onPick,
  });

  final MatchModel match;
  final int? selectedTeamId;
  final int score1;
  final int score2;

  /// Called with a team id to select, or with `null` to clear the pick.
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final t1 = match.team1;
    final t2 = match.team2;
    if (t1 == null || t2 == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: FirstTeamChip(
            team: t1,
            enabled: score1 > 0,
            selected: selectedTeamId == t1.id,
            onTap: () => onPick(selectedTeamId == t1.id ? null : t1.id),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FirstTeamChip(
            team: t2,
            enabled: score2 > 0,
            selected: selectedTeamId == t2.id,
            onTap: () => onPick(selectedTeamId == t2.id ? null : t2.id),
          ),
        ),
      ],
    );
  }
}

/// A single chip representing one team in the [FirstTeamPicker].
///
/// Tri-state: enabled+unselected (default), enabled+selected (primary
/// border), disabled (dimmed, no `GestureDetector`).
class FirstTeamChip extends StatelessWidget {
  const FirstTeamChip({
    super.key,
    required this.team,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final TeamModel team;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color bg;
    final Color border;
    final Color fg;
    final double borderWidth;
    if (!enabled) {
      bg = AppColors.surface;
      border = AppColors.outline.withValues(alpha: 0.4);
      fg = AppColors.onSurfaceMuted;
      borderWidth = 1;
    } else if (selected) {
      bg = AppColors.primaryContainer;
      border = AppColors.primary;
      fg = AppColors.onPrimaryContainer;
      borderWidth = 1.5;
    } else {
      bg = AppColors.surfaceHigh;
      border = AppColors.outline;
      fg = AppColors.onSurface;
      borderWidth = 1;
    }

    final content = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadii.pillRadius,
          border: Border.all(color: border, width: borderWidth),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TeamFlag(team: team, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                team.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (!enabled) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}
