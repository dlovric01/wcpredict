import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' hide IconAlignment;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:wcpredict/core/auth_repository.dart';
import 'package:wcpredict/core/logger.dart';
import 'package:wcpredict/core/supabase_client.dart';
import 'package:wcpredict/core/theme/app_colors.dart';
import 'package:wcpredict/core/theme/app_radii.dart';
import 'package:wcpredict/core/theme/app_spacing.dart';
import 'package:wcpredict/shared/widgets/app_logo.dart';
class SocialSignInScreen extends StatefulWidget {
  const SocialSignInScreen({super.key});

  @override
  State<SocialSignInScreen> createState() => _SocialSignInScreenState();
}

class _SocialSignInScreenState extends State<SocialSignInScreen> {
  final _repo = AuthRepository();
  bool _loading = false;

  Future<void> _signInWithApple() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _repo.signInWithApple();
      // Router redirect listens to auth state and sends us to /matches.
    } catch (e, st) {
      talker.handle(e, st, 'Apple Sign-In failed');
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _repo.signInWithGoogle();
      // Router redirect listens to auth state and sends us to /matches.
    } catch (e, st) {
      talker.handle(e, st, 'Google Sign-In failed');
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Debug-only quick login that signs in with the regression-suite
  /// test credentials. Signs up on first use (the project allows
  /// anonymous signup with email confirmation off), then signs in.
  ///
  /// Only wired up when `kDebugMode` is true — release builds never
  /// see this code path.
  Future<void> _devQuickLogin(String name) async {
    if (_loading) return;
    setState(() => _loading = true);
    final email = '$name@wctest.invalid';
    const password = 'TestPass99!';
    try {
      try {
        await supabase.auth
            .signInWithPassword(email: email, password: password);
      } on AuthException catch (e) {
        // Invalid login → create the account first, then sign in. The
        // project has signup enabled with email confirmations off so
        // the new session lands immediately.
        if (e.statusCode == '400' || e.statusCode == '401') {
          await supabase.auth.signUp(
            email: email,
            password: password,
            data: {'display_name': name},
          );
          if (supabase.auth.currentSession == null) {
            await supabase.auth
                .signInWithPassword(email: email, password: password);
          }
        } else {
          rethrow;
        }
      }
    } catch (e, st) {
      talker.handle(e, st, 'Dev login failed');
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    final message = _friendlyError(e);
    // Silent cancel — don't pester the user.
    if (message == null) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
        ),
      );
  }

  /// Returns `null` for cancellations (no snackbar shown for those).
  String? _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('cancel')) return null;
    if (s.contains('network') ||
        s.contains('socket') ||
        s.contains('connection')) {
      return 'Network error — check your connection and try again.';
    }
    if (s.contains('rate') || s.contains('too many')) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    return 'Sign-in failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final showApple = Platform.isIOS || Platform.isMacOS;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Center(child: AppLogo(size: 100))
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scale(
                      begin: const Offset(0.8, 0.8),
                      duration: 400.ms,
                      curve: Curves.easeOut),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'WC2026 Predict',
                style: tt.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 80.ms, duration: 400.ms),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Pick scores. Compete with friends.',
                style:
                    tt.bodyLarge?.copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 140.ms, duration: 400.ms),
              const SizedBox(height: AppSpacing.xxl),
              const SizedBox(height: AppSpacing.xl),
              if (showApple) ...[
                _AppleButton(onPressed: _loading ? null : _signInWithApple)
                    .animate()
                    .fadeIn(delay: 260.ms, duration: 400.ms)
                    .slideY(begin: 0.1, end: 0, duration: 400.ms),
                const SizedBox(height: AppSpacing.md),
              ],
              _GoogleButton(onPressed: _loading ? null : _signInWithGoogle)
                  .animate()
                  .fadeIn(delay: showApple ? 320.ms : 260.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0, duration: 400.ms),
              if (_loading) ...[
                const SizedBox(height: AppSpacing.lg),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              if (kDebugMode) ...[
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: AppRadii.cardRadius,
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'DEV QUICK LOGIN',
                        textAlign: TextAlign.center,
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          for (final name in const ['alice', 'bob', 'charlie'])
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: name == 'bob' ? 4 : 0,
                                ),
                                child: OutlinedButton(
                                  onPressed: _loading
                                      ? null
                                      : () => _devQuickLogin(name),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.secondary,
                                    side: BorderSide(
                                      color: AppColors.secondary
                                          .withValues(alpha: 0.5),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                  ),
                                  child: Text(
                                    name[0].toUpperCase() + name.substring(1),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'By signing in, you agree to our Terms of Service and Privacy Policy',
                style: tt.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared height for both social sign-in buttons.
///
/// 50 dp gives a comfortable tap target while keeping `sign_in_with_apple`'s
/// internal text size (height × 0.43 ≈ 21.5 pt) refined rather than chunky.
/// Both buttons share this so they sit as a visually consistent pair.
const double _kAuthButtonHeight = 50;

/// Width of the leading icon column. Mirrors `sign_in_with_apple`'s
/// `_appleIconSizeScale = 28/44`, so the Apple logo and the Google "G"
/// occupy the same left-aligned column.
const double _kAuthIconColWidth = _kAuthButtonHeight * (28 / 44);

/// Font size for button labels. Matches `sign_in_with_apple`'s `height * 0.43`
/// so the Apple and Google labels render at the exact same size.
const double _kAuthFontSize = _kAuthButtonHeight * 0.43;

/// Apple's HIG-compliant Sign in with Apple button.
///
/// Uses [SignInWithAppleButton] from the `sign_in_with_apple` package so the
/// button complies with Apple's branding requirements (App Store Review
/// Guideline 4.8). White on dark surface, SF Pro text, Apple logomark pinned
/// to the left so the label is optically centered.
class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kAuthButtonHeight,
      child: SignInWithAppleButton(
        onPressed: onPressed ?? () {},
        style: SignInWithAppleButtonStyle.white,
        borderRadius: AppRadii.buttonRadius,
        height: _kAuthButtonHeight,
        iconAlignment: IconAlignment.left,
      ),
    );
  }
}

/// Google-branded "Sign in with Google" button.
///
/// Mirrors the internal layout of [SignInWithAppleButton] (column widths,
/// padding, font metrics) so it stacks as a visually consistent pair with
/// the Apple button: official multi-color G pinned to the left, label
/// optically centered, identical height and text size.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFF1F1F1F);
    return SizedBox(
      height: _kAuthButtonHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: foreground,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _kAuthIconColWidth,
              height: _kAuthIconColWidth,
              child: Center(
                child: Image.asset(
                  'assets/auth/google_g.png',
                  width: _kAuthFontSize,
                  height: _kAuthFontSize,
                ),
              ),
            ),
            const Expanded(
              child: Text(
                'Sign in with Google',
                textAlign: TextAlign.center,
                style: TextStyle(
                  inherit: false,
                  fontSize: _kAuthFontSize,
                  color: foreground,
                  fontFamily: '.SF Pro Text',
                  letterSpacing: -0.41,
                ),
              ),
            ),
            const SizedBox(width: _kAuthIconColWidth),
          ],
        ),
      ),
    );
  }
}
