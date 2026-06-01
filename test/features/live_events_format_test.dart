// Tests the live-events timeline's icon / color / label mappers.
// Branches matter because they're how a user actually reads a match —
// a yellow card being painted red would be alarming.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/features/matches/live_events_format.dart';

void main() {
  group('iconForEvent', () {
    test('goal → soccer ball', () {
      expect(iconForEvent('goal', null), Symbols.sports_soccer);
      expect(iconForEvent('goal', 'penalty'), Symbols.sports_soccer);
      expect(iconForEvent('goal', 'own_goal'), Symbols.sports_soccer);
    });

    test('card → square', () {
      expect(iconForEvent('card', 'yellow'), Symbols.square);
      expect(iconForEvent('card', 'red'), Symbols.square);
    });

    test('subst → swap', () {
      expect(iconForEvent('subst', null), Symbols.swap_horiz);
    });

    test('unknown / null type → fallback circle', () {
      expect(iconForEvent('shootout_kick', null), Symbols.circle);
      expect(iconForEvent(null, null), Symbols.circle);
      expect(iconForEvent('mystery', null), Symbols.circle);
    });
  });

  group('colorForEvent', () {
    test('goal → primary emerald', () {
      expect(colorForEvent('goal', null), AppColors.primary);
    });

    test('red card uses error red, yellow card uses secondary amber', () {
      expect(colorForEvent('card', 'red'), AppColors.error);
      expect(colorForEvent('card', 'yellow'), AppColors.secondary);
      // Detail null falls through to "card" default = secondary
      expect(colorForEvent('card', null), AppColors.secondary);
    });

    test('subst → tertiary blue', () {
      expect(colorForEvent('subst', null), AppColors.tertiary);
    });

    test('unknown → muted', () {
      expect(colorForEvent('shootout_kick', null), AppColors.onSurfaceMuted);
      expect(colorForEvent(null, null), AppColors.onSurfaceMuted);
    });
  });

  group('fallbackEventName', () {
    test('own goal beats everything (even if type=goal)', () {
      // The detail check runs first — protects against unlabelled events
      // where only `detail` is populated.
      expect(fallbackEventName('goal', 'own_goal'), 'Own Goal');
      expect(fallbackEventName(null, 'own_goal'), 'Own Goal');
    });

    test('penalty detail wins over type', () {
      expect(fallbackEventName('goal', 'penalty'), 'Penalty');
    });

    test('plain goal', () {
      expect(fallbackEventName('goal', null), 'Goal');
    });

    test('cards', () {
      expect(fallbackEventName('card', 'red'), 'Red Card');
      expect(fallbackEventName('card', 'yellow'), 'Yellow Card');
      expect(fallbackEventName('card', null), 'Yellow Card');
    });

    test('substitution', () {
      expect(fallbackEventName('subst', null), 'Substitution');
    });

    test('unknown type / null → Unknown', () {
      expect(fallbackEventName(null, null), 'Unknown');
      expect(fallbackEventName('shootout_kick', null), 'Unknown');
    });
  });

  group('formatEventDetail', () {
    test('every known detail key maps to a friendly string', () {
      expect(formatEventDetail('own_goal'), 'Own Goal');
      expect(formatEventDetail('penalty'), 'Penalty');
      expect(formatEventDetail('red'), 'Red Card');
      expect(formatEventDetail('yellow'), 'Yellow Card');
    });

    test('unknown detail string is returned verbatim', () {
      // api-sports.io occasionally invents new detail values; render
      // them raw rather than dropping the event entirely.
      expect(formatEventDetail('handball'), 'handball');
      expect(formatEventDetail(''), '');
    });
  });
}
