// lib/core/business/business_service.dart
//
// All business lifecycle operations in one place: create (with seeding +
// owner membership, atomically), update profile, switch the current
// selection, archive/reactivate, and delete (only when the business has no
// financial history). Everything here takes an explicit businessId — no
// hidden global state — so the same code maps cleanly onto Supabase
// row-level security later.

import 'package:bos_application/core/business/local_business_purge.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/authorization_providers.dart';
import '../auth/authorization_service.dart';
import '../auth/bos_access.dart';
import '../auth/membership_service.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../sync/sync_tracker.dart';

const _uuid = Uuid();

class BusinessException implements Exception {
  final String message;
  const BusinessException(this.message);

  @override
  String toString() => message;
}

/// Valid business operating models. Extensible: new ids need no migration.
abstract final class BusinessTypes {
  static const retailer = 'retailer';
  static const wholesaler = 'wholesaler';
  static const distributor = 'distributor';
  static const manufacturer = 'manufacturer';
  static const serviceProvider = 'service_provider';

  static const labels = <String, String>{
    retailer: 'Retailer',
    wholesaler: 'Wholesaler',
    distributor: 'Distributor',
    manufacturer: 'Manufacturer',
    serviceProvider: 'Service provider',
  };

  static String labelOf(String? id) => labels[id] ?? id ?? '';
}

final businessServiceProvider = Provider<BusinessService>(
  (ref) => BusinessService(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
    cloud: ref.watch(supabaseAvailableProvider)
        ? ref.watch(cloudBusinessServiceProvider)
        : null,
  ),
);

class BusinessService {
  final AppDatabase db;
  final AuthorizationService auth;
  final CloudBusinessService? cloud;
  BusinessService(this.db, this.auth, {this.cloud});

  /// Every ACTIVE business the signed-in user belongs to. This is the only
  /// correct way to list "my businesses" — never query Businesses directly
  /// without going through BusinessMembers, or another tenant's rows leak.
  Future<List<BusinessesData>> listMyBusinesses({
    bool includeArchived = false,
  }) async {
    final uid = auth.userId;
    if (uid == null) return const [];

    final memberships = await (db.select(
      db.businessMembers,
    )..where((m) => m.userId.equals(uid) & m.status.equals('active'))).get();
    if (memberships.isEmpty) return const [];

    final ids = memberships.map((m) => m.businessId).toList();
    var query = db.select(db.businesses)..where((b) => b.id.isIn(ids));
    if (!includeArchived) {
      query = query..where((b) => b.isActive.equals(true));
    }
    return (query..orderBy([(b) => OrderingTerm.asc(b.name)])).get();
  }

  /// The currently-selected business, validated: must exist, be active, and
  /// be a business the signed-in user actively belongs to. Returns null when
  /// the stored selection is stale (archived/deleted/not a member) so the
  /// caller can pick a fallback.
  Future<BusinessesData?> resolveCurrent(String? businessId) async {
    if (businessId == null) return null;
    final uid = auth.userId;
    if (uid == null) return null;

    final row = await (db.select(
      db.businesses,
    )..where((b) => b.id.equals(businessId))).getSingleOrNull();
    if (row == null || !row.isActive) return null;

    final membership =
        await (db.select(db.businessMembers)..where(
              (m) =>
                  m.businessId.equals(businessId) &
                  m.userId.equals(uid) &
                  m.status.equals('active'),
            ))
            .getSingleOrNull();
    if (membership == null) return null;
    return row;
  }

  Future<BusinessesData> _requireActive(String businessId) async {
    final row = await (db.select(
      db.businesses,
    )..where((b) => b.id.equals(businessId))).getSingleOrNull();
    if (row == null) {
      throw const BusinessException('That business does not exist.');
    }
    if (!row.isActive) {
      throw const BusinessException(
        'That business is archived. Reactivate it first.',
      );
    }
    return row;
  }

  /// Creates a new business with its owner membership and default chart of
  /// accounts/categories, atomically. When [setAsCurrent] is true the new
  /// business becomes the current selection in the same transaction.
  Future<BusinessesData> createBusiness({
    required String name,
    String? businessType,
    String? industry,
    String? legalName,
    String? description,
    String? email,
    String? phone,
    String currency = 'PHP',
    String timezone = 'Asia/Manila',
    bool setAsCurrent = true,
  }) async {
    final uid = auth.userId;
    if (uid == null) {
      throw const PermissionDeniedException('You are not signed in.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const BusinessException('Enter a business name.');
    }

    // Create it in the cloud FIRST so the server creates the business row and
    // the owner membership. Without that, RLS rejects every later upload.
    final String id;
    final cloudService = cloud;
    if (cloudService != null) {
      try {
        id = await cloudService.createBusiness(
          name: trimmed,
          businessType: businessType,
          industry: industry?.trim(),
          currencyCode: currency,
          timezone: timezone,
        );
      } on CloudBusinessException catch (e) {
        throw BusinessException(
          e.code == 'network_error'
              ? 'You need an internet connection to create a business.'
              : e.message,
        );
      }
    } else {
      id = _uuid.v4();
    }

    await db.transaction(() async {
      if (setAsCurrent) {
        await (db.update(
          db.businesses,
        )).write(const BusinessesCompanion(isCurrent: Value(false)));
      }

      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: id,
              name: trimmed,
              legalName: Value(legalName?.trim()),
              businessType: Value(businessType),
              industry: Value(industry?.trim()),
              businessCategory: Value(industry?.trim()),
              description: Value(description?.trim()),
              email: Value(email?.trim()),
              phone: Value(phone?.trim()),
              currency: Value(currency),
              timezone: Value(timezone),
              ownerUserId: uid,
              isCurrent: Value(setAsCurrent),
            ),
          );

      // Deterministic ids + insertOrIgnore inside => safe to re-run.
      await db.seedDefaultsForBusiness(id);
      await MembershipService.insertOwnerMembership(
        db,
        businessId: id,
        userId: uid,
      );
    });

