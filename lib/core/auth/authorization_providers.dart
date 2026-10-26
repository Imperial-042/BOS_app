// lib/core/auth/authorization_providers.dart
//
// Reactive chain:
//   authenticated user + selected business
//     -> membership -> role -> AuthorizationService

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId, ledgerVersionProvider;
import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'authorization_service.dart';
import 'bos_access.dart';
import 'permission_overrides.dart';

// ---------------------------------------------------------------------------
// WHO is signed in.
//
// BOS has no login screen yet, so main.dart sets this at startup to the
// selected business's ownerUserId (the "local device user"). When a real
// authentication provider is added, set this from it instead — nothing else
// in the authorization layer changes. Null = signed out = everything denied.
// ---------------------------------------------------------------------------
final authenticatedUserIdProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// WHICH business is selected.
//
// kCurrentBusinessId is a mutable global. This provider re-reads it whenever
// ledgerVersionProvider changes (the app bumps that on every business
// switch), and Riverpod only notifies dependents when the VALUE changes, so
// permissions/data refresh exactly when the selected business changes.
// Switch code may also call ref.invalidate(selectedBusinessIdProvider).
// ---------------------------------------------------------------------------
final selectedBusinessIdProvider = Provider<String>((ref) {
  ref.watch(ledgerVersionProvider);
  return kCurrentBusinessId;
});

// ---------------------------------------------------------------------------

/// Every business the signed-in user actively belongs to.
final businessMembershipsProvider = StreamProvider<List<BusinessMember>>((ref) {
  final uid = ref.watch(authenticatedUserIdProvider);
  if (uid == null) return Stream.value(const <BusinessMember>[]);
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.businessMembers,
  )..where((m) => m.userId.equals(uid) & m.status.equals('active'))).watch();
});

/// Pending invitations addressed to the signed-in user.
final pendingInvitationsProvider = StreamProvider<List<BusinessMember>>((ref) {
  final uid = ref.watch(authenticatedUserIdProvider);
  if (uid == null) return Stream.value(const <BusinessMember>[]);
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.businessMembers,
  )..where((m) => m.userId.equals(uid) & m.status.equals('invited'))).watch();
});

/// The selected business row.
final currentBusinessProvider = StreamProvider<BusinessesData?>((ref) {
  final id = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.businesses,
  )..where((b) => b.id.equals(id))).watchSingleOrNull();
});

/// The signed-in user's ACTIVE membership in the selected business.
final currentBusinessMembershipProvider = StreamProvider<BusinessMember?>((
  ref,
) {
  final uid = ref.watch(authenticatedUserIdProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  if (uid == null) return Stream.value(null);
  final db = ref.watch(databaseProvider);
  return (db.select(db.businessMembers)..where(
        (m) =>
            m.userId.equals(uid) &
            m.businessId.equals(businessId) &
            m.status.equals('active'),
      ))
      .watchSingleOrNull();
});

final currentRoleProvider = Provider<BosRole?>((ref) {
  final m = ref.watch(currentBusinessMembershipProvider).value;
  final customs = ref.watch(customRolesProvider).value ?? const <CustomRole>[];
  return resolveBaseRole(m?.role, customs);
});

/// Every custom permission override for the SELECTED business (all roles).
/// A role with no rows here just uses RolePermissions.of's defaults.
final rolePermissionOverridesProvider =
    StreamProvider<List<RolePermissionOverride>>((ref) {
      final businessId = ref.watch(selectedBusinessIdProvider);
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.rolePermissionOverrides,
      )..where((o) => o.businessId.equals(businessId))).watch();
    });

/// The business's custom roles, in display order.
final customRolesProvider = StreamProvider<List<CustomRole>>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.customRoles)
        ..where((r) => r.businessId.equals(businessId))
        ..orderBy([
          (r) => OrderingTerm.asc(r.sortOrder),
          (r) => OrderingTerm.asc(r.name),
        ]))
      .watch();
});

/// Rebuilds on user / business / membership / override change. Services
/// should `ref.watch` this so they are recreated with the right permissions.
final authorizationServiceProvider = Provider<AuthorizationService>((ref) {
  final uid = ref.watch(authenticatedUserIdProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final membership = ref.watch(currentBusinessMembershipProvider).value;
  if (uid == null) return AuthorizationService.denied;

  final customs = ref.watch(customRolesProvider).value ?? const <CustomRole>[];
  final roleId = membership?.role;
  final base = resolveBaseRole(roleId, customs);
  final overrides =
      ref.watch(rolePermissionOverridesProvider).value ?? const [];
  return AuthorizationService(
    userId: uid,
    businessId: businessId,
    membership: membership,
    resolvedRole: base,
    effectivePermissions: base == null
        ? null
        : PermissionsResolver.effectivePermissions(
            base,
            overrides,
            roleId: roleId,
          ),
  );
});

/// Convenience for widgets: `ref.watch(canProvider(BosPermission.salesVoid))`.
final canProvider = Provider.family<bool, BosPermission>(
  (ref, permission) => ref.watch(authorizationServiceProvider).can(permission),
);
