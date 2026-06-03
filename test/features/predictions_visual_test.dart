// Visual smoke tests for the merged PREDICTIONS tab. Each test pumps the
// real MatchDetailScreen with every Supabase-touching provider overridden
// by a hand-crafted scenario, then captures the rendered tab as a PNG via
// `matchesGoldenFile`. Run with:
//
//   flutter test --update-goldens test/features/predictions_visual_test.dart
//
// Goldens land under `test/features/goldens/predictions/<scenario>.png`.

import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/prediction_model.dart';
import 'package:wcpredict/core/models/profile_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/theme/app_theme.dart';
import 'package:wcpredict/features/matches/live_scoring.dart';
import 'package:wcpredict/features/matches/match_detail_screen.dart';
import 'package:wcpredict/shared/providers/auth_provider.dart';
import 'package:wcpredict/shared/providers/boosters_provider.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/shared/providers/match_predictions_provider.dart';
import 'package:wcpredict/shared/providers/matches_provider.dart';
import 'package:wcpredict/shared/providers/predictions_provider.dart';

// ── Fixture data ────────────────────────────────────────────────────────────

const _matchId = 999001;
const _selfUid = 'self-uid';
const _bobUid = 'bob-uid';
const _carolUid = 'carol-uid';
const _doraUid = 'dora-uid';

const _teamA = TeamModel(id: 100, name: 'France', code: 'FRA');
const _teamB = TeamModel(id: 200, name: 'Brazil', code: 'BRA');

MatchModel _match({
  required String status,
  required DateTime kickoff,
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
      kickoffTime: kickoff,
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

// ── Scaffolding ─────────────────────────────────────────────────────────────

/// Test-safe clone of `appTheme` that bypasses google_fonts. In the offline
/// test env google_fonts can't fetch Inter, leaving Flutter to substitute
/// the Ahem-style box glyph for every character. Stripping the
/// google-fonts-built TextTheme back to default lets Flutter test's
/// bundled Roboto render real characters.
ThemeData _testTheme() {
  // Force the loaded Roboto onto every TextStyle the appTheme owns —
  // `.apply(fontFamily:)` walks both the textTheme and primaryTextTheme
  // entries and sets the family, but leaves colours / weights / sizes
  // intact so the goldens still look like the production layout.
  return appTheme.copyWith(
    textTheme: appTheme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: appTheme.primaryTextTheme.apply(fontFamily: 'Roboto'),
  );
}

Widget _harness(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: _testTheme(),
        debugShowCheckedModeBanner: false,
        home: const MatchDetailScreen(
          matchId: _matchId,
          initialTab: 'predictions',
        ),
      ),
    );

List<Override> _baseOverrides({
  required MatchModel match,
  required PredictionModel? selfPrediction,
  required List<PredictionRow> rows,
}) =>
    [
      currentUserIdProvider.overrideWith((_) => _selfUid),
      matchByIdProvider(_matchId).overrideWith((_) async => match),
      myPredictionProvider(_matchId)
          .overrideWith((_) async => selfPrediction),
      liveMatchProvider(_matchId).overrideWith((_) => null),
      matchLineupProvider(_matchId).overrideWith((_) async => const []),
      boosterForMatchProvider(_matchId)
          .overrideWith((_) async => null),
      predictionsForMatchProvider(_matchId)
          .overrideWith((_) async => rows),
    ];

Future<void> _capture(
  WidgetTester tester, {
  required List<Override> overrides,
  required String goldenName,
}) async {
  // iPhone-ish portrait canvas so the goldens read like a real screen.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_harness(overrides));
  // pumpAndSettle is unsafe here: matches in `live` status mount
  // `_LiveChip`, whose AnimationController calls `repeat(reverse: true)`
  // — settle would loop forever. A handful of explicit pumps lets the
  // overridden FutureProviders flush their value and the locked layout
  // settle without waiting on the infinite pulse animation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));

  await expectLater(
    find.byType(MatchDetailScreen),
    matchesGoldenFile('goldens/predictions/$goldenName.png'),
  );
}

Future<void> _ensureSupabase() async {
  // Supabase singleton must exist because the global `supabase` getter
  // throws when accessed before `Supabase.initialize`. Dummy URL is fine —
  // we never make a real call because every Supabase-touching provider
  // is overridden below.
  //
  // SharedPreferences is mocked first because Supabase's GoTrue async
  // storage constructor reaches for it during init; without the mock the
  // platform channel throws `MissingPluginException`.
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  try {
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'dummy-anon-key',
      debug: false,
    );
  } catch (_) {
    // Already initialised across tests — fine.
  }
}

