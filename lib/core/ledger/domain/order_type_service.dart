// Customizable POS order types. Each type has a "kind" and flags that decide
// what the cashier must fill in (table, customer, address, platform order no).

import 'dart:math' as math;

import 'package:bos_application/core/auth/authorization_providers.dart'
    show selectedBusinessIdProvider;
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class OrderTypeSpec {
  final String name;
  final String kind;
  final bool table;
  final bool customer;
  final bool address;
  final bool reference;

  const OrderTypeSpec(
    this.name, {
    this.kind = 'other',
    this.table = false,
    this.customer = false,
    this.address = false,
    this.reference = false,
  });
}

const kOrderKindLabels = <String, String>{
  'dine_in': 'Dine in',
  'takeout': 'Take out',
  'pickup': 'Pick up',
  'delivery': 'Delivery (own riders)',
  'online': 'Online / platform order',
  'other': 'Other',
};

/// Ready-made sets for different kinds of business.
const kOrderTypePacks = <String, List<OrderTypeSpec>>{
  'Restaurant / café': [
    OrderTypeSpec('Dine in', kind: 'dine_in', table: true),
    OrderTypeSpec('Take out', kind: 'takeout'),
    OrderTypeSpec('Pick up', kind: 'pickup', customer: true),
    OrderTypeSpec('Delivery', kind: 'delivery', customer: true, address: true),
    OrderTypeSpec('GrabFood', kind: 'online', reference: true),
    OrderTypeSpec('Foodpanda', kind: 'online', reference: true),
    OrderTypeSpec('Maxim', kind: 'online', reference: true),
  ],
  'Retail & online store': [
    OrderTypeSpec('Walk-in'),
    OrderTypeSpec('Pick up', kind: 'pickup', customer: true),
    OrderTypeSpec('Delivery', kind: 'delivery', customer: true, address: true),
    OrderTypeSpec('Shopee', kind: 'online', reference: true),
    OrderTypeSpec('Lazada', kind: 'online', reference: true),
    OrderTypeSpec('Online order', kind: 'online', reference: true),
  ],
  'Service & wholesale': [
    OrderTypeSpec('On-site'),
    OrderTypeSpec('Pick up', kind: 'pickup', customer: true),
    OrderTypeSpec('Delivery', kind: 'delivery', customer: true, address: true),
    OrderTypeSpec(
      'Home service',
      kind: 'delivery',
      customer: true,
      address: true,
    ),
  ],
};

class OrderTypeService {
  final AppDatabase db;
  OrderTypeService(this.db);

  Future<List<PosOrderType>> _all(String businessId) => (db.select(
    db.posOrderTypes,
  )..where((t) => t.businessId.equals(businessId))).get();

  Future<void> addDefaults(String businessId) =>
      db.seedDefaultOrderTypes(businessId);

  PosOrderTypesCompanion _companion(
    OrderTypeSpec s, {
    String? id,
    String? businessId,
    int? sortOrder,
  }) {
    final name = s.name.trim();
    if (id != null) {
      return PosOrderTypesCompanion.insert(
        id: id,
        businessId: businessId!,
        name: name,
        sortOrder: Value(sortOrder ?? 0),
        kind: Value(s.kind),
        requiresTable: Value(s.table),
        requiresCustomer: Value(s.customer),
        requiresAddress: Value(s.address),
        requiresReference: Value(s.reference),
      );
    }
    return PosOrderTypesCompanion(
      name: Value(name),
      kind: Value(s.kind),
      requiresTable: Value(s.table),
      requiresCustomer: Value(s.customer),
      requiresAddress: Value(s.address),
      requiresReference: Value(s.reference),
    );
  }

  Future<void> add(String businessId, OrderTypeSpec spec) async {
    if (spec.name.trim().isEmpty) throw StateError('Enter a name.');
    final all = await _all(businessId);
    if (all.any(
      (t) => t.name.toLowerCase() == spec.name.trim().toLowerCase(),
    )) {
      throw StateError('"${spec.name.trim()}" already exists.');
    }
    final next = all.isEmpty
        ? 0
        : all.map((t) => t.sortOrder).reduce(math.max) + 1;
    await db
        .into(db.posOrderTypes)
        .insert(
          _companion(
            spec,
            id: const Uuid().v4(),
            businessId: businessId,
            sortOrder: next,
          ),
        );
  }

  /// Adds the types of a preset that don't exist yet. Returns how many.
  Future<int> addPack(String businessId, List<OrderTypeSpec> specs) async {
    final all = await _all(businessId);
    final have = {for (final t in all) t.name.toLowerCase()};
    var next = all.isEmpty
        ? 0
        : all.map((t) => t.sortOrder).reduce(math.max) + 1;
    var added = 0;
    for (final s in specs) {
      if (have.contains(s.name.toLowerCase())) continue;
      await db
          .into(db.posOrderTypes)
          .insert(
            _companion(
              s,
              id: const Uuid().v4(),
              businessId: businessId,
              sortOrder: next++,
            ),
          );
      added++;
    }
    return added;
  }

  Future<void> update(PosOrderType type, OrderTypeSpec spec) async {
    final clean = spec.name.trim();
    if (clean.isEmpty) throw StateError('Enter a name.');
    final all = await _all(type.businessId);
    if (all.any(
      (t) => t.id != type.id && t.name.toLowerCase() == clean.toLowerCase(),
    )) {
      throw StateError('"$clean" already exists.');
    }
    await (db.update(
      db.posOrderTypes,
    )..where((t) => t.id.equals(type.id))).write(_companion(spec));
  }

  Future<void> setActive(PosOrderType type, bool active) =>
      (db.update(db.posOrderTypes)..where((t) => t.id.equals(type.id))).write(
        PosOrderTypesCompanion(isActive: Value(active)),
      );

  /// Past receipts keep their text label.
  Future<void> delete(PosOrderType type) =>
      (db.delete(db.posOrderTypes)..where((t) => t.id.equals(type.id))).go();
}

final orderTypeServiceProvider = Provider<OrderTypeService>(
  (ref) => OrderTypeService(ref.watch(databaseProvider)),
);

/// Every order type of the selected business (active and hidden).
final allOrderTypesProvider = StreamProvider<List<PosOrderType>>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.posOrderTypes)
        ..where((t) => t.businessId.equals(businessId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.name),
        ]))
      .watch();
});
