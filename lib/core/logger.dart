import 'package:talker_flutter/talker_flutter.dart';

/// Global logger instance. Use this everywhere instead of `print` or `debugPrint`.
///
/// In debug builds the logs stream to the console in color.
/// In release builds they are kept in the ring-buffer so the TalkerScreen
/// (accessible from Profile → "View logs") always has recent history.
final talker = TalkerFlutter.init(
  settings: TalkerSettings(
    // Keep last 500 entries in the ring-buffer in all build modes.
    maxHistoryItems: 500,
    // Always enabled — we need logs in release to diagnose field issues.
    enabled: true,
    useConsoleLogs: true,
  ),
);