/// Load Roboto from the Flutter SDK cache so Text widgets render real
/// glyphs instead of the test framework's box placeholder. The path is
/// derived from `Platform.resolvedExecutable` (the Dart used to run the
/// test) which sits alongside the same SDK's `cache/artifacts/material_fonts`.
Future<void> _loadRoboto() async {
  // The "dart" running the test is actually flutter_tester at:
  //   <flutterRoot>/bin/cache/artifacts/engine/<platform>/flutter_tester
  // material_fonts lives a few levels over at:
  //   <flutterRoot>/bin/cache/artifacts/material_fonts
  // so material_fonts == flutter_tester.parent.parent.parent / 'material_fonts'.
  final exe = File(Platform.resolvedExecutable);
  final fontsDir = '${exe.parent.parent.parent.path}/material_fonts';
  // No SDK fonts available — silent fallback to the box-glyph default.
  if (!Directory(fontsDir).existsSync()) return;
  for (final fileName in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final file = File('$fontsDir/$fileName');
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// Wrapper that registers a visual-smoke test and skips it unless the
/// caller is regenerating goldens (`--update-goldens`) or has opted in
/// via `WC_VISUAL=1`. Without the skip, pixel-perfect comparisons fail
/// intermittently on sub-pixel anti-aliasing drift in default runs.
@isTest
void _visualTest(String name, WidgetTesterCallback body) {
  testWidgets(name, body, skip: !_runVisualSmoke);
}

// Default `flutter test` runs skip this file because golden pixel
// comparisons fail intermittently on sub-pixel anti-aliasing drift.
// Use `flutter test --update-goldens test/features/predictions_visual_test.dart`
// to regenerate the snapshots; set `WC_VISUAL=1` in the env to run the
// pixel comparisons explicitly.
final _runVisualSmoke = const bool.fromEnvironment('WC_VISUAL') ||
    // --update-goldens passes through as an autoUpdateGoldenFiles flag on
    // the binding; when true the comparator writes instead of comparing,
    // so the run is safe regardless of anti-aliasing noise.
    autoUpdateGoldenFiles;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // google_fonts hits the network on first use; the first test that
    // pumps a themed widget eats an "HttpException 400" because the test
    // env's HttpClient stubs everything to 400. After the first failure
    // it transparently falls back to the platform default font. The
    // `_warmup` test below absorbs that first failure so the real tests
    // can rely on the fallback path.
    await _ensureSupabase();
    await _loadRoboto();
  });

  // ── 0. Warm-up — eat the first google_fonts failure ──────────────────────
  // Pumping any themed widget triggers GoogleFonts' first HTTP attempt,
  // which throws in the offline test environment. After this absorbed
  // failure subsequent pumps use the bundled platform fallback silently.
  testWidgets('warmup (absorbs google_fonts first-load failure)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: appTheme,
      home: const SizedBox.shrink(),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    // Failing exceptions from google_fonts are reported through
    // TestWidgetsFlutterBinding's takeException slot; drain it so the
    // test passes.
    tester.takeException();
  });

  // ── 1. Pre-kickoff — empty form ───────────────────────────────────────────
  _visualTest('scheduled · empty form (no prediction yet)', (tester) async {
    final m = _match(
      status: 'scheduled',
      kickoff: DateTime.now().add(const Duration(days: 1)),
    );
    await _capture(
      tester,
      overrides: _baseOverrides(
        match: m,
        selfPrediction: null,
        rows: const [],
      ),
      goldenName: '01_scheduled_form_empty',
    );
  });

  // ── 2. Pre-kickoff — form with an existing pick ───────────────────────────
  _visualTest('scheduled · form with existing prediction', (tester) async {
    final m = _match(
      status: 'scheduled',
      kickoff: DateTime.now().add(const Duration(days: 1)),
    );
    final selfPred =
        _pred(userId: _selfUid, pt1: 2, pt2: 1, firstTeamId: _teamA.id);
    await _capture(
      tester,
      overrides: _baseOverrides(
        match: m,
        selfPrediction: selfPred,
        rows: const [],
      ),
      goldenName: '02_scheduled_form_filled',
    );
  });

  // ── 3. Live — self predicted, opponents hidden ────────────────────────────
  _visualTest('live · self pinned with picks revealed', (tester) async {
    final m = _match(
      status: 'live',
      kickoff: DateTime.now().subtract(const Duration(minutes: 70)),
      s1: 2,
      s2: 1,
    );
    final selfPred = _pred(
      userId: _selfUid,
      pt1: 2,
      pt2: 1,
      firstTeamId: _teamA.id,
      scorerId: 4001,
    );
    final rows = <PredictionRow>[
      PredictionRow(
        profile: _profile(_selfUid, 'Danijel'),
        prediction: selfPred,
        score: _score(pm: 5, pft: 2, pgs: 8),
        isSelf: true,
      ),
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
    ];
    await _capture(
      tester,
      overrides:
          _baseOverrides(match: m, selfPrediction: selfPred, rows: rows),
      goldenName: '03_live_self_full_hit',
    );
  });

  // ── 4. Live — self didn't predict ─────────────────────────────────────────
  _visualTest('live · self placeholder + opponents hidden picks',
      (tester) async {
    final m = _match(
      status: 'live',
      kickoff: DateTime.now().subtract(const Duration(minutes: 35)),
      s1: 1,
      s2: 0,
    );
    final rows = <PredictionRow>[
      PredictionRow(
        profile: _profile(_selfUid, 'Danijel'),
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
    ];
    await _capture(
      tester,
      overrides:
          _baseOverrides(match: m, selfPrediction: null, rows: rows),
      goldenName: '04_live_self_no_prediction',
    );
  });

  // ── 5. Final — self predicted, full breakdown for everyone ───────────────
  _visualTest('final · self exact + opponents revealed', (tester) async {
    final m = _match(
      status: 'final',
      kickoff: DateTime.now().subtract(const Duration(hours: 3)),
      s1: 2,
      s2: 1,
    );
    final selfPred = _pred(
      userId: _selfUid,
      pt1: 2,
      pt2: 1,
      firstTeamId: _teamA.id,
      scorerId: 4001,
    );
    final rows = <PredictionRow>[
      PredictionRow(
        profile: _profile(_selfUid, 'Danijel'),
        prediction: selfPred,
        score: _score(pm: 5, pft: 2, pgs: 8),
        isSelf: true,
      ),
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
    ];
    await _capture(
      tester,
      overrides:
          _baseOverrides(match: m, selfPrediction: selfPred, rows: rows),
      goldenName: '05_final_self_exact',
    );
  });

  // ── 6. Final — self didn't predict ────────────────────────────────────────
  _visualTest('final · self placeholder + opponents revealed',
      (tester) async {
    final m = _match(
      status: 'final',
      kickoff: DateTime.now().subtract(const Duration(hours: 3)),
      s1: 3,
      s2: 0,
    );
    final rows = <PredictionRow>[
      PredictionRow(
        profile: _profile(_selfUid, 'Danijel'),
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
    ];
    await _capture(
      tester,
      overrides:
          _baseOverrides(match: m, selfPrediction: null, rows: rows),
      goldenName: '06_final_self_no_prediction',
    );
  });

  // ── 7. Final · solo user (no group-mates) ─────────────────────────────────
  _visualTest('final · solo user, only self row', (tester) async {
    final m = _match(
      status: 'final',
      kickoff: DateTime.now().subtract(const Duration(hours: 3)),
      s1: 1,
      s2: 1,
    );
    final selfPred = _pred(userId: _selfUid, pt1: 1, pt2: 1);
    final rows = <PredictionRow>[
      PredictionRow(
        profile: _profile(_selfUid, 'Danijel'),
        prediction: selfPred,
        score: _score(pm: 5),
        isSelf: true,
      ),
    ];
    await _capture(
      tester,
      overrides:
          _baseOverrides(match: m, selfPrediction: selfPred, rows: rows),
      goldenName: '07_final_solo_user',
    );
  });

  // ── 8. Empty state — locked but no participants returned ──────────────────
  _visualTest('locked · empty state (zero rows)', (tester) async {
    final m = _match(
      status: 'live',
      kickoff: DateTime.now().subtract(const Duration(minutes: 35)),
      s1: 0,
      s2: 0,
    );
    await _capture(
      tester,
      overrides: _baseOverrides(
        match: m,
        selfPrediction: null,
        rows: const [],
      ),
      goldenName: '08_locked_empty',
    );
  });

  // ── 9. Final round with auto multiplier (×6) ─────────────────────────────
  _visualTest('final · Final round ×6 auto multiplier surfaces in chips',
      (tester) async {
    final m = _match(
      status: 'final',
      kickoff: DateTime.now().subtract(const Duration(hours: 3)),
      s1: 2,
      s2: 1,
      round: 'Final',
    );
    final selfPred = _pred(
      userId: _selfUid,
      pt1: 2,
      pt2: 1,
      firstTeamId: _teamA.id,
      scorerId: 4001,
    );
    final rows = <PredictionRow>[
      PredictionRow(
        profile: _profile(_selfUid, 'Danijel'),
        prediction: selfPred,
        score: _score(pm: 5, pft: 2, pgs: 8, mult: 6),
        isSelf: true,
      ),
      PredictionRow(
        profile: _profile(_bobUid, 'Bob'),
        prediction: _pred(userId: _bobUid, pt1: 1, pt2: 0),
        score: _score(pm: 2, mult: 6),
      ),
    ];
    await _capture(
      tester,
      overrides:
          _baseOverrides(match: m, selfPrediction: selfPred, rows: rows),
      goldenName: '09_final_with_multiplier',
    );
  });
}
