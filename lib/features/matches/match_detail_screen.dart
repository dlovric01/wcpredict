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
// ---------------------------------------------------------------------------
// Overview Tab
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
    final isFinalOrLive =
        match.status == 'final' || match.status == 'live';

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(matchByIdProvider(matchId));
        ref.invalidate(matchEventsStreamProvider(matchId));
        ref.invalidate(myPredictionProvider(matchId));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: isFinalOrLive
            ? [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Match Events',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.onSurface,
                        ),
                  ),
                ),
                LiveEventsWidget(matchId: matchId),
              ]
            : [
                _MatchInfoCard(match: match),
                const SizedBox(height: 12),
                _PredictionSummaryCard(
                  match: match,
                  prediction: prediction,
                  onPredictTap: onPredictTap,
                ),
              ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MatchInfoCard
// ---------------------------------------------------------------------------

class _MatchInfoCard extends StatelessWidget {
  const _MatchInfoCard({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kickoff = match.kickoffTime;
    final dateStr = kickoff != null
        ? DateFormat('EEEE d MMMM yyyy · HH:mm').format(kickoff.toLocal())
        : null;

    final rows = <(IconData, String)>[
      if (match.round != null) (Symbols.emoji_events, match.round!),
      if (match.groupLetter != null)
        (Symbols.group, 'Group ${match.groupLetter}'),
      if (dateStr != null) (Symbols.schedule, dateStr),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.outline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Match Info',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: AppColors.onSurface)),
          const SizedBox(height: 10),
          for (final (icon, label) in rows) ...[
            Row(
              children: [
                Icon(icon, size: 15, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PredictionSummaryCard
// ---------------------------------------------------------------------------

class _PredictionSummaryCard extends StatelessWidget {
  const _PredictionSummaryCard({
    required this.match,
    required this.prediction,
    required this.onPredictTap,
  });
  final MatchModel match;
  final PredictionModel? prediction;
  final VoidCallback onPredictTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = match.isLocked;
    final pred = prediction;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.outline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Prediction',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: AppColors.onSurface)),
          const SizedBox(height: 10),
          if (pred != null) ...[
            Text(
              '${pred.predictedTeam1 ?? '?'} – ${pred.predictedTeam2 ?? '?'}',
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (pred.predictedScorerId != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Symbols.sports_soccer,
                      size: 13, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    'Goalscorer pick submitted',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            if (!locked) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onPredictTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Edit prediction →'),
              ),
            ],
          ] else if (!locked) ...[
            Text(
              "You haven't predicted yet.",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPredictTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.buttonRadius),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Predict this match',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Symbols.lock,
                    size: 15, color: AppColors.locked),
                const SizedBox(width: 6),
                Text(
                  'Predictions closed',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.locked),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Predict Tab
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
  late int _score1;
  late int _score2;
  int? _firstTeamId;
  int? _scorerId;
  bool _saving = false;
  String _playerSearch = '';

  bool get _isZeroZero => _score1 == 0 && _score2 == 0;
  bool get _locked => widget.match.isLocked;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _score1 = p?.predictedTeam1 ?? 0;
    _score2 = p?.predictedTeam2 ?? 0;
    _firstTeamId = p?.predictedFirstTeamId;
    _scorerId = p?.predictedScorerId;
  }

  @override
  void didUpdateWidget(_PredictTab old) {
    super.didUpdateWidget(old);
    if (old.existing == null && widget.existing != null) {
      final p = widget.existing!;
      setState(() {
        _score1 = p.predictedTeam1 ?? 0;
        _score2 = p.predictedTeam2 ?? 0;
        _firstTeamId = p.predictedFirstTeamId;
        _scorerId = p.predictedScorerId;
      });
    }
  }

  void _setScore1(int v) => setState(() {
        _score1 = v.clamp(0, 20);
        _clearConditionalsIfNeeded();
      });

  void _setScore2(int v) => setState(() {
        _score2 = v.clamp(0, 20);
        _clearConditionalsIfNeeded();
      });

  void _clearConditionalsIfNeeded() {
    if (_isZeroZero) {
      _firstTeamId = null;
      _scorerId = null;
    }
  }

  List<PlayerModel> get _allPlayers => [
        ...widget.match.team1?.players ?? [],
        ...widget.match.team2?.players ?? [],
      ];

  List<PlayerModel> get _filteredPlayers {
    if (_playerSearch.isEmpty) return _allPlayers;
    final q = _playerSearch.toLowerCase();
    return _allPlayers.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _save() async {
    if (_locked) return;
    setState(() => _saving = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      await supabase.from('predictions').upsert(
        {
          'user_id': user.id,
          'match_id': widget.match.id,
          'predicted_team1': _score1,
          'predicted_team2': _score2,
          'predicted_first_team_id': _isZeroZero ? null : (_firstTeamId ?? widget.match.team1?.id),
          'predicted_scorer_id': _isZeroZero ? null : _scorerId,
        },
        onConflict: 'user_id,match_id',
      );

      ref.invalidate(myPredictionProvider(widget.matchId));
      ref.invalidate(matchByIdProvider(widget.matchId));

      if (mounted) {
        HapticFeedback.mediumImpact();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t1 = widget.match.team1;
    final t2 = widget.match.team2;

    // ── Locked state ─────────────────────────────────────────────────────
    if (_locked) {
      final pred = widget.existing;
      final isFinal = widget.match.status == 'final';

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: AppRadii.buttonRadius,
                border: Border.all(color: AppColors.locked),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      color: AppColors.locked, size: 15),
                  const SizedBox(width: 8),
                  Text(
                    isFinal
                        ? 'Predictions closed · Full time'
                        : 'Predictions locked · Match has started',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.locked),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (pred == null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: AppColors.outline),
                ),
                child: Row(
                  children: [
                    const Icon(Symbols.lock,
                        size: 16, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'No prediction submitted',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFinal ? 'Your Result' : 'Your Prediction',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isFinal ? 'Actual' : 'Live',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.match.scoreFtTeam1 ?? 0}'
                                ' – '
                                '${widget.match.scoreFtTeam2 ?? 0}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                            width: 1, height: 40, color: AppColors.outline),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'You',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: AppColors.onSurfaceVariant),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${pred.predictedTeam1 ?? '?'}'
                                  ' – '
                                  '${pred.predictedTeam2 ?? '?'}',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: AppColors.onSurface,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isFinal && pred.pointsEarned != null) ...[
                      const SizedBox(height: 12),
                      VerdictPill(
                          points: pred.pointsEarned,
                          scorePoints: pred.pointsScore),
                    ] else if (!isFinal) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Points update at full time',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    // ── Unlocked form ─────────────────────────────────────────────────
    final t1Players = _filteredPlayers
        .where((p) => p.teamId == (t1?.id ?? -1))
        .toList();
    final t2Players = _filteredPlayers
        .where((p) => p.teamId == (t2?.id ?? -1))
        .toList();

    return Column(
      children: [
        // ── Fixed score pickers (never scroll) ─────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _ScorePicker(
                  value: _score1,
                  team: t1,
                  onChanged: _setScore1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '–',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: AppColors.onSurfaceMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: _ScorePicker(
                  value: _score2,
                  team: t2,
                  onChanged: _setScore2,
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ── Scrollable: first scorer + goalscorer ───────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              if (_isZeroZero)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: AppColors.onSurfaceMuted),
                      const SizedBox(width: 6),
                      Text(
                        'Set a score to unlock first scorer & goalscorer picks',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),

              if (!_isZeroZero) ...[
                Text(
                  'First Team to Score',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment<int>(
                      value: t1?.id ?? 0,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TeamFlag(team: t1, size: 16),
                          const SizedBox(width: 5),
                          Text(t1?.code ?? 'T1'),
                        ],
                      ),
                    ),
                    ButtonSegment<int>(
                      value: t2?.id ?? 0,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TeamFlag(team: t2, size: 16),
                          const SizedBox(width: 5),
                          Text(t2?.code ?? 'T2'),
                        ],
                      ),
                    ),
                  ],
                  selected: {_firstTeamId ?? (t1?.id ?? 0)},
                  onSelectionChanged: (s) =>
                      setState(() => _firstTeamId = s.first),
                ),

                const SizedBox(height: 20),
                Text(
                  'Goalscorer (optional)',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search players…',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _playerSearch = v),
                ),
                const SizedBox(height: 12),
                if (t1 != null && t1Players.isNotEmpty) ...[
                  Text(
                    t1.name,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.onSurfaceMuted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: t1Players
                        .map((p) => _PlayerChip(
                              player: p,
                              selected: p.id == _scorerId,
                              onTap: () => setState(() =>
                                  _scorerId =
                                      _scorerId == p.id ? null : p.id),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (t2 != null && t2Players.isNotEmpty) ...[
                  Text(
                    t2.name,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.onSurfaceMuted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: t2Players
                        .map((p) => _PlayerChip(
                              player: p,
                              selected: p.id == _scorerId,
                              onTap: () => setState(() =>
                                  _scorerId =
                                      _scorerId == p.id ? null : p.id),
                            ))
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),

        // ── Save button — pinned ───────────────────────────────────────────
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.buttonRadius),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(
                        widget.existing != null
                            ? 'Update Prediction'
                            : 'Save Prediction',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Teams Tab
// ---------------------------------------------------------------------------

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.match});
  final MatchModel match;

  bool get _hasLineups {
    final t1 = match.team1?.players;
    final t2 = match.team2?.players;
    return (t1 != null && t1.isNotEmpty) || (t2 != null && t2.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_hasLineups) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.group,
                size: 40, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 12),
            Text(
              'Lineups not yet announced',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.onSurfaceMuted),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (match.formationTeam1 != null || match.formationTeam2 != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (match.team1 != null)
                    Text(
                      '${match.team1!.code}  ${match.formationTeam1 ?? ''}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Spacer(),
                  if (match.team2 != null)
                    Text(
                      '${match.formationTeam2 ?? ''}  ${match.team2!.code}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          _FormationPitch(match: match),
          const SizedBox(height: 16),
          _SubstitutesList(match: match),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ScorePicker
// ---------------------------------------------------------------------------

class _ScorePicker extends StatelessWidget {
  const _ScorePicker({
    required this.value,
    required this.team,
    required this.onChanged,
  });

  final int value;
  final TeamModel? team;
  final ValueChanged<int> onChanged;

  void _inc() {
    if (value >= 20) return;
    HapticFeedback.selectionClick();
    onChanged(value + 1);
  }

  void _dec() {
    if (value <= 0) return;
    HapticFeedback.selectionClick();
    onChanged(value - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = value > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamFlag(team: team, tbd: team == null, size: 28),
        const SizedBox(height: 4),
        Text(
          team?.code ?? '—',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _inc,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 80,
            height: 64,
            decoration: BoxDecoration(
              color: highlight
                  ? AppColors.primaryContainer
                  : AppColors.surfaceHigh,
              borderRadius: AppRadii.buttonRadius,
              border: Border.all(
                color: highlight ? AppColors.primary : AppColors.outline,
                width: highlight ? 1.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: theme.textTheme.displaySmall?.copyWith(
                color: highlight
                    ? AppColors.onPrimaryContainer
                    : AppColors.onSurface,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepBtn(icon: Icons.remove, enabled: value > 0, onTap: _dec),
            const SizedBox(width: 14),
            _StepBtn(icon: Icons.add, enabled: value < 20, onTap: _inc),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _StepBtn
// ---------------------------------------------------------------------------

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? AppColors.outlineVariant : AppColors.outline,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.onSurface : AppColors.onSurfaceMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PlayerChip
// ---------------------------------------------------------------------------

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.player,
    required this.selected,
    required this.onTap,
  });

  final PlayerModel player;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.primaryContainer : AppColors.surfaceHigh,
          borderRadius: AppRadii.pillRadius,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PositionBadge(position: player.position),
            const SizedBox(width: 6),
            Text(
              player.name,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected
                    ? AppColors.onPrimaryContainer
                    : AppColors.onSurface,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (player.jerseyNumber != null) ...[
              const SizedBox(width: 4),
              Text(
                '#${player.jerseyNumber}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? AppColors.onPrimaryContainer
                          .withValues(alpha: 0.7)
                      : AppColors.onSurfaceMuted,
                ),
              ),
            ],
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
        final yFrac = 0.04 + (row - 1) / t1MaxRow * 0.40;
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
        final yFrac = 0.56 + (t2MaxRow - row) / t2MaxRow * 0.40;
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

// ---------------------------------------------------------------------------
// _PositionBadge — used by _PlayerRow (Teams tab) and _PlayerChip (Predict tab)
// ---------------------------------------------------------------------------

class _PositionBadge extends StatelessWidget {
  const _PositionBadge({required this.position});
  final String? position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = (position ?? '').toUpperCase();
    final pos = switch (raw) {
      final s when s.startsWith('GK') => 'GK',
      final s when s == 'DEF' ||
              s == 'DF' ||
              s == 'CB' ||
              s == 'LB' ||
              s == 'RB' ||
              s == 'LWB' ||
              s == 'RWB' =>
        'DEF',
      final s when s == 'MID' ||
              s == 'MF' ||
              s == 'CM' ||
              s == 'DM' ||
              s == 'AM' ||
              s == 'LM' ||
              s == 'RM' =>
        'MID',
      final s when s == 'FWD' ||
              s == 'FW' ||
              s == 'ST' ||
              s == 'LW' ||
              s == 'RW' ||
              s == 'CF' ||
              s == 'SS' =>
        'FWD',
      _ => raw.isEmpty ? '?' : raw,
    };

    final color = AppColors.forPosition(pos);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        pos,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}
