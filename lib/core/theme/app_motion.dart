import 'package:flutter/material.dart';

/// Motion constants for the Stadium Night design system.
abstract final class AppMotion {
  /// Standard — most transitions.
  static const Duration standard = Duration(milliseconds: 200);

  /// Emphasized — modal enter/exit, hero transitions.
  static const Duration emphasized = Duration(milliseconds: 400);

  /// Short — icon swap, chip selection.
  static const Duration short = Duration(milliseconds: 150);

  /// Stagger delay between list items (cap applied at 10 items).
  static const Duration listStagger = Duration(milliseconds: 50);

  /// Slide distance for list entrance animations (dp).
  static const double slideY = 8;

  /// Standard curve.
  static const Curve curve = Curves.easeInOut;

  /// Emphasized curve.
  static const Curve emphasizedCurve = Curves.easeOutCubic;
}
