// lib/core/branch/branch_service.dart  (NEW FILE)
//
// Create / edit / deactivate branches and assign staff.
// Writes are picked up by the SQLite change-log triggers (branches and
// branch_members are registered in sync_change_log.dart), so no manual
// SyncTracker.record calls are needed.

import 'dart:math' as math;

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart'
    show AuditLogger;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';

const _uuid = Uuid();

const philippineProvinces = [
  'Abra',
  'Agusan del Norte',
  'Agusan del Sur',
  'Aklan',
  'Albay',
  'Antique',
  'Apayao',
  'Aurora',
  'Basilan',
  'Bataan',
  'Batanes',
  'Batangas',
  'Benguet',
  'Biliran',
  'Bohol',
  'Bukidnon',
  'Bulacan',
  'Cagayan',
  'Camarines Norte',
  'Camarines Sur',
  'Camiguin',
  'Capiz',
  'Catanduanes',
  'Cavite',
  'Cebu',
  'Cotabato',
  'Davao de Oro',
  'Davao del Norte',
  'Davao del Sur',
  'Davao Occidental',
  'Davao Oriental',
  'Dinagat Islands',
  'Eastern Samar',
  'Guimaras',
  'Ifugao',
  'Ilocos Norte',
  'Ilocos Sur',
  'Iloilo',
  'Isabela',
  'Kalinga',
  'La Union',
  'Laguna',
  'Lanao del Norte',
  'Lanao del Sur',
  'Leyte',
  'Maguindanao del Norte',
  'Maguindanao del Sur',
  'Marinduque',
  'Masbate',
  'Metro Manila (NCR)',
  'Misamis Occidental',
  'Misamis Oriental',
  'Mountain Province',
  'Negros Occidental',
  'Negros Oriental',
  'Northern Samar',
  'Nueva Ecija',
  'Nueva Vizcaya',
  'Occidental Mindoro',
  'Oriental Mindoro',
  'Palawan',
  'Pampanga',
  'Pangasinan',
  'Quezon',
  'Quirino',
  'Rizal',
  'Romblon',
  'Samar',
  'Sarangani',
  'Siquijor',
  'Sorsogon',
  'South Cotabato',
  'Southern Leyte',
  'Sultan Kudarat',
  'Sulu',
  'Surigao del Norte',
  'Surigao del Sur',
  'Tarlac',
  'Tawi-Tawi',
  'Zambales',
  'Zamboanga del Norte',
  'Zamboanga del Sur',
  'Zamboanga Sibugay',
];

bool isPhilippinesCountry(String country) {
  final normalized = country.trim().toLowerCase();
  return normalized == 'ph' ||
      normalized == 'philippines' ||
      normalized == 'the philippines';
}

String formatBranchAddress({
  required String country,
  required String province,
  required String city,
  required String streetBarangay,
  required String postalCode,
}) => [
  streetBarangay.trim(),
  city.trim(),
  province.trim(),
  postalCode.trim(),
  country.trim(),
].where((part) => part.isNotEmpty).join(', ');

void validateBranchAddress({
  required String country,
  required String province,
  required String city,
  required String streetBarangay,
  required String postalCode,
}) {
  final fields = {
    'country': country,
    'province/state': province,
    'city': city,
    'street/barangay': streetBarangay,
    'postal code': postalCode,
  };
  final missing = fields.entries
      .where((entry) => entry.value.trim().isEmpty)
      .map((entry) => entry.key)
      .toList();
  if (missing.isNotEmpty) {
    throw StateError(
      'Enter the required branch address: ${missing.join(', ')}.',
    );
  }
}

class BranchService {
  BranchService(this.db, this.auth);
  final AppDatabase db;
  final AuthorizationService auth;

  Future<Branch> _get(String id) =>
      (db.select(db.branches)..where((b) => b.id.equals(id))).getSingle();

