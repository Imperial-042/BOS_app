// lib/core/supabase/supabase_auth_service.dart
//
// Supabase Auth wrapper. Translates SDK exceptions into domain-level
// [CloudAuthException]s so the UI never surfaces raw Postgrest/Auth
// exception text. Authentication (who you are) lives here; authorization
// (what you can touch) lives in PostgreSQL RLS + business memberships.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'supabase_service.dart';

class CloudAuthException implements Exception {
  final String code;
  final String message;
  const CloudAuthException(this.code, this.message);

  /// The user dismissed the provider's sign-in UI — not an error worth
  /// surfacing; the UI should just return to its idle state.
  bool get isCancellation => code == 'cancelled';

  @override
  String toString() => message;
}

/// Result of email/password registration. When the Supabase project
/// requires email confirmation, [sessionEstablished] is false: the account
/// exists but no session was issued, so the UI must NOT sign the user in.
class CloudAuthSignUpResult {
  final User user;
  final bool sessionEstablished;
  const CloudAuthSignUpResult({
    required this.user,
    required this.sessionEstablished,
  });
}

CloudAuthException _mapAuthError(Object error) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid') && message.contains('credential')) {
      return const CloudAuthException(
        'invalid_credentials',
        'Incorrect email or password.',
      );
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return const CloudAuthException(
        'email_exists',
        'An account with that email already exists.',
      );
    }
    if (message.contains('email not confirmed') ||
        (message.contains('confirm') && message.contains('email'))) {
      return const CloudAuthException(
        'email_not_confirmed',
        'Please verify your email address before signing in.',
      );
    }
    if (message.contains('expired')) {
      return const CloudAuthException(
        'session_expired',
        'Your session has expired. Please sign in again.',
      );
    }
    return CloudAuthException('auth_error', error.message);
  }
  return const CloudAuthException(
    'network_error',
    'Could not reach the server. Check your connection and try again.',
  );
}

class CloudAuthService {
  final SupabaseClient _client;
  CloudAuthService(this._client);

  GoTrueClient get _auth => _client.auth;

  /// The signed-in cloud user id (Supabase Auth UUID), or null.
  String? get currentUserId => _auth.currentUser?.id;

  bool get isSignedIn => currentUserId != null;

  /// The signed-in cloud user's email, or null when signed out.
  String? get currentEmail => _auth.currentUser?.email;

  /// The display name captured at registration (user metadata). Never use
  /// this for authorization decisions — user metadata is user-editable.
  String? get currentDisplayName {
    final metadata = _auth.currentUser?.userMetadata;
    final name = metadata?['display_name'] ?? metadata?['full_name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  /// Auth state changes (signed in / out / token refreshed / recovery).
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  Future<CloudAuthSignUpResult> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: displayName == null ? null : {'display_name': displayName},
      );
      final user = response.user;
      if (user == null) {
        throw const CloudAuthException(
          'auth_error',
          'Registration did not return a user. Try signing in.',
        );
      }
      // Email-confirmation projects return a user with NO session: the
      // account isn't usable until the inbox link is tapped.
      return CloudAuthSignUpResult(
        user: user,
        sessionEstablished: response.session != null,
      );
    } catch (error) {
      throw _mapAuthError(error);
    }
  }

  Future<User> signIn({required String email, required String password}) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const CloudAuthException(
          'invalid_credentials',
          'Incorrect email or password.',
        );
      }
      return user;
    } catch (error) {
      throw _mapAuthError(error);
    }
  }

  /// Native Google sign-in (Android/iOS/macOS): google_sign_in obtains an
  /// ID token from Google, then Supabase exchanges it for a session. Works
  /// for both existing accounts and first-time registrations — Supabase
  /// creates the auth user (and the handle_new_user trigger the profile)
  /// on first sign-in.
  ///
  /// Throws [CloudAuthException] with code 'cancelled' when the user
  /// dismisses the Google sheet, 'not_configured' when the Google client
  /// IDs weren't supplied via --dart-define, and 'unsupported_platform' on
  /// platforms where google_sign_in has no native flow.
  Future<User> signInWithGoogle() async {
    if (!SupabaseConfig.isGoogleAuthConfigured) {
      throw const CloudAuthException(
        'not_configured',
        'Google sign-in isn\'t configured for this build.',
      );
    }
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      throw const CloudAuthException(
        'unsupported_platform',
        'Google sign-in is not available on this platform.',
      );
    }

    try {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        serverClientId: SupabaseConfig.googleServerClientId,
        clientId: SupabaseConfig.googleIosClientId.isEmpty
            ? null
            : SupabaseConfig.googleIosClientId,
      );

      final account = await googleSignIn.authenticate();

      // The ID token is all Supabase needs. The access token is optional
      // (used for Google API access) and requires extra scope consent, so
      // never fail sign-in over it.
      String? accessToken;
      try {
        const scopes = ['email', 'profile'];
        accessToken = (await account.authorizationClient.authorizationForScopes(
          scopes,
        ))?.accessToken;
      } catch (_) {
        accessToken = null;
      }

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const CloudAuthException(
          'google_error',
          'Google did not return an identity token. Try again.',
        );
      }

      final response = await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      final user = response.user;
      if (user == null) {
        throw const CloudAuthException(
          'auth_error',
          'Google sign-in did not return a user. Try again.',
        );
      }
      return user;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const CloudAuthException(
          'cancelled',
          'Google sign-in was cancelled.',
        );
      }
      throw CloudAuthException(
        'google_error',
        error.description ?? 'Google sign-in failed. Try again.',
      );
    } catch (error) {
      if (error is CloudAuthException) rethrow;
      throw _mapAuthError(error);
    }
  }

  Future<void> signOut() async {
    await signOutWithScope(SignOutScope.local);
  }

  Future<void> signOutWithScope(SignOutScope scope) async {
    try {
      if (scope == SignOutScope.local) {
        try {
          await _client.rpc('end_current_device_session');
        } on Object catch (error) {
          // Local sign-out must remain possible offline; the JWT is still
          // bounded by its expiry if the server could not record this event.
          // ignore: avoid_print
          print(
            '[auth] device session end was not confirmed '
            '(${error.runtimeType})',
          );
        }
      }
      await _auth.signOut(scope: scope);
    } catch (error) {
      throw _mapAuthError(error);
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } catch (error) {
      throw _mapAuthError(error);
    }
  }

  /// Sets a new password for the signed-in user (post-recovery or an
  /// authenticated change from the Security screen).
  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      throw _mapAuthError(error);
    }
  }
}

final cloudAuthServiceProvider = Provider<CloudAuthService>((ref) {
  return CloudAuthService(ref.watch(supabaseClientProvider));
});
