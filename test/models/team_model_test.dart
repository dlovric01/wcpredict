// TeamModel — covers JSON round-trip, default code handling, players-join
// parsing, and the intentional omission of `players` from toJson (it lives
// in a separate join and is written via the players table).
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/team_model.dart';

void main() {
  group('TeamModel.fromJson + toJson', () {
    test('round-trips a fully-populated row with nested players', () {
      final t = TeamModel.fromJson({
        'id': 99001,
        'name': 'Alpha',
        'code': 'ALP',
        'flag_url': 'https://example.test/alp.svg',
        'group_letter': 'A',
        'players': [
          {
            'id': 99101,
            'team_id': 99001,
            'name': 'Alpha Striker',
            'position': 'FWD',
            'jersey_number': 9,
            'grid': '4:1',
            'is_starter': true,
          },
        ],
      });
      expect(t.id, 99001);
      expect(t.name, 'Alpha');
      expect(t.code, 'ALP');
      expect(t.flagUrl, 'https://example.test/alp.svg');
      expect(t.groupLetter, 'A');
      expect(t.players, isNotNull);
      expect(t.players!.length, 1);
      expect(t.players!.first.name, 'Alpha Striker');
      expect(t.players!.first.jerseyNumber, 9);

      // toJson intentionally excludes `players` — they come from joins.
      final j = t.toJson();
      expect(j.keys.toSet(),
          {'id', 'name', 'code', 'flag_url', 'group_letter'});
      expect(j['code'], 'ALP');
      expect(j['flag_url'], 'https://example.test/alp.svg');
    });

    test('code defaults to empty string when missing/null', () {
      // Model uses `(json['code'] as String?) ?? ''` — so null code is allowed.
      final t = TeamModel.fromJson({
        'id': 1,
        'name': 'NoCode',
        // 'code' omitted entirely
      });
      expect(t.code, '');
      expect(t.players, isNull);
      expect(t.groupLetter, isNull);
      expect(t.flagUrl, isNull);
    });

    test('players null when key is non-list', () {
      final t = TeamModel.fromJson({
        'id': 1,
        'name': 'X',
        'code': 'XXX',
        'players': 'not-a-list', // model checks `rawPlayers is List`
      });
      expect(t.players, isNull);
    });

    test('parses numerics from doubles (defensive)', () {
      final t = TeamModel.fromJson({
        'id': 99001.0,
        'name': 'X',
        'code': 'XXX',
      });
      expect(t.id, 99001);
    });
  });
}
