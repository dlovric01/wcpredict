import 'dart:async';
import 'package:flutter/material.dart';

import 'package:wcpredict/core/theme/app_colors.dart';

/// A live countdown chip that ticks down to [target].
///
/// Displays "X d Y h" for > 24 h, "Y h Z m" for > 1 h, or "Z m" for < 1 h.
/// Stops ticking once [target] is reached.
class CountdownPill extends StatefulWidget {
  const CountdownPill({super.key, required this.target});

  final DateTime target;

  @override
  State<CountdownPill> createState() => _CountdownPillState();
}

class _CountdownPillState extends State<CountdownPill> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  void _tick() {
    final r = widget.target.difference(DateTime.now());
    if (mounted) setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _label {
    final r = _remaining;
    if (r == Duration.zero) return 'Started';
    final days = r.inDays;
    final hours = r.inHours % 24;
    final minutes = r.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${r.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(
        _label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}
