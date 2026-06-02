import 'package:flutter/material.dart';

import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';

/// Global `ScaffoldMessenger` key attached to `MaterialApp.router`.
///
/// Wiring this at the app root means snackbars survive
/// `context.go(...)` navigations — so an action that succeeds in a modal
/// or detail screen can announce itself on the destination page.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Visual variant of a feedback snackbar.
enum _FeedbackKind { success, error, info }

/// Single entry point for transient UI feedback (snackbars).
///
/// Keeps colors, icons, behavior, and duration consistent across the app
/// and routes through [appMessengerKey] so feedback persists across
/// route transitions.
abstract final class AppFeedback {
  /// Confirmation for a completed user action (prediction saved, joined
  /// group, name updated, …). Green palette.
  static void success(String message) =>
      _show(message, kind: _FeedbackKind.success);

  /// Recoverable failure (network, validation, server). Red palette.
  static void error(String message) =>
      _show(message, kind: _FeedbackKind.error);

  /// Neutral notice (code copied, etc.). Surface palette.
  static void info(String message) =>
      _show(message, kind: _FeedbackKind.info);

  static void _show(String message, {required _FeedbackKind kind}) {
    final messenger = appMessengerKey.currentState;
    if (messenger == null) return;

    final ({Color background, Color foreground, IconData icon}) style =
        switch (kind) {
      _FeedbackKind.success => (
          background: AppColors.primaryContainer,
          foreground: AppColors.onPrimaryContainer,
          icon: Icons.check_circle_outline,
        ),
      _FeedbackKind.error => (
          background: AppColors.errorContainer,
          foreground: AppColors.onErrorContainer,
          icon: Icons.error_outline,
        ),
      _FeedbackKind.info => (
          background: AppColors.surfaceHighest,
          foreground: AppColors.onSurface,
          icon: Icons.info_outline,
        ),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: style.background,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.pillRadius),
          content: Row(
            children: [
              Icon(style.icon, color: style.foreground, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: style.foreground),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
