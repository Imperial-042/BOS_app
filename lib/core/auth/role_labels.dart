// lib/core/auth/role_labels.dart
//
// Custom roles: names, the role list used by pickers, and the owner-only
// service to create / rename / re-base / delete them.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Built-in roles a custom role may start from.
const List<BosRole> kCustomBaseRoles = [
  BosRole.manager,
  BosRole.accountant,
  BosRole.cashier,
  BosRole.inventory,
  BosRole.employee,
  BosRole.hr,
  BosRole.staff,
];

extension CustomRoleX on CustomRole {
  /// The id stored in business_members.role.
  String get roleId => '$kCustomRolePrefix$id';
}

/// One assignable role (built-in or custom), as shown in pickers.
class RoleRef {
  const RoleRef({
    required this.id,
    required this.label,
    required this.base,
    required this.custom,
  });

  final String id;
  final String label;

  /// Built-in role whose defaults apply.
  final BosRole base;
  final bool custom;
}

/// Everything except the owner: built-ins first, then custom roles.
final roleRefsProvider = Provider<List<RoleRef>>((ref) {
  final customs = ref.watch(customRolesProvider).value ?? const <CustomRole>[];
  final out = <RoleRef>[];
  for (final r in BosRole.values) {
    if (r == BosRole.owner) continue;
    out.add(RoleRef(id: r.id, label: r.label, base: r, custom: false));
  }
  for (final c in customs) {
    final base = BosRole.fromId(c.baseRole);
    if (base == null || base == BosRole.owner) continue;
    out.add(RoleRef(id: c.roleId, label: c.name, base: base, custom: true));
  }
  return out;
});

/// role id -> custom name. Built-in roles are not in this map.
final roleLabelsProvider = Provider<AsyncValue<Map<String, String>>>((ref) {
  return ref
      .watch(customRolesProvider)
      .whenData((rows) => {for (final c in rows) c.roleId: c.name});
});

/// The name to show for [roleId].
String roleLabelFor(Map<String, String> labels, String? roleId) {
  if (roleId == null) return '';
  final custom = labels[roleId]?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final builtIn = BosRole.fromId(roleId);
  if (builtIn != null) return builtIn.label;
  return roleId.startsWith(kCustomRolePrefix) ? 'Removed role' : roleId;
}

/// The signed-in person's role name, for headers and profile badges.
final currentRoleLabelProvider = Provider<String>((ref) {
  final m = ref.watch(currentBusinessMembershipProvider).value;
  final labels =
      ref.watch(roleLabelsProvider).value ?? const <String, String>{};
  return roleLabelFor(labels, m?.role);
});

// ============================================================================
// SERVICE (owner only)
// ============================================================================

class CustomRoleService {
  CustomRoleService(this.db, this.auth, this.businessId);

  final AppDatabase db;
  final AuthorizationService auth;
  final String businessId;

  static const _uuid = Uuid();

  Future<List<CustomRole>> _all() => (db.select(
    db.customRoles,
  )..where((r) => r.businessId.equals(businessId))).get();

  String _validName(String raw, List<CustomRole> all, {String? exceptId}) {
    final text = raw.trim();
    if (text.isEmpty) throw StateError('Enter a role name.');
    if (text.length > 30) {
      throw StateError('Role names can be up to 30 characters.');
    }
    final lower = text.toLowerCase();
    for (final r in BosRole.values) {
      if (r.label.toLowerCase() == lower) {
        throw StateError('"$text" is already a built-in role.');
      }
    }
    for (final c in all) {
      if (c.id != exceptId && c.name.toLowerCase() == lower) {
        throw StateError('You already have a role called "$text".');
      }
    }
    return text;
  }

  void _checkBase(BosRole base) {
    if (!kCustomBaseRoles.contains(base)) {
      throw StateError('Choose a different starting role.');
    }
  }

  Future<void> create({required String name, required BosRole base}) async {
    auth.requireOwner();
    _checkBase(base);
    final all = await _all();
    final text = _validName(name, all);
    final id = _uuid.v4();
    await db.transaction(() async {
      await db
          .into(db.customRoles)
          .insert(
            CustomRolesCompanion.insert(
              id: id,
              businessId: businessId,
              name: text,
              baseRole: base.id,
              sortOrder: Value(all.length),
            ),
          );
      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: auth.userId,
        action: 'role.custom_created',
        entityType: 'custom_roles',
        entityId: id,
        entityLabel: text,
        module: AuditModule.security,
        actionType: AuditActionType.permission,
        details: {'base': base.id},
      );
    });
  }

  Future<void> update(
    CustomRole role, {
    required String name,
    required BosRole base,
  }) async {
    auth.requireOwner();
    _checkBase(base);
    final all = await _all();
    final text = _validName(name, all, exceptId: role.id);
    if (text == role.name && base.id == role.baseRole) return;
    await db.transaction(() async {
      await (db.update(
        db.customRoles,
      )..where((r) => r.id.equals(role.id))).write(
        CustomRolesCompanion(
          name: Value(text),
          baseRole: Value(base.id),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: auth.userId,
        action: 'role.custom_updated',
        entityType: 'custom_roles',
        entityId: role.id,
        entityLabel: text,
        module: AuditModule.security,
        actionType: AuditActionType.permission,
        before: {'name': role.name, 'base': role.baseRole},
        after: {'name': text, 'base': base.id},
      );
    });
  }

  /// People and pending invites that still use [roleId].
  Future<int> usage(String roleId) async {
    final members =
        await (db.select(db.businessMembers)..where(
              (m) =>
                  m.businessId.equals(businessId) &
                  m.role.equals(roleId) &
                  m.status.equals('removed').not(),
            ))
            .get();
    final invites =
        await (db.select(db.businessInvites)..where(
              (i) =>
                  i.businessId.equals(businessId) &
                  i.role.equals(roleId) &
                  i.status.equals('pending'),
            ))
            .get();
    return members.length + invites.length;
  }

  Future<void> delete(CustomRole role) async {
    auth.requireOwner();
    final inUse = await usage(role.roleId);
    if (inUse > 0) {
      throw StateError(
        '$inUse ${inUse == 1 ? 'person or invite still has' : 'people or invites still have'} '
        'this role. Move them to another role first.',
      );
    }
    await db.transaction(() async {
      await (db.delete(db.rolePermissionOverrides)..where(
            (o) => o.businessId.equals(businessId) & o.role.equals(role.roleId),
          ))
          .go();
      await (db.delete(
        db.customRoles,
      )..where((r) => r.id.equals(role.id))).go();
      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: auth.userId,
        action: 'role.custom_deleted',
        entityType: 'custom_roles',
        entityId: role.id,
        entityLabel: role.name,
        module: AuditModule.security,
        actionType: AuditActionType.permission,
      );
    });
  }
}

final customRoleServiceProvider = Provider<CustomRoleService>(
  (ref) => CustomRoleService(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
    ref.watch(selectedBusinessIdProvider),
  ),
);
