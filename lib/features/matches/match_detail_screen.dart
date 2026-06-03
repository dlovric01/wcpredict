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
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/features/matches/predict_logic.dart';
import 'package:wcpredict/features/rules/rules_screen.dart';
import 'package:wcpredict/features/matches/first_team_picker.dart';
import 'package:wcpredict/features/matches/live_events_widget.dart';
import 'package:wcpredict/features/matches/live_scoring.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/providers/match_predictions_provider.dart';
import 'package:wcpredict/shared/utils/live_minute.dart';
import 'package:wcpredict/shared/utils/score_format.dart';
import 'package:wcpredict/shared/utils/player_name_format.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';
import 'package:wcpredict/shared/widgets/countdown_pill.dart';
import 'package:wcpredict/shared/providers/boosters_provider.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';
import 'package:wcpredict/shared/widgets/app_feedback.dart';
import 'package:wcpredict/shared/utils/date_format.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MatchDetailScreen extends ConsumerStatefulWidget {
  const MatchDetailScreen({super.key, required this.matchId, this.initialTab});
  final int matchId;
  /// Optional dev/test override: one of `overview` / `predict` / `teams` /
  /// `others`. When non-null, takes precedence over the auto-pick logic
  /// in [_setInitialTab]. Wired through the `/matches/:id?tab=teams`
  /// query parameter — used to drive the simulator past TCC-blocked taps.
  final String? initialTab;

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _initialTabSet = false;

  static const Map<String, int> _tabIndexByName = {
    'overview': 0,
    'predict': 1,        // Legacy alias for the merged tab
    'predictions': 1,
    'teams': 2,
    'others': 1,         // Legacy alias for the merged tab (lands on PREDICTIONS)
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final override = widget.initialTab?.toLowerCase();
    final idx = override == null ? null : _tabIndexByName[override];
    if (idx != null) {
      _tabController.index = idx;
      _initialTabSet = true;
    }
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
                  Tab(text: 'PREDICTIONS'),
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
                    _PredictionsTab(
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
    final dateStr =
        kickoff != null ? formatMatchKickoffVerbose(kickoff) : null;

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
                  Expanded(
                    child: Text(
                      _resolveScorerName(match, pred.predictedScorerId).isEmpty
                          ? 'Goalscorer pick submitted'
                          : 'Goalscorer: ${_resolveScorerName(match, pred.predictedScorerId)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
// Predictions Tab — single surface that owns both the pre-lock predict
// form AND the post-lock ranked list (self pinned, opponents below).
// ---------------------------------------------------------------------------

class _PredictionsTab extends ConsumerStatefulWidget {
  const _PredictionsTab({
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
  ConsumerState<_PredictionsTab> createState() => _PredictionsTabState();
}

class _PredictionsTabState extends ConsumerState<_PredictionsTab> {
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
  void didUpdateWidget(_PredictionsTab old) {
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
    // Match has started (or finished, or been cancelled). The form is
    // replaced by the merged predictions list: self pinned at the top
    // with their own picks + live points chips always visible (computed
    // from realtime events while the match is in play, settled from
    // points_earned once status='final'), then every group-mate who
    // predicted this match sorted by current points.
    if (locked) {
      return _LockedPredictionsList(
        match: widget.match,
        matchId: widget.matchId,
      );
    }

    // ── Unlocked form ─────────────────────────────────────────────────
    // Whole form scrolls as a single surface — score pickers, divider,
    // optional pickers — so the layout adapts gracefully to any device
    // size (and to any preview-screen scenario bar pinned underneath).
    // The save button sits outside the scroll, glued to the bottom.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Score pickers ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
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
                const SizedBox(height: 8),
                const Divider(height: 1),
                // ── Optional pickers + multiplier/booster badges ──────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Auto-multiplier badge (3rd place / Final)
                      if (widget.match.autoMultiplier > 1) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer
                                .withValues(alpha: 0.35),
                            borderRadius: AppRadii.cardRadius,
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.4)),
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
                                  size: 14,
                                  color: AppColors.onSurfaceMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Set a score to unlock first-team & goalscorer picks',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.onSurfaceMuted),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (!_isZeroZero) ...[
                        Text(
                          'First team to score (optional · +2 pts)',
                          style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        FirstTeamPicker(
                          match: widget.match,
                          selectedTeamId: _firstTeamId,
                          score1: _score1,
                          score2: _score2,
                          onPick: (id) =>
                              setState(() => _firstTeamId = id),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Goalscorer (optional · +8 pts)',
                          style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        _ScorerPickerButton(
                          scorerId: _scorerId,
                          match: widget.match,
                          onPick: (id) =>
                              setState(() => _scorerId = id),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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

class _TeamsTab extends ConsumerWidget {
  const _TeamsTab({required this.match});
  final MatchModel match;

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

    if (a.isStarter != b.isStarter) return a.isStarter ? -1 : 1;
    final cmp = posRank(a).compareTo(posRank(b));
    if (cmp != 0) return cmp;
    final na = a.jerseyNumber ?? 999;
    final nb = b.jerseyNumber ?? 999;
    return na.compareTo(nb);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineupAsync = ref.watch(matchLineupProvider(match.id));

    // Loading: only show a spinner while we have nothing else to fall back
    // on. If the legacy `team.players` roster is already present, render it
    // immediately so the user isn't staring at an empty screen waiting for
    // a per-match lineup row count.
    if (lineupAsync.isLoading) {
      final t1Fallback = match.team1?.players ?? const <PlayerModel>[];
      final t2Fallback = match.team2?.players ?? const <PlayerModel>[];
      if (t1Fallback.isEmpty && t2Fallback.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
      }
      return _buildRoster(context, const <PlayerModel>[]);
    }

    if (lineupAsync.hasError) {
      return _TabEmptyState(
        icon: Symbols.group,
        primaryText: 'Could not load lineup.',
        secondaryText: '${lineupAsync.error}',
      );
    }

    return _buildRoster(context, lineupAsync.requireValue);
  }

  Widget _buildRoster(BuildContext context, List<PlayerModel> lineup) {
    final team1Id = match.team1Id;
    final team2Id = match.team2Id;

    // Source of truth for the *matchday* squad (11 starters + named bench)
    // is `match_lineups` — written by `poll_lineups` ~45 min before kickoff
    // for the upcoming fixture. Before that arrives we render the full
    // season roster from `team.players` so the user always sees the
    // available pool of players (rather than an empty placeholder).
    List<PlayerModel> t1List =
        lineup.where((p) => p.teamId == team1Id).toList();
    List<PlayerModel> t2List =
        lineup.where((p) => p.teamId == team2Id).toList();
    final usingMatchLineup = t1List.isNotEmpty || t2List.isNotEmpty;
    if (!usingMatchLineup) {
      t1List = [...(match.team1?.players ?? <PlayerModel>[])];
      t2List = [...(match.team2?.players ?? <PlayerModel>[])];
    }

    t1List.sort(_playerSort);
    t2List.sort(_playerSort);

    // Starter/sub split is only meaningful when the matchday lineup
    // confirmed which 11 start; otherwise treat the whole list as one
    // roster (no section labels, no formation tag).
    final t1Starters = usingMatchLineup
        ? t1List.where((p) => p.isStarter).toList()
        : const <PlayerModel>[];
    final t1Subs = usingMatchLineup
        ? t1List.where((p) => !p.isStarter).toList()
        : const <PlayerModel>[];
    final t2Starters = usingMatchLineup
        ? t2List.where((p) => p.isStarter).toList()
        : const <PlayerModel>[];
    final t2Subs = usingMatchLineup
        ? t2List.where((p) => !p.isStarter).toList()
        : const <PlayerModel>[];

    final t1ShowSplit = usingMatchLineup && t1Starters.isNotEmpty;
    final t2ShowSplit = usingMatchLineup && t2Starters.isNotEmpty;
    final t1RenderStarters = t1ShowSplit ? t1Starters : t1List;
    final t1RenderSubs = t1ShowSplit ? t1Subs : const <PlayerModel>[];
    final t2RenderStarters = t2ShowSplit ? t2Starters : t2List;
    final t2RenderSubs = t2ShowSplit ? t2Subs : const <PlayerModel>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!usingMatchLineup) ...[
            _LineupsPendingBanner(kickoff: match.kickoffTime),
            const SizedBox(height: 12),
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Team 1 ──────────────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (match.team1 != null) _TeamHeader(team: match.team1!),
                      if (t1ShowSplit)
                        _RosterSectionLabel(
                          label: 'Starting XI',
                          formation: match.formationTeam1,
                          rightAlign: false,
                        ),
                      for (final p in t1RenderStarters)
                        _PlayerRow(player: p, rightAlign: false),
                      if (t1RenderSubs.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const _RosterSectionLabel(
                          label: 'Substitutes',
                          rightAlign: false,
                        ),
                        for (final p in t1RenderSubs)
                          _PlayerRow(player: p, rightAlign: false),
                      ],
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
                      if (t2ShowSplit)
                        _RosterSectionLabel(
                          label: 'Starting XI',
                          formation: match.formationTeam2,
                          rightAlign: true,
                        ),
                      for (final p in t2RenderStarters)
                        _PlayerRow(player: p, rightAlign: true),
                      if (t2RenderSubs.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const _RosterSectionLabel(
                          label: 'Substitutes',
                          rightAlign: true,
                        ),
                        for (final p in t2RenderSubs)
                          _PlayerRow(player: p, rightAlign: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertically-fixed empty/error state used by both TEAMS and OTHERS tabs.
///
/// Both tabs anchor their empty content at the same offset from the top
/// of the tab body (96px), so switching tabs doesn't shift the icon up
/// or down between them. A `Center` widget would re-anchor to the
/// midpoint of available height, which differs between tabs once the
/// hero card pushes the body down by a different amount.
class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({
    required this.icon,
    required this.primaryText,
    this.secondaryText,
  });

  final IconData icon;
  final String primaryText;
  final String? secondaryText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 24),
      children: [
        Icon(icon, size: 40, color: AppColors.onSurfaceMuted),
        const SizedBox(height: 12),
        Text(
          primaryText,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.onSurfaceMuted),
        ),
        if (secondaryText != null) ...[
          const SizedBox(height: 8),
          Text(
            secondaryText!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.onSurfaceMuted),
          ),
        ],
      ],
    );
  }
}

/// Compact info banner shown above the Teams tab roster while the
/// matchday lineup is still pending (no `match_lineups` rows yet).
/// Tells the user that the list below is the season-long squad, not
/// the eventual starting XI, and surfaces the countdown to the
/// poll_lineups window so they know when to expect the real lineup.
class _LineupsPendingBanner extends StatelessWidget {
  const _LineupsPendingBanner({required this.kickoff});

  final DateTime? kickoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFutureKickoff =
        kickoff != null && kickoff!.isAfter(DateTime.now());
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.outline, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Symbols.schedule, size: 18,
              color: AppColors.onSurfaceMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Lineups available about 45 minutes before kickoff.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
          if (hasFutureKickoff) ...[
            const SizedBox(width: 8),
            CountdownPill(target: kickoff!),
          ],
        ],
      ),
    );
  }
}

/// Compact section header used inside the Teams tab to separate the
/// starting XI from substitutes. Mirrors the team-side alignment so the
/// label sits on the same edge as the team header above.
class _RosterSectionLabel extends StatelessWidget {
  const _RosterSectionLabel({
    required this.label,
    required this.rightAlign,
    this.formation,
  });
  final String label;
  final bool rightAlign;
  final String? formation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = formation != null && formation!.isNotEmpty
        ? '$label · $formation'
        : label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Row(
        mainAxisAlignment:
            rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
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
// PREDICTIONS Tab — locked view
// ---------------------------------------------------------------------------
// Pinned-at-top self row + ranked group-mate list, both driven by the
// realtime providers in `match_predictions_provider.dart`. Rendered by
// `_PredictionsTab` once a match is locked (kickoff has passed); the
// editable form takes over pre-lock.

class _LockedPredictionsList extends ConsumerWidget {
  const _LockedPredictionsList({required this.match, required this.matchId});
  final MatchModel match;
  final int matchId;

  String _headerCopy() {
    switch (match.status) {
      case 'final':
        return 'Final results';
      case 'live':
        return 'Live potential — updates as the match progresses';
      case 'cancelled':
        return 'Match cancelled';
      default:
        // Locked via wall-clock (kickoff passed) but status hasn't flipped
        // to 'live' yet — cron lag window.
        return 'Predictions locked · Match has started';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rowsAsync = ref.watch(predictionsForMatchProvider(matchId));

    Future<void> refresh() async {
      // Refresh the whole chain: participant set, predictions, boosters,
      // events. matchByIdProvider is invalidated too in case status flipped
      // between navigations — `predictionsForMatchProvider` depends on it.
      ref.invalidate(predictionParticipantsProvider);
      ref.invalidate(matchPredictionsByUserProvider(matchId));
      ref.invalidate(matchBoostersByUserProvider(matchId));
      ref.invalidate(matchByIdProvider(matchId));
      // Wait for the family's next emission so the spinner stays up
      // until fresh data lands, not just until the invalidate returns.
      await ref.read(predictionsForMatchProvider(matchId).future);
    }

    Widget wrapWithRefresh(Widget child) => RefreshIndicator(
          onRefresh: refresh,
          color: AppColors.primary,
          backgroundColor: AppColors.surfaceHigh,
          child: child,
        );

    return rowsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (e, _) => wrapWithRefresh(
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
          children: [
            Text(
              'Could not load predictions.\nPull to retry.\n\n$e',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.onSurfaceMuted),
            ),
          ],
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return wrapWithRefresh(
            const _TabEmptyState(
              icon: Symbols.group,
              primaryText:
                  'No predictions for this match yet.\nPull to refresh.',
            ),
          );
        }

        return wrapWithRefresh(
          ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text(
                    _headerCopy(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                );
              }
              final row = rows[index - 1];
              return _PredictionRowTile(row: row, match: match);
            },
          ),
        );
      },
    );
  }
}

