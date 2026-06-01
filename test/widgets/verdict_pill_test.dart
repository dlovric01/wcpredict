// VerdictPill — covers the label rendering matrix for every combination of
// pointsMatch / pointsFirstTeam / pointsGoalscorer that drives the badge.
//
// The pill is the user's primary at-a-glance signal of how a finalized
// prediction scored; a regression here is immediately visible to every
// user.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/shared/widgets/verdict_pill.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('VerdictPill — pending state', () {
    testWidgets('renders nothing when points are null (not yet scored)', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(points: null)));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('VerdictPill — base match-result verdicts', () {
    testWidgets('exact score → "EXACT +X"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 5,
        pointsMatch: 5,
      )));
      expect(find.text('EXACT +5'), findsOneWidget);
    });

    testWidgets('goal-diff → "GOAL DIFF +3"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 3,
        pointsMatch: 3,
      )));
      expect(find.text('GOAL DIFF +3'), findsOneWidget);
    });

    testWidgets('outcome → "OUTCOME +2"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 2,
        pointsMatch: 2,
      )));
      expect(find.text('OUTCOME +2'), findsOneWidget);
    });

    testWidgets('miss with no bonuses → "MISS +0"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 0,
        pointsMatch: 0,
      )));
      expect(find.text('MISS +0'), findsOneWidget);
    });
  });

  group('VerdictPill — first-team + goalscorer suffixes', () {
    testWidgets('exact + first-team hit → "EXACT • 1ST +7"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 7,
        pointsMatch: 5,
        pointsFirstTeam: 2,
      )));
      expect(find.text('EXACT • 1ST +7'), findsOneWidget);
    });

    testWidgets('exact + goalscorer hit → "EXACT • GS +13"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 13,
        pointsMatch: 5,
        pointsGoalscorer: 8,
      )));
      expect(find.text('EXACT • GS +13'), findsOneWidget);
    });

    testWidgets('exact + both bonuses → "EXACT • 1ST • GS +15"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 15,
        pointsMatch: 5,
        pointsFirstTeam: 2,
        pointsGoalscorer: 8,
      )));
      expect(find.text('EXACT • 1ST • GS +15'), findsOneWidget);
    });

    testWidgets('outcome + first-team only → "OUTCOME • 1ST +4"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 4,
        pointsMatch: 2,
        pointsFirstTeam: 2,
      )));
      expect(find.text('OUTCOME • 1ST +4'), findsOneWidget);
    });
  });

  group('VerdictPill — multiplier suffix', () {
    testWidgets('multiplier shown when > 1', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 30,
        pointsMatch: 5,
        multiplier: 6, // Final auto-multiplier
      )));
      expect(find.text('EXACT ×6 +30'), findsOneWidget);
    });

    testWidgets('multiplier of 1 not shown', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 5,
        pointsMatch: 5,
        multiplier: 1,
      )));
      expect(find.text('EXACT +5'), findsOneWidget);
    });

    testWidgets('multiplier + both bonuses → full suffix chain', (t) async {
      // QF booster ×4 × (5 + 2 + 8) = 60
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 60,
        pointsMatch: 5,
        pointsFirstTeam: 2,
        pointsGoalscorer: 8,
        multiplier: 4,
      )));
      expect(find.text('EXACT ×4 • 1ST • GS +60'), findsOneWidget);
    });
  });

  group('VerdictPill — miss with bonus picks (BONUS branch)', () {
    testWidgets('miss + first-team only → "BONUS • 1ST +2"', (t) async {
      // User predicted wrong direction but the first-team pick still hit.
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 2,
        pointsMatch: 0,
        pointsFirstTeam: 2,
      )));
      expect(find.text('BONUS • 1ST +2'), findsOneWidget);
    });

    testWidgets('miss + goalscorer only → "BONUS • GS +8"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 8,
        pointsMatch: 0,
        pointsGoalscorer: 8,
      )));
      expect(find.text('BONUS • GS +8'), findsOneWidget);
    });

    testWidgets('miss + both bonuses → "BONUS • 1ST • GS +10"', (t) async {
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 10,
        pointsMatch: 0,
        pointsFirstTeam: 2,
        pointsGoalscorer: 8,
      )));
      expect(find.text('BONUS • 1ST • GS +10'), findsOneWidget);
    });

    testWidgets('miss + both bonuses + multiplier ×3 → scaled', (t) async {
      // R16 booster ×3 over 0 + 2 + 8 = 10 → 30
      await t.pumpWidget(_wrap(const VerdictPill(
        points: 30,
        pointsMatch: 0,
        pointsFirstTeam: 2,
        pointsGoalscorer: 8,
        multiplier: 3,
      )));
      expect(find.text('BONUS ×3 • 1ST • GS +30'), findsOneWidget);
    });
  });
}
