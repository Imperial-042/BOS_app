// lib/core/business/module_config_service.dart
//
// Per-business module enablement. A module with no config row uses its
// default (enabled). Administration can never be disabled — it's where this
// configuration lives, so locking it out would be unrecoverable.
//
// This is deliberately separate from user authorization: a module can be
// enabled for the business while a member's role still hides it from them.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/authorization_providers.dart';
import '../auth/authorization_service.dart';
import '../auth/bos_access.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';

/// Stable module ids matching BosModule's `name` values in main.dart.
abstract final class BosModuleIds {
  static const management = 'management';
  static const finance = 'finance';
  static const inventory = 'inventory';
  static const salesPos = 'salesPos';
  static const people = 'people';
  static const administration = 'administration';

  /// Modules that can be toggled per business. Administration is excluded
  /// on purpose (see file header).
  static const toggleable = <String>[
    management,
    finance,
    inventory,
    salesPos,
    people,
  ];
}

final moduleConfigServiceProvider = Provider<ModuleConfigService>(
  (ref) => ModuleConfigService(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
  ),
);

class ModuleConfigService {
  final AppDatabase db;
  final AuthorizationService auth;
  ModuleConfigService(this.db, this.auth);

  /// moduleId -> enabled. Missing rows mean "enabled by default".
  Stream<Map<String, bool>> watchConfigs(String businessId) {
    return (db.select(
      db.businessModuleConfigs,
    )..where((c) => c.businessId.equals(businessId))).watch().map((rows) {
      return {for (final row in rows) row.moduleId: row.enabled};
    });
  }

  bool isEnabled(Map<String, bool> configs, String moduleId) =>
      moduleId == BosModuleIds.administration || (configs[moduleId] ?? true);

  Future<void> setEnabled({
    required String businessId,
    required String moduleId,
    required bool enabled,
  }) async {
    auth.require(BosPermission.businessSettings, businessId: businessId);
    if (moduleId == BosModuleIds.administration) {
      throw StateError('The Administration module cannot be disabled.');
    }

    final existing =
        await (db.select(db.businessModuleConfigs)..where(
              (c) =>
                  c.businessId.equals(businessId) & c.moduleId.equals(moduleId),
            ))
            .getSingleOrNull();

    if (enabled && existing == null) {
      return; // Default is enabled; nothing to store.
    }

    if (existing == null) {
      await db
          .into(db.businessModuleConfigs)
          .insert(
            BusinessModuleConfigsCompanion.insert(
              id: '${businessId}_$moduleId',
              businessId: businessId,
              moduleId: moduleId,
              enabled: Value(enabled),
            ),
          );
    } else {
      await (db.update(
        db.businessModuleConfigs,
      )..where((c) => c.id.equals(existing.id))).write(
        BusinessModuleConfigsCompanion(
          enabled: Value(enabled),
          configVersion: Value(existing.configVersion + 1),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }
}

/// Enabled-state map for the SELECTED business, live-updating. The
/// navigation shell watches this so module visibility reacts to toggles.
final moduleConfigsProvider = StreamProvider<Map<String, bool>>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  return ref.watch(moduleConfigServiceProvider).watchConfigs(businessId);
});
