// TournamentResultsModel — single-row table mirror set by an admin when
// the tournament concludes. Three derived states drive the UI:
//   hasWinner / hasGoldenBoot / isFinalised.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/tournament_results_model.dart';

void main() {
  group('TournamentResultsModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final r = TournamentResultsModel.fromJson({
        'winner_team_id': 99001,
        'golden_boot_player_id': 99101,
        'set_at': '2026-07-19T22:00:00.000Z',
      });
      expect(r.winnerTeamId, 99001);
      expect(r.goldenBootPlayerId, 99101);
      expect(r.setAt?.toUtc().toIso8601String(), '2026-07-19T22:00:00.000Z');

      final j = r.toJson();
      expect(j.keys.toSet(),
          {'winner_team_id', 'golden_boot_player_id', 'set_at'});
    });

    test('all fields tolerate null (pre-tournament empty row)', () {
      final r = TournamentResultsModel.fromJson({});
      expect(r.winnerTeamId, isNull);
      expect(r.goldenBootPlayerId, isNull);
      expect(r.setAt, isNull);
    });

    test('parses numerics from doubles', () {
      final r = TournamentResultsModel.fromJson({
        'winner_team_id': 99001.0,
        'golden_boot_player_id': 99101.0,
      });
      expect(r.winnerTeamId, 99001);
      expect(r.goldenBootPlayerId, 99101);
    });
  });

  group('TournamentResultsModel computed flags', () {
    test('both null → hasWinner=false, hasGoldenBoot=false, isFinalised=false',
        () {
      const r = TournamentResultsModel();
      expect(r.hasWinner, isFalse);
      expect(r.hasGoldenBoot, isFalse);
      expect(r.isFinalised, isFalse);
    });

    test('only winner set → hasWinner=true, isFinalised=true', () {
      const r = TournamentResultsModel(winnerTeamId: 99001);
      expect(r.hasWinner, isTrue);
      expect(r.hasGoldenBoot, isFalse);
      expect(r.isFinalised, isTrue);
    });

    test('only golden boot set → hasGoldenBoot=true, isFinalised=true', () {
      const r = TournamentResultsModel(goldenBootPlayerId: 99101);
      expect(r.hasWinner, isFalse);
      expect(r.hasGoldenBoot, isTrue);
      expect(r.isFinalised, isTrue);
    });

    test('both set → all flags true', () {
      const r = TournamentResultsModel(
        winnerTeamId: 99001,
        goldenBootPlayerId: 99101,
      );
      expect(r.hasWinner, isTrue);
      expect(r.hasGoldenBoot, isTrue);
      expect(r.isFinalised, isTrue);
    });
  });
}
