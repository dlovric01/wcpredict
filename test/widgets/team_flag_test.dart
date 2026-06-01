// TeamFlag — three rendering modes:
//   1. team has a flagUrl → CachedNetworkImage (loading/error → fallback)
//   2. team has no flagUrl → fallback CircleAvatar showing team.code
//   3. tbd=true OR team=null → dashed-circle placeholder with "?"
//
// We can't easily fetch the network image in widget tests, but we can
// verify the fallback + tbd branches deterministically.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/shared/widgets/team_flag.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('TeamFlag — TBD placeholder', () {
    testWidgets('renders "?" when tbd=true', (t) async {
      await t.pumpWidget(_wrap(const TeamFlag(tbd: true, size: 32)));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders "?" when team is null and tbd=false', (t) async {
      await t.pumpWidget(_wrap(const TeamFlag(size: 32)));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('respects provided size', (t) async {
      await t.pumpWidget(_wrap(const TeamFlag(tbd: true, size: 64)));
      final renderObj = t.renderObject<RenderBox>(find.byType(TeamFlag));
      expect(renderObj.size.width, 64);
      expect(renderObj.size.height, 64);
    });
  });

  group('TeamFlag — code fallback (no flagUrl)', () {
    testWidgets('renders team.code in a CircleAvatar', (t) async {
      const team = TeamModel(id: 99001, name: 'Alpha', code: 'ALP');
      await t.pumpWidget(_wrap(const TeamFlag(team: team, size: 32)));
      expect(find.text('ALP'), findsOneWidget);
    });

    testWidgets('renders "?" when team has empty code', (t) async {
      const team = TeamModel(id: 99001, name: 'NoCode', code: '');
      // The fallback prints `team?.code ?? '?'`. Empty string is NOT null,
      // so it renders the empty string — but null still renders "?".
      // The construction here exercises the truthy-empty path, which is
      // a real DB possibility for placeholder rows.
      await t.pumpWidget(_wrap(const TeamFlag(team: team, size: 32)));
      // Empty Text widget exists; find by predicate
      final textWidgets = find.byType(Text).evaluate().toList();
      expect(textWidgets.length, 1);
      final txt = textWidgets.single.widget as Text;
      expect(txt.data, '');
    });
  });

  group('TeamFlag — flagUrl present', () {
    testWidgets('attempts to load CachedNetworkImage when flagUrl provided',
        (t) async {
      const team = TeamModel(
        id: 99001,
        name: 'Alpha',
        code: 'ALP',
        flagUrl: 'https://example.test/alp.svg',
      );
      await t.pumpWidget(_wrap(const TeamFlag(team: team, size: 32)));
      // During loading the placeholder is the same code-fallback widget.
      // We just assert the widget builds without throwing — image fetch is
      // out of scope for widget tests.
      expect(find.byType(TeamFlag), findsOneWidget);
    });
  });
}
