// lib/core/stock/stock_service.dart  (NEW FILE)
//
// THE ONLY place stock quantities are read or changed.
//
//   * Stock is an append-only ledger per branch:
//       supplies  -> inventory_movements        (quantity signed, stock unit)
//       products  -> product_stock_movements    (quantity signed)
//     Stock at a branch = SUM(quantity). Movements sync; quantities don't, so
//     two devices (or a transfer) can never overwrite each other's stock.
//
//   * supplies.current_stock / products.current_stock are now a LOCAL
//     PROJECTION of the branch selected on this device. They are not synced.
//     Existing screens that only READ them keep working. Code that WRITES them
//     must call moveSupply / moveProduct instead.
//
//   * Old rows with branch_id NULL count as the Main Branch.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;
import '../auth/authorization_providers.dart';
import '../branch/branch_providers.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';

const _uuid = Uuid();

/// SQL for "the branch this movement row belongs to" (NULL -> Main Branch).
String _branchOf(String businessExpr) =>
    'COALESCE(m.branch_id, (SELECT b.id FROM branches b '
    'WHERE b.business_id = $businessExpr AND b.is_headquarters = 1 LIMIT 1))';

/// Drift filter: an inventory movement belongs to [branchId].
/// Old rows with branch_id NULL count as the Main Branch.
Expression<bool> inventoryMovementInBranch(
  $InventoryMovementsTable m,
  String businessId,
  String branchId,
) {
  final isMain = branchId == AppDatabase.mainBranchId(businessId);
  return isMain
      ? (m.branchId.equals(branchId) | m.branchId.isNull())
      : m.branchId.equals(branchId);
}

class StockService {
  StockService(this.db, {this.viewBranchId});

  final AppDatabase db;

  /// The branch this device shows. Writes to that branch refresh the
  /// current_stock projection immediately.
  final String? viewBranchId;

  // --------------------------------------------------------------- reads ----

  Future<double> supplyQty(String branchId, String supplyId) async {
    final r = await db
        .customSelect(
          'SELECT COALESCE(SUM(m.quantity), 0) AS q FROM inventory_movements m '
          'JOIN supplies s ON s.id = m.supply_id '
          'WHERE m.supply_id = ? AND ${_branchOf('s.business_id')} = ?',
          variables: [
            Variable.withString(supplyId),
            Variable.withString(branchId),
          ],
        )
        .getSingle();
    return (r.data['q'] as num).toDouble();
  }

