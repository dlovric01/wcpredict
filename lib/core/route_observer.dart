import 'package:flutter/material.dart';

import 'logger.dart';

/// [NavigatorObserver] that logs route push / pop / replace / remove events
/// to [talker].
///
/// Passed to [GoRouter.observers] in router.dart.
class AppRouteObserver extends NavigatorObserver {
  AppRouteObserver();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    talker.info('[Nav →] push ${_name(route)}'
        '${previousRoute != null ? ' (from ${_name(previousRoute)})' : ''}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    talker.info('[Nav ←] pop  ${_name(route)}'
        '${previousRoute != null ? ' (to ${_name(previousRoute)})' : ''}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    talker.info('[Nav ↺] replace ${_name(oldRoute)} → ${_name(newRoute)}');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    talker.info('[Nav ✕] remove ${_name(route)}');
  }

  static String _name(Route<dynamic>? r) =>
      r?.settings.name ?? r.runtimeType.toString();
}
