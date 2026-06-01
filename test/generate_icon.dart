// One-off icon generator (NOT a unit test — does not match `*_test.dart`
// so it is excluded from `flutter test` by convention).
//
// Run with: flutter test test/generate_icon.dart
// Produces: assets/icon/app_icon.png (1024×1024)
// Then run: dart run flutter_launcher_icons

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wcpredict/shared/widgets/app_logo.dart';

void main() {
  testWidgets('export AppLogo as 1024×1024 app icon PNG', (tester) async {
    const logicalSize = 512.0; // pixelRatio 2.0 → 1024×1024 output
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0E1A),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: logicalSize,
                height: logicalSize,
                color: const Color(0xFF1A2138),
                child: AppLogo(size: logicalSize),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final outDir = Directory('assets/icon');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    final outFile = File('assets/icon/app_icon.png');
    outFile.writeAsBytesSync(bytes);

    // ignore: avoid_print
    print('✓ Icon written to ${outFile.path} '
        '(${image.width}×${image.height}px, ${bytes.length} bytes)');
  });
}
