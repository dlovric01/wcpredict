import 'package:wcpredict/core/models/match_model.dart';

/// Returns the user-visible minute label for a live match given the
/// current wall-clock time, or null when the match is not in play
/// (scheduled / final / cancelled / kickoff not yet reached).
///
/// Two sources, in priority order:
///
/// 1. **`match.currentPeriod` + `currentMinute` + `currentMinuteExtra`**
///    written by `poll_live_matches` from api-sports.io
///    `fixture.status.elapsed / extra / short`. Authoritative
///    broadcast minute — what's on the TV bug. Period values:
///      * `1H` / `2H`  — regulation halves, show "$minute'" (with
///        "+extra'" stoppage when present)
///      * `HT`         — half-time break
///      * `ET`         — extra time, show "$minute'"
///      * `BT`         — break time (between regulation and ET)
///      * `P`  / `PEN` — penalty shootout
///      * `INT`        — interrupted
///
/// 2. Wall-clock fallback derived from `kickoff_time` + 15-min
///    half-time-break heuristic. Used when the api fields are stale
///    or absent (e.g. between cron polls, or right after kickoff
///    before the first live poll lands).
String? formatLiveMinute(MatchModel match, DateTime now) {
  if (match.status != 'live') return null;

  // ── Source of truth: api-sports broadcast state ────────────────────
  final period = match.currentPeriod;
  if (period != null && period.isNotEmpty) {
    return _fromBroadcast(
      period: period,
      minute: match.currentMinute,
      extra: match.currentMinuteExtra,
    );
  }

  // ── Fallback: derive from kickoff wall-clock ───────────────────────
  final kickoff = match.kickoffTime;
  if (kickoff == null) return null;
  final secs = now.difference(kickoff).inSeconds;
  if (secs <= 0) return null;
  return _fromElapsed(
    minutes: secs / 60.0,
    hasEt: match.scoreEtTeam1 != null || match.scoreEtTeam2 != null,
  );
}

/// Maps the api-sports broadcast period + minute fields to a UI label.
String _fromBroadcast({
  required String period,
  required int? minute,
  required int? extra,
}) {
  switch (period) {
    case 'HT':
      return 'HT';
    case 'BT':
      return 'BT'; // break before extra time
    case 'P':
    case 'PEN':
      return 'PEN';
    case 'INT':
      return 'INT'; // interrupted (suspended)
    case '1H':
    case '2H':
    case 'ET':
      if (minute == null) return '';
      if (extra != null && extra > 0) return "$minute+$extra'";
      return "$minute'";
    default:
      // Unknown phase — best effort: render minute if we have one.
      if (minute == null) return '';
      if (extra != null && extra > 0) return "$minute+$extra'";
      return "$minute'";
  }
}

/// Wall-clock fallback. Returns a label using the elapsed-minutes
/// since kickoff, with windowed heuristics for half-time and stoppage.
///
/// Window summary (elapsed minutes since kickoff):
///   * 0..45   → "1'..45'"        (first half)
///   * 45..47  → "45+1'..45+2'"   (first-half stoppage heuristic)
///   * 47..60  → "HT"             (half-time break)
///   * 60..105 → "46'..90'"       (second half; subtracts the 15-min break)
///   * 105..107 → "90+1'..90+2'"  (second-half stoppage heuristic)
///   * 107+     → ET when et fields populated; otherwise keep ticking 90+X
String _fromElapsed({required double minutes, required bool hasEt}) {
  if (minutes <= 45) {
    final m = minutes.floor().clamp(1, 45);
    return "$m'";
  }
  if (minutes < 47) {
    final extra = (minutes - 45).ceil().clamp(1, 9);
    return "45+$extra'";
  }
  if (minutes < 60) return 'HT';

  final m2h = minutes - 15;
  if (m2h <= 90) {
    return "${m2h.floor().clamp(46, 90)}'";
  }
  if (m2h < 92) {
    final extra = (m2h - 90).ceil().clamp(1, 9);
    return "90+$extra'";
  }
  if (hasEt) {
    return "${m2h.floor().clamp(91, 120)}'";
  }
  final extra = (m2h - 90).ceil().clamp(1, 15);
  return "90+$extra'";
}
