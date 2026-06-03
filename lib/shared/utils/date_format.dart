// Centralised user-facing date formatters.
//
// The app uses 24-hour, day-first European style throughout. These
// helpers exist so any callsite that needs to render a date can do so
// without inventing a new format and drifting from the rest of the UI.
//
// Pure — no `DateTime.now()` reads, no locale switching, no globals.

import 'package:intl/intl.dart';

/// Formats a lock/deadline timestamp like "Thu 11 Jun · 21:00".
///
/// Used everywhere we tell the user when something will close:
/// tournament-pick lock, booster window, prediction lock. Includes the
/// short weekday so the user can place the deadline at a glance
/// without parsing a date.
String formatLockDeadline(DateTime when) =>
    DateFormat('EEE d MMM · HH:mm').format(when.toLocal());

/// Formats a kickoff timestamp for the match detail header, verbose
/// enough to read as a single sentence: "Thursday 11 June 2026 · 21:00".
String formatMatchKickoffVerbose(DateTime when) =>
    DateFormat('EEEE d MMMM yyyy · HH:mm').format(when.toLocal());

/// Formats a kickoff timestamp for compact contexts (match cards, list
/// rows): "11 Jun · 21:00". No weekday — the chip bar / day grouping
/// surfaces day-of-week separately.
String formatMatchKickoffCompact(DateTime when) =>
    DateFormat('d MMM · HH:mm').format(when.toLocal());
