import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';
import 'package:wcpredict/core/models/team_model.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.match,
    this.myPrediction,
  });

  final MatchModel match;
  final PredictionModel? myPrediction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLive = match.status == 'live';
    final isFinal = match.status == 'final';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: null, // navigation handled by parent via GoRouter
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Team 1
                  Expanded(
                    child: _TeamSide(
                      team: match.team1,
                      align: CrossAxisAlignment.start,
                    ),
                  ),
                  // Centre: score / time + status badge
                  _CentreScore(match: match, isLive: isLive, isFinal: isFinal),
                  // Team 2
                  Expanded(
                    child: _TeamSide(
                      team: match.team2,
                      align: CrossAxisAlignment.end,
                    ),
                  ),
                ],
              ),
              if (myPrediction != null) ...[
                const SizedBox(height: 6),
                _PredictionRow(prediction: myPrediction!, colorScheme: cs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TeamSide extends StatelessWidget {
  const _TeamSide({required this.team, required this.align});

  final TeamModel? team;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final t = team;
    if (t == null) {
      return const SizedBox.shrink();
    }
    final isStart = align == CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        TeamFlag(team: t, size: 36),
        const SizedBox(height: 4),
        Text(
          t.code,
          textAlign: isStart ? TextAlign.left : TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CentreScore extends StatelessWidget {
  const _CentreScore({
    required this.match,
    required this.isLive,
    required this.isFinal,
  });

  final MatchModel match;
  final bool isLive;
  final bool isFinal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LiveDot(),
                const SizedBox(width: 4),
                Text(
                  '${match.scoreFtTeam1 ?? 0} – ${match.scoreFtTeam2 ?? 0}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ] else if (isFinal) ...[
            Text(
              '${match.scoreFtTeam1 ?? 0} – ${match.scoreFtTeam2 ?? 0}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'FT',
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ] else ...[
            Text(
              _formatKickoff(match.kickoffTime ?? DateTime.now()),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  String _formatKickoff(DateTime kickoff) {
    final now = DateTime.now();
    final local = kickoff.toLocal();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final timeStr = DateFormat('HH:mm').format(local);
    if (isToday) return 'Today $timeStr';
    return DateFormat('dd MMM HH:mm').format(local);
  }
}

// ---------------------------------------------------------------------------

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PredictionRow extends StatelessWidget {
  const _PredictionRow({
    required this.prediction,
    required this.colorScheme,
  });

  final PredictionModel prediction;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.sports_soccer, size: 12, color: colorScheme.primary),
        const SizedBox(width: 4),
        Text(
          'Your pick: ${prediction.predictedTeam1} – ${prediction.predictedTeam2}',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (prediction.pointsEarned != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '+${prediction.pointsEarned}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
