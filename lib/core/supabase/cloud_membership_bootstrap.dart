// lib/core/supabase/cloud_membership_bootstrap.dart
//
// After a user joins a business in Supabase (invite-code redemption, or
// signing in on a new device), the rest of the app still reads Drift. This
// copies the user's cloud memberships + business rows into Drift so the
// existing providers (membership -> role -> permissions) just work.
//
// Rules:
//   * Cloud is authoritative for memberships (always upserted).
//   * A business row is only inserted when it isn't already local, so local
//     edits are never overwritten by a thinner cloud row.
//   * Default accounts/categories are seeded for newly added businesses using
//     the same deterministic ids the owner's device used, so ids line up with
//     whatever the sync pull later brings in.

import 'package:bos_application/core/business/local_business_purge.dart';
import 'package:bos_application/core/sync/sync_change_log.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../sync/sync_tracker.dart';

/// SharedPreferences key used to remember an invite code across the
/// email-confirmation step of registration. Keyed by email so a code saved
/// for one account can never be redeemed by a different account that signs
/// in later on the same device.
String pendingInviteKey(String email) =>
    'pending_invite_${email.trim().toLowerCase()}';

/// SharedPreferences key set at registration when the person chose to start
/// their own business (no invite code). Keyed by email, like the invite key,
/// so it survives the email-confirmation step.
String createBusinessIntentKey(String email) =>
    'create_business_${email.trim().toLowerCase()}';

class CloudAdoptResult {
  /// Businesses that were NOT in Drift before this call.
  final List<String> addedBusinessIds;

  /// Businesses removed locally because the owner deleted them.
  final List<String> removedBusinessIds;

  const CloudAdoptResult(
    this.addedBusinessIds, [
    this.removedBusinessIds = const [],
  ]);

  String? get firstAdded =>
      addedBusinessIds.isEmpty ? null : addedBusinessIds.first;
}

