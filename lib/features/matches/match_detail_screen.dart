import 'dart:ui' as ui;

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
import 'package:wcpredict/features/matches/predict_logic.dart';
import 'package:wcpredict/features/rules/rules_screen.dart';
import 'package:wcpredict/features/matches/first_team_picker.dart';
import 'package:wcpredict/features/matches/live_events_widget.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/utils/live_minute.dart';
import 'package:wcpredict/shared/utils/score_format.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';
import 'package:wcpredict/shared/widgets/verdict_pill.dart';
import 'package:wcpredict/shared/providers/boosters_provider.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';
import 'package:wcpredict/shared/widgets/app_feedback.dart';

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
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How scoring works',
            onPressed: () {
              final m = matchAsync.valueOrNull;
              final anchor = (m != null && (m.isBoosterRound || m.autoMultiplier > 1))
                  ? RuleSection.multipliers
                  : RuleSection.matchScoring;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RulesScreen(anchor: anchor),
                ),
              );
            },
          ),
        ],
      ),
      body: matchAsync.when(
        // matchByIdProvider re-fetches whenever the matches table changes
        // (status / score updates). Keep the existing screen visible
        // during the reload instead of flashing a spinner.
        skipLoadingOnReload: true,
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
              // The hero is its own ConsumerWidget; only the score region
              // (and the live-minute pill inside it) rebuilds on score /
              // status / minute ticks. Team sides + the surrounding
              // Scaffold stay static.
              _HeroScoreCard(match: match, matchId: widget.matchId),
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
  const _HeroScoreCard({required this.match, required this.matchId});

  /// Baseline match (cached + teams joined). Status / scores are
  /// served fresh per-frame by [_LiveCenterColumn] reading the live
  /// overlay; the team sides we pass to [_TeamSide] never change once
  /// the cache loads, so those siblings stay out of the rebuild scope.
  final MatchModel match;
  final int matchId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceHigh, AppColors.surfaceBase],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _TeamSide(team: match.team1, rightAlign: false)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _LiveCenterColumn(match: match, matchId: matchId),
            ),
            Expanded(child: _TeamSide(team: match.team2, rightAlign: true)),
          ],
        ),
      ),
    );
  }
}

/// Centre column of the hero card — status chip, live score, sub-labels.
///
/// Watches [liveMatchProvider] so a Realtime score / status update only
/// rebuilds this subtree. The pulsing LIVE dot and the live minute pill
/// are isolated further inside `_LiveChip` so their animation and 10-s
/// ticker don't drag the score Text along with them.
class _LiveCenterColumn extends ConsumerWidget {
  const _LiveCenterColumn({required this.match, required this.matchId});
  final MatchModel match;
  final int matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final overlay = ref.watch(liveMatchProvider(matchId));
    final m = mergeWithLive(match, overlay);

