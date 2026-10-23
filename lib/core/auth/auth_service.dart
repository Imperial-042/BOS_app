// lib/core/auth/auth_service.dart
//
// Local (on-device) login credentials: register, sign in, and change
// password against the `Users` table. Passwords are never stored in the
// clear — only a salted SHA-256 hash is persisted.
//
// This is the "real authentication provider" the rest of the auth layer
// (authenticatedUserIdProvider, AuthorizationService, MembershipService) was
// already built to expect.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

const _uuid = Uuid();

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final AppDatabase db;
  AuthService(this.db);

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  Future<AppUser?> _findByEmail(String email) {
    final normalized = _normalizeEmail(email);
    return (db.select(
      db.users,
    )..where((u) => u.email.equals(normalized))).getSingleOrNull();
  }

  /// Looks up a registered user by email, for inviting them to a business.
  /// Returns null if nobody has created an account with that email yet.
  Future<AppUser?> findByEmail(String email) => _findByEmail(email);

  /// Ensures a local Users row exists for a Supabase-authenticated user, so
  /// the Drift-based business/membership layer keeps working against the
  /// cloud user UUID. No password is set — local rows for cloud users are
  /// identity shells, not credentials. Idempotent.
  Future<void> ensureLocalUser({
    required String id,
    required String email,
    required String displayName,
  }) async {
    final existing = await (db.select(
      db.users,
    )..where((u) => u.id.equals(id))).getSingleOrNull();

    if (existing != null) return;

    final salt = _generateSalt();

    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: id,
            email: _normalizeEmail(email),
            passwordHash: _hash(const Uuid().v4(), salt),
            passwordSalt: salt,
            displayName: displayName.trim().isEmpty
                ? email.split('@').first
                : displayName.trim(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Creates a new login. Throws [AuthException] if the email is taken or
  /// the input fails basic validation.
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalized = _normalizeEmail(email);
    if (!normalized.contains('@') || !normalized.contains('.')) {
      throw const AuthException('Enter a valid email address.');
    }
    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters long.');
    }
    if (displayName.trim().isEmpty) {
      throw const AuthException('Enter your name.');
    }

    if (await _findByEmail(normalized) != null) {
      throw const AuthException('An account with that email already exists.');
    }

    final salt = _generateSalt();
    final id = _uuid.v4();
    final user = UsersCompanion.insert(
      id: id,
      email: normalized,
      passwordHash: _hash(password, salt),
      passwordSalt: salt,
      displayName: displayName.trim(),
    );

    try {
      await db.into(db.users).insert(user);
    } catch (_) {
      // Unique index race: two registrations for the same email at once.
      throw const AuthException('An account with that email already exists.');
    }

    return (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();
  }

  /// Verifies credentials and returns the matching user. Throws
  /// [AuthException] on any mismatch (kept generic so callers can't probe
  /// whether an email is registered).
  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final user = await _findByEmail(email);
    if (user == null ||
        _hash(password, user.passwordSalt) != user.passwordHash) {
      throw const AuthException('Incorrect email or password.');
    }

    await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(lastLoginAt: Value(DateTime.now())),
    );

    return user;
  }

  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = await (db.select(
      db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    if (_hash(currentPassword, user.passwordSalt) != user.passwordHash) {
      throw const AuthException('Your current password is incorrect.');
    }
    if (newPassword.length < 6) {
      throw const AuthException(
        'New password must be at least 6 characters long.',
      );
    }

    final salt = _generateSalt();
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        passwordHash: Value(_hash(newPassword, salt)),
        passwordSalt: Value(salt),
      ),
    );
  }

  /// Updates the name shown for this account (greeting, drawer, avatar).
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      throw const AuthException('Enter your name.');
    }
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(displayName: Value(name)),
    );
  }
}
