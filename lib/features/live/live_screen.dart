import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';

class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveAsync = ref.watch(liveMatchesProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        title: const Text('Live'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(liveMatchesProvider),
        child: liveAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          data: (matches) {
            if (matches.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sensors_off_outlined,
                        size: 48, color: AppColors.onSurfaceMuted),
                    SizedBox(height: 12),
                    Text(
                      'No live or upcoming matches today',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }

            final live = matches.where((m) => m.status == 'live').toList();
            final scheduled = matches
                .where((m) => m.status == 'scheduled')
                .toList();
            final recent = matches
                .where((m) =>
                    m.status == 'final' || m.status == 'finished')
                .toList();

            return CustomScrollView(
              slivers: [
                if (live.isNotEmpty) ..._section(context, 'Now Playing', live),
                if (scheduled.isNotEmpty)
                  ..._section(context, 'Today', scheduled),
                if (recent.isNotEmpty)
                  ..._section(context, 'Recent Results', recent),
                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _section(
      BuildContext context, String title, List<MatchModel> matches) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _LiveMatchTile(match: matches[i]),
          childCount: matches.length,
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------

class _LiveMatchTile extends StatelessWidget {
  const _LiveMatchTile({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final t1 = match.team1;
    final t2 = match.team2;
    final isLive = match.status == 'live';
    final isFinal = match.status == 'final' || match.status == 'finished';
    final kickoff = match.kickoffTime;
    final dateStr = kickoff != null
        ? DateFormat('HH:mm').format(kickoff.toLocal())
        : '—';

    return InkWell(
      onTap: () => context.push('/matches/${match.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Teams
            Expanded(
              child: Row(
                children: [
                  if (t1 != null) ...[TeamFlag(team: t1, size: 22), const SizedBox(width: 6)],
                  Text(
                    t1?.code ?? '?',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      isFinal || isLive
                          ? '${match.scoreFtTeam1 ?? 0} – ${match.scoreFtTeam2 ?? 0}'
                          : 'vs',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: isLive
                                  ? AppColors.live
                                  : AppColors.onSurface),
                    ),
                  ),
                  Text(
                    t2?.code ?? '?',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (t2 != null) ...[const SizedBox(width: 6), TeamFlag(team: t2, size: 22)],
                ],
              ),
            ),
            // Badge
            if (isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.live.withValues(alpha: 0.15),
                  borderRadius: AppRadii.pillRadius,
                ),
                child: Text('LIVE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.live,
                          fontWeight: FontWeight.w700,
                        )),
              )
            else if (!isLive && !isFinal)
              Text(
                dateStr,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
