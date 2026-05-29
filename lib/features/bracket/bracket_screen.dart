import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/supabase_client.dart';

// ---------------------------------------------------------------------------
// Provider — knockout matches
// ---------------------------------------------------------------------------
const _knockoutRounds = ['R32', 'R16', 'QF', 'SF', 'Final'];

final _knockoutMatchesProvider =
    FutureProvider<List<MatchModel>>((ref) async {
  final data = await supabase
      .from('matches')
      .select(
          '*, team1:teams!team1_id(id,name,code,flag_url), team2:teams!team2_id(id,name,code,flag_url)')
      .inFilter('round', _knockoutRounds)
      .order('kickoff_time');
  return (data as List)
      .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class BracketScreen extends ConsumerWidget {
  const BracketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(_knockoutMatchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bracket')),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (matches) => _BracketBody(matches: matches),
      ),
    );
  }
}

class _BracketBody extends StatelessWidget {
  const _BracketBody({required this.matches});

  final List<MatchModel> matches;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Bracket available June 27',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ),
      );
    }

    // Check if all R32 matches are still scheduled — bracket not started yet
    final r32 = matches.where((m) => m.round == 'R32').toList();
    if (r32.isNotEmpty && r32.every((m) => m.status == 'scheduled')) {
      // Further check: if the first R32 kickoff is in the future
      final firstKickoff = r32
          .where((m) => m.kickoffTime != null)
          .map((m) => m.kickoffTime!)
          .fold<DateTime?>(null, (earliest, k) {
        return earliest == null || k.isBefore(earliest) ? k : earliest;
      });
      if (firstKickoff != null && firstKickoff.isAfter(DateTime.now())) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sports_soccer,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Bracket available June 27',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  'Round of 32 begins ${_formatDate(firstKickoff)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: () async {}, // parent provider handles refresh via ref
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          for (final round in _knockoutRounds) ...[
            _RoundSection(
              round: round,
              matches:
                  matches.where((m) => m.round == round).toList(),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';
}

// ---------------------------------------------------------------------------
// Round section
// ---------------------------------------------------------------------------
class _RoundSection extends StatelessWidget {
  const _RoundSection({required this.round, required this.matches});

  final String round;
  final List<MatchModel> matches;

  String get _roundLabel => switch (round) {
        'R32' => 'Round of 32',
        'R16' => 'Round of 16',
        'QF' => 'Quarter-finals',
        'SF' => 'Semi-finals',
        'Final' => 'Final',
        _ => round,
      };

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _roundLabel,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                _MatchCard(match: matches[i]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Match card
// ---------------------------------------------------------------------------
class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});

  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final t1Name = match.team1?.name ?? 'TBD';
    final t2Name = match.team2?.name ?? 'TBD';
    final isScheduled = match.status == 'scheduled';
    final isFinal = match.status == 'final';

    return GestureDetector(
      onTap: () => context.push('/matches/${match.id}'),
      child: Card(
        elevation: 2,
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TeamRow(name: t1Name, score: isFinal ? match.scoreFtTeam1 : null),
              const Divider(height: 16),
              _TeamRow(name: t2Name, score: isFinal ? match.scoreFtTeam2 : null),
              const Spacer(),
              Row(
                children: [
                  if (match.status == 'live')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('LIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    )
                  else if (isScheduled)
                    const Icon(Icons.schedule, size: 12, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.name, this.score});

  final String name;
  final int? score;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (score != null)
          Text(
            '$score',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }
}
