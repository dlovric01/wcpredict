import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/providers/auth_provider.dart';

/// Handles the deep-link redirect from Supabase after the user taps the
/// magic link in their email.  Navigation to /home is driven by the router's
/// redirect (which listens to auth state changes), so this screen only needs
/// to show a loading state and recover the session from the URL.
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCallback());
  }

  Future<void> _handleCallback() async {
    try {
      final uri = GoRouterState.of(context).uri;
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      // Router redirect will fire automatically via GoRouterRefreshStream once
      // the auth state changes.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen so we navigate as soon as auth state becomes signed-in.
    ref.listen(authStateProvider, (_, next) {
      next.whenData((state) {
        if (state.event == AuthChangeEvent.signedIn && mounted) {
          context.go('/home');
        }
      });
    });

    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 56, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      'Sign-in failed',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => context.go('/sign-in'),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Signing you in…'),
                ],
              ),
      ),
    );
  }
}
