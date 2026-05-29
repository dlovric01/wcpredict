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
