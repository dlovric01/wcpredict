import 'package:flutter/material.dart';

final wcpredictTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF003082), // FIFA blue
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);
