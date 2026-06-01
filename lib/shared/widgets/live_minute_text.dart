import 'dart:async';

import 'package:flutter/material.dart';

/// Live minute counter for a match in play.
///
/// Computes `(now - kickoff).inMinutes` and ticks every 30 s so the
/// label stays current without waiting for the next Realtime push from
/// poll_live_matches. Renders nothing if the kickoff is unknown or the
/// match is not actually live.
///
/// Output:
/// - `0'` immediately after kickoff
/// - `n'` while the elapsed time is in [0, 90]
/// - `90+` once past 90 (we can't tell first-half vs second-half
///   stoppage from the data; the wider score row already shows HT, so
///   a clamped 90+ is honest)
class LiveMinuteText extends StatefulWidget {
  const LiveMinuteText({
    super.key,
    required this.kickoff,
    required this.status,
    this.style,
  });

  final DateTime? kickoff;
  final String? status;
  final TextStyle? style;

  @override
  State<LiveMinuteText> createState() => _LiveMinuteTextState();
}

class _LiveMinuteTextState extends State<LiveMinuteText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(LiveMinuteText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) {
      _timer?.cancel();
      _start();
    }
  }

  void _start() {
    if (widget.status != 'live') return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? _label() {
    if (widget.status != 'live' || widget.kickoff == null) return null;
    final elapsed = DateTime.now().difference(widget.kickoff!).inMinutes;
    if (elapsed < 0) return "0'";
    if (elapsed > 90) return "90+'";
    return "$elapsed'";
  }

  @override
  Widget build(BuildContext context) {
    final label = _label();
    if (label == null) return const SizedBox.shrink();
    return Text(label, style: widget.style);
  }
}
