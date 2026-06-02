import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/logger.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/models/tournament_prediction_model.dart';
import 'package:wcpredict/core/models/tournament_results_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';
import 'package:wcpredict/shared/providers/tournament_provider.dart';
import 'package:wcpredict/features/rules/rules_screen.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';
import 'package:wcpredict/shared/widgets/app_feedback.dart';

/// World Cup winner (+75) and Golden Boot (+50) bonus picks. Submitted any
/// time before the opening match; locked thereafter by the DB trigger.
class TournamentPredictionsScreen extends ConsumerStatefulWidget {
  const TournamentPredictionsScreen({super.key});

  @override
  ConsumerState<TournamentPredictionsScreen> createState() =>
      _TournamentPredictionsScreenState();
}

class _TournamentPredictionsScreenState
    extends ConsumerState<TournamentPredictionsScreen> {
  // Local working state. Initialised from the loaded prediction once available.
  int? _winnerTeamId;
  int? _goldenBootPlayerId;
  bool _hydrated = false;
  bool _saving = false;

  void _hydrate(TournamentPredictionModel? pred) {
    if (_hydrated) return;
    _hydrated = true;
    _winnerTeamId = pred?.wcWinnerTeamId;
    _goldenBootPlayerId = pred?.goldenBootPlayerId;
  }

  Future<void> _save() async {
    final user = supabase.auth.currentUser;
    if (user == null || _saving) return;
    setState(() => _saving = true);
    try {
      await supabase.from('tournament_predictions').upsert({
        'user_id': user.id,
        'wc_winner_team_id': _winnerTeamId,
        'golden_boot_player_id': _goldenBootPlayerId,
      });
      ref.invalidate(myTournamentPredictionProvider);
      AppFeedback.success('Tournament picks saved');
    } catch (e, st) {
      talker.handle(e, st, 'Tournament prediction save failed');
      AppFeedback.error('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickWinner() async {
    final picked = await showAppSheet<int>(
      context: context,
      builder: (_) => _TeamPickerSheet(selectedId: _winnerTeamId),
    );
    if (picked != null) setState(() => _winnerTeamId = picked);
  }

  Future<void> _pickGoldenBoot() async {
    final picked = await showAppSheet<int>(
      context: context,
      builder: (_) => _PlayerPickerSheet(selectedId: _goldenBootPlayerId),
    );
    if (picked != null) setState(() => _goldenBootPlayerId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final predAsync = ref.watch(myTournamentPredictionProvider);
    final resultsAsync = ref.watch(tournamentResultsProvider);
    final locked = ref.watch(tournamentLockedProvider);
    final openingAsync = ref.watch(tournamentOpeningKickoffProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournament Picks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How scoring works',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RulesScreen(anchor: RuleSection.tournament),
              ),
            ),
          ),
        ],
      ),
      body: predAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (pred) {
          _hydrate(pred);
          final results = resultsAsync.valueOrNull;
          final opening = openingAsync.valueOrNull;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _HeaderCard(
                locked: locked,
                opening: opening,
                pred: pred,
                results: results,
              ),
              const SizedBox(height: AppSpacing.lg),
              _PickRow(
                label: 'World Cup Winner',
                bonus: '+75',
                selectedLabel: _WinnerLabel(teamId: _winnerTeamId),
                onTap: locked ? null : _pickWinner,
              ),
              const SizedBox(height: AppSpacing.md),
              _PickRow(
                label: 'Golden Boot',
                bonus: '+50',
                selectedLabel: _GoldenBootLabel(playerId: _goldenBootPlayerId),
                onTap: locked ? null : _pickGoldenBoot,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!locked)
                Builder(builder: (_) {
                  // Save is a no-op when neither pick is set — disable
                  // the button so the user can't fire an empty upsert
                  // that just clobbers an existing row with NULLs.
                  final hasPick = _winnerTeamId != null ||
                      _goldenBootPlayerId != null;
                  return FilledButton(
                    onPressed: (_saving || !hasPick) ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save picks'),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

// ─── Selection labels (resolve by id, render async) ───────────────────────────

class _WinnerLabel extends ConsumerWidget {
  const _WinnerLabel({required this.teamId});
  final int? teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (teamId == null) return const _LabelText('Not picked');
    final async = ref.watch(teamByIdProvider(teamId!));
    return async.when(
      loading: () => const _LabelText('…'),
      error: (_, __) => const _LabelText('Unknown'),
      data: (t) => _LabelText(t?.name ?? 'Unknown'),
    );
  }
}

class _GoldenBootLabel extends ConsumerWidget {
  const _GoldenBootLabel({required this.playerId});
  final int? playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (playerId == null) return const _LabelText('Not picked');
    final async = ref.watch(playerByIdProvider(playerId!));
    return async.when(
      loading: () => const _LabelText('…'),
      error: (_, __) => const _LabelText('Unknown'),
      data: (hit) {
        if (hit == null) return const _LabelText('Unknown');
        final team = hit.team?.name;
        return _LabelText(
            team == null ? hit.player.name : '${hit.player.name} · $team');
      },
    );
  }
}

class _LabelText extends StatelessWidget {
  const _LabelText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text);
}

// ─── Header: lock state + results + earned bonus ──────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.locked,
    required this.opening,
    required this.pred,
    required this.results,
  });

  final bool locked;
  final DateTime? opening;
  final TournamentPredictionModel? pred;
  final TournamentResultsModel? results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earned = pred?.pointsEarned ?? 0;

    final List<Widget> rows = [];

    if (locked) {
      rows.add(Text(
        'Locked',
        style: theme.textTheme.titleMedium?.copyWith(
          color: AppColors.error,
          fontWeight: FontWeight.w700,
        ),
      ));
      if (opening != null) {
        rows.add(Text(
          'Opening match: ${opening!.toLocal()}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.onSurfaceMuted),
        ));
      }
    } else {
      rows.add(Text(
        'Open until the opening match',
        style:
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ));
      if (opening != null) {
        rows.add(Text(
          'Locks at ${opening!.toLocal()}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.onSurfaceMuted),
        ));
      }
    }

    if (results != null && (results!.hasWinner || results!.hasGoldenBoot)) {
      rows.add(const SizedBox(height: 8));
      rows.add(Text(
        'Bonus earned: +$earned pts',
        style: theme.textTheme.titleSmall?.copyWith(
          color: earned > 0 ? AppColors.primary : AppColors.onSurfaceMuted,
          fontWeight: FontWeight.w600,
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

// ─── A tappable row for a single pick (winner or golden boot) ─────────────────

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.bonus,
    required this.selectedLabel,
    required this.onTap,
  });

  final String label;
  final String bonus;
  final Widget selectedLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;

    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: AppRadii.cardRadius,
      child: InkWell(
        borderRadius: AppRadii.cardRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: theme.textTheme.titleMedium),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            bonus,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: disabled
                            ? AppColors.onSurfaceMuted
                            : theme.colorScheme.onSurface,
                      ),
                      child: selectedLabel,
                    ),
                  ],
                ),
              ),
              if (!disabled) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Team picker bottom sheet (searchable, 50-row pages) ──────────────────────

