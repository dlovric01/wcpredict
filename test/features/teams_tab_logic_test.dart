import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/features/matches/teams_tab_logic.dart';

MatchModel _match({String? f1, String? f2}) {
  return MatchModel(
    id: 1,
    team1Id: 10,
    team2Id: 20,
    team1: const TeamModel(id: 10, name: 'Alpha', code: 'ALP'),
    team2: const TeamModel(id: 20, name: 'Bravo', code: 'BRV'),
    formationTeam1: f1,
    formationTeam2: f2,
  );
}

void main() {
  group('teamsTabLineupReady', () {
    test('false when both formations null', () {
      expect(teamsTabLineupReady(_match()), isFalse);
    });

    test('false when only team1 formation present', () {
      expect(teamsTabLineupReady(_match(f1: '4-3-3')), isFalse);
    });

    test('false when only team2 formation present', () {
      expect(teamsTabLineupReady(_match(f2: '4-2-3-1')), isFalse);
    });

    test('false when a formation is an empty string', () {
      expect(teamsTabLineupReady(_match(f1: '', f2: '4-4-2')), isFalse);
      expect(teamsTabLineupReady(_match(f1: '4-4-2', f2: '')), isFalse);
    });

    test('true when both formations populated', () {
      expect(
        teamsTabLineupReady(_match(f1: '4-3-3', f2: '3-5-2')),
        isTrue,
      );
    });
  });
}
