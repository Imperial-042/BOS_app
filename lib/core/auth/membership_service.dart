// lib/core/auth/membership_service.dart
//
// Business membership lifecycle + audit logging.
//
//   invite  -> status 'invited' (NOT effective)
//   accept  -> status 'active'  (role becomes effective)
//
// Every mutating call re-reads the ACTOR's membership from the database
// inside the transaction (never trusts a cached snapshot), checks the
// permission against that fresh row, and writes an audit entry.
//
// Owner rules (single-owner model):
//   * the owner can't be demoted, suspended or removed directly
//   * the owner role can't be handed out by invite / role change
//   * ownership moves only through transferOwnership()
//   * nobody can change their own role

import 'dart:math';

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'authorization_providers.dart';
import 'authorization_service.dart';
import 'bos_access.dart';
import 'permission_overrides.dart';

const _uuid = Uuid();

// ============================================================================
// AUDIT
// ============================================================================

abstract final class AuditLogger {
  /// Call inside the same transaction as the action being audited.
  /// New optional args are classified automatically from [action] when omitted.
  static Future<void> record(
    AppDatabase db, {
    required String businessId,
    required String? userId,
    required String action,
    required String entityType,
    String? entityId,
    Map<String, Object?>? details,
    AuditModule? module,
    AuditActionType? actionType,
    String? entityLabel,
    String? reason,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) async {
    await AuditWriter.write(
      db,
      businessId: businessId,
      userId: userId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      details: details,
      module: module,
      actionType: actionType,
      entityLabel: entityLabel,
      reason: reason,
      before: before,
      after: after,
    );
  }
}

// ============================================================================
// SERVICE
// ============================================================================

final membershipServiceProvider = Provider<MembershipService>(
  (ref) => MembershipService(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
    cloud: ref.watch(supabaseAvailableProvider)
        ? ref.watch(cloudBusinessServiceProvider)
        : null,
  ),
);

/// Every non-removed member of the SELECTED business, for the Users & Roles
/// screen. Re-streams whenever a membership row changes.
final businessMembersProvider = StreamProvider<List<BusinessMember>>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.businessMembers)
        ..where(
          (m) =>
              m.businessId.equals(businessId) &
              m.status.equals('removed').not(),
        )
        ..orderBy([(m) => OrderingTerm.asc(m.joinedAt)]))
      .watch();
});

/// Unredeemed invite codes for the SELECTED business, newest first.
final pendingBusinessInvitesProvider = StreamProvider<List<BusinessInvite>>((
  ref,
) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.businessInvites)
        ..where(
          (i) => i.businessId.equals(businessId) & i.status.equals('pending'),
        )
        ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
      .watch();
});

class MembershipService {
  final AppDatabase db;
  final AuthorizationService auth;
  final CloudBusinessService? cloud;
  MembershipService(this.db, this.auth, {this.cloud});

  // ----- Creation-time helpers (call from business-creation flows) --------

