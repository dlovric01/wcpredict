// ProfileModel — simple value object mirroring the public.profiles row.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/profile_model.dart';

void main() {
  group('ProfileModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final p = ProfileModel.fromJson({
        'user_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'display_name': 'Alice',
        'avatar_url': 'https://example.test/alice.png',
        'created_at': '2026-05-01T10:00:00.000Z',
      });
      expect(p.userId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(p.displayName, 'Alice');
      expect(p.avatarUrl, 'https://example.test/alice.png');
      expect(p.createdAt?.toUtc().toIso8601String(),
          '2026-05-01T10:00:00.000Z');

      final j = p.toJson();
      expect(j.keys.toSet(),
          {'user_id', 'display_name', 'avatar_url', 'created_at'});
    });

    test('displayName, avatarUrl, createdAt all tolerate null', () {
      final p = ProfileModel.fromJson({'user_id': 'u'});
      expect(p.displayName, isNull);
      expect(p.avatarUrl, isNull);
      expect(p.createdAt, isNull);
      final j = p.toJson();
      expect(j['display_name'], isNull);
      expect(j['avatar_url'], isNull);
      expect(j['created_at'], isNull);
    });
  });
}
