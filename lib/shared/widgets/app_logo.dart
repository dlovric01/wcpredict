import 'package:flutter/material.dart';

import 'package:wcpredict/core/theme/app_colors.dart';

/// Stylized WC Predict app logo.
///
/// Rendered as a [CustomPaint] pitch arc (emerald) with an amber dot.
/// Fully scalable via [size].
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Background circle — surfaceHigh
    canvas.drawCircle(
      center,
      r,
      Paint()..color = AppColors.surfaceHigh,
    );

    // Pitch arc — primary (emerald)
    final arcPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: r * 0.62);
    canvas.drawArc(rect, 3.14, 3.14, false, arcPaint);

    // Centre line
    canvas.drawLine(
      Offset(center.dx - r * 0.55, center.dy),
      Offset(center.dx + r * 0.55, center.dy),
      arcPaint,
    );

    // Amber dot — "the ball"
    canvas.drawCircle(
      Offset(center.dx + r * 0.25, center.dy - r * 0.28),
      r * 0.13,
      Paint()..color = AppColors.secondary,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