class _TeamPickerSheet extends ConsumerStatefulWidget {
  const _TeamPickerSheet({this.selectedId});
  final int? selectedId;

  @override
  ConsumerState<_TeamPickerSheet> createState() => _TeamPickerSheetState();
}

class _TeamPickerSheetState extends ConsumerState<_TeamPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(teamSearchProvider(_query));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search teams…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Search failed: $e')),
              data: (teams) {
                if (teams.isEmpty) {
                  return const Center(child: Text('No matches'));
                }
                return ListView.builder(
                  controller: controller,
                  itemCount: teams.length,
                  itemBuilder: (_, i) => _teamTile(teams[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamTile(TeamModel t) {
    final selected = t.id == widget.selectedId;
    return ListTile(
      leading: t.flagUrl != null
          ? CachedNetworkImage(
              imageUrl: t.flagUrl!,
              width: 32,
              height: 22,
              fit: BoxFit.cover,
            )
          : const SizedBox(width: 32),
      title: Text(t.name),
      subtitle: Text(t.code),
      trailing:
          selected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () => Navigator.of(context).pop(t.id),
    );
  }
}

// ─── Player picker bottom sheet (searchable, 50-row pages) ────────────────────

class _PlayerPickerSheet extends ConsumerStatefulWidget {
  const _PlayerPickerSheet({this.selectedId});
  final int? selectedId;

  @override
  ConsumerState<_PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends ConsumerState<_PlayerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(playerSearchProvider(_query));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search players…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Search failed: $e')),
              data: (hits) {
                if (hits.isEmpty) {
                  if (_query.trim().isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Start typing to find a player.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return const Center(child: Text('No players match.'));
                }
                return ListView.builder(
                  controller: controller,
                  itemCount: hits.length,
                  itemBuilder: (_, i) => _playerTile(hits[i]),
                );
              },
            ),
          ),
          const Padding(
            padding:
                EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
            child: Text(
              'Showing up to 50 results — refine your search if you don\'t see the player.',
              style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerTile(PlayerSearchHit hit) {
    final p = hit.player;
    final selected = p.id == widget.selectedId;
    final subtitle = hit.team?.name ?? p.position ?? '—';
    return ListTile(
      leading: hit.team?.flagUrl != null
          ? CachedNetworkImage(
              imageUrl: hit.team!.flagUrl!,
              width: 32,
              height: 22,
              fit: BoxFit.cover,
            )
          : const SizedBox(width: 32),
      title: Text(p.name),
      subtitle: Text(subtitle),
      trailing:
          selected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () => Navigator.of(context).pop(p.id),
    );
  }
}
