// Pure formatters / icon mappers used by the live-events timeline. Kept
// in their own file (rather than at the bottom of the widget) so they
// can be exercised by unit tests without instantiating a widget tree.
//
// Event types come from the `match_events.type` column:
//   * 'goal'           — regular-time / extra-time scoring event
//   * 'card'           — yellow / red booking (detail = 'yellow'|'red')
//   * 'subst'          — substitution
//   * 'shootout_kick'  — penalty-shootout kick (only post-FT)
//
// Detail values for goals: `null`, 'penalty', 'own_goal'.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:wcpredict/core/theme/app_colors.dart';

IconData iconForEvent(String? type, String? detail) {
  return switch (type) {
    'goal' => Symbols.sports_soccer,
    'card' => Symbols.square,
    'subst' => Symbols.swap_horiz,
    _ => Symbols.circle,
  };
}

Color colorForEvent(String? type, String? detail) {
  return switch (type) {
    'goal' => AppColors.primary,
    'card' when detail == 'red' => AppColors.error,
    'card' => AppColors.secondary,
    'subst' => AppColors.tertiary,
    _ => AppColors.onSurfaceMuted,
  };
}

/// Human-readable label when `match_events.player_name` is missing (rare —
/// happens when the api-sports.io payload omits the scorer for whatever
/// reason).
String fallbackEventName(String? type, String? detail) {
  if (detail == 'own_goal') return 'Own Goal';
  if (detail == 'penalty') return 'Penalty';
  if (type == 'goal') return 'Goal';
  if (type == 'card' && detail == 'red') return 'Red Card';
  if (type == 'card') return 'Yellow Card';
  if (type == 'subst') return 'Substitution';
  return 'Unknown';
}

/// User-facing string for the `detail` column. Used as a subtitle under
/// the event row.
String formatEventDetail(String detail) {
  switch (detail) {
    case 'own_goal':
      return 'Own Goal';
    case 'penalty':
      return 'Penalty';
    case 'red':
      return 'Red Card';
    case 'yellow':
      return 'Yellow Card';
    default:
      return detail;
  }
}
