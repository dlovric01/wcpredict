import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';
import 'package:wcpredict/shared/utils/score_format.dart';
import 'package:wcpredict/shared/utils/date_format.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.match,
    this.onTap,
  });

  final MatchModel match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardRadius,
        side: const BorderSide(color: AppColors.outline, width: 1),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppRadii.cardRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _TeamSide(team: match.team1, alignLeft: true),
              _CentreScore(match: match),
              _TeamSide(team: match.team2, alignLeft: false),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TeamSide extends StatelessWidget {
  const _TeamSide({required this.team, required this.alignLeft});

  final TeamModel? team;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final cross =
        alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final align = alignLeft ? TextAlign.left : TextAlign.right;
    return Expanded(
      child: Column(
        crossAxisAlignment: cross,
        children: [
          TeamFlag(team: team, tbd: team == null, size: 28),
          const SizedBox(height: 4),
          Text(
            team?.code ?? '?',
            textAlign: align,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          Text(
            team?.name ?? 'TBD',
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CentreScore extends StatelessWidget {
  const _CentreScore({required this.match});

  final MatchModel match;

  static const _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isLive = match.status == 'live';
    final isFinal = match.status == 'final';
    final isLocked = match.isLocked && !isLive && !isFinal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LiveDot(),
                const SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: tt.labelSmall?.copyWith(color: AppColors.live),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              formatScore(match.scoreFtTeam1, match.scoreFtTeam2),
              style: tt.displaySmall?.copyWith(fontFeatures: _tabular),
            ),
          ] else if (isFinal) ...[
            Text(
              formatScore(match.scoreFtTeam1, match.scoreFtTeam2),
              style: tt.displaySmall?.copyWith(fontFeatures: _tabular),
            ),
            const SizedBox(height: 2),
            Text(
              'FT',
              style: tt.labelSmall?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ] else if (isLocked) ...[
            Text(
              'vs',
              style: tt.headlineMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.lock, size: 14, color: AppColors.locked),
          ] else ...[
            Text(
              'vs',
              style: tt.headlineMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatKickoff(match.kickoffTime),
              style: tt.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatKickoff(DateTime? kickoff) {
    if (kickoff == null) return '--:--';
    final local = kickoff.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return DateFormat('HH:mm').format(local);
    return formatMatchKickoffCompact(kickoff);
  }
}

// ---------------------------------------------------------------------------

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.live.withValues(alpha: 0.5 + 0.5 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
