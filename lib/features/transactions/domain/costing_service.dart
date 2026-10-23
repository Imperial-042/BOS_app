// lib/features/production/domain/costing_service.dart
//
// Everything about "how much does this actually cost":
//   - recordPurchase(): the Supplies Price List's entry point. Every
//     purchase updates stock AND recalculates a weighted-average
//     cost per base unit — this is what makes Supplies Price List
//     double as the raw-material input for the whole costing system.
//   - computeProductCost(): recursively walks a recipe (including
//     nested sub-recipes) and sums each ingredient's cost, converted
//     into whatever unit the recipe specifies.
//   - computeProfitability(): cost + sell price -> gross profit/margin.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../presentation/screens/transaction_page.dart' show kCurrentBusinessId;
import 'production_service.dart'; // UnitConverter, UnitMismatchException

// ============================================================
// RESULT TYPES
// ============================================================

class CostBreakdownEntry {
  final String componentName;
  final int costCents;
  const CostBreakdownEntry({
    required this.componentName,
    required this.costCents,
  });
}

class ProductCostResult {
  final int totalCostCents; // cost of ONE output unit
  final List<CostBreakdownEntry> breakdown;
  const ProductCostResult({
    required this.totalCostCents,
    required this.breakdown,
  });
}

class ProfitabilityResult {
  final int costCents;
  final int? sellPriceCents;
  final int? grossProfitCents;
  final double? grossMarginPercent;
  const ProfitabilityResult({
    required this.costCents,
    required this.sellPriceCents,
    required this.grossProfitCents,
    required this.grossMarginPercent,
  });
}

// ============================================================
// COSTING SERVICE
// ============================================================

class CostingService {
  final AppDatabase db;

  /// The branch whose stock purchases and adjustments change.
  final String branchId;
  late final StockService _stock = StockService(db, viewBranchId: branchId);

  /// Called before any write that changes stock or costs. Throws
  /// PermissionDeniedException when the current member may not do it.
  /// Supplied by the provider so it always reads the CURRENT role.
  final void Function(BosPermission permission)? guard;

  CostingService(this.db, {required this.branchId, this.guard});

  static double calculateWeightedAverageCost({
    required double existingQuantity,
    required int existingValueCents,
    required double incomingQuantity,
    required int incomingValueCents,
  }) {
    final totalQuantity = existingQuantity + incomingQuantity;
    if (totalQuantity <= 0) {
      return 0.0;
    }

    return ((existingValueCents + incomingValueCents) / totalQuantity);
  }

  // ------------------------------------------------------------
  // PURCHASING — the Supplies Price List's "Add Item" / "Add Price"
  // actions should call this instead of writing supplies rows directly.
  // ------------------------------------------------------------

