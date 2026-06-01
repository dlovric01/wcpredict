import 'package:flutter/material.dart';

/// All design-system color tokens for the "Stadium Night" dark theme.
///
/// Rules:
/// - Reference these constants everywhere in the UI layer.
/// - Do NOT use `Colors.X` hardcoded values outside this file.
/// - `AppColors.*` values that have a Material3 semantic equivalent are
///   mirrored in the [ColorScheme] returned by [AppColors.colorScheme].
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surfaces — deepest → highest
  // ---------------------------------------------------------------------------
  static const Color surfaceBase = Color(0xFF0A0E1A); // app background — midnight
  static const Color surface = Color(0xFF11162A); // default cards, sheets
  static const Color surfaceHigh = Color(0xFF1A2138); // raised cards, headers
  static const Color surfaceHighest = Color(0xFF232C49); // modal sheets, selected
  static const Color outline = Color(0xFF2E3656); // hairlines, borders
  static const Color outlineVariant = Color(0xFF404A6B); // secondary dividers

  // ---------------------------------------------------------------------------
  // Primary — Pitch Emerald
  // ---------------------------------------------------------------------------
  static const Color primary = Color(0xFF00C566);
  static const Color onPrimary = Color(0xFF001A0B);
  static const Color primaryContainer = Color(0xFF003D1F);
  static const Color onPrimaryContainer = Color(0xFF6CFFA6);

  // ---------------------------------------------------------------------------
  // Secondary — Goal Amber
  // ---------------------------------------------------------------------------
  static const Color secondary = Color(0xFFFFB627);
  static const Color onSecondary = Color(0xFF271800);
  static const Color secondaryContainer = Color(0xFF4A3000);
  static const Color onSecondaryContainer = Color(0xFFFFDDA1);

  // ---------------------------------------------------------------------------
  // Tertiary — Sky Cobalt (FIFA blue heritage)
  // ---------------------------------------------------------------------------
  static const Color tertiary = Color(0xFF5A8DFF);
  static const Color tertiaryContainer = Color(0xFF1B2D5C);
  static const Color onTertiaryContainer = Color(0xFFC7D7FF);

  // ---------------------------------------------------------------------------
  // Semantic
  // ---------------------------------------------------------------------------
  static const Color error = Color(0xFFFF5C5C);
  static const Color onError = Color(0xFF2D0000);
  static const Color errorContainer = Color(0xFF5C0000);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  static const Color success = primary; // alias
  static const Color warning = secondary; // alias

  /// Pulsing live indicator — red (distinct from success/green).
  static const Color live = Color(0xFFFF3B5C);

  /// Muted lavender-grey for locked predictions.
  static const Color locked = Color(0xFF8B95B8);

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------
  static const Color onSurface = Color(0xFFF5F7FF); // primary text — warm white
  static const Color onSurfaceVariant = Color(0xFFB4BBD6); // secondary text
  static const Color onSurfaceMuted = Color(0xFF7A82A0); // tertiary / disabled

  // ---------------------------------------------------------------------------
  // Medal tiers
  // ---------------------------------------------------------------------------
  static const Color gold = Color(0xFFFFD15A);
  static const Color silver = Color(0xFFC9D4E8);
  static const Color bronze = Color(0xFFE89968);

  // ---------------------------------------------------------------------------
  // Player positions (desaturated for dark readability)
  // ---------------------------------------------------------------------------
  static const Color positionGk = Color(0xFFFFD15A); // amber-gold
  static const Color positionDef = Color(0xFF5A8DFF); // sky cobalt
  static const Color positionMid = Color(0xFF00C566); // pitch emerald
  static const Color positionFwd = Color(0xFFFF6B6B); // warm coral

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the position badge color for a given position string.
  static Color forPosition(String? position) {
    switch (position?.toUpperCase()) {
      case 'GK':
        return positionGk;
      case 'DEF':
        return positionDef;
      case 'MID':
        return positionMid;
      case 'FWD':
        return positionFwd;
      default:
        return onSurfaceMuted;
    }
  }

  /// The Material3 [ColorScheme] that maps these tokens to the standard set.
  static ColorScheme get colorScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onPrimary, // legible on cobalt
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: onSurface,
        onInverseSurface: surfaceBase,
        inversePrimary: primaryContainer,
        surfaceTint: primary,
      );
}
