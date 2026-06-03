// Debug-only preview surface for the merged PREDICTIONS tab.
//
// Renders the real `MatchDetailScreen` against a fully-mocked provider
// graph so every lifecycle state — pre-kickoff form, live with self
// pinned, final with revealed chips, multiplier, empty, solo — can be
// inspected on a real device without any DB setup.
//
// Reachable at `/dev/predictions-preview` when `kDebugMode`. The
// scenario picker is a horizontal chip row pinned to the bottom (under
// the home indicator) so the predictions tab content fills the rest of
// the screen exactly as a user would see it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/features/matches/live_scoring.dart';
import 'package:wcpredict/features/matches/match_detail_screen.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';
import 'package:wcpredict/shared/providers/boosters_provider.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/shared/providers/match_predictions_provider.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';

const int _matchId = 999001;
const String _selfUid = 'self-uid';
const String _bobUid = 'bob-uid';
const String _carolUid = 'carol-uid';
const String _doraUid = 'dora-uid';

const TeamModel _teamA = TeamModel(id: 100, name: 'France', code: 'FRA');
const TeamModel _teamB = TeamModel(id: 200, name: 'Brazil', code: 'BRA');

MatchModel _match({
  required String status,
  required Duration kickoffDelta,
  int? s1,
  int? s2,
  String round = 'Matchday 1',
}) =>
    MatchModel(
      id: _matchId,
      team1Id: _teamA.id,
      team2Id: _teamB.id,
      team1: _teamA,
      team2: _teamB,
      status: status,
      scoreFtTeam1: s1,
      scoreFtTeam2: s2,
      kickoffTime: DateTime.now().add(kickoffDelta),
      round: round,
    );

PredictionModel _pred({
  required String userId,
  int? pt1,
  int? pt2,
  int? firstTeamId,
  int? scorerId,
}) =>
    PredictionModel(
      id: 'p-$userId',
      userId: userId,
      matchId: _matchId,
      predictedTeam1: pt1,
      predictedTeam2: pt2,
      predictedFirstTeamId: firstTeamId,
      predictedScorerId: scorerId,
    );

ProfileModel _profile(String uid, String name) =>
    ProfileModel(userId: uid, displayName: name);

LiveScore _score({
  int pm = 0,
  int pft = 0,
  int pgs = 0,
  int mult = 1,
}) =>
    LiveScore(
      pointsMatch: pm,
      pointsFirstTeam: pft,
      pointsGoalscorer: pgs,
      multiplier: mult,
    );

// Fake "other match" id used by the "booster on other match" scenario.
// Picked above the api-sports id space so it never collides with real data.
const int _otherMatchId = 999002;

const TeamModel _otherTeam1 = TeamModel(id: 300, name: 'United States', code: 'USA');
const TeamModel _otherTeam2 = TeamModel(id: 400, name: 'Canada', code: 'CAN');

final MatchModel _otherMatch = MatchModel(
  id: _otherMatchId,
  team1Id: _otherTeam1.id,
  team2Id: _otherTeam2.id,
  team1: _otherTeam1,
  team2: _otherTeam2,
  status: 'scheduled',
  kickoffTime: DateTime.now().add(const Duration(days: 2)),
  round: 'QF',
);

final PredictionModel _otherMatchSelfPrediction = PredictionModel(
  id: 'p-self-other',
  userId: _selfUid,
  matchId: _otherMatchId,
  predictedTeam1: 3,
  predictedTeam2: 1,
  predictedFirstTeamId: _otherTeam1.id,
);

class _Scenario {
  final String label;
  final MatchModel match;
  final PredictionModel? selfPrediction;
  final List<PredictionRow> rows;

  /// Round booster row for the current user. May point at THIS match
  /// (toggle shows "applied here") or at a different match in the same
  /// round (toggle shows the "currently on another match" warning + tap
  /// triggers the move-confirm sheet).
  final RoundBoosterModel? roundBooster;

  const _Scenario({
    required this.label,
    required this.match,
    required this.selfPrediction,
    required this.rows,
    this.roundBooster,
  });

  /// True when the round's booster row targets THIS match. Drives the
  /// `boosterForMatchProvider(_matchId)` override — when the row is on a
  /// different match this family must return null.
  bool get _boosterAppliedHere =>
      roundBooster != null && roundBooster!.matchId == _matchId;

