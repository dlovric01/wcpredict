import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wcpredict/core/logger.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/shared/widgets/app_logo.dart';
import 'package:wcpredict/features/auth/auth_callback_helpers.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  ConsumerState<AuthCallbackScreen> createState() =>
      _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  String? _error;
  Timer? _timeout;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    // Fast path: cold-start where Supabase.initialize already awaited the
    // PKCE exchange before the widget was ever built.
    if (supabase.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/matches');
      });
      return;
    }

    // Listen for the signedIn event whether it comes from supabase_flutter's
    // internal app_links handler (cold-start / some warm-start cases) OR
    // from the manual getSessionFromUrl call below.
    _authSubscription = supabase.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.signedIn) {
          _timeout?.cancel();
          if (mounted) context.go('/matches');
        }
      },
      onError: (Object e) {
        talker.error('[Auth] onAuthStateChange error in callback', e);
        if (mounted) setState(() => _error = _friendlyError(e.toString()));
      },
    );

    // Attempt the PKCE exchange manually.
    //
    // On iOS warm-start (app in background, user taps magic link), the OS
    // delivers the deep link to Flutter's navigator channel but supabase_flutter's
    // app_links stream does not reliably fire — leaving the code unexchanged.
    // We do it ourselves via the URI GoRouter already parsed from the link.
    //
    // If supabase_flutter happens to also do it (cold-start / fixed OS version),
    // one call wins and the other gets an AuthException; the catch block then
    // checks currentSession and navigates if the winner already signed us in.
    WidgetsBinding.instance.addPostFrameCallback((_) => _completeSignIn());

    _timeout = Timer(const Duration(seconds: 12), () {
      if (mounted && _error == null) {
        setState(() => _error =
            'The link may have expired or already been used.\nRequest a new one.');
      }
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _completeSignIn() async {
    final uri = GoRouterState.of(context).uri;
    final params = uri.queryParameters;

    // Flow A: token_hash + type (Supabase "verifyOTP" email template).
    // This is what the wcpredict-auth page sends:
    //   .../auth/callback?token_hash=pkce_xxx&type=magiclink
    final tokenHash = params['token_hash'];
    final typeStr = params['type'];
    if (tokenHash != null && tokenHash.isNotEmpty && typeStr != null) {
      talker.info('[Auth] Verifying OTP token_hash (type=$typeStr)');
      try {
        await supabase.auth.verifyOTP(
          type: _otpType(typeStr),
          tokenHash: tokenHash,
        );
        // signedIn fires → onAuthStateChange listener navigates to /matches.
      } on AuthException catch (e) {
        talker.error('[Auth] verifyOTP failed', e);
        if (supabase.auth.currentSession != null) {
          if (mounted) context.go('/matches');
          return;
        }
        if (mounted) setState(() => _error = _friendlyError(e.message));
      } catch (e, st) {
        talker.handle(e, st, '[Auth] verifyOTP unexpected error');
        if (mounted) setState(() => _error = _friendlyError(e.toString()));
      }
      return;
    }

    // Flow B: ?code= (PKCE authorization-code email template).
    final code = params['code'];
    if (code != null && code.isNotEmpty) {
      talker.info('[Auth] Exchanging PKCE code');
      try {
        await supabase.auth.getSessionFromUrl(uri);
      } on AuthException catch (e) {
        talker.error('[Auth] getSessionFromUrl failed', e);
        if (supabase.auth.currentSession != null) {
          if (mounted) context.go('/matches');
          return;
        }
        if (mounted) setState(() => _error = _friendlyError(e.message));
      } catch (e, st) {
        talker.handle(e, st, '[Auth] getSessionFromUrl unexpected error');
        if (supabase.auth.currentSession != null) {
          if (mounted) context.go('/matches');
          return;
        }
        if (mounted) setState(() => _error = _friendlyError(e.toString()));
      }
      return;
    }

    // Neither token_hash nor code — surface any explicit error the link
    // carried; otherwise supabase_flutter may still deliver via app_links
    // and the onAuthStateChange listener will catch it.
    final errDesc = params['error_description'] ?? params['error'];
    talker.warning('[Auth] Callback URI has no token_hash/code: $uri');
    if (errDesc != null && mounted) {
      setState(() => _error = _friendlyError(errDesc));
    }
  }

  OtpType _otpType(String raw) => parseOtpType(raw);

  String _friendlyError(String raw) => friendlyAuthError(raw);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLogo(size: 64)
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(
                    duration: 1500.ms,
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
              const SizedBox(height: 24),
              Text('Signing you in…', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Just a moment',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              if (_error == null)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: AppRadii.cardRadius,
                    ),
                    child: Text(
                      _error!,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/sign-in'),
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
