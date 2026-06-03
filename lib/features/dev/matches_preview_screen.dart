// Debug-only preview of `MatchesListScreen` with hand-crafted match +
// booster data so the round-boosters strip and the green-tinted boosted
// match card render without needing live knockout fixtures in the
// production database.
//
// Reachable at `/dev/matches-preview?scenario=N` (1-indexed) when
// kDebugMode. Scenarios cycle through:
//   1. Group stage only — strip hidden, all matches plain
//   2. Knockout scheduled, no boosters applied — strip shows blank rows
//   3. QF booster applied — strip highlights QF row + match card tinted

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/features/matches/matches_list_screen.dart';
import 'package:wcpredict/shared/providers/boosters_provider.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';

const String _selfUid = 'self-uid';

const TeamModel _teamFra = TeamModel(id: 100, name: 'France', code: 'FRA');
const TeamModel _teamBra = TeamModel(id: 200, name: 'Brazil', code: 'BRA');
const TeamModel _teamUsa = TeamModel(id: 300, name: 'United States', code: 'USA');
const TeamModel _teamCan = TeamModel(id: 400, name: 'Canada', code: 'CAN');
const TeamModel _teamEng = TeamModel(id: 500, name: 'England', code: 'ENG');
const TeamModel _teamGer = TeamModel(id: 600, name: 'Germany', code: 'GER');

MatchModel _match({
  required int id,
  required TeamModel t1,
  required TeamModel t2,
  required String round,
  required Duration kickoffDelta,
  String status = 'scheduled',
  int? s1,
  int? s2,
}) =>
    MatchModel(
      id: id,
      team1Id: t1.id,
      team2Id: t2.id,
      team1: t1,
      team2: t2,
      round: round,
      kickoffTime: DateTime.now().add(kickoffDelta),
      status: status,
      scoreFtTeam1: s1,
      scoreFtTeam2: s2,
    );

class _Scenario {
  final String label;
  final List<MatchModel> matches;
  final List<PredictionModel> myPredictions;
  final Map<String, RoundBoosterModel> myBoosters;

  const _Scenario({
    required this.label,
    required this.matches,
    required this.myPredictions,
    required this.myBoosters,
  });

  List<Override> get overrides => [
        allMatchesProvider.overrideWith((_) async => matches),
        myAllPredictionsProvider.overrideWith((_) async => myPredictions),
        myBoostersProvider.overrideWith((_) async => myBoosters),
      ];
}

/// Group-stage fixtures shared across all scenarios. The `status` arg
/// flips between 'scheduled' (group stage in progress, knockout blocked)
/// and 'final' (group stage done, knockout teams known).
List<MatchModel> _groupStage({required String status}) => [
      _match(
        id: 700001,
        t1: _teamFra,
        t2: _teamBra,
        round: 'Matchday 3',
        kickoffDelta: const Duration(days: -1),
        status: status,
        s1: status == 'final' ? 2 : null,
        s2: status == 'final' ? 1 : null,
      ),
      _match(
        id: 700002,
        t1: _teamUsa,
        t2: _teamCan,
        round: 'Matchday 3',
        kickoffDelta: const Duration(days: -1, hours: 3),
        status: status,
        s1: status == 'final' ? 1 : null,
        s2: status == 'final' ? 0 : null,
      ),
      _match(
        id: 700003,
        t1: _teamEng,
        t2: _teamGer,
        round: 'Matchday 3',
        kickoffDelta: const Duration(days: -1, hours: 6),
        status: status,
        s1: status == 'final' ? 3 : null,
        s2: status == 'final' ? 0 : null,
      ),
    ];

/// R16 fixtures. `status` propagates so we can simulate "R16 finished →
/// QF active" by passing 'final' here.
List<MatchModel> _r16({required String status}) => [
      _match(
        id: 800001,
        t1: _teamFra,
        t2: _teamGer,
        round: 'R16',
        kickoffDelta: const Duration(days: 5),
        status: status,
        s1: status == 'final' ? 3 : null,
        s2: status == 'final' ? 1 : null,
      ),
      _match(
        id: 800002,
        t1: _teamUsa,
        t2: _teamEng,
        round: 'R16',
        kickoffDelta: const Duration(days: 5, hours: 4),
        status: status,
        s1: status == 'final' ? 2 : null,
        s2: status == 'final' ? 1 : null,
      ),
    ];

final _qfMatches = <MatchModel>[
  _match(
    id: 800101,
    t1: _teamFra,
    t2: _teamUsa,
    round: 'QF',
    kickoffDelta: const Duration(days: 9),
  ),
  _match(
    id: 800102,
    t1: _teamBra,
    t2: _teamEng,
    round: 'QF',
    kickoffDelta: const Duration(days: 9, hours: 4),
  ),
];

final _sfMatches = <MatchModel>[
  _match(
    id: 800201,
    t1: _teamFra,
    t2: _teamBra,
    round: 'SF',
    kickoffDelta: const Duration(days: 13),
  ),
];

List<_Scenario> _buildScenarios() {
  return [
    // 1. Group stage still in progress → no booster card
    _Scenario(
      label: '1. Group stage live',
      matches: _groupStage(status: 'scheduled'),
      myPredictions: const [],
      myBoosters: const {},
    ),
    // 2. Group stage done, R16 active, no booster applied
    _Scenario(
      label: '2. R16 active',
      matches: [
        ..._groupStage(status: 'final'),
        ..._r16(status: 'scheduled'),
      ],
      myPredictions: const [],
      myBoosters: const {},
    ),
    // 3. R16 active, booster applied to FRA vs GER
    _Scenario(
      label: '3. R16 booster applied',
      matches: [
        ..._groupStage(status: 'final'),
        ..._r16(status: 'scheduled'),
      ],
      myPredictions: const [],
      myBoosters: const {
        'R16': RoundBoosterModel(
          userId: _selfUid,
          round: 'R16',
          matchId: 800001,
          multiplier: 3,
        ),
      },
    ),
    // 4. R16 done, QF active, QF booster applied to FRA vs USA
    _Scenario(
      label: '4. QF booster applied',
      matches: [
        ..._groupStage(status: 'final'),
        ..._r16(status: 'final'),
        ..._qfMatches,
        ..._sfMatches,
      ],
      myPredictions: const [],
      myBoosters: const {
        'QF': RoundBoosterModel(
          userId: _selfUid,
          round: 'QF',
          matchId: 800101,
          multiplier: 4,
        ),
      },
    ),
  ];
}

class MatchesPreviewScreen extends ConsumerStatefulWidget {
  const MatchesPreviewScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<MatchesPreviewScreen> createState() =>
      _MatchesPreviewScreenState();
}

class _MatchesPreviewScreenState
    extends ConsumerState<MatchesPreviewScreen> {
  late int _selectedIndex;
  late final List<_Scenario> _scenarios;

  @override
  void initState() {
    super.initState();
    _scenarios = _buildScenarios();
    _selectedIndex =
        widget.initialIndex.clamp(0, _scenarios.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final scenario = _scenarios[_selectedIndex];
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      // Nested ProviderScope rebuilds the whole MatchesListScreen with
      // mocked data. Switch scenarios by relaunching with the
      // `?scenario=N` query param (see `/dev/matches-preview` route).
      body: ProviderScope(
        key: ValueKey<int>(_selectedIndex),
        overrides: scenario.overrides,
        child: const MatchesListScreen(),
      ),
    );
  }
}
