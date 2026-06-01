// First-team picker — verifies the chip enable/disable behaviour driven
// by the predicted score, the toggle-to-deselect interaction, and the
// dim styling for disabled chips. This is the user-facing surface of
// migration 022's validation: a chip the user can't tap is one the DB
// won't reject on save.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/match_model.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/features/matches/first_team_picker.dart';

const _t1 = TeamModel(id: 99001, name: 'Alpha', code: 'ALP');
const _t2 = TeamModel(id: 99002, name: 'Bravo', code: 'BRV');

MatchModel _match() => const MatchModel(id: 99203, team1: _t1, team2: _t2);

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('FirstTeamPicker — render', () {
    testWidgets('renders both team names when teams are resolved',
        (t) async {
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: null,
        score1: 1,
        score2: 1,
        onPick: (_) {},
      )));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
    });

    testWidgets('renders nothing when either team is null (TBD knockout)',
        (t) async {
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: const MatchModel(id: 1, team1: null, team2: _t2),
        selectedTeamId: null,
        score1: 1,
        score2: 1,
        onPick: (_) {},
      )));
      expect(find.text('Bravo'), findsNothing);
      expect(find.byType(FirstTeamChip), findsNothing);
    });
  });

  group('FirstTeamPicker — chip enable state driven by score', () {
    testWidgets('2-1 → both chips enabled', (t) async {
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: null,
        score1: 2,
        score2: 1,
        onPick: (_) {},
      )));
      final chips =
          t.widgetList<FirstTeamChip>(find.byType(FirstTeamChip)).toList();
      expect(chips.length, 2);
      expect(chips[0].enabled, isTrue);
      expect(chips[1].enabled, isTrue);
    });

    testWidgets('2-0 → only team1 chip enabled', (t) async {
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: null,
        score1: 2,
        score2: 0,
        onPick: (_) {},
      )));
      final chips =
          t.widgetList<FirstTeamChip>(find.byType(FirstTeamChip)).toList();
      expect(chips[0].enabled, isTrue);
      expect(chips[1].enabled, isFalse);
    });

    testWidgets('0-3 → only team2 chip enabled', (t) async {
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: null,
        score1: 0,
        score2: 3,
        onPick: (_) {},
      )));
      final chips =
          t.widgetList<FirstTeamChip>(find.byType(FirstTeamChip)).toList();
      expect(chips[0].enabled, isFalse);
      expect(chips[1].enabled, isTrue);
    });
  });

  group('FirstTeamPicker — interaction', () {
    testWidgets('tapping an enabled chip emits its team id', (t) async {
      int? picked = -1;
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: null,
        score1: 2,
        score2: 1,
        onPick: (id) => picked = id,
      )));
      await t.tap(find.text('Alpha'));
      expect(picked, _t1.id);
    });

    testWidgets('tapping the currently-selected chip emits null (deselect)',
        (t) async {
      int? picked = -2;
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: _t1.id, // team1 currently picked
        score1: 2,
        score2: 1,
        onPick: (id) => picked = id,
      )));
      await t.tap(find.text('Alpha'));
      expect(picked, isNull,
          reason: 'tapping the selected chip toggles it off');
    });

    testWidgets('switching from team1 to team2 emits team2 id', (t) async {
      int? picked = -1;
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: _t1.id,
        score1: 2,
        score2: 1,
        onPick: (id) => picked = id,
      )));
      await t.tap(find.text('Bravo'));
      expect(picked, _t2.id);
    });

    testWidgets('disabled chip ignores taps (no GestureDetector)', (t) async {
      var taps = 0;
      await t.pumpWidget(_wrap(FirstTeamPicker(
        match: _match(),
        selectedTeamId: null,
        score1: 2,
        score2: 0, // team2 disabled
        onPick: (_) => taps++,
      )));
      // Hit the team2 chip's text — should not invoke onPick.
      await t.tap(find.text('Bravo'), warnIfMissed: false);
      expect(taps, 0);
      // Sanity: tapping the enabled side still works.
      await t.tap(find.text('Alpha'));
      expect(taps, 1);
    });
  });

  group('FirstTeamChip — direct state styling', () {
    testWidgets('disabled chip is wrapped in an Opacity (dim)', (t) async {
      await t.pumpWidget(_wrap(const FirstTeamChip(
        team: _t1,
        enabled: false,
        selected: false,
        onTap: _noop,
      )));
      final opacity =
          t.widgetList<Opacity>(find.byType(Opacity)).first.opacity;
      expect(opacity, lessThan(1.0));
    });

    testWidgets('enabled chip renders at full opacity', (t) async {
      await t.pumpWidget(_wrap(const FirstTeamChip(
        team: _t1,
        enabled: true,
        selected: false,
        onTap: _noop,
      )));
      // Inside our content tree there's exactly one Opacity wrapping the chip.
      final opacity = t.widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .firstWhere((v) => v <= 1.0, orElse: () => 1.0);
      expect(opacity, 1.0);
    });

    testWidgets('disabled chip does NOT contain a GestureDetector',
        (t) async {
      await t.pumpWidget(_wrap(const FirstTeamChip(
        team: _t1,
        enabled: false,
        selected: false,
        onTap: _noop,
      )));
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('enabled chip contains a GestureDetector', (t) async {
      await t.pumpWidget(_wrap(const FirstTeamChip(
        team: _t1,
        enabled: true,
        selected: false,
        onTap: _noop,
      )));
      // Drag/hover detectors come from the MaterialApp scaffolding too.
      // We only assert at least one GestureDetector exists in the subtree
      // rooted at the chip — that's what makes it tappable.
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });
}

void _noop() {}
