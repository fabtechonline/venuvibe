import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(SupabaseConfig.client);
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseConfig.client.auth.onAuthStateChange;
});

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) async {
      if (state.session?.user != null) {
        return ref
            .read(authRepositoryProvider)
            .getProfile(state.session!.user.id);
      }
      return null;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String role = 'user',
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    // With email confirmation enabled there is no session yet — RLS would
    // block the profile write. It happens after the OTP step instead.
    if (response.session != null && response.user != null) {
      await completeProfile(
        userId: response.user!.id,
        email: email,
        fullName: fullName,
        role: role,
      );
    }
    return response;
  }

  Future<void> completeProfile({
    required String userId,
    required String email,
    required String fullName,
    String role = 'user',
  }) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'email': email,
      'full_name': fullName,
      'role': role,
    });
  }

  /// Emails a 6-digit password-reset code (recovery template).
  Future<void> sendPasswordResetCode(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  /// Verifies a 6-digit email code (signup confirmation or recovery);
  /// a successful verification establishes a session.
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
    required OtpType type,
  }) {
    return _client.auth.verifyOTP(email: email, token: code, type: type);
  }

  /// Re-sends the signup confirmation code.
  Future<void> resendSignupCode(String email) async {
    await _client.auth.resend(type: OtpType.signup, email: email);
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<Profile?> getProfile(String userId) async {
    final data =
        await _client.from('profiles').select().eq('id', userId).single();
    return Profile.fromJson(data);
  }

  Future<void> updateProfile(Profile profile) async {
    await _client
        .from('profiles')
        .update(profile.toJson())
        .eq('id', profile.id);
  }
}
