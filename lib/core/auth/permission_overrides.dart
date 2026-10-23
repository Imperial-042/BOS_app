// lib/core/auth/permission_overrides.dart
//
// Layers per-business RolePermissionOverrides rows on top of the compiled-in
// defaults. Custom roles use their STARTING role's defaults, with overrides
// keyed by the custom role id (c_<uuid>). The owner is never overridable.

import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'bos_access.dart';

/// The built-in role whose defaults apply to [roleId]. Null for an unknown or
/// not-yet-synced custom role (callers must treat null as "no access").
BosRole? resolveBaseRole(String? roleId, Iterable<CustomRole> customs) {
  if (roleId == null) return null;
  final builtIn = BosRole.fromId(roleId);
  if (builtIn != null) return builtIn;
  if (!roleId.startsWith(kCustomRolePrefix)) return null;
  final id = roleId.substring(kCustomRolePrefix.length);
  for (final c in customs) {
    if (c.id == id) {
      final base = BosRole.fromId(c.baseRole);
      return base == BosRole.owner ? null : base;
    }
  }
  return null;
}

abstract final class PermissionsResolver {
  /// [role] supplies the defaults; [roleId] (default role.id) selects which
  /// override rows apply.
  static Set<BosPermission> effectivePermissions(
    BosRole role,
    Iterable<RolePermissionOverride> overrides, {
    String? roleId,
  }) {
    if (role == BosRole.owner) return Set.of(BosPermission.values);

    final key = roleId ?? role.id;
    final result = RolePermissions.of(role).toSet();
    for (final override in overrides) {
      if (override.role != key) continue;
      final permission = BosPermission.fromId(override.permission);
      if (permission == null) continue;
      if (override.granted) {
        result.add(permission);
      } else {
        result.remove(permission);
      }
    }
    return result;
  }

  /// Fresh-from-DB check for a built-in role.
  static Future<bool> allows(
    AppDatabase db, {
    required String businessId,
    required BosRole role,
    required BosPermission permission,
    String? roleId,
  }) async {
    if (role == BosRole.owner) return true;

    final row =
        await (db.select(db.rolePermissionOverrides)..where(
              (o) =>
                  o.businessId.equals(businessId) &
                  o.role.equals(roleId ?? role.id) &
                  o.permission.equals(permission.id),
            ))
            .getSingleOrNull();
    if (row != null) return row.granted;
    return RolePermissions.allows(role, permission);
  }

  /// Same, from a stored role id (built-in or custom).
  static Future<bool> allowsRoleId(
    AppDatabase db, {
    required String businessId,
    required String roleId,
    required BosPermission permission,
  }) async {
    final customs = await (db.select(
      db.customRoles,
    )..where((r) => r.businessId.equals(businessId))).get();
    final base = resolveBaseRole(roleId, customs);
    if (base == null) return false;
    return allows(
      db,
      businessId: businessId,
      role: base,
      permission: permission,
      roleId: roleId,
    );
  }

  static Future<void> setOverride(
    AppDatabase db, {
    required String businessId,
    required BosRole role,
    required BosPermission permission,
    required bool granted,
    String? roleId,
    String? roleLabel,
  }) {
    final key = roleId ?? role.id;
    return db.transaction(() async {
      final rowId = AppDatabase.cloudCompatibleDefaultId(
        'role_permission_overrides',
        '${businessId}_${key}_${permission.id}',
      );
      final defaultAllowed = RolePermissions.allows(role, permission);
      final isDefault = defaultAllowed == granted;
      final existing =
          await (db.select(db.rolePermissionOverrides)..where(
                (o) =>
                    o.businessId.equals(businessId) &
                    o.role.equals(key) &
                    o.permission.equals(permission.id),
              ))
              .getSingleOrNull();
      final before = existing?.granted ?? defaultAllowed;

      if (isDefault) {
        if (existing == null) return;
        await (db.delete(
          db.rolePermissionOverrides,
        )..where((o) => o.id.equals(existing.id))).go();
      } else if (existing != null) {
        await (db.update(
          db.rolePermissionOverrides,
        )..where((o) => o.id.equals(existing.id))).write(
          RolePermissionOverridesCompanion(
            granted: Value(granted),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await db
            .into(db.rolePermissionOverrides)
            .insert(
              RolePermissionOverridesCompanion.insert(
                id: rowId,
                businessId: businessId,
                role: key,
                permission: permission.id,
                granted: granted,
              ),
            );
      }

      if (before != granted) {
        await AuditWriter.write(
          db,
          businessId: businessId,
          userId: null,
          action: 'permission.override_changed',
          entityType: 'role_permission_overrides',
          entityId: rowId,
          entityLabel: '${roleLabel ?? role.label}: ${permission.id}',
          before: {'granted': before},
          after: {'granted': granted},
          details: {'role': key, 'permission': permission.id},
        );
      }
    });
  }
}
