// Pure logic for the knockout-booster surfaces — extracted so it can be
// unit-tested without spinning up a widget tree.
//
// Two responsibilities:
//   1. `activeBoosterRound` — decides which knockout round, if any, the
//      "apply your booster" card should surface on the matches list. The
//      rule is: the previous bracket stage MUST be fully `final` (so we
//      don't show TBD placeholders) AND the current round MUST still have
//      at least one match that is pre-kickoff (so the user can act).
//   2. `allGroupStageFinal` — gate used by `activeBoosterRound` when the
//      candidate round is R32. Group-stage matches use rounds
//      `Matchday 1/2/3` or the legacy `Group Stage` literal.
//
// Mirrors the UX contract for the booster card in `matches_list_screen.dart`.

import 'package:wcpredict/core/models/match_model.dart';

/// Knockout rounds in bracket order. Surface the booster card for the
/// first round in this list whose previous stage is fully final AND that
/// still has at least one unlocked match.
///
/// `Final` and 3rd-Place are excluded — they use auto-multipliers, never
/// a user-chosen booster.
const List<String> kBoosterRoundsInOrder = ['R32', 'R16', 'QF', 'SF'];

/// Returns the round the booster card should surface for, or `null` when
/// no round is actionable.
///
/// Pure over the supplied match list — no globals, no `DateTime.now()`
/// reads (matches' own `isLocked` is consulted instead).
String? activeBoosterRound(List<MatchModel> matches) {
  for (var i = 0; i < kBoosterRoundsInOrder.length; i++) {
    final round = kBoosterRoundsInOrder[i];
    final roundMatches = matches.where((m) => m.round == round).toList();
    if (roundMatches.isEmpty) continue;

    // Previous stage must have fully finalised so the bracket teams are
    // real. R32's gate is the group stage; later rounds gate on the
    // previous knockout round.
    final prevRoundFinal = i == 0
        ? allGroupStageFinal(matches)
        : matches
            .where((m) => m.round == kBoosterRoundsInOrder[i - 1])
            .every((m) => m.status == 'final');
    if (!prevRoundFinal) continue;

    // At least one match in THIS round must still be pre-kickoff.
    final hasUnlocked = roundMatches.any((m) => !m.isLocked);
    if (!hasUnlocked) continue;

    return round;
  }
  return null;
}

/// `true` when at least one group-stage match exists AND every group-
/// stage match has status `final`. Group-stage rounds are `Matchday 1/2/3`
/// in the production schema; the legacy `Group Stage` literal is accepted
/// for backwards compatibility with seed data.
bool allGroupStageFinal(List<MatchModel> matches) {
  final group = matches.where((m) {
    final r = m.round ?? '';
    return r.startsWith('Matchday') || r == 'Group Stage';
  }).toList();
  if (group.isEmpty) return false;
  return group.every((m) => m.status == 'final');
}