  Future<Map<String, double>> supplyQtyMap(
    String businessId,
    String branchId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT m.supply_id AS id, SUM(m.quantity) AS q '
          'FROM inventory_movements m JOIN supplies s ON s.id = m.supply_id '
          'WHERE s.business_id = ? AND ${_branchOf('s.business_id')} = ? '
          'GROUP BY m.supply_id',
          variables: [
            Variable.withString(businessId),
            Variable.withString(branchId),
          ],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): (r.data['q'] as num).toDouble(),
    };
  }

  Future<double> productQty(String branchId, String productId) async {
    final r = await db
        .customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS q FROM product_stock_movements '
          'WHERE product_id = ? AND branch_id = ?',
          variables: [
            Variable.withString(productId),
            Variable.withString(branchId),
          ],
        )
        .getSingle();
    return (r.data['q'] as num).toDouble();
  }

  Future<Map<String, double>> productQtyMap(
    String businessId,
    String branchId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT product_id AS id, SUM(quantity) AS q '
          'FROM product_stock_movements WHERE business_id = ? AND branch_id = ? '
          'GROUP BY product_id',
          variables: [
            Variable.withString(businessId),
            Variable.withString(branchId),
          ],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): (r.data['q'] as num).toDouble(),
    };
  }

  // -------------------------------------------------------------- writes ----
  // Call inside the caller's transaction. Pass [id] for deterministic,
  // idempotent movements (transfers); a repeated id is ignored.

  Future<void> moveSupply({
    required String branchId,
    required String supplyId,
    required String type,
    required double quantity,
    String unit = '',
    String? referenceType,
    String? referenceId,
    String? notes,
    String? shoppingCartItemId,
    String? id,
  }) async {
    if (!quantity.isFinite) {
      throw ArgumentError('Stock movement quantity must be finite.');
    }
    final supply = await (db.select(
      db.supplies,
    )..where((s) => s.id.equals(supplyId))).getSingleOrNull();
    if (supply == null || !supply.isActive) {
      throw StateError('This supply is unavailable.');
    }
    await _requireActiveBranch(branchId, supply.businessId);
    await db
        .into(db.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: id ?? _uuid.v4(),
            supplyId: supplyId,
            movementType: type,
            unit: unit,
            quantity: quantity,
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            notes: Value(notes),
            shoppingCartItemId: Value(shoppingCartItemId),
            branchId: Value(branchId),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await _projectSupply(supplyId, branchId);
  }

  Future<void> moveProduct({
    required String branchId,
    required String productId,
    required String type,
    required double quantity,
    String? businessId,
    String? referenceType,
    String? referenceId,
    String? notes,
    String? id,
  }) async {
    if (!quantity.isFinite) {
      throw ArgumentError('Stock movement quantity must be finite.');
    }
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (product == null || !product.isActive) {
      throw StateError('This product is unavailable.');
    }
    final biz = businessId ?? product.businessId;
    if (product.businessId != biz) {
      throw StateError('This product does not belong to this business.');
    }
    await _requireActiveBranch(branchId, biz);
    await db
        .into(db.productStockMovements)
        .insert(
          ProductStockMovementsCompanion.insert(
            id: id ?? _uuid.v4(),
            businessId: biz,
            branchId: branchId,
            productId: productId,
            movementType: type,
            quantity: quantity,
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            notes: Value(notes),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await _projectProduct(productId, branchId);
  }

  Future<void> _requireActiveBranch(String branchId, String businessId) async {
    final branch =
        await (db.select(db.branches)..where(
              (b) =>
                  b.id.equals(branchId) &
                  b.businessId.equals(businessId) &
                  b.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (branch == null) {
      throw StateError('Choose an active branch in this business.');
    }
  }

  // ---------------------------------------------------------- projection ----

  Future<void> _quiet(Future<void> Function() body) async {
    await db.customStatement('UPDATE sync_context SET suppress = 1');
    try {
      await body();
    } finally {
      await db.customStatement('UPDATE sync_context SET suppress = 0');
    }
  }

  Future<void> _projectSupply(String supplyId, String branchId) async {
    if (viewBranchId != branchId) return;
    await _quiet(
      () => db.customStatement(
        'UPDATE supplies SET current_stock = COALESCE((SELECT SUM(m.quantity) '
        'FROM inventory_movements m WHERE m.supply_id = supplies.id AND '
        '${_branchOf('supplies.business_id')} = ?), 0) WHERE id = ?',
        [branchId, supplyId],
      ),
    );
    db.notifyUpdates({TableUpdate('supplies')});
  }

  Future<void> _projectProduct(String productId, String branchId) async {
    if (viewBranchId != branchId) return;
    await _quiet(
      () => db.customStatement(
        'UPDATE products SET current_stock = COALESCE((SELECT SUM(m.quantity) '
        'FROM product_stock_movements m WHERE m.product_id = products.id '
        'AND m.branch_id = ?), 0) WHERE id = ?',
        [branchId, productId],
      ),
    );
    db.notifyUpdates({TableUpdate('products')});
  }

  /// Recomputes the projection for every supply and product of a business.
  static Future<void> recompute(
    AppDatabase db, {
    required String businessId,
    required String branchId,
  }) async {
    await db.customStatement('UPDATE sync_context SET suppress = 1');
    try {
      await db.customStatement(
        'UPDATE supplies SET current_stock = COALESCE((SELECT SUM(m.quantity) '
        'FROM inventory_movements m WHERE m.supply_id = supplies.id AND '
        '${_branchOf('supplies.business_id')} = ?), 0) WHERE business_id = ?',
        [branchId, businessId],
      );
      await db.customStatement(
        'UPDATE products SET current_stock = COALESCE((SELECT SUM(m.quantity) '
        'FROM product_stock_movements m WHERE m.product_id = products.id '
        'AND m.branch_id = ?), 0) WHERE business_id = ?',
        [branchId, businessId],
      );
    } finally {
      await db.customStatement('UPDATE sync_context SET suppress = 0');
    }
    db.notifyUpdates({TableUpdate('supplies'), TableUpdate('products')});
  }

  /// DEBUG: lists supplies whose current_stock column disagrees with the
  /// ledger. Anything listed was changed by code that bypassed StockService.
  Future<List<String>> findProjectionMismatches(
    String businessId,
    String branchId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT s.name AS name, s.current_stock AS col, COALESCE((SELECT '
          'SUM(m.quantity) FROM inventory_movements m WHERE m.supply_id = s.id '
          'AND ${_branchOf('s.business_id')} = ?), 0) AS calc '
          'FROM supplies s WHERE s.business_id = ?',
          variables: [
            Variable.withString(branchId),
            Variable.withString(businessId),
          ],
        )
        .get();
    return [
      for (final r in rows)
        if (((r.data['col'] as num) - (r.data['calc'] as num)).abs() > 1e-6)
          '${r.read<String>('name')}: column ${r.data['col']} vs ledger ${r.data['calc']}',
    ];
  }
}

/// Keeps the current_stock projection in step with the selected branch.
class StockProjection {
  StockProjection(this._ref);
  final Ref _ref;

  Future<void> refresh() async {
    final branchId = _ref.read(selectedBranchIdProvider);
    if (branchId.isEmpty) return;
    await StockService.recompute(
      _ref.read(databaseProvider),
      businessId: _ref.read(selectedBusinessIdProvider),
      branchId: branchId,
    );
    // Open screens re-read on this signal.
    _ref.read(ledgerVersionProvider.notifier).state++;
  }
}

/// Watch it once near the top of the app (see _AccessGate). It refreshes on
/// start and whenever the selected branch (or business) changes.
final stockProjectionProvider = Provider<StockProjection>((ref) {
  final p = StockProjection(ref);
  ref.listen<String>(
    selectedBranchIdProvider,
    (_, _) => unawaited(p.refresh()),
    fireImmediately: true,
  );
  return p;
});

/// StockService for the branch this device is viewing.
final stockServiceProvider = Provider<StockService>(
  (ref) => StockService(
    ref.watch(databaseProvider),
    viewBranchId: ref.watch(selectedBranchIdProvider),
  ),
);