/// Single row on the predictions list — works for self and opponents.
///
/// Self-specific treatment (driven by [PredictionRow.isSelf]):
///   * Name reads "You" instead of the profile display name.
///   * Avatar uses the primary accent tint instead of the neutral surface.
///   * Card border is accented so it pops from the opponent list.
///   * Picks (Predicted / Live + scores + chips) are ALWAYS revealed
///     because they're not a spoiler to the owner — even mid-match.
///   * If self never predicted, the tile collapses to a compact
///     "You didn't predict this match" placeholder instead.
///
/// Opponent rows reveal picks only at FT (existing spoiler rule).
class _PredictionRowTile extends StatelessWidget {
  const _PredictionRowTile({required this.row, required this.match});

  final PredictionRow row;
  final MatchModel match;

  /// Tier-color matches the `_PointsBadge` rule in `user_predictions_screen.dart`
  /// so the leaderboard reads like the per-user predictions list.
  Color _pointColor(int? earned, {required bool isFinal}) {
    if (!isFinal) return AppColors.onSurfaceMuted;
    if (earned == null) return AppColors.onSurfaceMuted;
    if (earned >= 8) return AppColors.gold;
    if (earned >= 5) return AppColors.primary;
    if (earned >= 1) return AppColors.secondary;
    return AppColors.onSurfaceMuted;
  }

