import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'http_logger.dart';
import 'logger.dart';

SupabaseClient get supabase => Supabase.instance.client;

/// Initialises Supabase and wires up persistent logging for:
///  - every HTTP request/response (via [LoggingHttpClient])
///  - every auth state change (signed-in, signed-out, token refresh, errors)
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    httpClient: LoggingHttpClient(),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Log every auth state transition for the lifetime of the app.
  // This stream never closes, so we intentionally never cancel it.
  supabase.auth.onAuthStateChange.listen(
    (data) {
      talker.info('[Auth] ${data.event.name}'
          '${data.session != null ? ' — user: ${data.session!.user.email}' : ''}');
    },
    onError: (Object e, StackTrace st) {
      talker.error('[Auth] onAuthStateChange error', e, st);
    },
  );
}
