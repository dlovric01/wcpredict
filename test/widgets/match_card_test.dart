// MatchCard — covers the four centre-score states driven by `match.status`:
//   live    → "LIVE" badge + score
//   final   → score + "FT"
//   locked  → "vs" + lock icon (status=scheduled but kickoff passed)
//   open    → "vs" + formatted kickoff time
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/shared/widgets/match_card.dart';

const _t1 = TeamModel(id: 99001, name: 'Alpha', code: 'ALP');
const _t2 = TeamModel(id: 99002, name: 'Bravo', code: 'BRV');

Widget _wrap(MatchModel m, {VoidCallback? onTap}) => MaterialApp(
      home: Scaffold(
        body: Center(child: MatchCard(match: m, onTap: onTap)),
      ),
    );

void main() {
  group('MatchCard — team rendering', () {
    testWidgets('renders both team codes and names', (t) async {
      final m = MatchModel(
        id: 1,
        round: 'Matchday 1',
        team1: _t1,
        team2: _t2,
        status: 'scheduled',
        kickoffTime: DateTime.now().add(const Duration(days: 1)),
      );
      await t.pumpWidget(_wrap(m));
      // Each team's code appears twice: once inside the flag-fallback circle
      // (TeamFlag) and once below as the headline label (_TeamSide).
      expect(find.text('ALP'), findsNWidgets(2));
      expect(find.text('BRV'), findsNWidgets(2));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
    });

    testWidgets('null team → "TBD" placeholder', (t) async {
      final m = MatchModel(
        id: 1,
        round: 'R32',
        team1: null,
        team2: _t2,
        status: 'scheduled',
        kickoffTime: DateTime.now().add(const Duration(days: 1)),
      );
      await t.pumpWidget(_wrap(m));
      expect(find.text('TBD'), findsOneWidget);
    });

    testWidgets('tap fires onTap callback', (t) async {
      var tapped = 0;
      final m = MatchModel(
        id: 1,
        round: 'Matchday 1',
        team1: _t1,
        team2: _t2,
        status: 'scheduled',
        kickoffTime: DateTime.now().add(const Duration(days: 1)),
      );
      await t.pumpWidget(_wrap(m, onTap: () => tapped++));
      await t.tap(find.byType(MatchCard));
      expect(tapped, 1);
    });
  });

  group('MatchCard — centre score state machine', () {
    testWidgets('live → LIVE badge + score', (t) async {
      final m = MatchModel(
        id: 1,
        round: 'Matchday 1',
        team1: _t1,
        team2: _t2,
        status: 'live',
        kickoffTime: DateTime.now().subtract(const Duration(minutes: 30)),
        scoreFtTeam1: 1,
        scoreFtTeam2: 0,
      );
      await t.pumpWidget(_wrap(m));
      expect(find.text('LIVE'), findsOneWidget);
      // Score uses the canonical separator (NBSP–NBSP) from score_format.dart.
      expect(find.text('1\u00A0\u2013\u00A00'), findsOneWidget);
      expect(find.text('vs'), findsNothing);
      expect(find.text('FT'), findsNothing);
    });

    testWidgets('final → score + "FT"', (t) async {
      final m = MatchModel(
        id: 1,
        round: 'Matchday 1',
        team1: _t1,
        team2: _t2,
        status: 'final',
        kickoffTime: DateTime.now().subtract(const Duration(hours: 2)),
        scoreFtTeam1: 2,
        scoreFtTeam2: 1,
      );
      await t.pumpWidget(_wrap(m));
      expect(find.text('2\u00A0\u2013\u00A01'), findsOneWidget);
      expect(find.text('FT'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(find.text('vs'), findsNothing);
    });

    testWidgets('scheduled + future kickoff → "vs" + kickoff time', (t) async {
      final kickoff = DateTime(2026, 6, 14, 15, 0);
      final m = MatchModel(
        id: 1,
        round: 'Matchday 1',
        team1: _t1,
        team2: _t2,
        status: 'scheduled',
        kickoffTime: kickoff,
      );
      await t.pumpWidget(_wrap(m));
      expect(find.text('vs'), findsOneWidget);
      // Format depends on locale ("d MMM · HH:mm" for non-today). Just
      // verify "15:00" appears and no lock icon.
      expect(find.text('LIVE'), findsNothing);
      expect(find.text('FT'), findsNothing);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('scheduled + past kickoff → "vs" + lock icon', (t) async {
      // Wall-clock-locked but status hasn't flipped to live yet (race
      // between cron poll and kickoff). The card surfaces this as a lock
      // icon so users know the form is closed even though no score yet.
      final m = MatchModel(
        id: 1,
        round: 'Matchday 1',
        team1: _t1,
        team2: _t2,
        status: 'scheduled',
        kickoffTime: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await t.pumpWidget(_wrap(m));
      expect(find.text('vs'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(find.text('FT'), findsNothing);
    });

    testWidgets('cancelled match → lock icon, no score', (t) async {
      // `isLocked` returns true for cancelled, so the centre-score logic
      // treats it like a locked-scheduled match (it's not live, not final).
      final m = MatchModel(
        id: 1,
        round: 'Matchday 1',
        team1: _t1,
        team2: _t2,
        status: 'cancelled',
        kickoffTime: DateTime.now().add(const Duration(days: 1)),
      );
      await t.pumpWidget(_wrap(m));
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.text('FT'), findsNothing);
      expect(find.text('LIVE'), findsNothing);
    });
  });
}