/// RLS only returns tombstones for businesses this account belonged to.
Future<List<String>> purgeDeletedBusinesses(
  AppDatabase db,
  SupabaseClient client,
) async {
  final rows = await client.from('deleted_businesses').select('business_id');
  final purged = <String>[];
  for (final r in rows) {
    final id = r['business_id'] as String;
    final local = await (db.select(
      db.businesses,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    if (local == null) continue;
    await purgeLocalBusiness(db, id);
    purged.add(id);
  }
  return purged;
}

Future<CloudAdoptResult> adoptCloudAccess(
  AppDatabase db,
  SupabaseClient client, {
  required String userId,
  bool seedDefaults = true,
}) async {
  final removed = <String>[];
  try {
    removed.addAll(await purgeDeletedBusinesses(db, client));
  } catch (_) {
    // Offline or table missing: skipped, retried on the next refresh.
  }
  final mine = List<Map<String, dynamic>>.from(
    await client
        .from('business_memberships')
        .select()
        .eq('user_id', userId)
        .eq('status', 'active'),
  );

  final activeBusinessIds = {for (final r in mine) r['business_id'] as String};
  final added = <String>[];

  for (final myRow in mine) {
    final businessId = myRow['business_id'] as String;

    final business = await client
        .from('businesses')
        .select()
        .eq('id', businessId)
        .maybeSingle();
    if (business == null) continue;

    // Everyone in the business, so Users & Roles isn't empty on this device.
    // RLS may only allow your own row; fall back to that.
    var everyone = <Map<String, dynamic>>[myRow];
    try {
      everyone = List<Map<String, dynamic>>.from(
        await client
            .from('business_memberships')
            .select()
            .eq('business_id', businessId),
      );
      if (!everyone.any((r) => r['id'] == myRow['id'])) everyone.add(myRow);
    } catch (_) {}

    final alreadyLocal =
        await (db.select(
          db.businesses,
        )..where((b) => b.id.equals(businessId))).getSingleOrNull() !=
        null;

    // Best-effort owner display name (RLS may hide other people's profiles).
    String? ownerName;
    try {
      final profile = await client
          .from('profiles')
          .select('display_name')
          .eq('id', business['owner_user_id'] as String)
          .maybeSingle();
      final name = (profile?['display_name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) ownerName = name;
    } catch (_) {}

    // Rows copied down from the cloud are not local edits; never echo them
    // back to the server.
    await SyncChangeLog.suppressed(
      db,
      () => db.transaction(() async {
        if (!alreadyLocal) {
          await db
              .into(db.businesses)
              .insert(
                businessCompanionFromCloud(business, ownerName: ownerName),
                mode: InsertMode.insertOrIgnore,
              );
        }
        for (final row in everyone) {
          if (row['user_id'] == userId) continue; // own row is written last
          await _upsertMember(db, row);
        }
        await _upsertMember(db, myRow); // active row always wins
      }),
    );

    if (!alreadyLocal) {
      if (seedDefaults) {
        // Same deterministic ids as the owner's device; the first pull
        // overwrites them with the cloud's real values.
        await SyncChangeLog.suppressed(
          db,
          () => db.seedDefaultsForBusiness(businessId),
        );
      }
      added.add(businessId);
    }
  }
  // Pick up suspensions/removals of THIS user so a revoked member loses
  // access on this device too.
  final inactive = await client
      .from('business_memberships')
      .select('business_id, status')
      .eq('user_id', userId)
      .neq('status', 'active');
  for (final r in inactive) {
    final bid = r['business_id'] as String;
    if (activeBusinessIds.contains(bid)) continue; // an active row exists

    await (db.update(
      db.businessMembers,
    )..where((m) => m.userId.equals(userId) & m.businessId.equals(bid))).write(
      BusinessMembersCompanion(
        status: Value(r['status'] as String),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  return CloudAdoptResult(added, removed);
}

/// One-time upgrade path: profiles saved before business edits were synced
/// exist only on the device that saved them. When the cloud row has no
/// profile but this device does, queue it so other devices receive it.
Future<bool> queueLocalProfileIfCloudBlank(
  AppDatabase db,
  SupabaseClient client, {
  required String businessId,
}) async {
  final local = await (db.select(
    db.businesses,
  )..where((b) => b.id.equals(businessId))).getSingleOrNull();
  if (local == null) return false;

  final hasLocalProfile =
      (local.ownerName?.trim().isNotEmpty ?? false) ||
      (local.businessCategory?.trim().isNotEmpty ?? false) ||
      (local.industry?.trim().isNotEmpty ?? false);
  if (!hasLocalProfile) return false;

  final cloud = await client
      .from('businesses')
      .select('owner_name, business_category, industry')
      .eq('id', businessId)
      .maybeSingle();
  if (cloud == null) return false;

  final cloudHasProfile = [
    cloud['owner_name'],
    cloud['business_category'],
    cloud['industry'],
  ].any((v) => v is String && v.trim().isNotEmpty);
  if (cloudHasProfile) return false;

  await SyncTracker.record(
    db,
    businessId: businessId,
    entityType: 'businesses',
    entityId: businessId,
    operation: SyncOp.update,
  );
  return true;
}

/// Builds the local business row for a business adopted from the cloud.
///
/// The cloud row is authoritative, so a business that already exists there
/// must never send the user back through "Set up your profile": text fields
/// the owner never filled in become empty strings (the onboarding check looks
/// for null), and the profile the owner saved on another device is carried
/// over as-is.
BusinessesCompanion businessCompanionFromCloud(
  Map<String, dynamic> b, {
  String? ownerName,
}) {
  String? text(String key) {
    final value = (b[key] as String?)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? firstText(List<String> keys) {
    for (final key in keys) {
      final value = text(key);
      if (value != null) return value;
    }
    return null;
  }

  final industry = firstText(['industry', 'business_category']);
  return BusinessesCompanion.insert(
    id: b['id'] as String,
    name: b['name'] as String,
    ownerUserId: b['owner_user_id'] as String,
    legalName: Value(text('legal_name')),
    businessType: Value(text('business_type')),
    industry: Value(industry),
    businessCategory: Value(firstText(['business_category', 'industry']) ?? ''),
    ownerName: Value(firstText(['owner_name']) ?? ownerName ?? ''),
    managerName: Value(text('manager_name')),
    description: Value(text('description')),
    email: Value(text('email')),
    phone: Value(text('phone')),
    addressCountry: Value(firstText(['address_country', 'country'])),
    addressProvince: Value(firstText(['address_province', 'province'])),
    addressCity: Value(firstText(['address_city', 'city'])),
    addressBarangay: Value(firstText(['address_barangay', 'barangay'])),
    addressZipCode: Value(firstText(['address_zip_code', 'postal_code'])),
    startingCapital: Value((b['starting_capital'] as num?)?.toInt() ?? 0),
    startingCapitalAccountId: Value(text('starting_capital_account_id')),
    currency: Value(firstText(['currency_code', 'currency']) ?? 'PHP'),
    timezone: Value(text('timezone') ?? 'Asia/Manila'),
    logoPath: Value(text('logo_path')),
    isActive: Value((b['is_active'] as bool?) ?? true),
    createdAt: Value(_dt(b['created_at'])),
    updatedAt: Value(_dt(b['updated_at'])),
  );
}

Future<void> _upsertMember(AppDatabase db, Map<String, dynamic> r) async {
  final businessId = r['business_id'] as String;
  final memberUserId = r['user_id'] as String;

  final matches =
      await (db.select(db.businessMembers)..where(
            (m) =>
                m.businessId.equals(businessId) & m.userId.equals(memberUserId),
          ))
          .get();
  final existing = matches.isEmpty ? null : matches.first;
  for (final extra in matches.skip(1)) {
    await (db.delete(
      db.businessMembers,
    )..where((m) => m.id.equals(extra.id))).go();
  }

  final invitedBy = r['invited_by'] as String?;
  final joinedAt = r['joined_at'] == null ? null : _dt(r['joined_at']);
  if (existing == null && (r['status'] as String?) == 'removed') return;
  final updatedAt = r['updated_at'] == null
      ? DateTime.now()
      : _dt(r['updated_at']);

  if (existing == null) {
    await db
        .into(db.businessMembers)
        .insert(
          BusinessMembersCompanion.insert(
            id: r['id'] as String,
            businessId: businessId,
            userId: memberUserId,
            role: r['role'] as String,
            status: Value((r['status'] as String?) ?? 'active'),
            invitedBy: Value(invitedBy),
            joinedAt: Value(joinedAt ?? DateTime.now()),
            updatedAt: Value(updatedAt),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  } else {
    await (db.update(
      db.businessMembers,
    )..where((m) => m.id.equals(existing.id))).write(
      BusinessMembersCompanion(
        role: Value(r['role'] as String),
        status: Value((r['status'] as String?) ?? 'active'),
        invitedBy: Value(invitedBy),
        joinedAt: Value(joinedAt ?? existing.joinedAt),
        updatedAt: Value(updatedAt),
      ),
    );
  }
}

Future<void> syncBusinessUsers(
  AppDatabase db,
  SupabaseClient client, {
  required String businessId,
}) async {
  // Members (with local identity shells so names show up)
  final members = List<Map<String, dynamic>>.from(
    await client.rpc(
      'list_business_members',
      params: {'p_business_id': businessId},
    ),
  );
  for (final r in members) {
    final uid = r['user_id'] as String;
    final email = ((r['email'] as String?) ?? '$uid@cloud.local').toLowerCase();
    final name = (r['display_name'] as String?)?.trim() ?? '';
    final existingUser = await (db.select(
      db.users,
    )..where((u) => u.id.equals(uid))).getSingleOrNull();
    if (existingUser == null) {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: uid,
              email: email,
              passwordHash: 'cloud',
              passwordSalt: 'cloud',
              displayName: name.isEmpty ? email.split('@').first : name,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else if (name.isNotEmpty && name != existingUser.displayName) {
      // The person renamed themselves: take the cloud name. Only written when
      // it actually differs, so unchanged syncs cause no database churn.
      await (db.update(db.users)..where((u) => u.id.equals(uid))).write(
        UsersCompanion(displayName: Value(name)),
      );
    }
    await _upsertMember(db, {...r, 'business_id': businessId});
  }

  // Invite codes (match on code; local and cloud ids differ)
  final invites = List<Map<String, dynamic>>.from(
    await client
        .from('business_invites')
        .select()
        .eq('business_id', businessId),
  );
  for (final r in invites) {
    final code = r['code'] as String;
    final existing = await (db.select(
      db.businessInvites,
    )..where((i) => i.code.equals(code))).getSingleOrNull();
    final status = Value(r['status'] as String);
    final usedBy = Value(r['used_by_user_id'] as String?);
    final usedAt = Value(r['used_at'] == null ? null : _dt(r['used_at']));
    if (existing == null) {
      await db
          .into(db.businessInvites)
          .insert(
            BusinessInvitesCompanion.insert(
              id: r['id'] as String,
              businessId: businessId,
              code: code,
              role: r['role'] as String,
              createdBy: r['created_by'] as String,
              status: status,
              usedByUserId: usedBy,
              usedAt: usedAt,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (db.update(
        db.businessInvites,
      )..where((i) => i.id.equals(existing.id))).write(
        BusinessInvitesCompanion(
          status: status,
          usedByUserId: usedBy,
          usedAt: usedAt,
        ),
      );
    }
  }
}

DateTime _dt(Object? v) {
  if (v is String) return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
  return DateTime.now();
}
