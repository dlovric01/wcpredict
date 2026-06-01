import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wcpredict/core/auth_repository.dart';

export 'package:wcpredict/core/auth_repository.dart' show AuthRepository;

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges,
);

final currentUserProvider = Provider<User?>(
  (ref) =>
      ref.watch(authStateProvider).whenData((s) => s.session?.user).valueOrNull,
);

/// The active user's id (or `null` when signed out).
///
/// Every user-scoped [Provider] / [FutureProvider] **MUST** `ref.watch`
/// this rather than reading `supabase.auth.currentUser` directly.
/// Token-refresh events keep the id stable (no re-fetch storm); sign-in
/// and sign-out flip it, which propagates through Riverpod and busts the
/// stale cache from the previous account.
///
/// Returning a [String] (not [User]) keeps the comparison value-based —
/// re-emitting the same user with a refreshed JWT does not trigger
/// dependent providers to re-run.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);