  /// Records a purchase and updates the supply's stock and
  /// weighted-average cost per base unit.
  ///
  /// [pricePerPurchaseUnitCents] is what one purchase unit costs (e.g.
  /// ₱100 for one pack), in cents.
  /// [purchaseQuantity] is how many purchase units were bought (e.g. 10 packs).
  /// [unitsPerPurchase] is the conversion — how many base units
  /// (grams/ml/pieces) are in ONE purchase unit (e.g. 1 pack = 100 g).
  /// [actualTotalPriceCents] is the actual total amount paid for this line.
  /// When provided, it is used for weighted-average stock valuation instead of
  /// inferring the value from a unit price.
  Future<void> recordPurchase({
    required String supplyId,
    required int pricePerPurchaseUnitCents,
    required double purchaseQuantity,
    required double unitsPerPurchase,
    required String purchaseUnit,
    required String storeName,
    String? storeAddress,
    String? supplierId,
    required DateTime date,
    String? notes,
    String? shoppingCartItemId,
    int? actualTotalPriceCents,
    bool updateSupplyReferenceFields = true,
  }) async {
    guard?.call(BosPermission.purchasingCreate);
    if (purchaseQuantity <= 0 || unitsPerPurchase <= 0) {
      throw ArgumentError(
        'Purchase quantity and units-per-purchase must be positive.',
      );
    }

    await db.transaction(() async {
      final supply = await (db.select(
        db.supplies,
      )..where((s) => s.id.equals(supplyId))).getSingle();

      // A purchase can never move another business's stock.
      if (supply.businessId != kCurrentBusinessId) {
        throw StateError('That supply does not belong to this business.');
      }

      final baseUnitsReceived = purchaseQuantity * unitsPerPurchase;
      final totalCostCents =
          actualTotalPriceCents ??
          (pricePerPurchaseUnitCents * purchaseQuantity).round();
      // Weighted average: blend the value of what's already on the
      // shelf with the value of what just arrived. The key input is the
      // actual total price paid for the received stock, not the default
      // or inferred unit price.
      final existingStock = await _stock.supplyQty(branchId, supplyId);
      final existingValue = existingStock * supply.costPerBaseUnit;
      final newWeightedCost = calculateWeightedAverageCost(
        existingQuantity: existingStock,
        existingValueCents: existingValue.round(),
        incomingQuantity: baseUnitsReceived,
        incomingValueCents: totalCostCents,
      );

      await (db.update(db.supplies)..where((s) => s.id.equals(supplyId))).write(
        SuppliesCompanion(
          costPerBaseUnit: Value(newWeightedCost),
          currentPrice: updateSupplyReferenceFields
              ? Value(pricePerPurchaseUnitCents)
              : const Value.absent(),
          purchaseUnit: updateSupplyReferenceFields
              ? Value(purchaseUnit)
              : const Value.absent(),
          unitsPerPurchase: updateSupplyReferenceFields
              ? Value(unitsPerPurchase)
              : const Value.absent(),
          updatedAt: Value(date),
        ),
      );

      await db
          .into(db.supplyPriceHistory)
          .insert(
            SupplyPriceHistoryCompanion.insert(
              id: const Uuid().v4(),
              supplyId: supplyId,
              price: pricePerPurchaseUnitCents,
              storeName: storeName,
              storeAddress: Value(storeAddress),
              supplierId: Value(supplierId),
              recordedDate: date,
              notes: Value(notes),
              purchaseQuantity: Value(purchaseQuantity),
              unitsPerPurchaseAtTime: Value(unitsPerPurchase),
              shoppingCartItemId: Value(shoppingCartItemId),
            ),
          );

      await _stock.moveSupply(
        branchId: branchId,
        supplyId: supplyId,
        type: 'restock',
        quantity: baseUnitsReceived,
        unit: supply.stockUnit,
        referenceType: 'purchase',
        notes: notes,
        shoppingCartItemId: shoppingCartItemId,
      );
    });
  }

  /// Manual stock correction (damage, spoilage, count fix, etc.) —
  /// does NOT affect cost per base unit, only quantity on hand.
  Future<void> adjustStock({
    required String supplyId,
    required double deltaBaseUnits, // negative to remove, positive to add
    required String reason,
    String auditAction = 'inventory.stock_adjusted',
  }) async {
    guard?.call(BosPermission.inventoryAdjust);
    await db.transaction(() async {
      final supply = await (db.select(
        db.supplies,
      )..where((s) => s.id.equals(supplyId))).getSingle();

      // Same tenant guard recordPurchase already has.
      if (supply.businessId != kCurrentBusinessId) {
        throw StateError('That supply does not belong to this business.');
      }

      final beforeStock = await _stock.supplyQty(branchId, supplyId);
      final newStock = beforeStock + deltaBaseUnits;
      if (newStock < 0) {
        throw StateError(
          'Adjustment would make stock negative for "${supply.name}".',
        );
      }

      await _stock.moveSupply(
        branchId: branchId,
        supplyId: supplyId,
        type: 'manual_adjustment',
        quantity: deltaBaseUnits,
        unit: supply.stockUnit,
        notes: reason,
      );

      await AuditWriter.write(
        db,
        businessId: supply.businessId,
        userId: null, // falls back to SyncTracker.currentUserId
        action: auditAction,
        module: AuditModule.inventory,
        actionType: AuditActionType.adjustment, // explicit: the classifier
        // would file 'stock_written_off' as a plain update
        entityType: 'supplies',
        entityId: supplyId,
        entityLabel: supply.name,
        reason: reason,
        before: {'stock': beforeStock},
        after: {'stock': newStock},
        details: {'delta': deltaBaseUnits, 'unit': supply.stockUnit},
      );
    });
  }
  // ------------------------------------------------------------
  // PRODUCT COST — recursive, unit-aware, nested-recipe-aware.
  // ------------------------------------------------------------

  Future<ProductCostResult> computeProductCost(String productId) async {
    final breakdown = <String, int>{};
    final totalCostForYield = await _costRecursive(
      productId,
      breakdown,
      const <String>{},
    );

    final recipe = await (db.select(
      db.recipes,
    )..where((r) => r.productId.equals(productId))).getSingleOrNull();
    final yieldQty = recipe?.yieldQuantity ?? 1;
    final costPerUnit = yieldQty <= 0
        ? totalCostForYield
        : totalCostForYield / yieldQty;

    return ProductCostResult(
      totalCostCents: costPerUnit.round(),
      breakdown:
          breakdown.entries
              .map(
                (e) => CostBreakdownEntry(
                  componentName: e.key,
                  costCents: (e.value / yieldQty).round(),
                ),
              )
              .toList()
            ..sort((a, b) => b.costCents.compareTo(a.costCents)),
    );
  }