  List<Override> get overrides => [
        currentUserIdProvider.overrideWith((_) => _selfUid),
        matchByIdProvider(_matchId).overrideWith((_) async => match),
        myPredictionProvider(_matchId)
            .overrideWith((_) async => selfPrediction),
        liveMatchProvider(_matchId).overrideWith((_) => null),
        matchLineupProvider(_matchId).overrideWith((_) async => const []),
        boosterForMatchProvider(_matchId).overrideWith(
          (_) async => _boosterAppliedHere ? roundBooster : null,
        ),
        predictionsForMatchProvider(_matchId)
            .overrideWith((_) async => rows),
        // Full booster map — keyed by round. Drives `_BoosterToggle`'s
        // cross-match detection.
        myBoostersProvider.overrideWith(
          (_) async => roundBooster == null
              ? const <String, RoundBoosterModel>{}
              : {roundBooster!.round: roundBooster!},
        ),
        // The booster-on-another-match scenario navigates the confirm
        // sheet through `matchByIdProvider(_otherMatchId)` + the user's
        // prediction on that other match. Stub both so the sheet renders
        // a complete preview instead of a loading spinner.
        matchByIdProvider(_otherMatchId).overrideWith((_) async => _otherMatch),
        myPredictionProvider(_otherMatchId)
            .overrideWith((_) async => _otherMatchSelfPrediction),
      ];
}

