import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/player_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/features/matches/live_events_widget.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';
import 'package:wcpredict/shared/widgets/verdict_pill.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MatchDetailScreen extends ConsumerStatefulWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final int matchId;

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _initialTabSet = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Called once the first non-loading prediction value arrives.
  // Defaults to Predict tab (index 1) when match is unlocked and no prediction
  // exists yet; Overview (index 0) for all other cases.
  void _setInitialTab(MatchModel match, PredictionModel? prediction) {
    if (_initialTabSet) return;
    _initialTabSet = true;
    if (!match.isLocked && prediction == null) {
      _tabController.index = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchAsync = ref.watch(matchByIdProvider(widget.matchId));
    final predAsync = ref.watch(myPredictionProvider(widget.matchId));

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: Builder(builder: (context) {
          final m = matchAsync.valueOrNull;
          if (m?.team1?.code != null && m?.team2?.code != null) {
            return Text('${m!.team1!.code} vs ${m.team2!.code}');
          }
          return const Text('Match');
        }),
        backgroundColor: AppColors.surfaceBase,
        foregroundColor: AppColors.onSurface,
        surfaceTintColor: AppColors.surfaceBase,
        elevation: 0,
      ),
      body: matchAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.onSurfaceVariant)),
        ),
        data: (match) {
          // Set initial tab once prediction state resolves.
          if (!predAsync.isLoading) {
            _setInitialTab(match, predAsync.valueOrNull);
          }
          return Column(
            children: [
              // ── Hero card — always visible above tabs ──────────────────
              _HeroScoreCard(
                match: match,
                liveOverride: ref
                    .watch(matchLiveStateProvider(widget.matchId))
                    .valueOrNull,
              ),
              // ── Tab bar ────────────────────────────────────────────────
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'OVERVIEW'),
                  Tab(text: 'PREDICT'),
                  Tab(text: 'TEAMS'),
                ],
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.onSurfaceMuted,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
                dividerColor: AppColors.outline,
              ),
              // ── Tab content ────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _OverviewTab(
                      match: match,
                      matchId: widget.matchId,
                      prediction: predAsync.valueOrNull,
                      onPredictTap: () => _tabController.animateTo(1),
                    ),
                    _PredictTab(
                      match: match,
                      matchId: widget.matchId,
                      existing: predAsync.valueOrNull,
                      onSaved: () => _tabController.animateTo(0),
                    ),
                    _TeamsTab(match: match),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero Score Card — pinned above tabs, always visible
// ---------------------------------------------------------------------------

class _HeroScoreCard extends StatelessWidget {
  const _HeroScoreCard({required this.match, this.liveOverride});
  final MatchModel match;
  final Map<String, dynamic>? liveOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFinalOrLive =
        match.status == 'final' || match.status == 'live';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceHigh, AppColors.surfaceBase],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _TeamSide(team: match.team1, rightAlign: false)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFinalOrLive)
                        Text(
                          '${liveOverride?['score_ft_team1'] ?? match.scoreFtTeam1 ?? 0}'
                          '–'
                          '${liveOverride?['score_ft_team2'] ?? match.scoreFtTeam2 ?? 0}',
                          style: theme.textTheme.displayMedium?.copyWith(
                            color: AppColors.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        Text(
                          match.kickoffTime != null
                              ? DateFormat('d MMM\nHH:mm')
                                  .format(match.kickoffTime!.toLocal())
                              : 'TBC',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      if (isFinalOrLive &&
                          match.scoreHtTeam1 != null &&
                          match.scoreHtTeam2 != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'HT ${match.scoreHtTeam1}–${match.scoreHtTeam2}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                    child: _TeamSide(team: match.team2, rightAlign: true)),
              ],
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: _StatusChip(match: match),
          ),
        ],
      ),
    );
  }
}