  @override
  Widget build(BuildContext context) {
    final isFinal = match.status == 'final';
    final isLive = match.status == 'live';
    final theme = Theme.of(context);
    final prediction = row.prediction;

    // Self with no prediction → compact placeholder card.
    if (row.isSelf && prediction == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Symbols.lock,
                  size: 18, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "You didn't predict this match",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final name = row.profile.displayName?.trim();
    final fallback = (name == null || name.isEmpty) ? '—' : name;
    final label = row.isSelf ? 'You' : fallback;
    // Initial always comes off the real display name (or fallback "—")
    // so the self avatar still shows the user's first letter, not "Y".
    final initial = fallback.substring(0, 1).toUpperCase();

    final score = row.score;
    final total = (score != null && (isFinal || isLive)) ? score.total : null;
    final pointColor = _pointColor(total, isFinal: isFinal);

    // Self always reveals own picks; opponents only at FT.
    final picksRevealed = row.isSelf || isFinal;
    // Live block label flips to "Live" for in-play, "Actual" once final.
    final actualLabel = isFinal ? 'Actual' : 'Live';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadii.cardRadius,
          border: row.isSelf
              ? Border.all(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  width: 1.5,
                )
              : null,
        ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: avatar + name | points badge ────────────────
              Row(
                children: [
                  _PredictionAvatar(initial: initial, isSelf: row.isSelf),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PredictionPointsBadge(total: total, color: pointColor),
                ],
              ),
              // ── Predicted / Actual scores — revealed by `picksRevealed`
              if (picksRevealed && prediction != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _PredictionScoreBlock(
                      label: 'Predicted',
                      score1: prediction.predictedTeam1,
                      score2: prediction.predictedTeam2,
                      highlight: false,
                    ),
                    const SizedBox(width: 20),
                    _PredictionScoreBlock(
                      label: actualLabel,
                      score1: match.scoreFtTeam1,
                      score2: match.scoreFtTeam2,
                      highlight: true,
                    ),
                  ],
                ),
              ],
              // ── Per-category chips: prediction picks + verdict merged
              if (picksRevealed && prediction != null && score != null) ...[
                const SizedBox(height: 10),
                _PredictionChips(
                  prediction: prediction,
                  match: match,
                  score: score,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PredictionAvatar extends StatelessWidget {
  const _PredictionAvatar({required this.initial, this.isSelf = false});
  final String initial;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isSelf
            ? AppColors.primaryContainer
            : AppColors.surfaceHighest,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelf ? AppColors.primary : AppColors.outline,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: isSelf ? AppColors.onPrimaryContainer : AppColors.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PredictionPointsBadge extends StatelessWidget {
  const _PredictionPointsBadge({required this.total, required this.color});
  final int? total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          total == null ? '—' : '$total',
          style: textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          'pts',
          style: textTheme.labelSmall
              ?.copyWith(color: AppColors.onSurfaceMuted),
        ),
      ],
    );
  }
}

