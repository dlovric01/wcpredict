// RoundBoosterModel — one row per (user, round) in public.round_boosters.
// Multipliers follow rules.md: R32=×2, R16=×3, QF=×4, SF=×5.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/round_booster_model.dart';

void main() {
  group('RoundBoosterModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final b = RoundBoosterModel.fromJson({
        'user_id': 'u',
        'round': 'QF',
        'match_id': 99205,
        'multiplier': 4,
        'created_at': '2026-06-14T12:00:00.000Z',
      });
      expect(b.userId, 'u');
      expect(b.round, 'QF');
      expect(b.matchId, 99205);
      expect(b.multiplier, 4);
      expect(b.createdAt?.toUtc().toIso8601String(),
          '2026-06-14T12:00:00.000Z');

      final j = b.toJson();
      expect(j.keys.toSet(),
          {'user_id', 'round', 'match_id', 'multiplier', 'created_at'});
      expect(j['multiplier'], 4);
    });

    test('createdAt null tolerated', () {
      final b = RoundBoosterModel.fromJson({
        'user_id': 'u',
        'round': 'R32',
        'match_id': 1,
        'multiplier': 2,
      });
      expect(b.createdAt, isNull);
      expect(b.toJson()['created_at'], isNull);
    });

    test('parses numerics from doubles', () {
      final b = RoundBoosterModel.fromJson({
        'user_id': 'u',
        'round': 'SF',
        'match_id': 99205.0,
        'multiplier': 5.0,
      });
      expect(b.matchId, 99205);
      expect(b.multiplier, 5);
    });

    test('every knockout-round multiplier survives round-trip', () {
      // R32=2, R16=3, QF=4, SF=5 per rules.md.
      for (final entry in const {'R32': 2, 'R16': 3, 'QF': 4, 'SF': 5}.entries) {
        final b = RoundBoosterModel.fromJson({
          'user_id': 'u',
          'round': entry.key,
          'match_id': 1,
          'multiplier': entry.value,
        });
        expect(b.round, entry.key);
        expect(b.multiplier, entry.value,
            reason: '${entry.key} maps to ×${entry.value}');
      }
    });
  });
}