List<_Scenario> _buildScenarios() {
  return [
    // 1. Scheduled · empty form
    _Scenario(
      label: '1. Empty form',
      match: _match(status: 'scheduled', kickoffDelta: const Duration(days: 1)),
      selfPrediction: null,
      rows: const [],
    ),
    // 2. Scheduled · filled form
    _Scenario(
      label: '2. Filled form',
      match: _match(status: 'scheduled', kickoffDelta: const Duration(days: 1)),
      selfPrediction: _pred(
        userId: _selfUid,
        pt1: 2,
        pt2: 1,
        firstTeamId: _teamA.id,
      ),
      rows: const [],
    ),
    // 3. Live · self pinned with picks revealed (full hit)
    _Scenario(
      label: '3. Live · full hit',
      match: _match(
        status: 'live',
        kickoffDelta: const Duration(minutes: -70),
        s1: 2,
        s2: 1,
      ),
      selfPrediction: _pred(
        userId: _selfUid,
        pt1: 2,
        pt2: 1,
        firstTeamId: _teamA.id,
        scorerId: 4001,
      ),
      rows: [
        PredictionRow(
          profile: _profile(_selfUid, 'Danijel'),
          prediction: _pred(
            userId: _selfUid,
            pt1: 2,
            pt2: 1,
            firstTeamId: _teamA.id,
            scorerId: 4001,
          ),
          score: _score(pm: 5, pft: 2, pgs: 8),
          isSelf: true,
        ),
        // Opponents sorted by points desc, then name asc — mirrors
        // production `buildPredictionRows` ordering exactly so the
        // preview never disagrees with what users see in the wild.
        PredictionRow(
          profile: _profile(_carolUid, 'Carol'),
          prediction: _pred(userId: _carolUid, pt1: 2, pt2: 0),
          score: _score(pm: 2),
        ),
        PredictionRow(
          profile: _profile(_bobUid, 'Bob'),
          prediction: _pred(
            userId: _bobUid,
            pt1: 1,
            pt2: 1,
            firstTeamId: _teamB.id,
          ),
          score: _score(pm: 0, pft: 0),
        ),
        PredictionRow(
          profile: _profile(_doraUid, 'Dora'),
          prediction: _pred(userId: _doraUid, pt1: 0, pt2: 2),
          score: _score(pm: 0),
        ),
      ],
    ),
    // 4. Live · self didn't predict
    _Scenario(
      label: '4. Live · no pred',
      match: _match(
        status: 'live',
        kickoffDelta: const Duration(minutes: -35),
        s1: 1,
        s2: 0,
      ),
      selfPrediction: null,
      rows: [
        const PredictionRow(
          profile: ProfileModel(userId: _selfUid, displayName: 'Danijel'),
          prediction: null,
          score: null,
          isSelf: true,
        ),
        PredictionRow(
          profile: _profile(_bobUid, 'Bob'),
          prediction: _pred(userId: _bobUid, pt1: 1, pt2: 0),
          score: _score(pm: 5),
        ),
        PredictionRow(
          profile: _profile(_carolUid, 'Carol'),
          prediction: _pred(userId: _carolUid, pt1: 2, pt2: 1),
          score: _score(pm: 2),
        ),
      ],
    ),
    // 5. Final · self exact + opponents revealed
    _Scenario(
      label: '5. Final · self exact',
      match: _match(
        status: 'final',
        kickoffDelta: const Duration(hours: -3),
        s1: 2,
        s2: 1,
      ),
      selfPrediction: _pred(
        userId: _selfUid,
        pt1: 2,
        pt2: 1,
        firstTeamId: _teamA.id,
        scorerId: 4001,
      ),
      rows: [
        PredictionRow(
          profile: _profile(_selfUid, 'Danijel'),
          prediction: _pred(
            userId: _selfUid,
            pt1: 2,
            pt2: 1,
            firstTeamId: _teamA.id,
            scorerId: 4001,
          ),
          score: _score(pm: 5, pft: 2, pgs: 8),
          isSelf: true,
        ),
        // Opponents sorted by points desc, name asc — Carol (10) beats
        // Bob (5) beats Dora (0). Matches production `buildPredictionRows`.
        PredictionRow(
          profile: _profile(_carolUid, 'Carol'),
          prediction: _pred(
            userId: _carolUid,
            pt1: 1,
            pt2: 0,
            scorerId: 4001,
          ),
          score: _score(pm: 2, pgs: 8),
        ),
        PredictionRow(
          profile: _profile(_bobUid, 'Bob'),
          prediction: _pred(
            userId: _bobUid,
            pt1: 3,
            pt2: 2,
            firstTeamId: _teamA.id,
          ),
          score: _score(pm: 3, pft: 2),
        ),
        PredictionRow(
          profile: _profile(_doraUid, 'Dora'),
          prediction: _pred(userId: _doraUid, pt1: 0, pt2: 2),
          score: _score(pm: 0),
        ),
      ],
    ),
    // 6. Final · self didn't predict, opponents revealed
    _Scenario(
      label: '6. Final · no pred',
      match: _match(
        status: 'final',
        kickoffDelta: const Duration(hours: -3),
        s1: 3,
        s2: 0,
      ),
      selfPrediction: null,
      rows: [
        const PredictionRow(
          profile: ProfileModel(userId: _selfUid, displayName: 'Danijel'),
          prediction: null,
          score: null,
          isSelf: true,
        ),
        PredictionRow(
          profile: _profile(_bobUid, 'Bob'),
          prediction: _pred(
            userId: _bobUid,
            pt1: 3,
            pt2: 0,
            firstTeamId: _teamA.id,
          ),
          score: _score(pm: 5, pft: 2),
        ),
        PredictionRow(
          profile: _profile(_carolUid, 'Carol'),
          prediction: _pred(userId: _carolUid, pt1: 2, pt2: 1),
          score: _score(pm: 2),
        ),
      ],
    ),
    // 7. Final · solo user (no group-mates)
    _Scenario(
      label: '7. Final · solo',
      match: _match(
        status: 'final',
        kickoffDelta: const Duration(hours: -3),
        s1: 1,
        s2: 1,
      ),
      selfPrediction: _pred(userId: _selfUid, pt1: 1, pt2: 1),
      rows: [
        PredictionRow(
          profile: _profile(_selfUid, 'Danijel'),
          prediction: _pred(userId: _selfUid, pt1: 1, pt2: 1),
          score: _score(pm: 5),
          isSelf: true,
        ),
      ],
    ),
    // 8. Locked · empty list (no participants)
    _Scenario(
      label: '8. Locked · empty',
      match: _match(
        status: 'live',
        kickoffDelta: const Duration(minutes: -35),
        s1: 0,
        s2: 0,
      ),
      selfPrediction: null,
      rows: const [],
    ),
    // 9. Final · ×6 multiplier (Final round)
    _Scenario(
      label: '9. Final ×6',
      match: _match(
        status: 'final',
        kickoffDelta: const Duration(hours: -3),
        s1: 2,
        s2: 1,
        round: 'Final',
      ),
      selfPrediction: _pred(
        userId: _selfUid,
        pt1: 2,
        pt2: 1,
        firstTeamId: _teamA.id,
        scorerId: 4001,
      ),
      rows: [
        PredictionRow(
          profile: _profile(_selfUid, 'Danijel'),
          prediction: _pred(
            userId: _selfUid,
            pt1: 2,
            pt2: 1,
            firstTeamId: _teamA.id,
            scorerId: 4001,
          ),
          score: _score(pm: 5, pft: 2, pgs: 8, mult: 6),
          isSelf: true,
        ),
        PredictionRow(
          profile: _profile(_bobUid, 'Bob'),
          prediction: _pred(userId: _bobUid, pt1: 1, pt2: 0),
          score: _score(pm: 2, mult: 6),
        ),
      ],
    ),
    // 10. QF form · booster NOT applied (toggle off)
    _Scenario(
      label: '10. QF · booster OFF',
      match: _match(
        status: 'scheduled',
        kickoffDelta: const Duration(days: 1),
        round: 'QF',
      ),
      selfPrediction: _pred(
        userId: _selfUid,
        pt1: 2,
        pt2: 1,
        firstTeamId: _teamA.id,
      ),
      rows: const [],
    ),
    // 11. QF form · booster applied (×4 toggle on, applied to this match)
    _Scenario(
      label: '11. QF · booster ×4',
      match: _match(
        status: 'scheduled',
        kickoffDelta: const Duration(days: 1),
        round: 'QF',
      ),
      selfPrediction: _pred(
        userId: _selfUid,
        pt1: 2,
        pt2: 1,
        firstTeamId: _teamA.id,
      ),
      roundBooster: const RoundBoosterModel(
        userId: _selfUid,
        round: 'QF',
        matchId: _matchId,
        multiplier: 4,
      ),
      rows: const [],
    ),
    // 12. QF form · booster currently on a DIFFERENT QF match
    //     Toggle renders in the "warning" state ("Currently on another QF
    //     match"). Tapping it triggers `_BoosterMoveConfirmSheet` which
    //     shows USA vs Canada + the user's 3-1 prediction there.
    _Scenario(
      label: '12. QF · move dialog',
      match: _match(
        status: 'scheduled',
        kickoffDelta: const Duration(days: 1),
        round: 'QF',
      ),
      selfPrediction: _pred(
        userId: _selfUid,
        pt1: 2,
        pt2: 1,
        firstTeamId: _teamA.id,
      ),
      roundBooster: const RoundBoosterModel(
        userId: _selfUid,
        round: 'QF',
        matchId: _otherMatchId, // applied to USA vs Canada, not this one
        multiplier: 4,
      ),
      rows: const [],
    ),
  ];
}