class _TeamSide extends StatelessWidget {
  const _TeamSide({required this.team, required this.rightAlign});
  final TeamModel? team;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTbd = team == null;
    final align =
        rightAlign ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        hasTbd
            ? TeamFlag(tbd: true, size: 56)
            : TeamFlag(team: team!, size: 56),
        const SizedBox(height: 8),
        Text(
          hasTbd ? 'TBD' : team!.name,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
          ),
          textAlign: rightAlign ? TextAlign.right : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          hasTbd ? '---' : team!.code,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.onSurfaceVariant),
          textAlign: rightAlign ? TextAlign.right : TextAlign.left,
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
    final theme = Theme.of(context);

    return switch (match.status) {
      'live' => _LiveChip(),
      'final' => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighest,
            borderRadius: AppRadii.pillRadius,
            border: Border.all(color: AppColors.outline),
          ),
          child: Text(
            'FT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      _ => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighest,
            borderRadius: AppRadii.pillRadius,
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Text(
            match.kickoffTime != null
                ? 'KO ${DateFormat('HH:mm').format(match.kickoffTime!.toLocal())}'
                : 'Scheduled',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    };
  }
}

class _LiveChip extends StatefulWidget {
  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.2).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.18),
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: AppColors.live.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _opacity,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.live,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.live,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview Tab — placeholder (Task 2 fills this in)
// ---------------------------------------------------------------------------

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({
    required this.match,
    required this.matchId,
    required this.prediction,
    required this.onPredictTap,
  });
  final MatchModel match;
  final int matchId;
  final PredictionModel? prediction;
  final VoidCallback onPredictTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('Overview — coming soon'));
  }
}

// ---------------------------------------------------------------------------
// Predict Tab — placeholder (Task 3 fills this in)
// ---------------------------------------------------------------------------

class _PredictTab extends ConsumerStatefulWidget {
  const _PredictTab({
    required this.match,
    required this.matchId,
    required this.existing,
    required this.onSaved,
  });
  final MatchModel match;
  final int matchId;
  final PredictionModel? existing;
  final VoidCallback onSaved;

  @override
  ConsumerState<_PredictTab> createState() => _PredictTabState();
}

class _PredictTabState extends ConsumerState<_PredictTab> {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Predict — coming soon'));
  }
}

// ---------------------------------------------------------------------------
// Teams Tab — placeholder (Task 4 fills this in)
// ---------------------------------------------------------------------------

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Teams — coming soon'));
  }
}

class _LineupsSection extends StatelessWidget {
  const _LineupsSection({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelSmall = theme.textTheme.labelSmall
        ?.copyWith(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: AppColors.outline),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.cardRadius,
          border: Border.all(color: AppColors.outline),
        ),
        child: ExpansionTile(
          title: Row(
            children: [
              Text('Lineups', style: theme.textTheme.titleMedium),
              if (match.formationTeam1 != null) ...[
                const Spacer(),
                Text('${match.team1?.code}  ${match.formationTeam1}', style: labelSmall),
                const SizedBox(width: 8),
                Text('${match.formationTeam2}  ${match.team2?.code}', style: labelSmall),
              ],
            ],
          ),
          iconColor: AppColors.onSurfaceVariant,
          collapsedIconColor: AppColors.onSurfaceVariant,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _FormationPitch(match: match),
            const SizedBox(height: 12),
            _SubstitutesList(match: match),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formation Pitch
// ---------------------------------------------------------------------------

class _FormationPitch extends StatelessWidget {
  const _FormationPitch({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final t1Starters = (match.team1?.players ?? [])
        .where((p) => p.isStarter && p.grid != null)
        .toList();
    final t2Starters = (match.team2?.players ?? [])
        .where((p) => p.isStarter && p.grid != null)
        .toList();

    int maxRow(List<PlayerModel> players) {
      int m = 1;
      for (final p in players) {
        final r = int.tryParse(p.grid!.split(':')[0]) ?? 1;
        if (r > m) m = r;
      }
      return m;
    }

    final t1MaxRow = maxRow(t1Starters);
    final t2MaxRow = maxRow(t2Starters);

    // Build row→count maps for x spacing
    Map<int, int> rowCounts(List<PlayerModel> players) {
      final counts = <int, int>{};
      for (final p in players) {
        final r = int.tryParse(p.grid!.split(':')[0]) ?? 1;
        counts[r] = (counts[r] ?? 0) + 1;
      }
      return counts;
    }

    final t1RowCounts = rowCounts(t1Starters);
    final t2RowCounts = rowCounts(t2Starters);

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      const height = 340.0;

      List<Widget> dots = [];

      for (final p in t1Starters) {
        final parts = p.grid!.split(':');
        final row = int.tryParse(parts[0]) ?? 1;
        final col = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
        final countInRow = t1RowCounts[row] ?? 1;
        final xFrac = col / (countInRow + 1);
        final yFrac = 0.04 + (t1MaxRow - row) / t1MaxRow * 0.40;
        final x = (xFrac * width - 14).clamp(0.0, width - 28);
        final y = (yFrac * height - 14).clamp(0.0, height - 28);
        dots.add(Positioned(
          left: x,
          top: y,
          child: _PlayerDot(player: p),
        ));
      }

      for (final p in t2Starters) {
        final parts = p.grid!.split(':');
        final row = int.tryParse(parts[0]) ?? 1;
        final col = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
        final countInRow = t2RowCounts[row] ?? 1;
        final xFrac = col / (countInRow + 1);
        final yFrac = 0.56 + (row - 1) / t2MaxRow * 0.40;
        final x = (xFrac * width - 14).clamp(0.0, width - 28);
        final y = (yFrac * height - 14).clamp(0.0, height - 28);
        dots.add(Positioned(
          left: x,
          top: y,
          child: _PlayerDot(player: p),
        ));
      }

      return SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _PitchPainter()),
              ),
              // Team 1 formation label (top)
              if (match.formationTeam1 != null)
                Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Text(
                    '${match.team1?.code ?? ''}  ${match.formationTeam1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // Team 2 formation label (bottom)
              if (match.formationTeam2 != null)
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: Text(
                    '${match.formationTeam2}  ${match.team2?.code ?? ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ...dots,
            ],
          ),
        ),
      );
    });
  }
}

