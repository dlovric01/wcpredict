// Pure logic for the Teams tab — extracted so it can be unit-tested
// without spinning up a widget tree.
//
// Mirrors the server-side rule from migration 022: a match's lineup is
// considered "confirmed" once `poll_lineups` has populated BOTH
// `formation_team1` and `formation_team2` on the match row. Counting
// `players.is_starter` is not enough — players are upserted by id, so a
// previous match's lineup leaves stale rows that satisfy a count check
// for the wrong fixture. The formation columns are per-match.

import 'package:wcpredict/core/models/match_model.dart';

/// Returns `true` when both teams' formations have been populated by
/// `poll_lineups`. The Teams tab uses this to decide between the
/// placeholder ("Lineups available about 45 minutes before kickoff") and
/// the rendered roster.
bool teamsTabLineupReady(MatchModel match) {
  final f1 = match.formationTeam1;
  final f2 = match.formationTeam2;
  return f1 != null && f1.isNotEmpty && f2 != null && f2.isNotEmpty;
}
