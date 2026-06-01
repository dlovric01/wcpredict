import 'package:wcpredict/core/models/match_model.dart';

/// Returns the user-visible minute label for a live match given the
/// current wall-clock time, or null when the match is not in play
/// (scheduled / final / cancelled / kickoff not yet reached).
///
/// The api-sports.io poll does not yet persist the live minute on the
/// matches row, so we derive the label from `kickoff_time` + the
/// 15-minute half-time break. The number a user actually cares about
/// — first/second half + roughly the minute — is always correct; the
/// boundary between 45+stoppage and HT (and 90+stoppage and FT/ET) is
/// approximated with windows that match what api-sports reports within
/// ±1 minute. Once an authoritative `current_minute` field arrives we
/// can swap the body without touching callers.
///
/// Window summary (elapsed minutes since kickoff):
///   * 0..45   → "1'..45'"        (first half)
///   * 45..47  → "45+1'..45+2'"   (first-half stoppage heuristic)
///   * 47..60  → "HT"             (half-time break)
///   * 60..105 → "46'..90'"       (second half; subtracts the 15-min break)
///   * 105..107 → "90+1'..90+2'"  (second-half stoppage heuristic)
///   * 107+     → ET when et fields populated; otherwise keep ticking 90+X
String? formatLiveMinute(MatchModel match, DateTime now) {
  if (match.status != 'live') return null;
  final kickoff = match.kickoffTime;
  if (kickoff == null) return null;
  final secs = now.difference(kickoff).inSeconds;
  if (secs <= 0) return null;
  final mins = secs / 60.0;

  // First half: 0..45.
  if (mins <= 45) {
    final m = mins.floor().clamp(1, 45);
    return "$m'";
  }

  // First-half stoppage window (45..47 elapsed). After that we assume
  // the half-time break has begun.
  if (mins < 47) {
    final extra = (mins - 45).ceil().clamp(1, 9);
    return "45+$extra'";
  }

  // Half-time break: 47..60 elapsed (≈ 13-minute window).
  if (mins < 60) return 'HT';

  // Second half — subtract the 15-minute break to get the displayed
  // minute. Clamp to 46 so the boundary "kickoff of 2H" (elapsed=60,
  // m2h=45) reads as the 46th minute rather than off-by-one to "45'".
  final m2h = mins - 15;
  if (m2h <= 90) {
    return "${m2h.floor().clamp(46, 90)}'";
  }

  // Second-half stoppage window: displayed 90..92.
  if (m2h < 92) {
    final extra = (m2h - 90).ceil().clamp(1, 9);
    return "90+$extra'";
  }

  // Beyond displayed 92': either extended stoppage, or extra time has
  // begun. We promote to ET as soon as the ET score fields exist;
  // otherwise we keep showing "90+X" until the poll catches up.
  final hasEt = match.scoreEtTeam1 != null || match.scoreEtTeam2 != null;
  if (hasEt) {
    return "${m2h.floor().clamp(91, 120)}'";
  }
  final extra = (m2h - 90).ceil().clamp(1, 15);
  return "90+$extra'";
}
