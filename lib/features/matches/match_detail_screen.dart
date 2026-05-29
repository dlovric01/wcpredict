import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/features/matches/live_events_widget.dart';
import 'package:wcpredict/features/matches/predict_modal.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';

class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final int matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchAsync = ref.watch(matchByIdProvider(matchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: matchAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (match) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(matchByIdProvider(matchId));
            ref.invalidate(matchEventsProvider(matchId));
            ref.invalidate(myPredictionProvider(matchId));
          },
          child: _MatchBody(match: match, matchId: matchId),
        ),
      ),
    );
  }
}

class _MatchBody extends ConsumerWidget {
  const _MatchBody({required this.match, required this.matchId});
  final MatchModel match;
  final int matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final predAsync = ref.watch(myPredictionProvider(matchId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TeamScoreCard(match: match),
        const SizedBox(height: 16),
        Center(child: _StatusChip(match: match)),
        const SizedBox(height: 24),
        predAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (pred) => _PredictionCard(
            match: match,
            prediction: pred,
            onPredict: () async {
              await showPredictModal(context, match: match, existing: pred);
              ref.invalidate(myPredictionProvider(matchId));
            },
          ),
        ),
        const SizedBox(height: 24),
        if (match.status == 'final') ...[
          Text('Match Events', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          LiveEventsWidget(matchId: matchId),
        ],
      ],
    );
  }
}

class _TeamScoreCard extends StatelessWidget {
  const _TeamScoreCard({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFinal = match.status == 'final';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: _TeamCol(
                team: match.team1,
                name: match.team1?.name ?? 'TBD',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: isFinal
                  ? Text(
                      '${match.scoreFtTeam1 ?? 0} – ${match.scoreFtTeam2 ?? 0}',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    )
                  : Text(
                      DateFormat('d MMM, HH:mm').format(
                        (match.kickoffTime ?? DateTime.now()).toLocal(),
                      ),
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
            ),
            Expanded(
              child: _TeamCol(
                team: match.team2,
                name: match.team2?.name ?? 'TBD',
                rightAlign: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamCol extends StatelessWidget {
  const _TeamCol({
    required this.team,
    required this.name,
    this.rightAlign = false,
  });
  final TeamModel? team;
  final String name;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          rightAlign ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (team != null) TeamFlag(team: team!, size: 40),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: rightAlign ? TextAlign.right : TextAlign.left,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (match.status) {
      'final'     => ('Full Time', Colors.green),
      'live'      => ('Live', Colors.red),
      'cancelled' => ('Cancelled', Colors.grey),
      _           => (match.round ?? 'Scheduled',
                      Theme.of(context).colorScheme.primary),
    };
    return Chip(
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({
    required this.match,
    required this.prediction,
    required this.onPredict,
  });
  final MatchModel match;
  final dynamic prediction;
  final VoidCallback onPredict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = match.isLocked;
    final hasPred = prediction != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Prediction', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (hasPred) ...[
              Text(
                '${prediction.predictedTeam1} – ${prediction.predictedTeam2}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (prediction.pointsEarned != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Points earned: ${prediction.pointsEarned}',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ] else
              Text(
                locked ? 'Predictions are locked.' : 'No prediction yet.',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            if (!locked) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPredict,
                  child: Text(hasPred ? 'Edit Prediction' : 'Predict'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
