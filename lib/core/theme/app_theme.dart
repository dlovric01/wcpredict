import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_radii.dart';
import 'app_typography.dart';

/// The single dark [ThemeData] for the wcpredict app ("Stadium Night").
///
/// This is the only theme; light mode is intentionally not supported.
final ThemeData appTheme = _build();

ThemeData _build() {
  final cs = AppColors.colorScheme;
  final tt = buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: cs,
    textTheme: tt,
    scaffoldBackgroundColor: AppColors.surfaceBase,

    // ── AppBar ───────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surfaceBase,
      foregroundColor: AppColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: tt.titleLarge,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.surfaceBase,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),

    // ── Bottom Nav ───────────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.onPrimaryContainer);
        }
        return const IconThemeData(color: AppColors.onSurfaceVariant);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return tt.labelSmall!.copyWith(color: AppColors.onPrimaryContainer);
        }
        return tt.labelSmall!.copyWith(color: AppColors.onSurfaceVariant);
      }),
      elevation: 0,
      height: 64,
    ),

    // ── Cards ────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardRadius,
        side: const BorderSide(color: AppColors.outline, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Chip ─────────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceHigh,
      selectedColor: AppColors.primaryContainer,
      labelStyle: tt.labelMedium,
      side: const BorderSide(color: AppColors.outline),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.pillRadius),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    // ── Buttons ──────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        textStyle: tt.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.onSurface,
        textStyle: tt.labelLarge,
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: tt.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surfaceHigh,
        foregroundColor: AppColors.onSurface,
        textStyle: tt.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
        elevation: 0,
      ),
    ),

    // ── Input / TextField ─────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      hintStyle: tt.bodyMedium!.copyWith(color: AppColors.onSurfaceMuted),
      labelStyle: tt.bodyMedium!.copyWith(color: AppColors.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppRadii.buttonRadius,
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadii.buttonRadius,
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadii.buttonRadius,
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadii.buttonRadius,
        borderSide: const BorderSide(color: AppColors.error),
      ),
    ),

    // ── Bottom Sheet ─────────────────────────────────────────────────────────
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBackgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      showDragHandle: true,
      dragHandleColor: AppColors.outlineVariant,
      elevation: 0,
      modalElevation: 0,
    ),

    // ── Dialog ───────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      titleTextStyle: tt.titleLarge,
      contentTextStyle:
          tt.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 1,
      space: 1,
    ),

    // ── List Tile ────────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      iconColor: AppColors.onSurfaceVariant,
      textColor: AppColors.onSurface,
      subtitleTextStyle: tt.bodySmall,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),

    // ── Icon ─────────────────────────────────────────────────────────────────
    iconTheme: const IconThemeData(color: AppColors.onSurfaceVariant, size: 24),

    // ── Segmented button ─────────────────────────────────────────────────────
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryContainer;
          }
          return AppColors.surfaceHigh;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.onPrimaryContainer;
          }
          return AppColors.onSurfaceVariant;
        }),
        side: WidgetStateProperty.all(
          const BorderSide(color: AppColors.outline),
        ),
      ),
    ),

    // ── Progress / Refresh ───────────────────────────────────────────────────
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
  );
}