class _PredictionScoreBlock extends StatelessWidget {
  const _PredictionScoreBlock({
    required this.label,
    required this.score1,
    required this.score2,
    required this.highlight,
  });
  final String label;
  final int? score1;
  final int? score2;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scoreText = (score1 != null && score2 != null)
        ? formatScore(score1, score2)
        : '—';
    final scoreColor =
        highlight ? AppColors.onSurface : AppColors.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: textTheme.labelSmall
                ?.copyWith(color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 2),
        Text(
          scoreText,
          style: textTheme.titleMedium?.copyWith(
            color: scoreColor,
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Unified chip row per predictions tile.
///
/// Each chip carries both the prediction's **context** (which team /
/// player the user picked) and the **verdict** (points awarded), green
/// when the category hit, gray when it missed. Categories the user
/// did not pick at all (e.g. no goalscorer) are omitted entirely.
///
/// Examples:
/// - "Exact · 5pts" (match-result category — always shown)
/// - "First team: United States · 2pts" (only when user picked a first team)
/// - "Scorer: C. Pulisic · 8pts" (only when user picked a goalscorer)
/// - "×3 booster" (only on boosted knockout matches)
class _PredictionChips extends StatelessWidget {
  const _PredictionChips({
    required this.prediction,
    required this.match,
    required this.score,
  });
  final PredictionModel prediction;
  final MatchModel match;
  final LiveScore score;

  @override
  Widget build(BuildContext context) {
    // Mutually-exclusive match-result label.
    final String matchLabel;
    switch (score.pointsMatch) {
      case 5:
        matchLabel = 'Exact';
      case 3:
        matchLabel = 'Goal diff';
      case 2:
        matchLabel = 'Outcome';
      default:
        matchLabel = 'Miss';
    }

    final chips = <Widget>[
      _PredictionChip(
        icon: score.pointsMatch > 0
            ? Icons.check_circle_outline
            : Icons.remove_circle_outline,
        label: '$matchLabel · ${score.pointsMatch}pts',
        hit: score.pointsMatch > 0,
      ),
    ];

    final ft = prediction.predictedFirstTeamId;
    if (ft != null) {
      chips.add(_PredictionChip(
        icon: score.pointsFirstTeam > 0
            ? Icons.check_circle_outline
            : Icons.remove_circle_outline,
        label:
            'First team: ${_resolveTeamName(match, ft)} · ${score.pointsFirstTeam}pts',
        hit: score.pointsFirstTeam > 0,
      ));
    }

    final sc = prediction.predictedScorerId;
    if (sc != null) {
      final scorer = abbreviateFullName(_resolveScorerName(match, sc));
      if (scorer.isNotEmpty) {
        chips.add(_PredictionChip(
          icon: score.pointsGoalscorer > 0
              ? Icons.check_circle_outline
              : Icons.remove_circle_outline,
          label: 'Scorer: $scorer · ${score.pointsGoalscorer}pts',
          hit: score.pointsGoalscorer > 0,
        ));
      }
    }

    if (score.multiplier > 1) {
      chips.add(_PredictionChip(
        icon: Icons.bolt_outlined,
        label: '×${score.multiplier} booster',
        hit: true,
      ));
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _PredictionChip extends StatelessWidget {
  const _PredictionChip({
    required this.icon,
    required this.label,
    required this.hit,
  });
  final IconData icon;
  final String label;
  final bool hit;

  @override
  Widget build(BuildContext context) {
    final color = hit ? AppColors.primary : AppColors.onSurfaceMuted;
    final bgColor = hit
        ? AppColors.primaryContainer.withValues(alpha: 0.5)
        : AppColors.surfaceHighest;
    // Cap chip width so an unusually long combined label
    // ("First team: <country> · Xpts") wraps to the next Wrap row
    // rather than blowing past the tile edge. The Flexible + ellipsis
    // pair inside is the final safety net for the unlikely case where
    // even the abbreviated name still overflows the cap.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppRadii.pillRadius,
          border: Border.all(
            color: hit
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.outline,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: hit ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ),
          ],
        ),
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

          // If the full name doesn't fit, drop the first name to an
          // initial via the shared `abbreviateFullName` helper. The
          // width check guards against unnecessary abbreviation on a
          // wide chip; threshold:0 forces abbreviation here (we've
          // already decided the name overflows). Falls back to plain
          // ellipsis when even the abbreviation overflows.
          final fullName = player.name;
          final fullWidth = _measureTextWidth(fullName, nameStyle);
          final displayName = fullWidth > availableForName
              ? abbreviateFullName(fullName, threshold: 0)
              : fullName;

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

/// Resolves a player_id to a display name by walking both teams' rosters.
/// Falls back to `#<id>` when the player is not on either side (out-of-date
/// roster cache or stale prediction); empty string when no id provided.
String _resolveScorerName(MatchModel match, int? playerId) {
  if (playerId == null) return '';
  for (final p in [
    ...?match.team1?.players,
    ...?match.team2?.players,
  ]) {
    if (p.id == playerId) return _decodeHtml(p.name);
  }
  return '#$playerId';
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
// _BoosterToggle — apply/remove the round booster for a knockout match.
//
// Three states:
//   * Applied here     — booster row exists with matchId == this match
//   * Used elsewhere   — booster row exists in this round but on another
//                        match. Switch shows OFF + warning subtitle, and
//                        tapping ON triggers `_BoosterMoveConfirmSheet`
//                        so the user reviews the prediction they'd be
//                        moving the multiplier away from.
//   * Unused this round — no booster row for the round. Tapping ON
//                         applies directly (no confirmation needed).
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

  Future<void> _apply() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      await supabase.from('round_boosters').upsert({
        'user_id': user.id,
        'round': widget.match.round,
        'match_id': widget.matchId,
        'multiplier': widget.match.boosterMultiplier,
      }, onConflict: 'user_id,round');
      ref.invalidate(boosterForMatchProvider(widget.matchId));
      ref.invalidate(myBoostersProvider);
      AppFeedback.success('Booster applied to this match');
    } catch (e) {
      AppFeedback.error('Booster update failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      await supabase
          .from('round_boosters')
          .delete()
          .eq('user_id', user.id)
          .eq('round', widget.match.round ?? '');
      ref.invalidate(boosterForMatchProvider(widget.matchId));
      ref.invalidate(myBoostersProvider);
      AppFeedback.success('Booster removed');
    } catch (e) {
      AppFeedback.error('Booster update failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onSwitchChanged(
    bool active, {
    required RoundBoosterModel? bookerElsewhere,
  }) async {
    if (!active) {
      await _remove();
      return;
    }
    if (bookerElsewhere != null) {
      // `showAppSheet` opens at the root navigator, which sits OUTSIDE
      // the nearest `ProviderScope`. Without re-injecting the same
      // container, any provider the sheet reads (the FROM match, the
      // user's prediction on it) falls through to production Supabase
      // — and in the dev preview where those rows don't exist, the
      // sheet renders an error. Capturing the container here and
      // wrapping the sheet child in `UncontrolledProviderScope` keeps
      // the modal aligned with the surface that triggered it.
      final container = ProviderScope.containerOf(context);
      final confirmed = await showAppSheet<bool>(
        context: context,
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: _BoosterMoveConfirmSheet(
            round: widget.match.round ?? '',
            multiplier: widget.match.boosterMultiplier,
            fromMatchId: bookerElsewhere.matchId,
            toMatchTeam1Code: widget.match.team1?.code,
            toMatchTeam2Code: widget.match.team2?.code,
          ),
        ),
      );
      if (confirmed != true) return;
    }
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    final boosterAsync = ref.watch(boosterForMatchProvider(widget.matchId));
    final myBoostersAsync = ref.watch(myBoostersProvider);
    final round = widget.match.round ?? '';
    final multiplier = widget.match.boosterMultiplier;
    final theme = Theme.of(context);

    final appliedHere = boosterAsync.valueOrNull != null;
    final roundBooster = myBoostersAsync.valueOrNull?[round];
    final usedElsewhere = !appliedHere &&
        roundBooster != null &&
        roundBooster.matchId != widget.matchId;

    final (Color bg, Color border, Color iconColor, Color titleColor) =
        appliedHere
            ? (
                AppColors.primaryContainer.withValues(alpha: 0.35),
                AppColors.primary.withValues(alpha: 0.5),
                AppColors.primary,
                AppColors.primary,
              )
            : usedElsewhere
                ? (
                    AppColors.secondaryContainer.withValues(alpha: 0.25),
                    AppColors.secondary.withValues(alpha: 0.5),
                    AppColors.secondary,
                    AppColors.secondary,
                  )
                : (
                    AppColors.surfaceHigh,
                    AppColors.outlineVariant,
                    AppColors.onSurfaceMuted,
                    AppColors.onSurface,
                  );

    // Once the host match locks (status flipped or wall-clock passed
    // kickoff), the booster row is no longer reversible from this
    // screen: the DB lock trigger rejects INSERT/UPDATE pointing at a
    // locked match, and migration 038 recomputes scoring when a booster
    // is DELETEd. A switch tap here would either no-op or permanently
    // strip the user's multiplier, so we render a non-interactive pill
    // for the post-lock case.
    final locked = widget.match.isLocked;
    final lockedAndApplied = locked && appliedHere;

    final subtitle = lockedAndApplied
        ? 'Locked in — ×$multiplier multiplier is final'
        : appliedHere
            ? 'Applied — your score is multiplied by $multiplier'
            : usedElsewhere
                ? 'Currently on another $round match · tap to move it here'
                : 'Use your $round booster on this match';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            appliedHere ? Icons.bolt : Icons.bolt_outlined,
            size: 18,
            color: iconColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$round Booster ×$multiplier',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                Text(
                  subtitle,
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
          else if (lockedAndApplied)
            // No switch — the multiplier is committed. The lock icon
            // mirrors the state of the rest of the locked UI.
            Icon(
              Icons.lock_outline,
              size: 18,
              color: iconColor,
            )
          else
            Switch(
              value: appliedHere,
              onChanged: (v) => _onSwitchChanged(
                v,
                bookerElsewhere: usedElsewhere ? roundBooster : null,
              ),
              activeTrackColor: AppColors.primary,
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet that confirms moving the round booster from one match
/// to another. Renders the *current* match (the one losing the booster)
/// with its teams + the user's prediction picks so the user has full
/// context before they commit.
class _BoosterMoveConfirmSheet extends ConsumerWidget {
  const _BoosterMoveConfirmSheet({
    required this.round,
    required this.multiplier,
    required this.fromMatchId,
    required this.toMatchTeam1Code,
    required this.toMatchTeam2Code,
  });

  final String round;
  final int multiplier;
  final int fromMatchId;
  final String? toMatchTeam1Code;
  final String? toMatchTeam2Code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fromMatchAsync = ref.watch(matchByIdProvider(fromMatchId));
    final fromPredAsync = ref.watch(myPredictionProvider(fromMatchId));
    final toLabel = toMatchTeam1Code != null && toMatchTeam2Code != null
        ? '$toMatchTeam1Code vs $toMatchTeam2Code'
        : 'this match';

    return AppSheetBody(
      title: 'Move your $round booster?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Confirming will remove the ×$multiplier multiplier from '
            'the match below and apply it to $toLabel instead.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: fromMatchAsync.when(
              loading: () => const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                'Could not load match details: $e',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.error),
              ),
              data: (fromMatch) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MoveSheetMatchBlock(
                    match: fromMatch,
                    prediction: fromPredAsync.valueOrNull,
                    multiplier: multiplier,
                  ),
                  if (fromMatch.isLocked) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer
                            .withValues(alpha: 0.25),
                        borderRadius: AppRadii.cardRadius,
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            size: 16,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This match has already kicked off. '
                              'Moving your booster will recompute its '
                              'score without the ×$multiplier multiplier.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurface,
                    side: const BorderSide(color: AppColors.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.buttonRadius,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Keep where it is'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.buttonRadius,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Move booster'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders the FROM match inside [_BoosterMoveConfirmSheet]: team flags +
/// names + the user's predicted score and (when present) first-team /
/// scorer picks. Defensive against missing prediction data so the sheet
/// still renders if the booster row outlived a deletion.
class _MoveSheetMatchBlock extends StatelessWidget {
  const _MoveSheetMatchBlock({
    required this.match,
    required this.prediction,
    required this.multiplier,
  });

  final MatchModel match;
  final PredictionModel? prediction;
  final int multiplier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pred = prediction;
    final hasScore =
        pred?.predictedTeam1 != null && pred?.predictedTeam2 != null;
    final ftPick = pred?.predictedFirstTeamId;
    final scorerPick = pred?.predictedScorerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row: round badge · team flags + names ────────────────
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${match.round ?? ''} · ×$multiplier',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            const Icon(Icons.bolt, size: 16, color: AppColors.secondary),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TeamFlag(team: match.team1, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                match.team1?.name ?? 'TBD',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              hasScore
                  ? '${pred!.predictedTeam1}'
                  : '—',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TeamFlag(team: match.team2, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                match.team2?.name ?? 'TBD',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              hasScore
                  ? '${pred!.predictedTeam2}'
                  : '—',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        // ── Optional pick chips ─────────────────────────────────────────
        if (ftPick != null || scorerPick != null) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: 10),
          if (ftPick != null)
            _MovePickRow(
              icon: Icons.flag_outlined,
              label: 'First to score',
              value: _resolveTeamName(match, ftPick),
            ),
          if (scorerPick != null) ...[
            if (ftPick != null) const SizedBox(height: 6),
            _MovePickRow(
              icon: Icons.sports_soccer_outlined,
              label: 'Goalscorer',
              value: abbreviateFullName(_resolveScorerName(match, scorerPick)),
            ),
          ],
        ],
        if (pred == null) ...[
          const SizedBox(height: 8),
          Text(
            'You haven\'t predicted this match yet — only the booster is at risk.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.onSurfaceMuted),
          ),
        ],
      ],
    );
  }
}

class _MovePickRow extends StatelessWidget {
  const _MovePickRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
