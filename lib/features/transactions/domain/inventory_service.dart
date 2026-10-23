import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/stock/stock_service.dart';

import '../../../core/database/app_database.dart';

/// Stock is a double (0.1 + 0.2 != 0.3); keep stored and audited values clean.
double _round(double v) => double.parse(v.toStringAsFixed(6));

class InventoryService {
  final AppDatabase db;

  /// The branch whose stock this service changes.
  final String branchId;
  late final StockService _stock = StockService(db, viewBranchId: branchId);

  InventoryService(this.db, {required this.branchId});

  Future<void> restockSupply({
    required String supplyId,
    required double quantity,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Restock quantity must be greater than zero.');
    }

    await db.transaction(() async {
      final supply = await (db.select(
        db.supplies,
      )..where((s) => s.id.equals(supplyId))).getSingleOrNull();
      if (supply == null) throw StateError('Supply not found.');

      final unit = supply.stockUnit.trim();
      if (unit.isEmpty) {
        throw StateError(
          'Supply "${supply.name}" does not have an inventory stock unit.',
        );
      }

      final added = _round(quantity);
      final before = _round(await _stock.supplyQty(branchId, supplyId));

      await _stock.moveSupply(
        branchId: branchId,
        supplyId: supplyId,
        type: 'restock',
        quantity: added,
        unit: unit,
        referenceType: referenceType,
        referenceId: referenceId,
        notes: notes,
      );
      final newStock = _round(before + added);

      await AuditWriter.write(
        db,
        businessId: supply.businessId,
        userId: null,
        action: 'inventory.stock_restocked',
        module: AuditModule.inventory,
        actionType: AuditActionType.update,
        entityType: 'supplies',
        entityId: supplyId,
        entityLabel: supply.name,
        before: {'stock': before},
        after: {'stock': newStock},
        details: {
          'added': added,
          'unit': unit,
          'branchId': branchId,
          'referenceType': referenceType,
          'referenceId': referenceId,
          'notes': notes,
        },
      );
    });
  }

  Future<void> adjustStock({
    required String supplyId,
    required double quantity,
    required String notes,
    String? referenceType,
    String? referenceId,
  }) async {
    if (quantity == 0) {
      throw ArgumentError('Adjustment quantity cannot be zero.');
    }
    final reason = notes.trim();
    if (reason.isEmpty) {
      throw ArgumentError('A reason is required to adjust stock.');
    }

    await db.transaction(() async {
      final supply = await (db.select(
        db.supplies,
      )..where((s) => s.id.equals(supplyId))).getSingleOrNull();
      if (supply == null) throw StateError('Supply not found.');

      final delta = _round(quantity);
      final before = _round(await _stock.supplyQty(branchId, supplyId));
      final newStock = _round(before + delta);
      if (newStock < 0) {
        throw StateError('Adjustment would make stock negative.');
      }

      await _stock.moveSupply(
        branchId: branchId,
        supplyId: supplyId,
        type: 'manual_adjustment',
        quantity: delta,
        unit: supply.stockUnit,
        referenceType: referenceType,
        referenceId: referenceId,
        notes: reason,
      );

      await AuditWriter.write(
        db,
        businessId: supply.businessId,
        userId: null,
        action: 'inventory.stock_adjusted',
        module: AuditModule.inventory,
        actionType: AuditActionType.adjustment,
        entityType: 'supplies',
        entityId: supplyId,
        entityLabel: supply.name,
        reason: reason,
        before: {'stock': before},
        after: {'stock': newStock},
        details: {
          'delta': delta,
          'unit': supply.stockUnit,
          'branchId': branchId,
          'referenceType': referenceType,
          'referenceId': referenceId,
        },
      );
    });
  }
}
