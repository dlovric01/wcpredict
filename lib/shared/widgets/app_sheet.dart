import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';

/// Standard bottom-sheet presenter for wcpredict.
///
/// Inherits background, shape, drag handle, and elevation from
/// `bottomSheetTheme` in `app_theme.dart` — sites must NOT override those
/// here. Enforces the presentation invariants every modal sheet shares:
///
/// - `useRootNavigator: true` — overlays the bottom navigation bar so the
///   sheet feels like a true modal, not a tab-scoped popup.
/// - `useSafeArea: true` — keeps the sheet's top edge below the notch when
///   it grows to full height.
/// - `isScrollControlled: true` — lets content size to its intrinsic height
///   and grow above the on-screen keyboard.
///
/// Pair with [AppSheetBody] for compact forms / action lists, or pass a
/// `DraggableScrollableSheet` for full-height pickers.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    // backgroundColor / shape / showDragHandle / elevation come from
    // BottomSheetThemeData in app_theme.dart — DO NOT override.
    builder: builder,
  );
}

/// Standard body wrapper for compact bottom sheets — forms, action lists,
/// info panes.
///
/// Handles three things every sheet body needs to get right:
///
/// 1. Consistent horizontal padding (`AppSpacing.lg`, 24 dp) so every sheet
///    has the same visual rhythm.
/// 2. Optional title rendered with `titleLarge`, centered under the drag
///    handle.
/// 3. Bottom inset that picks the larger of the on-screen keyboard
///    (`viewInsets.bottom`) and the home-indicator safe area
///    (`padding.bottom`). `showModalBottomSheet(useSafeArea: true)` wraps
///    the sheet in `SafeArea(bottom: false)` — bottom safe area is the
///    body's responsibility, not the modal's.
class AppSheetBody extends StatelessWidget {
  const AppSheetBody({
    super.key,
    this.title,
    required this.child,
  });

  /// Optional title rendered above [child].
  final String? title;

  /// Sheet body content. Use `Column(mainAxisSize: MainAxisSize.min, ...)`
  /// for short forms; wrap longer content in `SingleChildScrollView`.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Keyboard height when focused; home-indicator inset otherwise.
    final bottomInset = math.max(media.viewInsets.bottom, media.padding.bottom);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}
