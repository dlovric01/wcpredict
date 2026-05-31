# Match Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the match detail screen + bottom-sheet predict modal with a three-tab screen (Overview · Predict · Teams) that eliminates scroll-in-scroll.

**Architecture:** Single file replacement — `match_detail_screen.dart` is rewritten as a `ConsumerStatefulWidget` with a `TabController`. `predict_modal.dart` is deleted. All prediction form state moves into a private `_PredictTab` widget. No new providers, models, or routes are introduced.

**Tech Stack:** Flutter, flutter_riverpod, supabase_flutter, `AppColors` / `AppRadii` / `AppMotion` tokens, existing providers in `lib/shared/providers/`.

**Spec:** `docs/superpowers/specs/2026-05-31-match-screen-redesign.md`

---

## File Map

| Action | File | Notes |
|---|---|---|
| **Delete** | `lib/features/matches/predict_modal.dart` | Removed entirely |
| **Replace** | `lib/features/matches/match_detail_screen.dart` | All widgets stay in this file |
| Unchanged | `lib/features/matches/live_events_widget.dart` | Reused on Overview tab |
| Unchanged | `lib/shared/widgets/verdict_pill.dart` | Reused on locked Predict tab |
| Unchanged | `lib/shared/providers/predictions_provider.dart` | |
| Unchanged | `lib/shared/providers/match_detail_provider.dart` | |

---

## Task 1: Scaffold — Tab Chrome, Hero Card, Placeholder Tab Bodies

Delete `predict_modal.dart` and establish the compilable skeleton of the new screen: `MatchDetailScreen` with `TabController`, the pinned hero card, and stub bodies for the three tabs.

**Files:**
- Delete: `lib/features/matches/predict_modal.dart`
- Replace: `lib/features/matches/match_detail_screen.dart`

- [ ] **Step 1: Delete predict_modal.dart**

```bash
rm lib/features/matches/predict_modal.dart
```

- [ ] **Step 2: Write the new match_detail_screen.dart scaffold**

Replace the entire file with the following. This compiles and renders the tab chrome with placeholder content. Subsequent tasks fill in the tab bodies.

```dart
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
    return const Center(child: Text('Overview — coming in Task 2'));
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
    return const Center(child: Text('Predict — coming in Task 3'));
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
    return const Center(child: Text('Teams — coming in Task 4'));
  }
}
```

- [ ] **Step 2b: Append unchanged formation and lineup widgets**

The scaffold above doesn't include the formation/lineup/player widgets that Task 4 needs. Before the end of the scaffold code block (after the closing ` ``` `), append the following widgets verbatim — they are unchanged from the original `match_detail_screen.dart` and simply need to move into the new file. Copy them from the original file (`git show HEAD:lib/features/matches/match_detail_screen.dart`) at lines 533–939 which contain: `_LineupsSection`, `_FormationPitch`, `_PlayerDot`, `_PitchPainter`, `_SubstitutesList`, `_decodeHtml`, `_PlayerRow`, and `_PositionBadge`. Task 3 will replace `_PositionBadge` with an improved version; for now copy whatever is there.

```bash
# Extract the formation/lineup widgets from the old file into the new one
git show HEAD:lib/features/matches/match_detail_screen.dart \
  | awk 'NR>=533' >> lib/features/matches/match_detail_screen.dart
```

