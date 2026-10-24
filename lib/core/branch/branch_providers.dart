// lib/core/branch/branch_providers.dart  (NEW FILE)
//
// Which branch is this device working in?
//   * a business has 1..N branches (no limit)
//   * a user with no branch assignment can use every branch; otherwise only
//     the assigned ones (the owner can always use every branch)
//   * a device (e.g. a POS tablet) can be LOCKED to one branch
//   * the choice is per device + per business (SharedPreferences)
//
// Everything that depends on the branch must WATCH selectedBranchIdProvider,
// never read a global — that is what made POS leak between businesses.

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';

/// Call `await BranchPrefs.init();` once in main(), before runApp.
abstract final class BranchPrefs {
  static SharedPreferences? _p;

  static Future<void> init() async =>
      _p = await SharedPreferences.getInstance();

  static String? saved(String businessId) =>
      _p?.getString('branch_$businessId');
  static String? locked(String businessId) =>
      _p?.getString('branch_lock_$businessId');

  static Future<void> save(String businessId, String branchId) async {
    await _p?.setString('branch_$businessId', branchId);
  }

  static Future<void> setLock(String businessId, String? branchId) async {
    if (branchId == null) {
      await _p?.remove('branch_lock_$businessId');
    } else {
      await _p?.setString('branch_lock_$businessId', branchId);
    }
  }
}

/// Every branch of the selected business, including deactivated ones.
final allBranchesProvider = StreamProvider<List<Branch>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  return (db.select(db.branches)
        ..where((b) => b.businessId.equals(businessId))
        ..orderBy([
          (b) => OrderingTerm.desc(b.isHeadquarters),
          (b) => OrderingTerm.asc(b.name),
        ]))
      .watch();
});

/// Active branches only (main branch first).
final branchesProvider = Provider<List<Branch>>((ref) {
  final all = ref.watch(allBranchesProvider).value ?? const <Branch>[];
  return all.where((b) => b.isActive).toList();
});

/// This user's explicit branch assignments in the selected business.
final branchMembershipsProvider = StreamProvider<List<BranchMember>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final uid = ref.watch(authenticatedUserIdProvider);
  if (uid == null) return Stream.value(const <BranchMember>[]);
  return (db.select(db.branchMembers)..where(
        (m) =>
            m.businessId.equals(businessId) &
            m.userId.equals(uid) &
            m.status.equals('active'),
      ))
      .watch();
});

/// Everyone assigned to one branch (for the Branches screen).
final branchMembersOfProvider =
    StreamProvider.family<List<BranchMember>, String>((ref, branchId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.branchMembers)..where(
            (m) => m.branchId.equals(branchId) & m.status.equals('active'),
          ))
          .watch();
    });

/// Branches this user may work in.
/// NOTE: enforced in the app. Server-side per-branch RLS is a later step.
final allowedBranchesProvider = Provider<List<Branch>>((ref) {
  final all = ref.watch(branchesProvider);
  if (ref.watch(authorizationServiceProvider).isOwner) return all;

  final mineAsync = ref.watch(branchMembershipsProvider);
  // Not loaded yet: "unknown" must not be treated as "unassigned"
  // (which means every branch). Fail closed.
  if (!mineAsync.hasValue) return const <Branch>[];

  final mine = mineAsync.requireValue;
  if (mine.isEmpty) return all; // genuinely unassigned = every branch
  final ids = {for (final m in mine) m.branchId};
  return all.where((b) => ids.contains(b.id)).toList();
});

final savedBranchIdProvider = StateProvider.family<String?, String>(
  (ref, businessId) => BranchPrefs.saved(businessId),
);

final lockedBranchIdProvider = StateProvider.family<String?, String>(
  (ref, businessId) => BranchPrefs.locked(businessId),
);

/// THE branch this device is working in right now.
final selectedBranchIdProvider = Provider<String>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  final allowed = ref.watch(allowedBranchesProvider);

  if (allowed.isEmpty) {
    final isOwner = ref.watch(authorizationServiceProvider).isOwner;
    final mine =
        ref.watch(branchMembershipsProvider).value ?? const <BranchMember>[];
    // Assigned somewhere (e.g. only to a branch that is now deactivated, or
    // branches haven't loaded yet): never fall back to the Main Branch.
    if (!isOwner && mine.isNotEmpty) return mine.first.branchId;
    return AppDatabase.mainBranchId(businessId);
  }

  final locked = ref.watch(lockedBranchIdProvider(businessId));
  if (locked != null && allowed.any((b) => b.id == locked)) return locked;

  final saved = ref.watch(savedBranchIdProvider(businessId));
  return allowed.any((b) => b.id == saved) ? saved! : allowed.first.id;
});

final selectedBranchProvider = Provider<Branch?>((ref) {
  final id = ref.watch(selectedBranchIdProvider);
  final all = ref.watch(allBranchesProvider).value ?? const <Branch>[];
  for (final b in all) {
    if (b.id == id) return b;
  }
  return null;
});

/// Active branch assignments of EVERY member in the selected business.
final allBranchAssignmentsProvider = StreamProvider<List<BranchMember>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  return (db.select(db.branchMembers)..where(
        (m) => m.businessId.equals(businessId) & m.status.equals('active'),
      ))
      .watch();
});

/// userId -> names of the active branches they are assigned to.
/// A user missing from the map has no assignment = works in every branch.
final branchNamesByUserProvider = Provider<Map<String, List<String>>>((ref) {
  final branches = ref.watch(allBranchesProvider).value ?? const <Branch>[];
  final rows =
      ref.watch(allBranchAssignmentsProvider).value ?? const <BranchMember>[];
  final nameOf = {
    for (final b in branches)
      if (b.isActive) b.id: b.name,
  };
  final out = <String, List<String>>{};
  for (final m in rows) {
    final name = nameOf[m.branchId];
    if (name != null) (out[m.userId] ??= []).add(name);
  }
  for (final list in out.values) {
    list.sort();
  }
  return out;
});
