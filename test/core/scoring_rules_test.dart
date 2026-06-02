// Cross-file invariants for the scoring engine constants.
//
// These tests guard the values displayed in the rules screen, the
// computed multipliers on `MatchModel`, and the SQL scoring engine
// (which mirrors the same numbers in migration 017 / 022 / 026).
//
// If any single site drifts, one of these assertions will catch it.

import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/scoring_rules.dart';

void main() {
  group('per-match point categories', () {
    test('rules.md canonical values are preserved', () {
      // If any of these need to change, update rules.md, this test, the
      // SQL migrations, and the rules screen together — and verify the
      // regression suite still passes.
      expect(kPointsExact, 5);
      expect(kPointsGoalDiff, 3);
      expect(kPointsOutcome, 2);
      expect(kPointsFirstTeam, 2);
      expect(kPointsGoalscorer, 8);
    });

    test('max base score is the sum of the awardable categories', () {
      // Match-result categories are mutually exclusive — only the
      // highest fires — so the max contribution from that group is
      // `kPointsExact`. First-team and goalscorer stack on top.
      expect(
        kPointsMaxBase,
        kPointsExact + kPointsFirstTeam + kPointsGoalscorer,
      );
      expect(kPointsMaxBase, 15);
    });

    test('mutually-exclusive match-result categories descend in value', () {
      // Exact > GoalDiff > Outcome > 0. The trigger picks the highest
      // matching category; if this order were violated, awards would
      // collapse to the wrong tier.
      expect(kPointsExact, greaterThan(kPointsGoalDiff));
      expect(kPointsGoalDiff, greaterThan(kPointsOutcome));
      expect(kPointsOutcome, greaterThan(0));
    });
  });

  group('tournament bonuses', () {
    test('canonical values', () {
      expect(kPointsWorldCupWinner, 75);
      expect(kPointsGoldenBoot, 50);
    });

    test('max tournament sum agrees with components', () {
      expect(
        kPointsMaxTournament,
        kPointsWorldCupWinner + kPointsGoldenBoot,
      );
      expect(kPointsMaxTournament, 125);
    });
  });

  group('multiplier tables', () {
    test('booster multipliers cover R32/R16/QF/SF and only those', () {
      expect(kBoosterMultipliers.keys.toSet(), {'R32', 'R16', 'QF', 'SF'});
    });

    test('auto multipliers cover 3rd / Final and only those', () {
      expect(kAutoMultipliers.keys.toSet(), {'3rd', 'Final'});
    });

    test('booster ladder is strictly increasing R32 < R16 < QF < SF', () {
      expect(kBoosterMultipliers['R32']!, lessThan(kBoosterMultipliers['R16']!));
      expect(kBoosterMultipliers['R16']!, lessThan(kBoosterMultipliers['QF']!));
      expect(kBoosterMultipliers['QF']!, lessThan(kBoosterMultipliers['SF']!));
    });

    test('auto multipliers are at least as high as every manual booster', () {
      // The Final's auto ×6 is the largest stake; 3rd-place ×5 ties the
      // SF booster. The invariant is that auto multipliers never fall
      // below the booster ladder — otherwise a manual booster could
      // out-pay an auto-multiplied match.
      final maxBooster = kBoosterMultipliers.values.reduce(
        (a, b) => a > b ? a : b,
      );
      for (final auto in kAutoMultipliers.values) {
        expect(auto, greaterThanOrEqualTo(maxBooster),
            reason: 'auto multiplier must keep pace with booster ladder');
      }
    });

    test('booster and auto sets are disjoint', () {
      final overlap = kBoosterMultipliers.keys.toSet().intersection(
            kAutoMultipliers.keys.toSet(),
          );
      expect(overlap, isEmpty);
    });
  });

  group('MatchModel agrees with scoring_rules constants', () {
    MatchModel m(String round) => MatchModel(id: 1, round: round);

    test('autoMultiplier returns table value for every auto round', () {
      for (final entry in kAutoMultipliers.entries) {
        expect(m(entry.key).autoMultiplier, entry.value,
            reason: 'round ${entry.key}');
      }
    });

    test('boosterMultiplier returns table value for every booster round', () {
      for (final entry in kBoosterMultipliers.entries) {
        expect(m(entry.key).boosterMultiplier, entry.value,
            reason: 'round ${entry.key}');
      }
    });

    test('group-stage matches get no multipliers', () {
      final group = m('Matchday 1');
      expect(group.autoMultiplier, 1);
      expect(group.boosterMultiplier, 1);
      expect(group.isBoosterRound, isFalse);
      expect(group.isKnockout, isFalse);
    });

    test('isBoosterRound is exactly the manual-booster key set', () {
      for (final r in kBoosterMultipliers.keys) {
        expect(m(r).isBoosterRound, isTrue, reason: r);
      }
      for (final r in kAutoMultipliers.keys) {
        expect(m(r).isBoosterRound, isFalse,
            reason: 'auto-multiplier round $r should not be booster-eligible');
      }
    });

    test('isKnockout covers all booster + auto rounds', () {
      for (final r in kBoosterMultipliers.keys) {
        expect(m(r).isKnockout, isTrue, reason: r);
      }
      for (final r in kAutoMultipliers.keys) {
        expect(m(r).isKnockout, isTrue, reason: r);
      }
    });

    test('unknown round defaults to no multiplier', () {
      final unknown = m('GroupOfDeath');
      expect(unknown.autoMultiplier, 1);
      expect(unknown.boosterMultiplier, 1);
      expect(unknown.isKnockout, isFalse);
    });
  });
}