class _PlayerDot extends StatelessWidget {
  const _PlayerDot({required this.player});
  final PlayerModel player;

  @override
  Widget build(BuildContext context) {
    final pos = (player.position ?? '').toUpperCase();
    final color = AppColors.forPosition(pos);
    final name = _decodeHtml(player.name);
    final displayName = name.length > 8 ? name.substring(0, 8) : name;

    return SizedBox(
      width: 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              '${player.jerseyNumber ?? ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              shadows: [Shadow(color: Colors.black, blurRadius: 2)],
            ),
            overflow: TextOverflow.clip,
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF1A5C2A),
    );

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Outer border (inset 4px)
    canvas.drawRect(Rect.fromLTRB(4, 4, w - 4, h - 4), paint);

    // Halfway line
    canvas.drawLine(Offset(4, h / 2), Offset(w - 4, h / 2), paint);

    // Center circle (~12% of height radius)
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.12, paint);

    // Top penalty area: 20%→80% width, 0→18% height
    canvas.drawRect(
      Rect.fromLTRB(w * 0.20, 4, w * 0.80, h * 0.18),
      paint,
    );

    // Bottom penalty area: 20%→80% width, 82%→100% height
    canvas.drawRect(
      Rect.fromLTRB(w * 0.20, h * 0.82, w * 0.80, h - 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _SubstitutesList extends StatelessWidget {
  const _SubstitutesList({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t1Subs = (match.team1?.players ?? [])
        .where((p) => !p.isStarter)
        .toList();
    final t2Subs = (match.team2?.players ?? [])
        .where((p) => !p.isStarter)
        .toList();

    if (t1Subs.isEmpty && t2Subs.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (match.team1 != null)
                Text(
                  '${match.team1!.code} Subs',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 4),
              for (final p in t1Subs)
                _PlayerRow(player: p, rightAlign: false),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (match.team2 != null)
                Text(
                  '${match.team2!.code} Subs',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 4),
              for (final p in t2Subs)
                _PlayerRow(player: p, rightAlign: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// Minimal HTML entity decoder for player names stored with entities in the DB.
String _decodeHtml(String s) => s
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&nbsp;', ' ');

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.rightAlign});
  final PlayerModel player;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = _PositionBadge(position: player.position);
    final number = player.jerseyNumber;

    final displayName = _decodeHtml(
      number != null ? '$number. ${player.name}' : player.name,
    );

    final nameWidget = Expanded(
      child: Text(
        displayName,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurface),
        overflow: TextOverflow.ellipsis,
        textAlign: rightAlign ? TextAlign.right : TextAlign.left,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: rightAlign
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [nameWidget, const SizedBox(width: 6), badge],
            )
          : Row(
              children: [badge, const SizedBox(width: 6), nameWidget],
            ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  const _PositionBadge({required this.position});
  final String? position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pos = (position ?? '').toUpperCase();
    final color = AppColors.forPosition(pos);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        pos.isEmpty ? '?' : pos,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}
