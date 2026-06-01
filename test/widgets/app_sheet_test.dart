import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';
import 'package:wcpredict/shared/widgets/app_sheet.dart';

/// Regression tests for [AppSheetBody]. The widget owns the two pieces every
/// sheet body in the app got wrong before consolidation:
///
/// 1. Home-indicator inset (`MediaQuery.padding.bottom`) — `showModalBottomSheet`
///    with `useSafeArea: true` wraps the sheet in `SafeArea(bottom: false)`,
///    so this is the body's responsibility.
/// 2. Keyboard inset (`MediaQuery.viewInsets.bottom`) — focused text fields
///    must slide above the on-screen keyboard.
///
/// The body picks the larger of the two so neither case clips content.
void main() {
  Future<Rect> bodyPaddingRect(
    WidgetTester tester, {
    required double safeBottom,
    required double keyboard,
    String? title,
  }) async {
    final key = GlobalKey();
    // Bare Directionality + Material — no Scaffold, because Scaffold's
    // resizeToAvoidBottomInset: true strips viewInsets.bottom from the
    // MediaQuery it forwards to its body, masking what AppSheetBody sees.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(bottom: safeBottom),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: AppSheetBody(
                title: title,
                child: SizedBox(key: key, height: 40),
              ),
            ),
          ),
        ),
      ),
    );
    final inner = tester.getRect(find.byKey(key));
    final outer = tester.getRect(find.byType(AppSheetBody));
    return Rect.fromLTRB(
      inner.left - outer.left,
      inner.top - outer.top,
      outer.right - inner.right,
      outer.bottom - inner.bottom,
    );
  }

  group('AppSheetBody — bottom inset', () {
    testWidgets('home indicator alone → padding includes safe area', (t) async {
      final p = await bodyPaddingRect(t, safeBottom: 34, keyboard: 0);
      // bottom = AppSpacing.lg (24) + safeBottom (34) = 58
      expect(p.bottom, closeTo(AppSpacing.lg + 34, 0.5));
    });

    testWidgets('keyboard up → padding tracks keyboard, ignores safe area',
        (t) async {
      // When the keyboard is up, the system hides the home indicator and
      // viewInsets reports the full keyboard height. padding.bottom is 0.
      final p = await bodyPaddingRect(t, safeBottom: 0, keyboard: 300);
      expect(p.bottom, closeTo(AppSpacing.lg + 300, 0.5));
    });

    testWidgets('keyboard taller than safe area → max wins', (t) async {
      // Defensive: if both are reported simultaneously, we want the larger.
      final p = await bodyPaddingRect(t, safeBottom: 34, keyboard: 300);
      expect(p.bottom, closeTo(AppSpacing.lg + 300, 0.5));
    });

    testWidgets('no inset at all → just AppSpacing.lg', (t) async {
      final p = await bodyPaddingRect(t, safeBottom: 0, keyboard: 0);
      expect(p.bottom, closeTo(AppSpacing.lg, 0.5));
    });
  });

  group('AppSheetBody — horizontal padding', () {
    testWidgets('symmetric AppSpacing.lg on both sides', (t) async {
      final p = await bodyPaddingRect(t, safeBottom: 0, keyboard: 0);
      expect(p.left, closeTo(AppSpacing.lg, 0.5));
      expect(p.right, closeTo(AppSpacing.lg, 0.5));
    });
  });

  group('AppSheetBody — title', () {
    testWidgets('renders title above child when provided', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSheetBody(
              title: 'Create Group',
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(find.text('Create Group'), findsOneWidget);
    });

    testWidgets('omits title row when null', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSheetBody(
              child: const Text('child-only'),
            ),
          ),
        ),
      );
      expect(find.text('child-only'), findsOneWidget);
      // No additional Text widgets beyond the child were rendered.
      expect(find.byType(Text), findsOneWidget);
    });
  });
}