This appends lines 533–end (all the formation widgets) to the new scaffold file.

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/features/matches/match_detail_screen.dart
```

Expected: `No issues found!`

If you see "Undefined name 'showPredictModal'" anywhere else, search for it:
```bash
grep -r "showPredictModal\|predict_modal" lib/
```
There should be zero results (the only callsite was inside `match_detail_screen.dart` itself, which is now replaced).

- [ ] **Step 4: Commit**

```bash
git add lib/features/matches/match_detail_screen.dart
git rm lib/features/matches/predict_modal.dart
git commit -m "feat(match-screen): scaffold three-tab layout, delete predict modal"
```

---

## Task 2: Overview Tab

Implement `_OverviewTab`. Two states:
- **Scheduled**: match info card (venue, group, kickoff) + prediction summary card (shows your pick or a CTA to the Predict tab).
- **Live / Final**: events timeline using the existing `LiveEventsWidget`.

**Files:**
- Modify: `lib/features/matches/match_detail_screen.dart` — replace `_OverviewTab.build`

- [ ] **Step 1: Replace `_OverviewTab.build` with the full implementation**

Find the `_OverviewTab` class (the placeholder from Task 1) and replace its `build` method:

```dart
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
        ref.invalidate(matchEventsProvider(matchId));
        ref.invalidate(myPredictionProvider(matchId));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: isFinalOrLive
            ? [
                // Events timeline
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
                // Match info
                _MatchInfoCard(match: match),
                const SizedBox(height: 12),
                // Prediction summary
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
            // Has a prediction — show summary
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
            // No prediction, match open
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
            // No prediction, match locked
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
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/features/matches/match_detail_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/matches/match_detail_screen.dart
git commit -m "feat(match-screen): implement Overview tab"
```

---

## Task 3: Predict Tab — Full Form + Locked State

Implement `_PredictTab` with its state class, the prediction form (score picker, first team, goalscorer), and the locked state (result comparison + points). Also add the private widgets `_ScorePicker`, `_StepBtn`, `_PlayerChip`, and `_PositionBadge`.

**Files:**
- Modify: `lib/features/matches/match_detail_screen.dart` — replace `_PredictTab`, `_PredictTabState`; add helper widgets at the bottom of the file.

- [ ] **Step 1: Replace `_PredictTab` and `_PredictTabState` with the full implementation**

```dart
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

  // Sync form when parent passes a new `existing` value (e.g. after reload).
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
          'predicted_first_team_id': _isZeroZero ? null : _firstTeamId,
          'predicted_scorer_id': _isZeroZero ? null : _scorerId,
        },
        onConflict: 'user_id,match_id',
      );

      ref.invalidate(myPredictionProvider(widget.matchId));
      ref.invalidate(matchByIdProvider(widget.matchId));

      if (mounted) {
        HapticFeedback.mediumImpact();
        widget.onSaved(); // switches to Overview tab
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

    // ── Locked state ─────────────────────────────────────────────────────────
    if (_locked) {
      final pred = widget.existing;
      final isFinal = widget.match.status == 'final';

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Locked banner
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
              // Score comparison card
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
                        // Actual / Live score
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
                        Container(width: 1, height: 40, color: AppColors.outline),
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
                      // Live — show potential points
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

    // ── Unlocked form ─────────────────────────────────────────────────────────
    final t1Players = _filteredPlayers
        .where((p) => p.teamId == (t1?.id ?? -1))
        .toList();
    final t2Players = _filteredPlayers
        .where((p) => p.teamId == (t2?.id ?? -1))
        .toList();

    return Column(
      children: [
        // ── Fixed score pickers (never scroll) ───────────────────────────
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

        // ── Scrollable: first scorer + goalscorer ────────────────────────
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
                // ── First team to score ───────────────────────────────────
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

                // ── Goalscorer ────────────────────────────────────────────
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
                                  _scorerId = _scorerId == p.id ? null : p.id),
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
                                  _scorerId = _scorerId == p.id ? null : p.id),
                            ))
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),

        // ── Save button — pinned ─────────────────────────────────────────
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
```

- [ ] **Step 2: Add the private form widgets at the bottom of the file**

Append the following four classes after `_TeamsTab` (before the end of the file). These are moved from the now-deleted `predict_modal.dart`.

```dart
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
            _StepBtn(
                icon: Icons.remove, enabled: value > 0, onTap: _dec),
            const SizedBox(width: 14),
            _StepBtn(
                icon: Icons.add, enabled: value < 20, onTap: _inc),
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
          color: selected ? AppColors.primaryContainer : AppColors.surfaceHigh,
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
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (player.jerseyNumber != null) ...[
              const SizedBox(width: 4),
              Text(
                '#${player.jerseyNumber}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? AppColors.onPrimaryContainer.withValues(alpha: 0.7)
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
```

- [ ] **Step 3: Replace the single `_PositionBadge` at the bottom of the file**

The file currently has one `_PositionBadge` (from the old screen, used by `_PlayerRow`). Replace it with a version that also handles the extended position aliases needed by `_PlayerChip` (CB→DEF, DM→MID, etc.):

```dart
// ---------------------------------------------------------------------------
// _PositionBadge — used by both _PlayerRow (teams tab) and _PlayerChip (predict tab)
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
```

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/features/matches/match_detail_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/matches/match_detail_screen.dart
git commit -m "feat(match-screen): implement Predict tab — form and locked state"
```

---

## Task 4: Teams Tab

Replace the `_TeamsTab` placeholder. Reuse the formation and lineup widgets that already exist in the file — they were copied verbatim in Task 1 (they survive in the new `match_detail_screen.dart` since `_LineupsSection`, `_FormationPitch`, `_PlayerDot`, `_PitchPainter`, `_SubstitutesList`, `_PlayerRow`, and `_decodeHtml` all stayed).

**Files:**
- Modify: `lib/features/matches/match_detail_screen.dart` — replace `_TeamsTab.build`

- [ ] **Step 1: Replace `_TeamsTab` with the full implementation**

```dart
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
          // Formation header
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
          // Pitch
          _FormationPitch(match: match),
          const SizedBox(height: 16),
          // Substitutes
          _SubstitutesList(match: match),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/features/matches/match_detail_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/matches/match_detail_screen.dart
git commit -m "feat(match-screen): implement Teams tab"
```

---

## Task 5: Final Cleanup and Verification

Wire the refresh indicator on Overview to also invalidate `matchEventsProvider`, run full analysis, and make sure no dead imports or references remain.

**Files:**
- Modify: `lib/features/matches/match_detail_screen.dart` — import check

- [ ] **Step 1: Run full project analysis**

```bash
flutter analyze
```

Expected: `No issues found!` with no warnings or infos.

If you see `unused import` warnings, remove the flagged import lines from `match_detail_screen.dart`.

- [ ] **Step 2: Confirm predict_modal.dart is gone and no references remain**

```bash
grep -r "predict_modal\|showPredictModal" lib/
```

Expected: no output (zero matches).

- [ ] **Step 3: Smoke-test the build**

```bash
flutter build apk --debug \
  --dart-define=SUPABASE_URL=placeholder \
  --dart-define=SUPABASE_ANON_KEY=placeholder \
  2>&1 | tail -5
```

Expected: ends with `Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Final commit**

```bash
git add lib/features/matches/match_detail_screen.dart
git commit -m "feat(match-screen): complete redesign — tabbed Overview/Predict/Teams"
```

---

## Acceptance Checklist

After all tasks:

- [ ] No scroll-inside-scroll anywhere on the screen
- [ ] Predict tab shows the full form for scheduled matches
- [ ] Predict tab shows locked result + points for live/final matches
- [ ] Overview tab shows match info + prediction summary for scheduled matches
- [ ] Overview tab shows events timeline for live/final matches
- [ ] Teams tab shows formation pitch + empty state when no lineups
- [ ] Default tab is Predict when scheduled + no prediction; Overview otherwise
- [ ] Save/Update invalidates both `myPredictionProvider` and `matchByIdProvider`, then switches to Overview
- [ ] `predict_modal.dart` deleted, zero references to `showPredictModal` remain
- [ ] `flutter analyze` passes with no issues
