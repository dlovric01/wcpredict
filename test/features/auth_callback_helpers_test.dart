// Pure-function tests for the auth callback helpers. These are the only
// part of the OAuth/magic-link plumbing testable without a live Supabase
// auth server — the rest involves real network exchanges and is covered
// by the regression suite + manual QA.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wcpredict/features/auth/auth_callback_helpers.dart';

void main() {
  group('parseOtpType', () {
    test('every documented Supabase type maps correctly', () {
      expect(parseOtpType('signup'), OtpType.signup);
      expect(parseOtpType('invite'), OtpType.invite);
      expect(parseOtpType('recovery'), OtpType.recovery);
      expect(parseOtpType('email_change'), OtpType.emailChange);
      expect(parseOtpType('email'), OtpType.email);
      expect(parseOtpType('magiclink'), OtpType.magiclink);
    });

    test('unknown type falls back to magiclink', () {
      // Most common link shape — keep the UX functional rather than
      // erroring on a typo in the email template.
      expect(parseOtpType('nonsense'), OtpType.magiclink);
      expect(parseOtpType(''), OtpType.magiclink);
      expect(parseOtpType('MAGICLINK'), OtpType.magiclink);
    });
  });

  group('friendlyAuthError', () {
    test('expired / invalid / OTP / token → "link has expired"', () {
      const expectExpired = 'The link has expired or already been used.\n'
          'Request a new one.';
      expect(friendlyAuthError('OTP expired'), expectExpired);
      expect(friendlyAuthError('Invalid token'), expectExpired);
      expect(friendlyAuthError('Token already used'), expectExpired);
      expect(friendlyAuthError('Otp not found'), expectExpired);
      // Case-insensitive
      expect(friendlyAuthError('EXPIRED'), expectExpired);
    });

    test('network / connection → "network error"', () {
      const expectNetwork =
          'Network error — check your connection and try again.';
      expect(friendlyAuthError('Network unreachable'), expectNetwork);
      expect(friendlyAuthError('No internet connection'), expectNetwork);
      expect(friendlyAuthError('CONNECTION refused'), expectNetwork);
    });

    test('expired beats network (first match wins, by design)', () {
      // If a network error somehow mentions "token", it goes into the
      // expired bucket. Acceptable — both messages tell the user to retry.
      expect(friendlyAuthError('token network failed'),
          contains('expired'));
    });

    test('unknown error → generic fallback', () {
      const generic = 'Sign-in failed. Please try again.';
      expect(friendlyAuthError('Something unexpected'), generic);
      expect(friendlyAuthError(''), generic);
      expect(friendlyAuthError('500 internal server error'), generic);
    });
  });
}
