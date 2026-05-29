import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/widgets/match_card.dart';

/// Filter options for the fixtures screen.
enum _Filter { all, groupStage, knockout }

class FixturesScreen extends ConsumerStatefulWidget {
  const FixturesScreen({super.key});

  @override
  ConsumerState<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends ConsumerState<FixturesScreen> {
  _Filter _filter = _Filter.all;

  bool _matchesFilter(MatchModel m) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.groupStage:
        return m.round == 'Group Stage';
      case _Filter.knockout:
        return m.round != 'Group Stage';
    }
  }

  /// Group matches by round label, preserving order from the sorted list.
  Map<String, List<MatchModel>> _groupByRound(List<MatchModel> matches) {
    final map = <String, List<MatchModel>>{};
    for (final m in matches) {
      final round = m.round ?? 'Unknown';
      map.putIfAbsent(round, () => []).add(m);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final matchesAsync = ref.watch(allMatchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixtures'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
            tooltip: 'Filter',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _chip('All', _Filter.all),
                const SizedBox(width: 8),
                _chip('Group Stage', _Filter.groupStage),
                const SizedBox(width: 8),
                _chip('Knockout', _Filter.knockout),
              ],
            ),
          ),
          // Match list
          Expanded(
            child: matchesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: Colors.red)),
              ),
              data: (matches) {
                final filtered =
                    matches.where(_matchesFilter).toList();
                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('No matches found.'));
                }
                final grouped = _groupByRound(filtered);
                final rounds = grouped.keys.toList();

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(allMatchesProvider),
                  child: ListView.builder(
                    itemCount: rounds.fold<int>(
                        0,
                        (sum, r) =>
                            sum + 1 + (grouped[r]?.length ?? 0)),
                    itemBuilder: (context, i) {
                      // Flatten rounds + headers into a single list.
                      int cursor = 0;
                      for (final round in rounds) {
                        final items = grouped[round]!;
                        if (i == cursor) {
                          return _RoundHeader(round: round);
                        }
                        cursor++;
                        if (i < cursor + items.length) {
                          final match = items[i - cursor];
                          return GestureDetector(
                            onTap: () =>
                                context.push('/matches/${match.id}'),
                            child: MatchCard(match: match),
                          );
                        }
                        cursor += items.length;
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, _Filter value) {
    return FilterChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.round});
  final String round;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        round,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
