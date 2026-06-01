import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logger.dart';

/// Riverpod [ProviderObserver] that routes provider errors and lifecycle events
/// to [talker].
///
/// Registered on [ProviderScope] in main.dart. Errors surface at `error` level;
/// add/dispose at `verbose` (not printed by default — open Talker and enable
/// verbose to see them).
class AppProviderObserver extends ProviderObserver {
  const AppProviderObserver();

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    talker.verbose('[Riverpod +] ${_name(provider)}');
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    talker.verbose('[Riverpod −] ${_name(provider)}');
  }

  /// Called when a provider throws. Always surfaces at error level regardless
  /// of build mode.
  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    talker.error('[Riverpod ✗] ${_name(provider)}', error, stackTrace);
  }

  static String _name(ProviderBase<Object?> p) =>
      p.name ?? p.runtimeType.toString();
}