  /// Short unique code from the name: "Downtown Cafe" -> "DC", "Mall" -> "MAL".
  Future<String> _uniqueCode(String businessId, String name) async {
    final words = name
        .toUpperCase()
        .split(RegExp(r'[^A-Z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final base = words.isEmpty
        ? 'BR'
        : words.length > 1
        ? words.take(3).map((w) => w[0]).join()
        : words.first.substring(0, math.min(3, words.first.length));
    final taken =
        (await (db.select(
              db.branches,
            )..where((b) => b.businessId.equals(businessId))).get())
            .map((b) => (b.code ?? '').toUpperCase())
            .toSet();
    var code = base;
    var n = 2;
    while (taken.contains(code)) {
      code = '$base$n';
      n++;
    }
    return code;
  }

  /// New branch + its own cash drawer account. Starts with zero stock.
  Future<Branch> createBranch({
    required String businessId,
    required String name,
    required String country,
    required String province,
    required String city,
    required String streetBarangay,
    required String postalCode,
    String? phone,
  }) async {
    auth.require(BosPermission.branchManage, businessId: businessId);
    final clean = name.trim();
    if (clean.isEmpty) throw StateError('Enter a branch name.');
    validateBranchAddress(
      country: country,
      province: province,
      city: city,
      streetBarangay: streetBarangay,
      postalCode: postalCode,
    );
    final address = formatBranchAddress(
      country: country,
      province: province,
      city: city,
      streetBarangay: streetBarangay,
      postalCode: postalCode,
    );

    final id = _uuid.v4();
    final cashId = _uuid.v4();
    await db.transaction(() async {
      final code = await _uniqueCode(businessId, clean);
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: cashId,
              businessId: businessId,
              name: 'Cash on Hand - $clean',
              type: 'asset',
              isPaymentAccount: const Value(true),
            ),
          );
      await db
          .into(db.branches)
          .insert(
            BranchesCompanion.insert(
              id: id,
              businessId: businessId,
              name: clean,
              code: Value(code),
              address: Value(address),
              phone: Value(_blankToNull(phone)),
              cashAccountId: Value(cashId),
            ),
          );
      await _writeLocation(
        branchId: id,
        country: country,
        province: province,
        city: city,
        streetBarangay: streetBarangay,
        postalCode: postalCode,
      );
      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: auth.userId,
        action: 'admin.branch_created',
        module: AuditModule.administration,
        actionType: AuditActionType.create,
        entityType: 'branches',
        entityId: id,
        entityLabel: clean,
        after: {'name': clean, 'code': code},
      );
    });
    return _get(id);
  }

  Future<void> updateBranch(
    String branchId, {
    required String name,
    required String country,
    required String province,
    required String city,
    required String streetBarangay,
    required String postalCode,
    String? phone,
  }) async {
    final b = await _get(branchId);
    auth.require(BosPermission.branchManage, businessId: b.businessId);
    final clean = name.trim();
    if (clean.isEmpty) throw StateError('Enter a branch name.');
    validateBranchAddress(
      country: country,
      province: province,
      city: city,
      streetBarangay: streetBarangay,
      postalCode: postalCode,
    );
    final address = formatBranchAddress(
      country: country,
      province: province,
      city: city,
      streetBarangay: streetBarangay,
      postalCode: postalCode,
    );
    await db.transaction(() async {
      await (db.update(db.branches)..where((x) => x.id.equals(branchId))).write(
        BranchesCompanion(
          name: Value(clean),
          address: Value(address),
          phone: Value(_blankToNull(phone)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _writeLocation(
        branchId: branchId,
        country: country,
        province: province,
        city: city,
        streetBarangay: streetBarangay,
        postalCode: postalCode,
      );
      final cash = b.cashAccountId;
      if (cash != null && !b.isHeadquarters) {
        await (db.update(db.accounts)..where((a) => a.id.equals(cash))).write(
          AccountsCompanion(name: Value('Cash on Hand - $clean')),
        );
      }
    });
  }

  Future<void> _writeLocation({
    required String branchId,
    required String country,
    required String province,
    required String city,
    required String streetBarangay,
    required String postalCode,
  }) => db.customStatement(
    'UPDATE branches SET country = ?, province_state = ?, city = ?, '
    'street_barangay = ?, postal_code = ? WHERE id = ?',
    [
      country.trim(),
      province.trim(),
      city.trim(),
      streetBarangay.trim(),
      postalCode.trim(),
      branchId,
    ],
  );

  Future<void> setActive(String branchId, bool active) async {
    await db.transaction(() async {
      final b = await _get(branchId);
      auth.require(BosPermission.branchManage, businessId: b.businessId);
      if (!active) {
        if (b.isHeadquarters) {
          throw StateError('The main branch can\'t be deactivated.');
        }
        final open =
            await (db.select(db.posSessions)..where(
                  (s) => s.branchId.equals(branchId) & s.status.equals('open'),
                ))
                .get();
        if (open.isNotEmpty) {
          throw StateError('Close the open shift at this branch first.');
        }
        final moving =
            await (db.select(db.stockTransfers)..where(
                  (t) =>
                      t.status.equals('in_transit') &
                      (t.fromBranchId.equals(branchId) |
                          t.toBranchId.equals(branchId)),
                ))
                .get();
        if (moving.isNotEmpty) {
          throw StateError('Receive or cancel its stock transfers first.');
        }
      }
      await (db.update(db.branches)..where((x) => x.id.equals(branchId))).write(
        BranchesCompanion(
          isActive: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Assign / unassign a user to a branch.
  Future<void> setAssignment({
    required String businessId,
    required String branchId,
    required String userId,
    required bool assigned,
  }) async {
    auth.require(BosPermission.branchManage, businessId: businessId);
    final branch =
        await (db.select(db.branches)..where(
              (b) => b.id.equals(branchId) & b.businessId.equals(businessId),
            ))
            .getSingleOrNull();
    if (branch == null) {
      throw StateError('That branch does not belong to this business.');
    }
    final member =
        await (db.select(db.businessMembers)..where(
              (m) =>
                  m.businessId.equals(businessId) &
                  m.userId.equals(userId) &
                  m.status.equals('active'),
            ))
            .getSingleOrNull();
    if (member == null) {
      throw StateError('That user is not an active member of this business.');
    }
    final id = AppDatabase.cloudCompatibleDefaultId(
      'branch_members',
      '$branchId:$userId',
    );
    final existing = await (db.select(
      db.branchMembers,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      if (!assigned) return;
      await db
          .into(db.branchMembers)
          .insert(
            BranchMembersCompanion.insert(
              id: id,
              businessId: businessId,
              branchId: branchId,
              userId: userId,
            ),
          );
    } else {
      await (db.update(db.branchMembers)..where((m) => m.id.equals(id))).write(
        BranchMembersCompanion(
          status: Value(assigned ? 'active' : 'removed'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  static String? _blankToNull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

final branchServiceProvider = Provider<BranchService>(
  (ref) => BranchService(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
  ),
);
