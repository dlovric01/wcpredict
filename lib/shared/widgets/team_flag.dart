import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wcpredict/core/models/team_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';

/// Circular flag image for a team.
///
/// Falls back to a [CircleAvatar] with the team code when the image fails.
/// When [tbd] is true (team slot not yet resolved), renders a dashed-border
/// placeholder circle with a "?" — never an empty widget.
class TeamFlag extends StatelessWidget {
  const TeamFlag({
    super.key,
    this.team,
    this.size = 32.0,
    this.tbd = false,
    this.tbdLabel,
  });

  /// The team to display. If null and [tbd] is false, renders a "?" placeholder.
  final TeamModel? team;
  final double size;

  /// When true, renders an unresolved-team placeholder regardless of [team].
  final bool tbd;

  /// Optional label under the "?" (e.g., "QF1 winner"). Not rendered inline.
  final String? tbdLabel;

  @override
  Widget build(BuildContext context) {
    if (tbd || team == null) return _tbdPlaceholder(context);

    final flagUrl = team!.flagUrl;
    if (flagUrl != null && flagUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: flagUrl,
        width: size,
        height: size,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: size / 2,
          backgroundImage: imageProvider,
        ),
        errorWidget: (context, url, error) => _fallback(context),
        placeholder: (context, url) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.surfaceHigh,
      child: Text(
        team?.code ?? '?',
        style: TextStyle(
          fontSize: size * 0.3,
          fontWeight: FontWeight.bold,
          color: AppColors.onSurface,
        ),
      ),
    );
  }

  Widget _tbdPlaceholder(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DashedCirclePainter(size: size),
        child: Center(
          child: Text(
            '?',
            style: TextStyle(
              fontSize: size * 0.38,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.size});
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()
      ..color = AppColors.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - 1;

    // Draw dashed circle
    const dashCount = 12;
    const gapFraction = 0.4;
    const twoPi = 2 * 3.14159265;
    final dashAngle = twoPi / dashCount;
    final gapAngle = dashAngle * gapFraction;
    final arcAngle = dashAngle - gapAngle;

    for (var i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        arcAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
