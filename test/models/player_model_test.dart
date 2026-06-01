// PlayerModel — JSON round-trip, isStarter default, and nullable lineup
// fields (position/jersey/grid are absent until the lineup is fetched).
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/player_model.dart';

void main() {
  group('PlayerModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final p = PlayerModel.fromJson({
        'id': 99101,
        'team_id': 99001,
        'name': 'Alpha Striker',
        'position': 'FWD',
        'jersey_number': 9,
        'grid': '4:1',
        'is_starter': true,
      });
      expect(p.id, 99101);
      expect(p.teamId, 99001);
      expect(p.name, 'Alpha Striker');
      expect(p.position, 'FWD');
      expect(p.jerseyNumber, 9);
      expect(p.grid, '4:1');
      expect(p.isStarter, isTrue);

      final j = p.toJson();
      expect(j.keys.toSet(), {
        'id',
        'team_id',
        'name',
        'position',
        'jersey_number',
        'grid',
        'is_starter',
      });
      expect(j['team_id'], 99001);
      expect(j['is_starter'], isTrue);
    });

    test('isStarter defaults to true when key absent', () {
      // Model uses `(json['is_starter'] as bool?) ?? true` — the default
      // mirrors the most common case (starting XI fetched without a flag).
      final p = PlayerModel.fromJson({
        'id': 1,
        'team_id': 99001,
        'name': 'X',
      });
      expect(p.isStarter, isTrue);
    });

    test('isStarter respects explicit false (substitute)', () {
      final p = PlayerModel.fromJson({
        'id': 1,
        'team_id': 99001,
        'name': 'Sub',
        'is_starter': false,
      });
      expect(p.isStarter, isFalse);
    });

    test('optional lineup fields tolerate null', () {
      final p = PlayerModel.fromJson({
        'id': 1,
        'team_id': 99001,
        'name': 'X',
      });
      expect(p.position, isNull);
      expect(p.jerseyNumber, isNull);
      expect(p.grid, isNull);
    });

    test('parses numerics from doubles (defensive)', () {
      final p = PlayerModel.fromJson({
        'id': 99101.0,
        'team_id': 99001.0,
        'name': 'X',
        'jersey_number': 9.0,
      });
      expect(p.id, 99101);
      expect(p.teamId, 99001);
      expect(p.jerseyNumber, 9);
    });
  });
}
