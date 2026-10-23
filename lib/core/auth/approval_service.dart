// lib/core/auth/approval_service.dart
//
// Manager / owner approval by PIN, used to authorise sensitive POS actions
// (void and restore a receipt).
//
// WHY A PIN AND NOT THE LOGIN PASSWORD
//   Real sign-in goes through Supabase. The local `users` row of a cloud
//   account is only an identity shell with a random, unusable password
//   (see AuthService.ensureLocalUser), so a password can't be checked on the
//   device, and signing a second person in would replace the active session
//   and break sync. A PIN stored (salted + hashed) on this device works
//   offline and never touches the session.
//
// LIMITS
//   * The PIN lives on this device only (users is not a synced table). Each
//     owner/manager sets it once per device they approve on, and must have
//     signed in on that device at least once.
//   * Short numeric PINs can be guessed if someone copies the database file.
//     This stops casual misuse at the counter, not a determined attacker.
//   * Five wrong tries lock approvals for 60 seconds.

import 'dart:convert';
import 'dart:math';

import 'package:bos_application/core/auth/permission_overrides.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'authorization_providers.dart';
import 'bos_access.dart';

class ApprovalException implements Exception {
  final String message;
  const ApprovalException(this.message);

  @override
  String toString() => message;
}

class Approver {
  final String userId;
  final String name;
  final BosRole role;

  const Approver({
    required this.userId,
    required this.name,
    required this.role,
  });
}

class ApprovalService {
  final AppDatabase db;
  ApprovalService(this.db);

  static const _maxFailures = 5;
  static const _lockSeconds = 60;
  static final Map<String, int> _failures = {};
  static final Map<String, DateTime> _lockedUntil = {};

  static bool validPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  static String _salt() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:approval:$pin')).toString();

  /// True when at least one active member of the business has set a PIN.
  /// Until then approvals are not enforced, so a business is never locked out.
  static Future<bool> anyPinSet(AppDatabase db, String businessId) async {
    final rows = await db
        .customSelect(
          'SELECT 1 FROM business_members m '
          'JOIN users u ON u.id = m.user_id '
          "WHERE m.business_id = ? AND m.status = 'active' "
          'AND u.approval_pin_hash IS NOT NULL LIMIT 1',
          variables: [Variable.withString(businessId)],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<bool> hasPin(String userId) async {
    final u = await (db.select(
      db.users,
    )..where((x) => x.id.equals(userId))).getSingleOrNull();
    return u?.approvalPinHash != null;
  }

  Future<
    List<({BusinessMember member, BosRole role, String roleId, AppUser user})>
  >
  _members(String businessId) async {
    final customs = await (db.select(
      db.customRoles,
    )..where((r) => r.businessId.equals(businessId))).get();
    final members =
        await (db.select(db.businessMembers)..where(
              (m) =>
                  m.businessId.equals(businessId) & m.status.equals('active'),
            ))
            .get();
    final out =
        <
          ({BusinessMember member, BosRole role, String roleId, AppUser user})
        >[];
    for (final m in members) {
      final role = resolveBaseRole(m.role, customs);
      if (role == null) continue;
      final user = await (db.select(
        db.users,
      )..where((u) => u.id.equals(m.userId))).getSingleOrNull();
      if (user == null) continue;
      out.add((member: m, role: role, roleId: m.role, user: user));
    }
    return out;
  }

  /// Checks [pin] against owners/managers who are allowed to approve
  /// [permission]. Returns who approved.
  Future<Approver> verifyPin({
    required String businessId,
    required String pin,
    required BosPermission permission,
    required Set<BosPermission> Function(BosRole role, String roleId)
    permissionsOf,
  }) async {
    final now = DateTime.now();
    final locked = _lockedUntil[businessId];
    if (locked != null && now.isBefore(locked)) {
      final secs = locked.difference(now).inSeconds + 1;
      throw ApprovalException(
        'Too many wrong PINs. Try again in $secs seconds.',
      );
    }
    if (!validPin(pin)) {
      throw const ApprovalException('Enter the 4 to 8 digit approval PIN.');
    }

    for (final c in await _members(businessId)) {
      final hash = c.user.approvalPinHash;
      final salt = c.user.approvalPinSalt;
      if (hash == null || salt == null) continue;
      if (!permissionsOf(c.role, c.roleId).contains(permission)) continue;
      if (_hash(pin, salt) == hash) {
        _failures[businessId] = 0;
        return Approver(
          userId: c.user.id,
          name: c.user.displayName,
          role: c.role,
        );
      }
    }

    final n = (_failures[businessId] ?? 0) + 1;
    if (n >= _maxFailures) {
      _failures[businessId] = 0;
      _lockedUntil[businessId] = now.add(const Duration(seconds: _lockSeconds));
    } else {
      _failures[businessId] = n;
    }
    throw const ApprovalException(
      'Wrong PIN, or that person is not allowed to approve this.',
    );
  }

  /// Sets or changes a user's PIN. If they already have one, the current PIN
  /// must be given. PINs are kept unique inside a business so the audit log
  /// always names the right approver.
  Future<void> setPin({
    required String businessId,
    required String userId,
    required String newPin,
    String? currentPin,
  }) async {
    if (!validPin(newPin)) {
      throw const ApprovalException('The PIN must be 4 to 8 digits.');
    }

    final user = await (db.select(
      db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) {
      throw const ApprovalException('You are not signed in on this device.');
    }

    final existingHash = user.approvalPinHash;
    final existingSalt = user.approvalPinSalt;
    if (existingHash != null && existingSalt != null) {
      if (currentPin == null ||
          _hash(currentPin, existingSalt) != existingHash) {
        throw const ApprovalException('Your current PIN is incorrect.');
      }
    }

    for (final c in await _members(businessId)) {
      if (c.user.id == userId) continue;
      final h = c.user.approvalPinHash;
      final s = c.user.approvalPinSalt;
      if (h != null && s != null && _hash(newPin, s) == h) {
        throw const ApprovalException(
          'That PIN is already used by someone else. Choose another.',
        );
      }
    }

    final salt = _salt();
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        approvalPinHash: Value(_hash(newPin, salt)),
        approvalPinSalt: Value(salt),
      ),
    );
  }
}

final approvalServiceProvider = Provider<ApprovalService>(
  (ref) => ApprovalService(ref.watch(databaseProvider)),
);

/// Whether approvals are switched on for the selected business (someone has
/// set a PIN). Invalidate it after a PIN is saved.
final approvalEnabledProvider = FutureProvider<bool>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  return ApprovalService.anyPinSet(ref.watch(databaseProvider), businessId);
});