    return (db.select(
      db.businesses,
    )..where((b) => b.id.equals(id))).getSingle();
  }

  /// Updates profile fields. Writes both `industry` and the legacy
  /// `businessCategory` so old screens keep working.
  Future<void> updateProfile(
    String businessId, {
    String? name,
    String? legalName,
    String? businessType,
    String? industry,
    String? description,
    String? email,
    String? phone,
    String? currency,
    String? timezone,
    String? logoPath,
  }) async {
    auth.require(BosPermission.businessSettings, businessId: businessId);
    await _requireActive(businessId);

    if (name != null && name.trim().isEmpty) {
      throw const BusinessException('The business name cannot be empty.');
    }

    await (db.update(
      db.businesses,
    )..where((b) => b.id.equals(businessId))).write(
      BusinessesCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        legalName: legalName == null
            ? const Value.absent()
            : Value(legalName.trim()),
        businessType: Value(businessType),
        industry: industry == null
            ? const Value.absent()
            : Value(industry.trim()),
        businessCategory: industry == null
            ? const Value.absent()
            : Value(industry.trim()),
        description: description == null
            ? const Value.absent()
            : Value(description.trim()),
        email: email == null ? const Value.absent() : Value(email.trim()),
        phone: phone == null ? const Value.absent() : Value(phone.trim()),
        currency: currency == null ? const Value.absent() : Value(currency),
        timezone: timezone == null ? const Value.absent() : Value(timezone),
        logoPath: Value(logoPath),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await SyncTracker.record(
      db,
      businessId: businessId,
      entityType: 'businesses',
      entityId: businessId,
      operation: SyncOp.update,
    );
  }

  /// Marks [businessId] current and clears the flag everywhere else,
  /// atomically. The caller updates its local current-business state
  /// afterward. Throws when the business is archived or the user has no
  /// active membership.
  Future<BusinessesData> switchTo(String businessId) async {
    final business = await _requireActive(businessId);
    await MembershipService.validateSwitch(
      db,
      userId: auth.userId,
      businessId: businessId,
    );

    await db.transaction(() async {
      await (db.update(
        db.businesses,
      )).write(const BusinessesCompanion(isCurrent: Value(false)));
      await (db.update(db.businesses)..where((b) => b.id.equals(businessId)))
          .write(const BusinessesCompanion(isCurrent: Value(true)));
    });

    return business;
  }

  /// Archives a business: it stays fully readable as history but can no
  /// longer be switched into. Owner-only. Refuses to archive the business
  /// that is currently selected while it's the user's only active business.
  Future<void> archive(String businessId) async {
    auth.requireOwner();
    auth.require(BosPermission.businessManage, businessId: businessId);

    final business = await _requireActive(businessId);
    final remaining = (await listMyBusinesses())
        .where((b) => b.id != businessId)
        .toList();

    await db.transaction(() async {
      await (db.update(
        db.businesses,
      )..where((b) => b.id.equals(businessId))).write(
        BusinessesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'businesses',
        entityId: businessId,
        operation: SyncOp.update,
      );

      // If we just archived the current selection, move it to another
      // active business the user belongs to (or leave none when empty).
      if (business.isCurrent && remaining.isNotEmpty) {
        await (db.update(db.businesses)..where((b) => b.id.equals(businessId)))
            .write(const BusinessesCompanion(isCurrent: Value(false)));
        await (db.update(db.businesses)
              ..where((b) => b.id.equals(remaining.first.id)))
            .write(const BusinessesCompanion(isCurrent: Value(true)));
      }
    });
  }

  Future<void> reactivate(String businessId) async {
    auth.requireOwner();
    auth.require(BosPermission.businessManage, businessId: businessId);
    await (db.update(
      db.businesses,
    )..where((b) => b.id.equals(businessId))).write(
      BusinessesCompanion(
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await SyncTracker.record(
      db,
      businessId: businessId,
      entityType: 'businesses',
      entityId: businessId,
      operation: SyncOp.update,
    );
  }

  /// Whether a business can be permanently deleted: only when it has never
  /// posted a journal entry. Financial history is never destroyed.
  Future<bool> canDelete(String businessId) async {
    final row = await db
        .customSelect(
          'SELECT EXISTS(SELECT 1 FROM journal_entries WHERE business_id = ?) '
          'AS has_entries',
          variables: [Variable.withString(businessId)],
        )
        .getSingle();
    return row.read<int>('has_entries') == 0;
  }

  /// Permanently deletes a business with no financial history, purging its
  /// business-owned rows in FK-safe order. Anything with ledger history must
  /// be archived instead — [canDelete] enforces that.
  Future<void> delete(String businessId) async {
    auth.requireOwner();
    auth.require(BosPermission.businessDelete, businessId: businessId);

    if (!await canDelete(businessId)) {
      throw const BusinessException(
        'This business has financial records, so it cannot be deleted. '
        'Archive it instead to preserve its history.',
      );
    }

    // Cloud first: if this fails, nothing is deleted locally.
    final cloudService = cloud;
    if (cloudService != null) {
      try {
        await cloudService.deleteBusiness(businessId);
      } on CloudBusinessException catch (e) {
        throw BusinessException(
          e.code == 'network_error'
              ? 'You need an internet connection to delete a business.'
              : e.message,
        );
      }
    }

    try {
      await purgeLocalBusiness(db, businessId);
    } on BusinessPurgeException catch (e) {
      throw BusinessException(e.message);
    }
  }
}
