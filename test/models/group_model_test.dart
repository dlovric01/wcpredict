// GroupModel + GroupMemberModel — JSON round-trip + ISO-8601 timestamps.
// Both live in `lib/core/models/group_model.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/group_model.dart';

void main() {
  group('GroupModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final g = GroupModel.fromJson({
        'id': '11111111-2222-3333-4444-555555555555',
        'name': 'Office Pool',
        'owner_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'invite_code': 'WC2026',
        'created_at': '2026-05-01T10:00:00.000Z',
      });
      expect(g.id, '11111111-2222-3333-4444-555555555555');
      expect(g.name, 'Office Pool');
      expect(g.ownerId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(g.inviteCode, 'WC2026');
      expect(g.createdAt?.toUtc().toIso8601String(),
          '2026-05-01T10:00:00.000Z');

      final j = g.toJson();
      expect(
        j.keys.toSet(),
        {'id', 'name', 'owner_id', 'invite_code', 'created_at'},
        reason: 'member_count is only emitted when populated; '
            'this row was parsed without it',
      );
      expect(j['invite_code'], 'WC2026');
      expect(j['created_at'], '2026-05-01T10:00:00.000Z');
    });

    test('parses + serialises member_count when present', () {
      final g = GroupModel.fromJson({
        'id': 'g',
        'name': 'Office Pool',
        'owner_id': 'u',
        'member_count': 7,
      });
      expect(g.memberCount, 7);
      // Numerics-from-double defensive case.
      final g2 = GroupModel.fromJson({
        'id': 'g',
        'name': 'Office Pool',
        'owner_id': 'u',
        'member_count': 7.0,
      });
      expect(g2.memberCount, 7);

      final j = g.toJson();
      expect(j['member_count'], 7);
    });

    test('memberCount absent → omitted from toJson (not just null)', () {
      final g = GroupModel.fromJson({
        'id': 'g',
        'name': 'New Group',
        'owner_id': 'u',
      });
      expect(g.memberCount, isNull);
      expect(g.toJson().containsKey('member_count'), isFalse);
    });

    test('copyWith memberCount only patches the count, leaves rest intact', () {
      final base = GroupModel.fromJson({
        'id': 'g',
        'name': 'New Group',
        'owner_id': 'u',
        'invite_code': 'CODE',
      });
      final patched = base.copyWith(memberCount: 3);
      expect(patched.memberCount, 3);
      expect(patched.id, base.id);
      expect(patched.name, base.name);
      expect(patched.ownerId, base.ownerId);
      expect(patched.inviteCode, base.inviteCode);
    });

    test('tolerates null inviteCode and createdAt', () {
      final g = GroupModel.fromJson({
        'id': 'x',
        'name': 'New Group',
        'owner_id': 'u',
      });
      expect(g.inviteCode, isNull);
      expect(g.createdAt, isNull);
      expect(g.toJson()['invite_code'], isNull);
      expect(g.toJson()['created_at'], isNull);
    });
  });

  group('GroupMemberModel.fromJson + toJson', () {
    test('round-trips a fully-populated row', () {
      final m = GroupMemberModel.fromJson({
        'group_id': 'g-uuid',
        'user_id': 'u-uuid',
        'joined_at': '2026-05-02T09:00:00.000Z',
      });
      expect(m.groupId, 'g-uuid');
      expect(m.userId, 'u-uuid');
      expect(m.joinedAt?.toUtc().toIso8601String(),
          '2026-05-02T09:00:00.000Z');

      final j = m.toJson();
      expect(j.keys.toSet(), {'group_id', 'user_id', 'joined_at'});
      expect(j['joined_at'], '2026-05-02T09:00:00.000Z');
    });

    test('joinedAt null tolerated', () {
      final m = GroupMemberModel.fromJson({
        'group_id': 'g',
        'user_id': 'u',
      });
      expect(m.joinedAt, isNull);
      expect(m.toJson()['joined_at'], isNull);
    });
  });
}
