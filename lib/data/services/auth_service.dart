import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService(this.client);
  final SupabaseClient client;
  User? get currentUser => client.auth.currentUser;
  Stream<AuthState> get authChanges => client.auth.onAuthStateChange;
  Future<void> signIn(String email, String password) async =>
      client.auth.signInWithPassword(email: email.trim(), password: password);
  Future<void> signUp(String email, String password, String fullName) async =>
      client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );
  Future<void> signOut() => client.auth.signOut();
}
