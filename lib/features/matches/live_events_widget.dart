import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';

class LiveEventsWidget extends ConsumerWidget {
  const LiveEventsWidget({super.key, required this.matchId});

  final int matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(matchEventsProvider(matchId));

    return eventsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error loading events: $e',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      data: (events) {
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No events yet',
                  style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: events.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final event = events[index];
            return _EventTile(event: event)
                .animate()
                .fadeIn(duration: 300.ms)
                .slideY(begin: 0.2, end: 0, duration: 300.ms);
          },
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final MatchEventModel event;

  @override
  Widget build(BuildContext context) {
    final isGoal = event.type == 'goal';
    final icon = _iconForType(event.type, event.detail);

    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 36,
        child: Text(
          "${event.minute}'",
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          textAlign: TextAlign.right,
        ),
      ),
      title: Text(
        event.playerName ?? '—',
        style: TextStyle(
          fontWeight: isGoal ? FontWeight.bold : FontWeight.normal,
          fontSize: isGoal ? 15 : 14,
        ),
      ),
      subtitle: event.detail != null
          ? Text(event.detail!, style: const TextStyle(fontSize: 12))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          if (event.teamId != null)
            Text(
              '#${event.teamId}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
        ],
      ),
    );
  }

  String _iconForType(String? type, String? detail) {
    switch (type) {
      case 'goal':
        return '⚽';
      case 'card':
        return (detail == 'red') ? '🟥' : '🟨';
      case 'subst':
        return '↔️';
      case 'shootout_kick':
        return '🥅';
      default:
        return '•';
    }
  }
}