class PredictionsPreviewScreen extends ConsumerStatefulWidget {
  const PredictionsPreviewScreen({super.key, this.initialIndex = 0});

  /// Scenario index to land on at cold start. Set via the
  /// `?scenario=N` (1-indexed) query param on `/dev/predictions-preview`,
  /// which the router converts to 0-indexed. Out-of-range values are
  /// clamped to the first scenario in [initState].
  final int initialIndex;

  @override
  ConsumerState<PredictionsPreviewScreen> createState() =>
      _PredictionsPreviewScreenState();
}

class _PredictionsPreviewScreenState
    extends ConsumerState<PredictionsPreviewScreen> {
  late int _selectedIndex;
  late final List<_Scenario> _scenarios;

  @override
  void initState() {
    super.initState();
    _scenarios = _buildScenarios();
    _selectedIndex = widget.initialIndex
        .clamp(0, _scenarios.length - 1);
  }
  @override
  Widget build(BuildContext context) {
    final scenario = _scenarios[_selectedIndex];
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      // Nested ProviderScope rebuilds the whole MatchDetailScreen with
      // mocked data. Switch scenarios by relaunching with the
      // `?scenario=N` query param (see `/dev/predictions-preview` route).
      body: ProviderScope(
        key: ValueKey<int>(_selectedIndex),
        overrides: scenario.overrides,
        child: const MatchDetailScreen(
          matchId: _matchId,
          initialTab: 'predictions',
        ),
      ),
    );
  }
}
