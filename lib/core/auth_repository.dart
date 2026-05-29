import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

class AuthRepository {
  User? get currentUser => supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  Future<void> sendMagicLink(String email) async {
    await supabase.auth.signInWithOtp(
      email: email,
      emailRedirectTo: 'wcpredict://auth/callback',
    );
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  Future<void> updateDisplayName(String name) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('profiles').upsert({
      'user_id': userId,
      'display_name': name,
    });
  }
}
