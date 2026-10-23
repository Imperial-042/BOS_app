// lib/core/auth/authorization_service.dart
//
// Answers "what can this user do in the SELECTED business?".
// It is an immutable snapshot (user + business + membership). Providers
// rebuild it whenever the user, selected business, or membership changes,
// so a service that watches authorizationServiceProvider never sees
// Business A's permissions while Business B is selected.
//
// Fail-secure: anything missing / inactive / mismatched => no permissions.

import '../database/app_database.dart';
import 'bos_access.dart';

class PermissionDeniedException implements Exception {
  final String message;
  const PermissionDeniedException(this.message);

  @override
  String toString() => message;
}

class AuthorizationService {
  /// Authenticated user id (null = signed out).
  final String? userId;

  /// The SELECTED business.
  final String? businessId;

  /// The user's membership row for [businessId] (null = not a member).
  final BusinessMember? membership;

  /// The role's permissions after business-level overrides are applied
  /// (permission_overrides.dart). Null falls back to the compiled-in
  /// defaults for [currentRole].
  final Set<BosPermission>? effectivePermissions;

  /// The built-in role whose defaults apply (the starting role for a custom role).
  final BosRole? resolvedRole;

  const AuthorizationService({
    required this.userId,
    required this.businessId,
    required this.membership,
    this.effectivePermissions,
    this.resolvedRole,
  });

  /// A service that denies everything.
  static const AuthorizationService denied = AuthorizationService(
    userId: null,
    businessId: null,
    membership: null,
  );

  BusinessMember? get currentMembership => _valid ? membership : null;

  bool get _valid {
    final m = membership;
    return m != null &&
        userId != null &&
        businessId != null &&
        m.userId == userId &&
        m.businessId == businessId &&
        m.status == 'active';
  }

  BosRole? get currentRole =>
      _valid ? (resolvedRole ?? BosRole.fromId(membership!.role)) : null;

  String? get currentBusinessId => _valid ? businessId : null;

  bool get isOwner => currentRole == BosRole.owner;

  bool hasRole(BosRole role) => currentRole == role;

  bool can(BosPermission permission) {
    final role = currentRole;
    if (role == null) return false;
    final permissions = effectivePermissions ?? RolePermissions.of(role);
    return permissions.contains(permission);
  }

  bool canAny(Iterable<BosPermission> permissions) => permissions.any(can);

  bool canAll(Iterable<BosPermission> permissions) => permissions.every(can);

  /// Service-layer guard. Throws [PermissionDeniedException].
  ///
  /// Pass [businessId] whenever the operation targets a specific business
  /// so an operation can never be applied to a business other than the one
  /// the permission was resolved for.
  void require(BosPermission permission, {String? businessId}) {
    if (userId == null) {
      throw const PermissionDeniedException('You are not signed in.');
    }
    if (!_valid) {
      throw const PermissionDeniedException(
        'You are not an active member of this business.',
      );
    }
    if (businessId != null && businessId != this.businessId) {
      throw const PermissionDeniedException(
        'This action targets a different business than the one selected.',
      );
    }
    if (!can(permission)) {
      throw PermissionDeniedException(
        'Your role (${currentRole!.label}) isn\'t allowed to do this '
        '(${permission.id}).',
      );
    }
  }

  /// Passes if the user holds AT LEAST ONE of [permissions].
  void requireAny(Iterable<BosPermission> permissions, {String? businessId}) {
    final list = permissions.toList();
    if (list.isEmpty) {
      throw ArgumentError('requireAny needs at least one permission.');
    }
    final granted = list.firstWhere(can, orElse: () => list.first);
    require(granted, businessId: businessId);
  }

  void requireOwner() {
    require(BosPermission.businessDelete);
    if (!isOwner) {
      throw const PermissionDeniedException('Only the owner can do this.');
    }
  }
}
