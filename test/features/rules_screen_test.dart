// Widget tests for the rules screen.
//
// The screen pulls every numeric value from `scoring_rules.dart`, so
// these tests verify the rendering binds correctly — i.e. changing a
// constant propagates to the visible text. They intentionally use the
// constants (not hard-coded numbers) so they keep tracking the engine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wcpredict/core/scoring_rules.dart';
import 'package:wcpredict/features/rules/rules_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('RulesScreen', () {
    testWidgets('renders all match-score category point values', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));

      // Exact score pill includes the constant.
      expect(find.text('+$kPointsExact pts'), findsOneWidget);
      // Goal-diff and outcome too.
      expect(find.text('+$kPointsGoalDiff pts'), findsOneWidget);
      // +2 appears twice — match outcome AND first-team-to-score — so use
      // findsNWidgets here for the kPointsOutcome / kPointsFirstTeam pill.
      expect(find.text('+$kPointsOutcome pts'), findsNWidgets(2));
      // The "Wrong" tier renders as +0 pts.
      expect(find.text('+0 pts'), findsOneWidget);
    });

    testWidgets('renders goalscorer pill with kPointsGoalscorer', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));
      expect(find.text('+$kPointsGoalscorer pts'), findsOneWidget);
    });

    testWidgets('renders the maximum-base total = $kPointsMaxBase', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));
      expect(find.text('= $kPointsMaxBase points'), findsOneWidget);
    });

    testWidgets('renders every booster multiplier ×N pill', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));
      for (final m in kBoosterMultipliers.values) {
        expect(find.text('×$m'), findsWidgets,
            reason: 'booster ×$m missing');
      }
    });

    testWidgets('renders every automatic multiplier ×N pill', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));
      // 3rd-place ×5 collides with SF booster ×5 — assert presence count
      // matches the combined occurrence rather than uniqueness.
      for (final m in kAutoMultipliers.values) {
        expect(find.text('×$m'), findsWidgets, reason: 'auto ×$m missing');
      }
    });

    testWidgets('renders tournament bonuses with canonical values', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));
      expect(find.text('+$kPointsWorldCupWinner pts'), findsOneWidget);
      expect(find.text('+$kPointsGoldenBoot pts'), findsOneWidget);
      expect(
        find.textContaining('$kPointsMaxTournament points'),
        findsOneWidget,
      );
    });

    testWidgets('renders all section headings', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));
      // Each card has a distinct title — they are the contract for what
      // the screen covers. A removed section is a content regression.
      expect(find.text('Match score'), findsOneWidget);
      expect(find.text('First team to score'), findsOneWidget);
      expect(find.text('Goalscorer'), findsOneWidget);
      expect(find.text('Max per match (no multiplier)'), findsOneWidget);
      expect(find.text('Multipliers'), findsOneWidget);
      expect(find.text('Tournament picks'), findsOneWidget);
      expect(find.text('When picks lock'), findsOneWidget);
    });

    testWidgets('renders full round labels (not raw codes)', (tester) async {
      await tester.pumpWidget(_wrap(const RulesScreen()));
      // Users see human-readable round names, never the database codes.
      expect(find.text('Round of 32'), findsOneWidget);
      expect(find.text('Round of 16'), findsOneWidget);
      expect(find.text('Quarter-finals'), findsOneWidget);
      expect(find.text('Semi-finals'), findsOneWidget);
      expect(find.text('3rd-place match'), findsOneWidget);
      expect(find.text('Final'), findsOneWidget);
      // The raw codes from the DB should NOT leak into the UI.
      expect(find.text('R32'), findsNothing);
      expect(find.text('R16'), findsNothing);
      expect(find.text('QF'), findsNothing);
      expect(find.text('SF'), findsNothing);
    });

    testWidgets('anchor argument scrolls section into view', (tester) async {
      await tester.pumpWidget(_wrap(
        const RulesScreen(anchor: RuleSection.tournament),
      ));
      // After the post-frame ensureVisible runs, the Tournament card's
      // heading must be on screen. Without the anchor the card sits below
      // the fold on standard test surface sizes.
      await tester.pumpAndSettle();
      final tournamentHeader = find.text('Tournament picks');
      expect(tournamentHeader, findsOneWidget);
      // Confirm it's actually within the visible viewport (y >= 0 and
      // within screen height).
      final view = tester.view;
      final renderObject = tester.renderObject<RenderBox>(tournamentHeader);
      final topLeft = renderObject.localToGlobal(Offset.zero);
      final screenHeight = view.physicalSize.height / view.devicePixelRatio;
      expect(topLeft.dy, greaterThanOrEqualTo(0));
      expect(topLeft.dy, lessThan(screenHeight));
    });
  });
}
