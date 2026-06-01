// Pure helpers extracted from `auth_callback_screen.dart` so they can be
// unit-tested without spinning up the widget tree.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps the `?type=` query param Supabase sends on its e-mail callback
/// links to the [OtpType] enum required by `auth.verifyOTP`.
///
/// Unknown values fall through to `magiclink` — that's the most common
/// link shape and keeps the UX functional rather than erroring on a typo.
OtpType parseOtpType(String raw) {
  switch (raw) {
    case 'signup':
      return OtpType.signup;
    case 'invite':
      return OtpType.invite;
    case 'recovery':
      return OtpType.recovery;
    case 'email_change':
      return OtpType.emailChange;
    case 'email':
      return OtpType.email;
    case 'magiclink':
    default:
      return OtpType.magiclink;
  }
}

/// Maps a raw Supabase / network error string to a user-facing message
/// suitable for display in the auth callback screen.
///
/// Three buckets:
///   * Expired / invalid / OTP / token  → "The link has expired …"
///   * Network / connection             → "Network error …"
///   * Anything else                    → "Sign-in failed. Please try again."
String friendlyAuthError(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('expired') ||
      s.contains('invalid') ||
      s.contains('otp') ||
      s.contains('token')) {
    return 'The link has expired or already been used.\nRequest a new one.';
  }
  if (s.contains('network') || s.contains('connection')) {
    return 'Network error — check your connection and try again.';
  }
  return 'Sign-in failed. Please try again.';
}
