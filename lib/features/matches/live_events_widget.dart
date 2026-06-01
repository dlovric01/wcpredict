import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wcpredict/core/models/match_event_model.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/providers/match_detail_provider.dart';
import 'package:wcpredict/features/matches/live_events_format.dart';

class LiveEventsWidget extends ConsumerWidget {
  const LiveEventsWidget({super.key, required this.matchId});

  final int matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(matchEventsStreamProvider(matchId));
    final theme = Theme.of(context);

    return eventsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Error loading events: $e',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
      data: (events) {
        if (events.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No events',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: events.length,
          itemBuilder: (context, index) {
            return _EventRow(
              event: events[index],
              isFirst: index == 0,
              isLast: index == events.length - 1,
            )
                .animate(delay: (index * 60).ms)
                .fadeIn(duration: 200.ms)
                .slideX(begin: 0.1, end: 0);
          },
        );
      },
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final MatchEventModel event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGoal = event.type == 'goal';
    final dotColor = colorForEvent(event.type, event.detail);
    final dotRadius = isGoal ? 6.0 : 4.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Minute column
          SizedBox(
            width: 32,
            child: Text(
              event.minuteLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),

          const SizedBox(width: 4),

          // Timeline column
          SizedBox(
            width: 24,
            child: CustomPaint(
              size: const Size(24, 48),
              painter: _TimelinePainter(
                dotColor: dotColor,
                dotRadius: dotRadius,
                lineColor: AppColors.outline,
                drawTop: !isFirst,
                drawBottom: !isLast,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Event card
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: AppRadii.buttonRadius,
              ),
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(
                    iconForEvent(event.type, event.detail),
                    color: dotColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          event.playerName ?? fallbackEventName(event.type, event.detail),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: isGoal
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (event.detail != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            formatEventDetail(event.detail!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (event.teamCode != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      event.teamCode!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.dotColor,
    required this.dotRadius,
    required this.lineColor,
    required this.drawTop,
    required this.drawBottom,
  });

  final Color dotColor;
  final double dotRadius;
  final Color lineColor;
  final bool drawTop;
  final bool drawBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (drawTop) {
      canvas.drawLine(Offset(cx, 0), Offset(cx, cy - dotRadius), linePaint);
    }
    if (drawBottom) {
      canvas.drawLine(
          Offset(cx, cy + dotRadius), Offset(cx, size.height), linePaint);
    }

    // Dot
    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    if (dotRadius > 4) {
      // Larger ring for goals
      final ringPaint = Paint()
        ..color = dotColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), dotRadius + 3, ringPaint);
    }

    canvas.drawCircle(Offset(cx, cy), dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.dotColor != dotColor ||
      old.dotRadius != dotRadius ||
      old.lineColor != lineColor ||
      old.drawTop != drawTop ||
      old.drawBottom != drawBottom;
}

