// lib/core/auth/auth_providers.dart
//
// Wires AuthService + SessionStore into Riverpod, and bridges them to
// authenticatedUserIdProvider (authorization_providers.dart) so the rest of
// the auth layer — AuthorizationService, MembershipService, PermissionGate —
// keeps working unchanged.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'auth_service.dart';
import 'authorization_providers.dart';
import 'biometric_auth_service.dart';
import 'session_store.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(databaseProvider));
});

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return BiometricAuthService();
});

/// A previously signed-in user waiting to be let back in, restored from
/// disk on app start but NOT yet applied to [authenticatedUserIdProvider].
/// When [biometricEnabled] is true, the UI must confirm identity with
/// fingerprint/face/device passcode before resuming the session.
class PendingSession {
  final String userId;
  final String email;
  final String displayName;
  final bool biometricEnabled;

  const PendingSession({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.biometricEnabled,
  });
}

/// Runs once at app start: looks up a persisted session without signing
/// the user in. The UI decides whether to resume it immediately or gate it
/// behind a biometric prompt first.
final pendingSessionProvider = FutureProvider<PendingSession?>((ref) async {
  final userId = await SessionStore.readUserId();
  if (userId == null) return null;

  final db = ref.watch(databaseProvider);
  final user = await (db.select(
    db.users,
  )..where((u) => u.id.equals(userId))).getSingleOrNull();

  if (user == null) {
    // Stale/removed account — don't leave a dangling session behind.
    await SessionStore.clear();
    return null;
  }

  final biometricEnabled = await SessionStore.isBiometricEnabled();
  return PendingSession(
    userId: user.id,
    email: user.email,
    displayName: user.displayName,
    biometricEnabled: biometricEnabled,
  );
});

/// The signed-in user's own row (email, display name, etc).
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(authenticatedUserIdProvider);
  if (uid == null) return Stream.value(null);
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.users,
  )..where((u) => u.id.equals(uid))).watchSingleOrNull();
});

/// Looks up any user's own row by id — used to show a business member's
/// name/email next to their [BusinessMember] row.
final userByIdProvider = FutureProvider.family<AppUser?, String>((ref, userId) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.users,
  )..where((u) => u.id.equals(userId))).getSingleOrNull();
});
