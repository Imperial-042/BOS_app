import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

class InventoryService {
  final AppDatabase db;

  InventoryService(this.db);

  // ============================================================
  // RESTOCK
  // ============================================================

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

      if (supply == null) {
        throw StateError('Supply not found.');
      }

      final unit = supply.stockUnit.trim();

      if (unit.isEmpty) {
        throw StateError(
          'Supply "${supply.name}" does not have an inventory stock unit.',
        );
      }

      final newStock = supply.currentStock + quantity;

      await (db.update(db.supplies)..where((s) => s.id.equals(supplyId))).write(
        SuppliesCompanion(
          currentStock: Value(newStock),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              id: const Uuid().v4(),
              supplyId: supplyId,
              movementType: 'restock',
              quantity: quantity,
              unit: unit,
              referenceType: Value(referenceType),
              referenceId: Value(referenceId),
              notes: Value(notes),
            ),
          );
    });
  }

  // ============================================================
  // MANUAL ADJUSTMENT
  // ============================================================

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

    await db.transaction(() async {
      final supply = await (db.select(
        db.supplies,
      )..where((s) => s.id.equals(supplyId))).getSingleOrNull();

      if (supply == null) {
        throw StateError('Supply not found.');
      }

      final newStock = supply.currentStock + quantity;

      if (newStock < 0) {
        throw StateError('Adjustment would make stock negative.');
      }

      await (db.update(db.supplies)..where((s) => s.id.equals(supplyId))).write(
        SuppliesCompanion(
          currentStock: Value(newStock),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              id: const Uuid().v4(),
              supplyId: supplyId,
              movementType: 'manual_adjustment',
              quantity: quantity,
              unit: supply.stockUnit,
              referenceType: Value(referenceType),
              referenceId: Value(referenceId),
              notes: Value(notes),
            ),
          );
    });
  }
}
