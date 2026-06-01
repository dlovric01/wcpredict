// MatchEventModel — JSON round-trip including the nested `team.code` join,
// plus the `minuteLabel` getter's 4 branches (null / regular / extra-0 /
// stoppage-time). Verify toJson does NOT include `team_code` (it's a join
// projection, not a DB column).
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_event_model.dart';

void main() {
  group('MatchEventModel.fromJson + toJson', () {
    test('round-trips a fully-populated goal event with team join', () {
      final e = MatchEventModel.fromJson({
        'id': 555,
        'match_id': 99203,
        'minute': 12,
        'minute_extra': null,
        'type': 'goal',
        'team_id': 99001,
        'player_id': 99101,
        'player_name': 'Alpha Striker',
        'detail': null,
        'created_at': '2026-06-14T15:12:00.000Z',
        'team': {'code': 'ALP'},
      });
      expect(e.id, 555);
      expect(e.matchId, 99203);
      expect(e.minute, 12);
      expect(e.minuteExtra, isNull);
      expect(e.type, 'goal');
      expect(e.teamId, 99001);
      expect(e.playerId, 99101);
      expect(e.playerName, 'Alpha Striker');
      expect(e.detail, isNull);
      expect(e.teamCode, 'ALP');

      // toJson omits teamCode (it's a join, not a DB column).
      final j = e.toJson();
      expect(
        j.keys.toSet(),
        {
          'id',
          'match_id',
          'minute',
          'minute_extra',
          'type',
          'team_id',
          'player_id',
          'player_name',
          'detail',
          'created_at',
        },
      );
      expect(j.containsKey('team_code'), isFalse);
    });

    test('teamCode is null when team join missing', () {
      final e = MatchEventModel.fromJson({
        'id': 1,
        'match_id': 99203,
        'type': 'goal',
      });
      expect(e.teamCode, isNull);
    });

    test('teamCode is null when team join is non-map (e.g. raw id)', () {
      final e = MatchEventModel.fromJson({
        'id': 1,
        'match_id': 99203,
        'type': 'goal',
        'team': 99001, // non-map
      });
      expect(e.teamCode, isNull);
    });

    test('parses numerics from doubles', () {
      final e = MatchEventModel.fromJson({
        'id': 555.0,
        'match_id': 99203.0,
        'minute': 12.0,
        'minute_extra': 3.0,
        'team_id': 99001.0,
        'player_id': 99101.0,
      });
      expect(e.id, 555);
      expect(e.matchId, 99203);
      expect(e.minute, 12);
      expect(e.minuteExtra, 3);
      expect(e.teamId, 99001);
      expect(e.playerId, 99101);
    });

    test('detail like own_goal round-trips', () {
      final e = MatchEventModel.fromJson({
        'id': 1,
        'match_id': 99203,
        'type': 'goal',
        'detail': 'own_goal',
      });
      expect(e.detail, 'own_goal');
      expect(e.toJson()['detail'], 'own_goal');
    });
  });

  group('MatchEventModel.minuteLabel', () {
    MatchEventModel makeEvent({int? minute, int? minuteExtra}) =>
        MatchEventModel(
          id: 1,
          matchId: 99203,
          minute: minute,
          minuteExtra: minuteExtra,
        );

    test('null minute → em-dash', () {
      expect(makeEvent().minuteLabel, '—');
    });

    test('regular-time minute → "45\'"', () {
      expect(makeEvent(minute: 45).minuteLabel, "45'");
    });

    test('extra=0 treated as no stoppage time (just regular)', () {
      // The model's branch is `minuteExtra! > 0`, so 0 falls through to plain.
      expect(makeEvent(minute: 45, minuteExtra: 0).minuteLabel, "45'");
    });

    test('stoppage time → "90+3\'"', () {
      expect(makeEvent(minute: 90, minuteExtra: 3).minuteLabel, "90+3'");
    });

    test('first-half stoppage → "45+2\'"', () {
      expect(makeEvent(minute: 45, minuteExtra: 2).minuteLabel, "45+2'");
    });
  });
}
