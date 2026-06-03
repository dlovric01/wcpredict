// Pure helpers for the day-filter chip bar on the matches list.
//
// Two responsibilities:
//   1. `buildDayWindow(today)` returns the 7-day window the chip bar
//      surfaces — three days before, today, three days after — as a
//      list of `DateTime` set to local midnight. Centered on today so
//      the user sees the immediate past + immediate future at a glance.
//   2. `filterMatchesByDay(matches, day)` filters matches by local-
//      calendar date. `day == null` means "ALL" and is a passthrough.
//
// Calendar date comparison is intentionally LOCAL: a match kicking off
// at 23:30Z is rendered under "tomorrow" for a UTC+2 viewer because
// that's the date their device shows. The chip labels follow the same
// rule, so chip and card always agree.

import 'package:wcpredict/core/models/match_model.dart';

/// Number of days surfaced on either side of today. Total day chips =
/// `2 * kDayWindowRadius + 1`. The `ALL` chip is rendered separately.
const int kDayWindowRadius = 3;

/// Returns the chip-bar day window as a list of `DateTime` set to local
/// midnight: `[today - radius, …, today, …, today + radius]`. Length is
/// `2 * radius + 1` (7 with the default radius).
List<DateTime> buildDayWindow(DateTime today, {int radius = kDayWindowRadius}) {
  final midnight = DateTime(today.year, today.month, today.day);
  return [
    for (var i = -radius; i <= radius; i++)
      midnight.add(Duration(days: i)),
  ];
}

/// Filters `matches` to those whose kickoff falls on the local calendar
/// date `day`. `day == null` is treated as the "ALL" filter and returns
/// the input untouched. Matches with `kickoffTime == null` (TBD bracket
/// slots) are dropped when a day is selected — there's no calendar date
/// to compare against.
List<MatchModel> filterMatchesByDay(List<MatchModel> matches, DateTime? day) {
  if (day == null) return matches;
  return matches.where((m) {
    final k = m.kickoffTime;
    if (k == null) return false;
    final local = k.toLocal();
    return local.year == day.year &&
        local.month == day.month &&
        local.day == day.day;
  }).toList();
}

/// `true` when the two `DateTime` arguments fall on the same LOCAL
/// calendar date. Used by the chip bar to decide which chip is the
/// "today" chip + which chip is currently selected.
bool isSameLocalDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}
