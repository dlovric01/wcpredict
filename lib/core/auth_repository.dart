import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logger.dart';
import 'supabase_client.dart';
import 'push_notifications.dart';

class AuthRepository {
  User? get currentUser => supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  // Google Sign-In: serverClientId is the **Web** OAuth Client ID from
  // Google Cloud Console — it's what Supabase uses to verify the ID token.
  final _googleSignIn = GoogleSignIn(
    serverClientId: const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    scopes: const ['email', 'profile'],
  );

  /// Native Apple Sign-In (iOS only).
  ///
  /// Uses the system sheet; no web redirect, no Service ID, no .p8 key
  /// for the secret — Supabase verifies the JWT against Apple's public keys
  /// using the bundle ID as the audience.
  Future<AuthResponse> signInWithApple() async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError('Apple Sign-In is only available on iOS');
    }

    // Apple requires the nonce SHA256-hashed in the request and the raw
    // nonce passed to Supabase for verification.
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw Exception('No identity token received from Apple');
    }

    final response = await supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple only returns givenName/familyName on the FIRST sign-in. Capture
    // them now so the profile gets a real display name; future sign-ins
    // won't include these fields.
    final displayName = [credential.givenName, credential.familyName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ')
        .trim();
    await _ensureProfile(displayNameOverride: displayName.isEmpty ? null : displayName);
    await _registerPushForCurrentUser();
    return response;
  }

  /// Google Sign-In (iOS + Android).
  ///
  /// Native flow via `google_sign_in`, then exchange the ID token with
  /// Supabase. No web callback involved.
  Future<AuthResponse> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Sign-in cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception('No ID token received from Google');
    }

    final response = await supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    await _ensureProfile();
    await _registerPushForCurrentUser();
    return response;
  }

  Future<void> signOut() async {
    try {
      await pushNotifications?.unregisterForCurrentDevice();
    } catch (_) {
      // best-effort — token cleanup is non-essential
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // ignore — user may not have signed in with Google
    }
    await supabase.auth.signOut(scope: SignOutScope.local);
  }

  Future<void> _registerPushForCurrentUser() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await pushNotifications?.registerForUser(uid);
    } catch (e, st) {
      talker.handle(e, st, 'Push registration failed');
    }
  }

  Future<void> updateDisplayName(String name) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('profiles').upsert({
      'user_id': userId,
      'display_name': name,
    }, onConflict: 'user_id');
  }

  /// Insert/update the user's profile row after sign-in.
  ///
  /// [displayNameOverride] wins when provided (Apple's first-sign-in name).
  /// Otherwise we fall back to provider metadata.
  Future<void> _ensureProfile({String? displayNameOverride}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata;
    final displayName = displayNameOverride ??
        (metadata?['full_name'] as String?) ??
        (metadata?['name'] as String?) ??
        user.email?.split('@').first;

    if (displayName == null || displayName.isEmpty) return;

    try {
      await supabase.from('profiles').upsert({
        'user_id': user.id,
        'display_name': displayName,
      }, onConflict: 'user_id');
    } catch (e, st) {
      talker.handle(e, st, 'Profile upsert failed');
    }
  }

  /// Cryptographically-secure random nonce for Apple Sign-In.
  String _generateNonce([int length = 32]) {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }
}
