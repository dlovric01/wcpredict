import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'core/logger.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'router.dart';

class WcPredictApp extends StatelessWidget {
  const WcPredictApp({super.key});

  @override
  Widget build(BuildContext context) {
    return TalkerWrapper(
      talker: talker,
      options: const TalkerWrapperOptions(
        enableErrorAlerts: true,
      ),
      child: GestureDetector(
        // Dismiss the keyboard when the user taps outside any focused widget.
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: MaterialApp.router(
          title: 'WC2026 Predict',
          theme: appTheme,
          darkTheme: appTheme,
          themeMode: ThemeMode.dark,
          routerConfig: appRouter,
          debugShowCheckedModeBanner: false,
          // builder runs above the Navigator — the Stack here is always present
          // regardless of which route is active.
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (kDebugMode) const _LogFab(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small draggable floating button that opens [TalkerScreen].
///
/// Positioned in the bottom-right corner by default and draggable so it never
/// blocks content. Works in both debug and release builds.
class _LogFab extends StatefulWidget {
  const _LogFab();

  @override
  State<_LogFab> createState() => _LogFabState();
}

class _LogFabState extends State<_LogFab> {
  static const double _size = 40;
  static const double _initRight = 12;
  // Bottom-anchored: sits above the navigation bar
  static const double _initBottom = 88.0;

  double _right = _initRight;
  double _bottom = _initBottom;

  void _open() {
    appRouter.routerDelegate.navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => TalkerScreen(talker: talker),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Positioned(
      right: _right,
      bottom: _bottom + mq.padding.bottom,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _right = (_right - details.delta.dx)
                .clamp(0, mq.size.width - _size);
            _bottom = (_bottom - details.delta.dy)
                .clamp(0, mq.size.height - _size);
          });
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _open,
            borderRadius: BorderRadius.circular(_size / 2),
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                // Slightly transparent so it's less obtrusive
                color: AppColors.surfaceHighest.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outlineVariant, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.terminal_rounded,
                size: 18,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
