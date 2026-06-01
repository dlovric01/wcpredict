// TournamentPredictionModel — one row per user with WC winner + Golden Boot
// picks. rules.md: WC winner = 75 pts, Golden Boot = 50 pts, max combined
// = 125 pts. Locked at the opening-match kickoff by a DB trigger.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/tournament_prediction_model.dart';

void main() {
  group('TournamentPredictionModel.fromJson + toJson', () {
    test('round-trips a fully-populated row with both picks awarded', () {
      final p = TournamentPredictionModel.fromJson({
        'user_id': 'u',
        'wc_winner_team_id': 99001,
        'golden_boot_player_id': 99101,
        'points_wc': 75,
        'points_golden_boot': 50,
        'points_earned': 125,
        'created_at': '2026-05-01T10:00:00.000Z',
        'updated_at': '2026-07-19T22:00:00.000Z',
      });
      expect(p.userId, 'u');
      expect(p.wcWinnerTeamId, 99001);
      expect(p.goldenBootPlayerId, 99101);
      expect(p.pointsWc, 75);
      expect(p.pointsGoldenBoot, 50);
      expect(p.pointsEarned, 125);
      expect(p.createdAt?.toUtc().toIso8601String(),
          '2026-05-01T10:00:00.000Z');
      expect(p.updatedAt?.toUtc().toIso8601String(),
          '2026-07-19T22:00:00.000Z');

      final j = p.toJson();
      expect(j.keys.toSet(), {
        'user_id',
        'wc_winner_team_id',
        'golden_boot_player_id',
        'points_wc',
        'points_golden_boot',
        'points_earned',
        'created_at',
        'updated_at',
      });
      expect(j['points_earned'], 125);
    });

    test('user predicted only one (e.g. winner) — other field null', () {
      final p = TournamentPredictionModel.fromJson({
        'user_id': 'u',
        'wc_winner_team_id': 99001,
        // no golden boot
      });
      expect(p.wcWinnerTeamId, 99001);
      expect(p.goldenBootPlayerId, isNull);
      expect(p.pointsWc, 0); // default 0
      expect(p.pointsGoldenBoot, 0); // default 0
      expect(p.pointsEarned, 0); // default 0
    });

    test('parses numerics from doubles', () {
      final p = TournamentPredictionModel.fromJson({
        'user_id': 'u',
        'wc_winner_team_id': 99001.0,
        'golden_boot_player_id': 99101.0,
        'points_wc': 75.0,
        'points_golden_boot': 50.0,
        'points_earned': 125.0,
      });
      expect(p.wcWinnerTeamId, 99001);
      expect(p.goldenBootPlayerId, 99101);
      expect(p.pointsEarned, 125);
    });

    test('empty submission round-trips with all defaults', () {
      final p = TournamentPredictionModel.fromJson({'user_id': 'u'});
      expect(p.wcWinnerTeamId, isNull);
      expect(p.goldenBootPlayerId, isNull);
      expect(p.pointsWc, 0);
      expect(p.pointsGoldenBoot, 0);
      expect(p.pointsEarned, 0);
      expect(p.createdAt, isNull);
      expect(p.updatedAt, isNull);
    });
  });
}