  /// Returns the total cost (in cents) of producing ONE BATCH (i.e.
  /// `yieldQuantity` output units) of [productId]. [breakdownOut] is
  /// accumulated in "per batch" terms too — divided by yield at the
  /// top level in computeProductCost().
  Future<double> _costRecursive(
    String productId,
    Map<String, int> breakdownOut,
    Set<String> visited,
  ) async {
    if (visited.contains(productId)) {
      throw StateError('Circular recipe reference detected while costing.');
    }
    final nextVisited = {...visited, productId};

    final recipe = await (db.select(
      db.recipes,
    )..where((r) => r.productId.equals(productId))).getSingleOrNull();
    if (recipe == null) return 0;

    final components = await (db.select(
      db.recipeComponents,
    )..where((c) => c.recipeId.equals(recipe.id))).get();

    double total = 0;
    for (final component in components) {
      if (component.componentType == 'supply') {
        final supply = await (db.select(
          db.supplies,
        )..where((s) => s.id.equals(component.supplyId!))).getSingle();

        final quantityInStockUnit = UnitConverter.convert(
          component.quantityRequired,
          component.unit,
          supply.stockUnit,
        );

        final costCents = quantityInStockUnit * supply.costPerBaseUnit;
        breakdownOut[supply.name] =
            (breakdownOut[supply.name] ?? 0) + costCents.round();
        total += costCents;
      } else {
        final nestedProduct =
            await (db.select(db.products)
                  ..where((p) => p.id.equals(component.componentProductId!)))
                .getSingle();
        final nestedRecipe =
            await (db.select(db.recipes)
                  ..where((r) => r.productId.equals(nestedProduct.id)))
                .getSingleOrNull();
        final nestedYield = nestedRecipe?.yieldQuantity ?? 1;

        final nestedBatchCost = await _costRecursive(
          nestedProduct.id,
          breakdownOut,
          nextVisited,
        );
        final nestedCostPerUnit = nestedYield <= 0
            ? nestedBatchCost
            : nestedBatchCost / nestedYield;

        // component.quantityRequired is in component.unit, which should
        // match the nested product's own unit (e.g. "1 Espresso Base").
        final quantityInNestedUnit =
            UnitConverter.areCompatible(component.unit, nestedProduct.unit)
            ? UnitConverter.convert(
                component.quantityRequired,
                component.unit,
                nestedProduct.unit,
              )
            : component
                  .quantityRequired; // count-style units (e.g. "1 base") pass through

        final costCents = quantityInNestedUnit * nestedCostPerUnit;
        breakdownOut['${nestedProduct.name} (sub-recipe)'] =
            (breakdownOut['${nestedProduct.name} (sub-recipe)'] ?? 0) +
            costCents.round();
        total += costCents;
      }
    }

    return total;
  }

  // ------------------------------------------------------------
  // PROFITABILITY
  // ------------------------------------------------------------

  Future<ProfitabilityResult> computeProfitability(String productId) async {
    final costResult = await computeProductCost(productId);
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingle();

    if (product.sellPrice == null) {
      return ProfitabilityResult(
        costCents: costResult.totalCostCents,
        sellPriceCents: null,
        grossProfitCents: null,
        grossMarginPercent: null,
      );
    }

    final grossProfit = product.sellPrice! - costResult.totalCostCents;
    final margin = product.sellPrice! == 0
        ? 0.0
        : (grossProfit / product.sellPrice!) * 100;

    return ProfitabilityResult(
      costCents: costResult.totalCostCents,
      sellPriceCents: product.sellPrice,
      grossProfitCents: grossProfit,
      grossMarginPercent: margin,
    );
  }

  // ------------------------------------------------------------
  // "Which products use this ingredient?" — for a low-stock or
  // cost-change ripple check (spec sections 13 & 18).
  // ------------------------------------------------------------

  Future<List<Product>> findProductsUsingSupply(String supplyId) async {
    final componentRows = await (db.select(
      db.recipeComponents,
    )..where((c) => c.supplyId.equals(supplyId))).get();
    final recipeIds = componentRows.map((c) => c.recipeId).toSet();
    if (recipeIds.isEmpty) return [];

    final recipes = await (db.select(
      db.recipes,
    )..where((r) => r.id.isIn(recipeIds))).get();
    final productIds = recipes.map((r) => r.productId).toSet();

    return (db.select(db.products)..where((p) => p.id.isIn(productIds))).get();
  }
}
