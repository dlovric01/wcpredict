import 'package:flutter/material.dart';

/// Corner radii constants for the Stadium Night design system.
abstract final class AppRadii {
  /// Cards and containers — default.
  static const double card = 16;

  /// Bottom sheets, modals — large radius.
  static const double sheet = 24;

  /// Buttons.
  static const double button = 12;

  /// Chips, pills — fully rounded.
  static const double pill = 999;

  // ── Convenience BorderRadius objects ──────────────────────────────────────

  static final cardRadius = BorderRadius.circular(card);
  static final sheetRadius = const BorderRadius.vertical(top: Radius.circular(sheet));
  static final buttonRadius = BorderRadius.circular(button);
  static final pillRadius = BorderRadius.circular(pill);
}