    final status = m.status;
    final isLive = status == 'live';
    final isFinal = status == 'final';
    final hasHt = m.scoreHtTeam1 != null && m.scoreHtTeam2 != null;
    final hasEt = m.scoreEtTeam1 != null && m.scoreEtTeam2 != null;
    final hasPen = m.scorePenTeam1 != null && m.scorePenTeam2 != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLive || isFinal) ...[
          _StatusChip(match: m),
          const SizedBox(height: 8),
        ],
        if (isFinal)
          Text(
            formatScore(m.scoreFtTeam1, m.scoreFtTeam2),
            style: theme.textTheme.displayMedium?.copyWith(
              color: AppColors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          )
        else if (isLive)
          // During play we show the running score. The minute pill is
          // rendered inside the LIVE chip above; the HT score is folded
          // into a sub-row once both halves are populated.
          Text(
            formatScore(m.scoreFtTeam1, m.scoreFtTeam2),
            style: theme.textTheme.displayMedium?.copyWith(
              color: AppColors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          )
        else
          Text(
            m.kickoffTime != null
                ? DateFormat('d MMM\nHH:mm').format(m.kickoffTime!.toLocal())
                : 'TBC',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        // Sub-labels — half-time once available, then ET / PEN after FT.
        if (isLive && hasHt) ...[
          const SizedBox(height: 2),
          Text(
            formatLabeledScore('HT', m.scoreHtTeam1, m.scoreHtTeam2),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
        if (isFinal && hasHt) ...[
          const SizedBox(height: 2),
          Text(
            formatLabeledScore('HT', m.scoreHtTeam1, m.scoreHtTeam2),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
        if (isFinal && hasEt) ...[
          const SizedBox(height: 2),
          Text(
            formatLabeledScore('ET', m.scoreEtTeam1, m.scoreEtTeam2),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (isFinal && hasPen) ...[
          const SizedBox(height: 2),
          Text(
            formatLabeledScore('PEN', m.scorePenTeam1, m.scorePenTeam2),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
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
          maxLines: 1,
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
      'live' => _LiveChip(match: match),
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
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      // Scheduled / unknown: header already shows the date + time, no chip.
      _ => const SizedBox.shrink(),
    };
  }
}

/// LIVE pill — pulsing dot + label + live minute pill.
///
/// The pulse [AnimationController] only repaints the FadeTransition
/// subtree; the minute pill is an isolated [_LiveMinutePill] that
/// watches the global clock ticker so the surrounding chip's layout
/// never rebuilds on its account.
class _LiveChip extends StatefulWidget {
  const _LiveChip({required this.match});
  final MatchModel match;

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
          // Live-minute pill, separated by a dot. Subscribes to its
          // own clock ticker so the chip surrounding it is never
          // included in the 10-second rebuild scope.
          _LiveMinutePill(match: widget.match),
        ],
      ),
    );
  }
}

/// Live minute label ("4'", "HT", "90+2'", …). Watches the global
/// 10-second clock ticker so updates rebuild only this Text and
/// nothing above it. Returns an empty SizedBox when the match isn't
/// live or kickoff hasn't been reached.
class _LiveMinutePill extends ConsumerWidget {
  const _LiveMinutePill({required this.match});
  final MatchModel match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the ticker without `.select` is fine: the value (DateTime)
    // changes on every tick, which is the whole point — we want a
    // rebuild every 10 s. Riverpod still confines the rebuild to this
    // ConsumerWidget's subtree.
    final now = ref.watch(clockTickerProvider).valueOrNull ?? DateTime.now();
    final label = formatLiveMinute(match, now);
    if (label == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.live,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
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
    // Subscribe only to the overlay's status so a score update during
    // play doesn't rebuild the tab. The hero card carries the live
    // score; here we only care which sections are visible.
    final overlayStatus = ref.watch(
      liveMatchProvider(matchId).select((m) => m?.status),
    );
    final status = overlayStatus ?? match.status;
    final isFinal = status == 'final';
    final isLive = status == 'live';
    final showEvents = isLive || isFinal;

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
        children: [
          if (!showEvents) ...[
            _MatchInfoCard(match: match),
            const SizedBox(height: 12),
            _PredictionSummaryCard(
              match: match,
              prediction: prediction,
              onPredictTap: onPredictTap,
            ),
          ] else ...[
            // Prediction summary stays pinned above the timeline so the
            // user can keep eyeing their own picks while goals roll in.
            // Once the match is final the card shows the earned points;
            // during play it's the read-only picks view.
            _PredictionSummaryCard(
              match: match,
              prediction: prediction,
              onPredictTap: onPredictTap,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isFinal ? 'Match Events' : 'Live Events',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.onSurface,
                    ),
              ),
            ),
            LiveEventsWidget(matchId: matchId),
          ],
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
            if (pred.predictedFirstTeamId != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Symbols.flag,
                      size: 13, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    'First to score: ${_resolveTeamName(match, pred.predictedFirstTeamId!)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
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
                const Icon(Symbols.lock, size: 15, color: AppColors.locked),
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

  bool get _isZeroZero => _score1 == 0 && _score2 == 0;

  /// True when predictions must be locked. Delegated to the pure helper
  /// so it's unit-testable independently of the widget tree. The live
  /// overlay is read off the provider so a Realtime `status='live'`
  /// flip locks the form immediately, without waiting for the next
  /// match-by-id re-fetch.
  bool get _locked => predictTabLocked(
        widget.match,
        ref.read(liveMatchProvider(widget.matchId)),
      );

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _score1 = p?.predictedTeam1 ?? 0;
    _score2 = p?.predictedTeam2 ?? 0;
    _firstTeamId = p?.predictedFirstTeamId;
    _scorerId = p?.predictedScorerId;
    // Apply constraints so a previously-saved prediction that violates the
    // current rules (e.g. first-team from a 0-scoring side) is corrected.
    _enforceConstraints();
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
        _enforceConstraints();
      });
    }
  }

  void _setScore1(int v) => setState(() {
        _score1 = v.clamp(0, 20);
        _enforceConstraints();
      });

  void _setScore2(int v) => setState(() {
        _score2 = v.clamp(0, 20);
        _enforceConstraints();
      });

  /// Drop picks that violate the current score, via the pure helper in
  /// `predict_logic.dart` (which is unit-tested separately).
  void _enforceConstraints() {
    final result = sanitisePredictionPicks(
      score1: _score1,
      score2: _score2,
      firstTeamId: _firstTeamId,
      scorerId: _scorerId,
      team1Id: widget.match.team1?.id,
      team2Id: widget.match.team2?.id,
    );
    _firstTeamId = result.firstTeamId;
    _scorerId = result.scorerId;
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
          'predicted_first_team_id': _isZeroZero ? null : _firstTeamId,
          'predicted_scorer_id': _isZeroZero ? null : _scorerId,
        },
        onConflict: 'user_id,match_id',
      );

      ref.invalidate(myPredictionProvider(widget.matchId));
      ref.invalidate(matchByIdProvider(widget.matchId));
      ref.invalidate(myAllPredictionsProvider);

      if (mounted) {
        HapticFeedback.mediumImpact();
        widget.onSaved();
      }
      AppFeedback.success('Prediction saved');
    } catch (e) {
      AppFeedback.error('Could not save prediction: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t1 = widget.match.team1;
    final t2 = widget.match.team2;
    // Subscribe to the overlay's status so a kickoff during this build
    // session re-evaluates `_locked` and the predict UI flips to the
    // closed state without the user navigating away.
    final overlayStatus = ref.watch(
      liveMatchProvider(widget.matchId).select((m) => m?.status),
    );
    final locked = widget.match.isLocked ||
        overlayStatus == 'live' ||
        overlayStatus == 'final' ||
        overlayStatus == 'cancelled';

    // ── Locked state ─────────────────────────────────────────────────────
    if (locked) {
      final pred = widget.existing;
      final isFinal = widget.match.status == 'final';

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                formatScore(
                                  widget.match.scoreFtTeam1,
                                  widget.match.scoreFtTeam2,
                                ),
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
                          pointsMatch: pred.pointsMatch,
                          pointsFirstTeam: pred.pointsFirstTeam,
                          pointsGoalscorer: pred.pointsGoalscorer,
                          multiplier: pred.multiplier),
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
              // Auto-multiplier badge (3rd place / Final)
              if (widget.match.autoMultiplier > 1) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: AppRadii.cardRadius,
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.match.round} · auto ×${widget.match.autoMultiplier} multiplier',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // User booster toggle (R32/R16/QF/SF)
              if (widget.match.isBoosterRound) ...[
                _BoosterToggle(
                  match: widget.match,
                  matchId: widget.matchId,
                ),
                const SizedBox(height: 16),
              ],

              if (_isZeroZero)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: AppColors.onSurfaceMuted),
                      const SizedBox(width: 6),
                      Text(
                        'Set a score to unlock first-team & goalscorer picks',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),

              if (!_isZeroZero) ...[
                Text(
                  'First team to score (optional · +2 pts)',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                FirstTeamPicker(
                  match: widget.match,
                  selectedTeamId: _firstTeamId,
                  score1: _score1,
                  score2: _score2,
                  onPick: (id) => setState(() => _firstTeamId = id),
                ),
                const SizedBox(height: 20),
                Text(
                  'Goalscorer (optional · +8 pts)',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                _ScorerPickerButton(
                  scorerId: _scorerId,
                  match: widget.match,
                  onPick: (id) => setState(() => _scorerId = id),
                ),
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
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  bool get _hasPlayers {
    final t1 = match.team1?.players;
    final t2 = match.team2?.players;
    return (t1 != null && t1.isNotEmpty) || (t2 != null && t2.isNotEmpty);
  }

  /// Sort order: GK → DEF → MID → FWD → unknown; starters before subs.
  static int _playerSort(PlayerModel a, PlayerModel b) {
    int posRank(PlayerModel p) {
      final pos = (p.position ?? '').toUpperCase();
      if (pos.startsWith('GK')) {
        return 0;
      }
      if (pos == 'DEF' ||
          pos == 'DF' ||
          pos == 'CB' ||
          pos == 'LB' ||
          pos == 'RB' ||
          pos == 'LWB' ||
          pos == 'RWB') {
        return 1;
      }
      if (pos == 'MID' ||
          pos == 'MF' ||
          pos == 'CM' ||
          pos == 'DM' ||
          pos == 'AM' ||
          pos == 'LM' ||
          pos == 'RM') {
        return 2;
      }
      if (pos == 'FWD' ||
          pos == 'FW' ||
          pos == 'ST' ||
          pos == 'LW' ||
          pos == 'RW' ||
          pos == 'CF' ||
          pos == 'SS') {
        return 3;
      }
      return 4;
    }

    // Starters first
    if (a.isStarter != b.isStarter) return a.isStarter ? -1 : 1;
    // Then by position group
    final cmp = posRank(a).compareTo(posRank(b));
    if (cmp != 0) return cmp;
    // Then by jersey number
    final na = a.jerseyNumber ?? 999;
    final nb = b.jerseyNumber ?? 999;
    return na.compareTo(nb);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_hasPlayers) {
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

    final t1Players = [...(match.team1?.players ?? <PlayerModel>[])]
      ..sort(_playerSort);
    final t2Players = [...(match.team2?.players ?? <PlayerModel>[])]
      ..sort(_playerSort);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Team 1 ──────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (match.team1 != null) _TeamHeader(team: match.team1!),
                  const SizedBox(height: 4),
                  for (final p in t1Players)
                    _PlayerRow(player: p, rightAlign: false),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Team 2 ──────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (match.team2 != null)
                    _TeamHeader(team: match.team2!, rightAlign: true),
                  const SizedBox(height: 4),
                  for (final p in t2Players)
                    _PlayerRow(player: p, rightAlign: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.team, this.rightAlign = false});
  final TeamModel team;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flag = TeamFlag(team: team, size: 20);
    final name = Text(
      team.name,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: rightAlign
            ? [name, const SizedBox(width: 8), flag]
            : [flag, const SizedBox(width: 8), name],
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
    this.rightAlign = false,
  });

  final PlayerModel player;
  final bool selected;
  final VoidCallback onTap;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.labelMedium?.copyWith(
      color: selected ? AppColors.onPrimaryContainer : AppColors.onSurface,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
    final numberStyle = theme.textTheme.labelSmall?.copyWith(
      color: selected
          ? AppColors.onPrimaryContainer.withValues(alpha: 0.7)
          : AppColors.onSurfaceMuted,
    );
    final numberStr =
        player.jerseyNumber != null ? '#${player.jerseyNumber}' : null;

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (ctx, c) {
          // Available width for the name = chip max width minus everything else.
          // Chip horizontal padding (10+10), badge upper bound (~36), gap to name (6),
          // optional gap-to-number (4) + measured number text width.
          const chipHPad = 20.0;
          const badgeMaxWidth = 36.0;
          const gapBadgeName = 6.0;
          const gapNameNumber = 4.0;
          final numberWidth = numberStr == null
              ? 0.0
              : _measureTextWidth(numberStr, numberStyle);
          final reserved = chipHPad +
              badgeMaxWidth +
              gapBadgeName +
              (numberStr == null ? 0 : gapNameNumber + numberWidth);
          final availableForName = c.maxWidth - reserved;

          // If the full name doesn't fit, drop the first name to an initial.
          // Falls back to a plain ellipsis when even the abbreviation overflows.
          final fullName = player.name;
          final fullWidth = _measureTextWidth(fullName, nameStyle);
          String displayName = fullName;
          if (fullWidth > availableForName) {
            final tokens = fullName.split(RegExp(r'\s+'));
            if (tokens.length >= 2 &&
                tokens.first.length > 1 &&
                !tokens.first.endsWith('.')) {
              displayName = '${tokens.first[0]}. ${tokens.skip(1).join(' ')}';
            }
          }

          final badge = _PositionBadge(position: player.position);
          final nameWidget = Flexible(
            child: Text(
              displayName,
              style: nameStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          );
          final number =
              numberStr == null ? null : Text(numberStr, style: numberStyle);

          final children = <Widget>[
            badge,
            const SizedBox(width: gapBadgeName),
            nameWidget,
            if (number != null) ...[
              const SizedBox(width: gapNameNumber),
              number,
            ],
          ];

          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryContainer
                    : AppColors.surfaceHigh,
                borderRadius: AppRadii.pillRadius,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.outline,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: rightAlign ? children.reversed.toList() : children,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ScorerPickerButton — tappable row showing the currently selected scorer
// ---------------------------------------------------------------------------

class _ScorerPickerButton extends StatelessWidget {
  const _ScorerPickerButton({
    required this.scorerId,
    required this.match,
    required this.onPick,
  });

  final int? scorerId;
  final MatchModel match;
  final ValueChanged<int?> onPick;

  PlayerModel? get _selectedPlayer {
    if (scorerId == null) return null;
    final all = [
      ...match.team1?.players ?? [],
      ...match.team2?.players ?? [],
    ];
    try {
      return all.firstWhere((p) => p.id == scorerId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = _selectedPlayer;

    return InkWell(
      onTap: () async {
        final picked = await showAppSheet<int?>(
          context: context,
          builder: (_) => _ScorerPickerSheet(
            match: match,
            currentScorerId: scorerId,
          ),
        );
        // picked == null means the sheet was dismissed without a choice;
        // picked == -1 is the sentinel for "clear selection".
        if (picked == -1) {
          onPick(null);
        } else if (picked != null) {
          onPick(picked);
        }
      },
      borderRadius: AppRadii.buttonRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadii.buttonRadius,
          border: Border.all(
            color: player != null ? AppColors.primary : AppColors.outline,
            width: player != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (player != null) ...[
              _PositionBadge(position: player.position),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  player.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => onPick(null),
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.onSurfaceMuted),
              ),
            ] else ...[
              const Icon(Icons.search,
                  size: 16, color: AppColors.onSurfaceMuted),
              const SizedBox(width: 8),
              Text(
                'Pick a goalscorer…',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.onSurfaceMuted),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.onSurfaceMuted),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ScorerPickerSheet — full-height bottom sheet with search + team groups
// ---------------------------------------------------------------------------

class _ScorerPickerSheet extends StatefulWidget {
  const _ScorerPickerSheet(
      {required this.match, required this.currentScorerId});
  final MatchModel match;
  final int? currentScorerId;

  @override
  State<_ScorerPickerSheet> createState() => _ScorerPickerSheetState();
}

class _ScorerPickerSheetState extends State<_ScorerPickerSheet> {
  late final TextEditingController _searchCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PlayerModel> _filtered(List<PlayerModel>? players) {
    if (players == null) return [];
    if (_query.isEmpty) return players;
    final q = _query.toLowerCase();
    return players.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t1 = widget.match.team1;
    final t2 = widget.match.team2;
    final t1Players = _filtered(t1?.players);
    final t2Players = _filtered(t2?.players);
    final hasAny = t1Players.isNotEmpty || t2Players.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Pick Goalscorer',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: AppColors.onSurface)),
                ),
                if (widget.currentScorerId != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(-1),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search players…',
                isDense: true,
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // Player list — two columns: home left, away right (mirrored).
          Expanded(
            child: hasAny
                ? SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _PlayerColumn(
                            team: t1,
                            players: t1Players,
                            rightAlign: false,
                            currentScorerId: widget.currentScorerId,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PlayerColumn(
                            team: t2,
                            players: t2Players,
                            rightAlign: true,
                            currentScorerId: widget.currentScorerId,
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Text(
                      _query.isNotEmpty
                          ? 'No players match "$_query"'
                          : 'No player data available',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.onSurfaceMuted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({
    required this.team,
    required this.players,
    required this.rightAlign,
    required this.currentScorerId,
  });

  final TeamModel? team;
  final List<PlayerModel> players;
  final bool rightAlign;
  final int? currentScorerId;

  @override
  Widget build(BuildContext context) {
    if (team == null || players.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment:
          rightAlign ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _TeamGroupHeader(team: team!, rightAlign: rightAlign),
        for (final p in players) ...[
          _PlayerChip(
            player: p,
            selected: p.id == currentScorerId,
            rightAlign: rightAlign,
            onTap: () => Navigator.of(context).pop(p.id),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TeamGroupHeader extends StatelessWidget {
  const _TeamGroupHeader({required this.team, this.rightAlign = false});
  final TeamModel team;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    final flag = TeamFlag(team: team, size: 16);
    final name = Text(
      team.name,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: rightAlign
            ? [name, const SizedBox(width: 8), flag]
            : [flag, const SizedBox(width: 8), name],
      ),
    );
  }
}

/// Resolves a team_id to a display name by matching against the match's
/// two teams. Falls back to the id when the team is not on this match
/// (should not happen — the validation trigger rejects such writes).
String _resolveTeamName(MatchModel match, int teamId) {
  if (match.team1?.id == teamId) return match.team1!.name;
  if (match.team2?.id == teamId) return match.team2!.name;
  return '#$teamId';
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

/// Layout-time width measurement for a single-line text run.
double _measureTextWidth(String text, TextStyle? style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: ui.TextDirection.ltr,
  )..layout();
  return tp.size.width;
}

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
      final s
          when s == 'DEF' ||
              s == 'DF' ||
              s == 'CB' ||
              s == 'LB' ||
              s == 'RB' ||
              s == 'LWB' ||
              s == 'RWB' =>
        'DEF',
      final s
          when s == 'MID' ||
              s == 'MF' ||
              s == 'CM' ||
              s == 'DM' ||
              s == 'AM' ||
              s == 'LM' ||
              s == 'RM' =>
        'MID',
      final s
          when s == 'FWD' ||
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
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        pos,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BoosterToggle — apply/remove the round booster for a knockout match
// ---------------------------------------------------------------------------

class _BoosterToggle extends ConsumerStatefulWidget {
  const _BoosterToggle({required this.match, required this.matchId});
  final MatchModel match;
  final int matchId;

  @override
  ConsumerState<_BoosterToggle> createState() => _BoosterToggleState();
}

class _BoosterToggleState extends ConsumerState<_BoosterToggle> {
  bool _saving = false;

  Future<void> _toggle(bool active) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      if (active) {
        await supabase.from('round_boosters').upsert({
          'user_id': user.id,
          'round': widget.match.round,
          'match_id': widget.matchId,
          'multiplier': widget.match.boosterMultiplier,
        }, onConflict: 'user_id,round');
      } else {
        await supabase
            .from('round_boosters')
            .delete()
            .eq('user_id', user.id)
            .eq('round', widget.match.round ?? '');
      }
      ref.invalidate(boosterForMatchProvider(widget.matchId));
      ref.invalidate(myBoostersProvider);
      AppFeedback.success(active
          ? 'Booster applied to this match'
          : 'Booster removed');
    } catch (e) {
      AppFeedback.error('Booster update failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boosterAsync = ref.watch(boosterForMatchProvider(widget.matchId));
    final hasBooster = boosterAsync.valueOrNull != null;
    final multiplier = widget.match.boosterMultiplier;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasBooster
            ? AppColors.primaryContainer.withValues(alpha: 0.35)
            : AppColors.surfaceHigh,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(
          color: hasBooster
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasBooster ? Icons.bolt : Icons.bolt_outlined,
            size: 18,
            color: hasBooster ? AppColors.primary : AppColors.onSurfaceMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.match.round} Booster ×$multiplier',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: hasBooster ? AppColors.primary : AppColors.onSurface,
                  ),
                ),
                Text(
                  hasBooster
                      ? 'Applied — your score is multiplied by $multiplier'
                      : 'Use your ${widget.match.round} booster on this match',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_saving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: hasBooster,
              onChanged: _toggle,
              activeTrackColor: AppColors.primary,
            ),
        ],
      ),
    );
  }
}