  /// Inside your business-creation transaction, right after inserting the
  /// Businesses row:
  ///   await MembershipService.insertOwnerMembership(db,
  ///       businessId: id, userId: ownerUserId);
  /// Idempotent (deterministic id + insertOrIgnore).
  static Future<void> insertOwnerMembership(
    AppDatabase db, {
    required String businessId,
    required String userId,
  }) {
    return db
        .into(db.businessMembers)
        .insert(
          BusinessMembersCompanion.insert(
            id: 'mem_owner_$businessId',
            businessId: businessId,
            userId: userId,
            role: BosRole.owner.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Use BEFORE switching the selected business. Returns the membership or
  /// throws if the user has no active membership there.
  static Future<BusinessMember> validateSwitch(
    AppDatabase db, {
    required String? userId,
    required String businessId,
  }) async {
    if (userId == null) {
      throw const PermissionDeniedException('You are not signed in.');
    }
    final row =
        await (db.select(db.businessMembers)..where(
              (m) => m.businessId.equals(businessId) & m.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (row == null || row.status != 'active') {
      throw const PermissionDeniedException(
        'You don\'t have active access to that business.',
      );
    }
    return row;
  }

  // ----- Internals -----------------------------------------------------------

  Future<BusinessMember?> _find(String businessId, String userId) =>
      (db.select(db.businessMembers)..where(
            (m) => m.businessId.equals(businessId) & m.userId.equals(userId),
          ))
          .getSingleOrNull();

  /// Fresh-from-DB actor + permission check.
  Future<BusinessMember> _actor(
    String businessId,
    BosPermission permission,
  ) async {
    final uid = auth.userId;
    if (uid == null) {
      throw const PermissionDeniedException('You are not signed in.');
    }
    final row = await _find(businessId, uid);
    if (row == null || row.status != 'active') {
      throw const PermissionDeniedException(
        'You are not an active member of this business.',
      );
    }
    final allowed = await PermissionsResolver.allowsRoleId(
      db,
      businessId: businessId,
      roleId: row.role,
      permission: permission,
    );
    if (!allowed) {
      throw PermissionDeniedException(
        'Your role isn\'t allowed to do this (${permission.id}).',
      );
    }
    return row;
  }

  Future<BusinessMember> _target(String businessId, String userId) async {
    final row = await _find(businessId, userId);
    if (row == null || row.status == 'removed') {
      throw StateError('That user isn\'t a member of this business.');
    }
    return row;
  }

  void _guardNotOwner(BusinessMember target) {
    if (target.role == BosRole.owner.id) {
      throw StateError(
        'The owner can\'t be changed directly. Transfer ownership first.',
      );
    }
  }

  /// A built-in role (not owner) or a custom role of this business.
  Future<void> _requireAssignable(String businessId, String roleId) async {
    if (roleId == BosRole.owner.id) {
      throw StateError('The owner role can\'t be assigned here.');
    }
    if (BosRole.fromId(roleId) != null) return;
    if (roleId.startsWith(kCustomRolePrefix)) {
      final c =
          await (db.select(db.customRoles)..where(
                (r) =>
                    r.businessId.equals(businessId) &
                    r.id.equals(roleId.substring(kCustomRolePrefix.length)),
              ))
              .getSingleOrNull();
      if (c != null) return;
    }
    throw StateError('That role no longer exists.');
  }

  Future<void> _write(String memberId, BusinessMembersCompanion data) =>
      (db.update(
        db.businessMembers,
      )..where((m) => m.id.equals(memberId))).write(data);

  // ----- Queries -------------------------------------------------------------

  Future<List<BusinessMember>> listMembers(String businessId) async {
    await _actor(businessId, BosPermission.usersView);
    return (db.select(db.businessMembers)
          ..where(
            (m) =>
                m.businessId.equals(businessId) &
                m.status.equals('removed').not(),
          )
          ..orderBy([(m) => OrderingTerm.asc(m.joinedAt)]))
        .get();
  }

  // ----- Invitations ---------------------------------------------------------

  Future<BusinessMember> invite({
    required String businessId,
    required String userId,
    required BosRole role,
  }) async {
    if (cloud != null) {
      throw StateError('Use an invite code to add people.');
    }
    return db.transaction(() async {
      final actor = await _actor(businessId, BosPermission.usersInvite);
      if (role == BosRole.owner) {
        throw StateError(
          'The owner role can\'t be given by invitation. Use ownership '
          'transfer.',
        );
      }
      final existing = await _find(businessId, userId);
      String memberId;
      if (existing == null) {
        memberId = _uuid.v4();
        await db
            .into(db.businessMembers)
            .insert(
              BusinessMembersCompanion.insert(
                id: memberId,
                businessId: businessId,
                userId: userId,
                role: role.id,
                status: const Value('invited'),
                invitedBy: Value(actor.userId),
              ),
            );
      } else if (existing.status == 'removed') {
        memberId = existing.id;
        await _write(
          memberId,
          BusinessMembersCompanion(
            role: Value(role.id),
            status: const Value('invited'),
            invitedBy: Value(actor.userId),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        throw StateError(
          'This user is already a member, or already has a pending invitation.',
        );
      }

      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: actor.userId,
        action: 'user.invited',
        entityType: 'business_member',
        entityId: memberId,
        details: {'invitedUserId': userId, 'role': role.id},
      );
      return (db.select(
        db.businessMembers,
      )..where((m) => m.id.equals(memberId))).getSingle();
    });
  }

  // ----- Invite codes ---------------------------------------------------------
  //
  // The email-based `invite()` above only works if the invitee already has
  // a Users row (there's no server to send a real email through). An invite
  // CODE sidesteps that: it isn't tied to any existing account, so someone
  // can hand it to a brand-new hire who redeems it the moment they register.

  static const _inviteCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _generateInviteCode() {
    final random = Random.secure();
    return List.generate(
      8,
      (_) => _inviteCodeChars[random.nextInt(_inviteCodeChars.length)],
    ).join();
  }

  /// Creates a redeemable code for [role] in [businessId]. The role is
  /// fixed at generation time — whoever redeems it joins as exactly that.
  Future<BusinessInvite> createInviteCode({
    required String businessId,
    required BosRole role,
  }) => createInviteCodeForId(businessId: businessId, roleId: role.id);

  Future<BusinessInvite> createInviteCodeForId({
    required String businessId,
    required String roleId,
  }) async {
    await _requireAssignable(businessId, roleId);
    await _actor(businessId, BosPermission.usersInvite);
    final cloudCode = await cloud?.createInviteCode(
      businessId: businessId,
      role: roleId,
    );

    return db.transaction(() async {
      final actor = await _actor(businessId, BosPermission.usersInvite);
      final id = _uuid.v4();
      final code = cloudCode ?? _generateInviteCode();
      await db
          .into(db.businessInvites)
          .insert(
            BusinessInvitesCompanion.insert(
              id: id,
              businessId: businessId,
              code: code,
              role: roleId,
              createdBy: actor.userId,
            ),
          );
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: actor.userId,
        action: 'user.invite_code_created',
        entityType: 'business_invite',
        entityId: id,
        details: {'role': roleId},
      );
      return (db.select(
        db.businessInvites,
      )..where((i) => i.id.equals(id))).getSingle();
    });
  }

  Future<void> changeRole({
    required String businessId,
    required String targetUserId,
    required BosRole newRole,
  }) => changeRoleToId(
    businessId: businessId,
    targetUserId: targetUserId,
    newRoleId: newRole.id,
  );

  Future<void> changeRoleToId({
    required String businessId,
    required String targetUserId,
    required String newRoleId,
  }) async {
    await _actor(businessId, BosPermission.usersManageRoles);
    await _requireAssignable(businessId, newRoleId);
    await cloud?.setMemberRole(
      businessId: businessId,
      userId: targetUserId,
      role: newRoleId,
    );
    return db.transaction(() async {
      final actor = await _actor(businessId, BosPermission.usersManageRoles);
      if (actor.userId == targetUserId) {
        throw StateError('You can\'t change your own role.');
      }
      final target = await _target(businessId, targetUserId);
      _guardNotOwner(target);

      await _write(
        target.id,
        BusinessMembersCompanion(
          role: Value(newRoleId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: actor.userId,
        action: 'user.role_changed',
        entityType: 'business_member',
        entityId: target.id,
        details: {
          'targetUserId': targetUserId,
          'from': target.role,
          'to': newRoleId,
        },
      );
    });
  }

  Future<void> revokeInviteCode({
    required String businessId,
    required String inviteId,
  }) async {
    await _actor(businessId, BosPermission.usersInvite);
    final inv =
        await (db.select(db.businessInvites)..where(
              (i) => i.id.equals(inviteId) & i.businessId.equals(businessId),
            ))
            .getSingleOrNull();
    if (inv != null) {
      await cloud?.revokeInviteCode(businessId: businessId, code: inv.code);
    }

    return db.transaction(() async {
      final actor = await _actor(businessId, BosPermission.usersInvite);
      await (db.update(db.businessInvites)..where(
            (i) => i.id.equals(inviteId) & i.businessId.equals(businessId),
          ))
          .write(const BusinessInvitesCompanion(status: Value('revoked')));
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: actor.userId,
        action: 'user.invite_code_revoked',
        entityType: 'business_invite',
        entityId: inviteId,
      );
    });
  }

  /// Read-only lookup for the registration screen to validate a code before
  /// creating the account. No permission check — the redeemer isn't a
  /// member of anything yet.
  static Future<BusinessInvite?> findPendingInvite(
    AppDatabase db,
    String code,
  ) {
    final normalized = code.trim().toUpperCase();
    return (db.select(
          db.businessInvites,
        )..where((i) => i.code.equals(normalized) & i.status.equals('pending')))
        .getSingleOrNull();
  }

  /// Self-service: a brand-new user redeems a code right after registering,
  /// joining [BusinessInvite.businessId] as [BusinessInvite.role] directly
  /// (no separate "accept" step — the code itself is the proof of consent).
  static Future<BusinessMember> redeemInviteCode(
    AppDatabase db, {
    required String code,
    required String userId,
  }) {
    return db.transaction(() async {
      final invite = await findPendingInvite(db, code);

      if (invite == null) {
        throw StateError(
          'That invitation code is invalid or has already been used.',
        );
      }

      final existing =
          await (db.select(db.businessMembers)..where(
                (m) =>
                    m.businessId.equals(invite.businessId) &
                    m.userId.equals(userId),
              ))
              .getSingleOrNull();

      final memberId = existing?.id ?? _uuid.v4();

      if (existing == null) {
        await db
            .into(db.businessMembers)
            .insert(
              BusinessMembersCompanion.insert(
                id: memberId,
                businessId: invite.businessId,
                userId: userId,
                role: invite.role,
                status: const Value('active'),

                // IMPORTANT:
                // Preserve the identity of the person who created the invite.
                invitedBy: Value(invite.createdBy),

                joinedAt: Value(DateTime.now()),
              ),
            );
      } else {
        await (db.update(
          db.businessMembers,
        )..where((m) => m.id.equals(memberId))).write(
          BusinessMembersCompanion(
            role: Value(invite.role),
            status: const Value('active'),

            // IMPORTANT:
            // Existing memberships must also receive the inviter.
            invitedBy: Value(invite.createdBy),

            joinedAt: Value(existing.joinedAt),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      await (db.update(
        db.businessInvites,
      )..where((i) => i.id.equals(invite.id))).write(
        BusinessInvitesCompanion(
          status: const Value('used'),
          usedByUserId: Value(userId),
          usedAt: Value(DateTime.now()),
        ),
      );

      await AuditLogger.record(
        db,
        businessId: invite.businessId,
        userId: userId,
        action: 'user.invite_code_redeemed',
        entityType: 'business_member',
        entityId: memberId,
        details: {'role': invite.role, 'invitedBy': invite.createdBy},
      );

      return (db.select(
        db.businessMembers,
      )..where((m) => m.id.equals(memberId))).getSingle();
    });
  }

  /// The INVITED user accepts. Only the addressee can activate their own
  /// invitation — an id existing is never enough.
  Future<void> acceptInvitation(String businessId) {
    return db.transaction(() async {
      final uid = auth.userId;
      if (uid == null) {
        throw const PermissionDeniedException('You are not signed in.');
      }
      final row = await _find(businessId, uid);
      if (row == null || row.status != 'invited') {
        throw StateError('There is no pending invitation for you here.');
      }
      await _write(
        row.id,
        BusinessMembersCompanion(
          status: const Value('active'),
          joinedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: uid,
        action: 'user.invitation_accepted',
        entityType: 'business_member',
        entityId: row.id,
        details: {'role': row.role},
      );
    });
  }

  Future<void> declineInvitation(String businessId) {
    return db.transaction(() async {
      final uid = auth.userId;
      if (uid == null) {
        throw const PermissionDeniedException('You are not signed in.');
      }
      final row = await _find(businessId, uid);
      if (row == null || row.status != 'invited') return;
      await _write(
        row.id,
        BusinessMembersCompanion(
          status: const Value('removed'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: uid,
        action: 'user.invitation_declined',
        entityType: 'business_member',
        entityId: row.id,
      );
    });
  }

  Future<void> setSuspended({
    required String businessId,
    required String targetUserId,
    required bool suspended,
  }) async {
    await _actor(businessId, BosPermission.usersManageRoles);
    await cloud?.setMemberSuspended(
      businessId: businessId,
      userId: targetUserId,
      suspended: suspended,
    );

    return db.transaction(() async {
      final actor = await _actor(businessId, BosPermission.usersManageRoles);
      if (actor.userId == targetUserId) {
        throw StateError('You can\'t suspend yourself.');
      }
      final target = await _target(businessId, targetUserId);
      _guardNotOwner(target);
      if (target.status == 'invited') {
        throw StateError('Invitations can\'t be suspended — remove them.');
      }

      await _write(
        target.id,
        BusinessMembersCompanion(
          status: Value(suspended ? 'suspended' : 'active'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: actor.userId,
        action: suspended ? 'user.suspended' : 'user.reactivated',
        entityType: 'business_member',
        entityId: target.id,
        details: {'targetUserId': targetUserId},
      );
    });
  }

  Future<void> removeMember({
    required String businessId,
    required String targetUserId,
  }) async {
    await _actor(businessId, BosPermission.usersRemove);
    await cloud?.removeMember(businessId: businessId, userId: targetUserId);
    return db.transaction(() async {
      final actor = await _actor(businessId, BosPermission.usersRemove);
      if (actor.userId == targetUserId) {
        throw StateError('You can\'t remove yourself.');
      }
      final target = await _target(businessId, targetUserId);
      _guardNotOwner(target);

      await _write(
        target.id,
        BusinessMembersCompanion(
          status: const Value('removed'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: actor.userId,
        action: 'user.removed',
        entityType: 'business_member',
        entityId: target.id,
        details: {'targetUserId': targetUserId, 'role': target.role},
      );
    });
  }

  // ----- Ownership -----------------------------------------------------------

  /// Owner-only. The current owner becomes a Manager; the target (an ACTIVE
  /// member) becomes the single owner. Businesses.ownerUserId is kept in sync
  /// for compatibility.
  Future<void> transferOwnership({
    required String businessId,
    required String newOwnerUserId,
  }) async {
    await _actor(businessId, BosPermission.businessDelete);
    await cloud?.transferOwnership(
      businessId: businessId,
      newOwnerUserId: newOwnerUserId,
    );

    return db.transaction(() async {
      final actor = await _actor(businessId, BosPermission.businessDelete);
      if (actor.role != BosRole.owner.id) {
        throw const PermissionDeniedException('Only the owner can do this.');
      }
      if (actor.userId == newOwnerUserId) {
        throw StateError('You are already the owner.');
      }
      final target = await _target(businessId, newOwnerUserId);
      if (target.status != 'active') {
        throw StateError('Ownership can only go to an active member.');
      }

      final now = DateTime.now();
      // Demote first: a partial unique index allows only one live owner row.
      await _write(
        actor.id,
        BusinessMembersCompanion(
          role: Value(BosRole.manager.id),
          updatedAt: Value(now),
        ),
      );
      await _write(
        target.id,
        BusinessMembersCompanion(
          role: Value(BosRole.owner.id),
          updatedAt: Value(now),
        ),
      );
      await (db.update(db.businesses)..where((b) => b.id.equals(businessId)))
          .write(BusinessesCompanion(ownerUserId: Value(newOwnerUserId)));

      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: actor.userId,
        action: 'business.ownership_transferred',
        entityType: 'business',
        entityId: businessId,
        details: {'from': actor.userId, 'to': newOwnerUserId},
      );
    });
  }
}
