// CountdownPill — verifies the formatted countdown label across the three
// branches of `_label`: "Xd Yh" for >= 1 day, "Yh Zm" for >= 1 hour,
// "Zm" for under an hour, and "Started" when target is in the past.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/shared/widgets/countdown_pill.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('CountdownPill', () {
    testWidgets('shows "Started" when target is in the past', (t) async {
      final past = DateTime.now().subtract(const Duration(minutes: 5));
      await t.pumpWidget(_wrap(CountdownPill(target: past)));
      expect(find.text('Started'), findsOneWidget);
    });

    testWidgets('shows minutes only when < 1 hour away', (t) async {
      final soon = DateTime.now().add(const Duration(minutes: 17));
      await t.pumpWidget(_wrap(CountdownPill(target: soon)));
      // Allow some slack for the clock tick during pump
      final text = find.byType(Text).evaluate().single.widget as Text;
      expect(text.data, matches(RegExp(r'^\d+m$')));
      // Should be close to 17m (16 or 17 depending on ms)
      expect(RegExp(r'^(1[567])m$').hasMatch(text.data!), isTrue,
          reason: 'expected ~17m, got "${text.data}"');
    });

    testWidgets('shows "Xh Ym" when 1h ≤ remaining < 1d', (t) async {
      final later = DateTime.now().add(const Duration(hours: 3, minutes: 25));
      await t.pumpWidget(_wrap(CountdownPill(target: later)));
      final text = find.byType(Text).evaluate().single.widget as Text;
      expect(text.data, matches(RegExp(r'^3h \d+m$')),
          reason: 'expected "3h NNm", got "${text.data}"');
    });

    testWidgets('shows "Xd Yh" when ≥ 1 day away', (t) async {
      final daysAway = DateTime.now().add(const Duration(days: 2, hours: 5));
      await t.pumpWidget(_wrap(CountdownPill(target: daysAway)));
      final text = find.byType(Text).evaluate().single.widget as Text;
      expect(text.data, matches(RegExp(r'^2d \d+h$')),
          reason: 'expected "2d Nh", got "${text.data}"');
    });

    testWidgets('disposes its timer without leaking', (t) async {
      // The widget owns a periodic Timer — verify dispose runs cleanly.
      await t.pumpWidget(_wrap(
        CountdownPill(target: DateTime.now().add(const Duration(hours: 1))),
      ));
      await t.pumpWidget(_wrap(const SizedBox.shrink()));
      // If dispose throws, this fails. The empty pump triggers dispose.
      expect(find.byType(CountdownPill), findsNothing);
    });
  });
}
