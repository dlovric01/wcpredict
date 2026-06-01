import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Tabular figure font features — use anywhere scores, ranks, or points appear.
const tabularFigures = [FontFeature.tabularFigures()];

/// Builds the full [TextTheme] for the Stadium Night design system.
///
/// Display/headline → Inter, bold, tight tracking.
/// Body / label → Inter, regular.
/// Every style defaults to [AppColors.onSurface].
TextTheme buildTextTheme() {
  final base = GoogleFonts.interTextTheme().apply(
    bodyColor: AppColors.onSurface,
    displayColor: AppColors.onSurface,
  );

  return base.copyWith(
    // ── Display — wow moments (scores, leaderboard rank) ──────────────────
    displayLarge: base.displayLarge!.copyWith(
      fontSize: 57,
      fontWeight: FontWeight.w900,
      letterSpacing: -2,
      color: AppColors.onSurface,
      fontFeatures: tabularFigures,
    ),
    displayMedium: base.displayMedium!.copyWith(
      fontSize: 45,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
      color: AppColors.onSurface,
      fontFeatures: tabularFigures,
    ),
    displaySmall: base.displaySmall!.copyWith(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      color: AppColors.onSurface,
      fontFeatures: tabularFigures,
    ),

    // ── Headline ──────────────────────────────────────────────────────────
    headlineLarge: base.headlineLarge!.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: AppColors.onSurface,
    ),
    headlineMedium: base.headlineMedium!.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
    ),
    headlineSmall: base.headlineSmall!.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
    ),

    // ── Title ─────────────────────────────────────────────────────────────
    titleLarge: base.titleLarge!.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
    ),
    titleMedium: base.titleMedium!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      color: AppColors.onSurface,
    ),
    titleSmall: base.titleSmall!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: AppColors.onSurface,
    ),

    // ── Body ──────────────────────────────────────────────────────────────
    bodyLarge: base.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurface,
    ),
    bodyMedium: base.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurface,
    ),
    bodySmall: base.bodySmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurfaceVariant,
    ),

    // ── Label ─────────────────────────────────────────────────────────────
    labelLarge: base.labelLarge!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: AppColors.onSurface,
    ),
    labelMedium: base.labelMedium!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: AppColors.onSurface,
    ),
    labelSmall: base.labelSmall!.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: AppColors.onSurfaceVariant,
    ),
  );
}
