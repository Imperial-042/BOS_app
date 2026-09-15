// lib/features/production/domain/production_service.dart
//
// The engine behind Recipe-Based Inventory & Production:
//   - UnitConverter: converts between compatible units (g<->kg,
//     ml<->L, count units), so a recipe can say "18 g" while stock
//     is tracked in "kg" without the owner doing math.
//   - ProductionService.computeMaxProducible(): "how many can I
//     make right now" — recurses through nested recipes down to
//     raw supply stock, returns the limiting component.
//   - ProductionService.recordProduction(): the actual deduction —
//     call this whenever a sale/production event happens, and it
//     walks the same recipe tree, subtracting real stock.

import 'package:drift/drift.dart' hide Column, Table;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

// ============================================================
// UNIT CONVERSION
// ============================================================

class UnitMismatchException implements Exception {
  final String message;
  UnitMismatchException(this.message);
  @override
  String toString() => message;
}

class UnitConverter {
  UnitConverter._();

  // Every unit's size relative to its dimension's base unit
  // (gram for mass, milliliter for volume, "1" for count).
  static const Map<String, double> _toBaseFactor = {
    // mass -> base: gram
    'g': 1, 'gram': 1, 'grams': 1,
    'kg': 1000, 'kilogram': 1000, 'kilograms': 1000,
    // volume -> base: milliliter
    'ml': 1, 'milliliter': 1, 'milliliters': 1,
    'l': 1000, 'liter': 1000, 'liters': 1000, 'litre': 1000, 'litres': 1000,
    // count -> base: 1 (every count unit is directly comparable)
    'piece': 1, 'pieces': 1, 'pc': 1, 'pcs': 1, 'unit': 1, 'units': 1,
    'cup': 1, 'cups': 1, 'lid': 1, 'lids': 1, 'each': 1, 'bottle': 1,
    'bottles': 1, 'pack': 1, 'packs': 1, 'sack': 1, 'sacks': 1,
    'box': 1, 'boxes': 1, 'roll': 1, 'rolls': 1, 'serving': 1, 'servings': 1,
  };

  static const Map<String, String> _dimension = {
    'g': 'mass',
    'gram': 'mass',
    'grams': 'mass',
    'kg': 'mass',
    'kilogram': 'mass',
    'kilograms': 'mass',
    'ml': 'volume',
    'milliliter': 'volume',
    'milliliters': 'volume',
    'l': 'volume',
    'liter': 'volume',
    'liters': 'volume',
    'litre': 'volume',
    'litres': 'volume',
    'piece': 'count',
    'pieces': 'count',
    'pc': 'count',
    'pcs': 'count',
    'unit': 'count',
    'units': 'count',
    'cup': 'count',
    'cups': 'count',
    'lid': 'count',
    'lids': 'count',
    'each': 'count',
    'bottle': 'count',
    'bottles': 'count',
    'pack': 'count',
    'packs': 'count',
    'sack': 'count',
    'sacks': 'count',
    'box': 'count',
    'boxes': 'count',
    'roll': 'count',
    'rolls': 'count',
    'serving': 'count',
    'servings': 'count',
  };

  /// Converts [quantity] from [fromUnit] to [toUnit]. Throws
  /// [UnitMismatchException] if the units are unknown or belong to
  /// different dimensions (e.g. trying to convert grams to milliliters).
  static double convert(double quantity, String fromUnit, String toUnit) {
    final from = fromUnit.toLowerCase().trim();
    final to = toUnit.toLowerCase().trim();
    if (from == to) return quantity;

    final fromDim = _dimension[from];
    final toDim = _dimension[to];
    final fromFactor = _toBaseFactor[from];
    final toFactor = _toBaseFactor[to];

    if (fromDim == null || fromFactor == null) {
      throw UnitMismatchException('Unknown unit "$fromUnit".');
    }
    if (toDim == null || toFactor == null) {
      throw UnitMismatchException('Unknown unit "$toUnit".');
    }
    if (fromDim != toDim) {
      throw UnitMismatchException(
        'Cannot convert "$fromUnit" ($fromDim) to "$toUnit" ($toDim) — '
        'they measure different things.',
      );
    }

    final baseQuantity = quantity * fromFactor;
    return baseQuantity / toFactor;
  }

  /// True if two units can be compared/converted (same dimension).
  static bool areCompatible(String unitA, String unitB) {
    final a = _dimension[unitA.toLowerCase().trim()];
    final b = _dimension[unitB.toLowerCase().trim()];
    return a != null && b != null && a == b;
  }

  /// The dimension ('mass' | 'volume' | 'count') a unit belongs to,
  /// or null if unrecognized. Used to build contextual unit dropdowns
  /// (e.g. only show g/kg once the ingredient is mass-based).
  static String? dimensionOf(String unit) =>
      _dimension[unit.toLowerCase().trim()];
}

// ============================================================
// PRODUCIBILITY RESULT
// ============================================================

class ProducibilityResult {
  /// Maximum whole units of the product that can be produced right
  /// now, given current stock across the entire recipe tree.
  final int maxUnits;

  /// The name of the component that is currently the bottleneck
  /// (null if the product has no recipe, i.e. unconstrained).
  final String? limitingComponentName;

  /// Every direct/nested component's own max-units contribution —
  /// useful for showing "coffee beans: 100, milk: 66, syrup: 50..."
  final Map<String, int> componentMaxUnits;

  const ProducibilityResult({
    required this.maxUnits,
    required this.limitingComponentName,
    required this.componentMaxUnits,
  });
}

// ============================================================
// PRODUCTION SERVICE
// ============================================================

class ProductionService {
  final AppDatabase db;
  ProductionService(this.db);

  // ------------------------------------------------------------
  // "How many can I make right now?"
  // ------------------------------------------------------------

  Future<ProducibilityResult> computeMaxProducible(String productId) async {
    final componentLimits = <String, double>{};
    final maxUnits = await _maxProducibleRecursive(
      productId,
      componentLimits,
      const <String>{},
    );

    String? limitingName;
    double? limitingValue;
    componentLimits.forEach((name, value) {
      if (limitingValue == null || value < limitingValue!) {
        limitingValue = value;
        limitingName = name;
      }
    });

    final isUnconstrained = maxUnits.isInfinite;

    return ProducibilityResult(
      maxUnits: isUnconstrained ? 0 : maxUnits.floor(),
      limitingComponentName: isUnconstrained ? null : limitingName,
      componentMaxUnits: {
        for (final entry in componentLimits.entries)
          entry.key: entry.value.isInfinite ? 0 : entry.value.floor(),
      },
    );
  }

  Future<double> _maxProducibleRecursive(
    String productId,
    Map<String, double> componentLimitsOut,
    Set<String> visited,
  ) async {
    if (visited.contains(productId)) {
      throw StateError(
        'Circular recipe reference detected — a recipe eventually '
        'requires itself as an ingredient.',
      );
    }
    final nextVisited = {...visited, productId};

    final recipe = await (db.select(
      db.recipes,
    )..where((r) => r.productId.equals(productId))).getSingleOrNull();

    // No recipe defined: treat as unconstrained. (A purely purchased
    // finished good with no BOM — the caller decides what to do
    // with an "unconstrained" result.)
    if (recipe == null) return double.infinity;

    final components = await (db.select(
      db.recipeComponents,
    )..where((c) => c.recipeId.equals(recipe.id))).get();

    if (components.isEmpty) return double.infinity;

    double? overallMax;

    for (final component in components) {
      final perOutputUnit = component.quantityRequired / recipe.yieldQuantity;
      if (perOutputUnit <= 0) continue;

      late final double availableInComponentUnit;
      late final String label;

      if (component.componentType == 'supply') {
        final supply = await (db.select(
          db.supplies,
        )..where((s) => s.id.equals(component.supplyId!))).getSingle();
        label = supply.name;
        availableInComponentUnit = UnitConverter.convert(
          supply.currentStock.toDouble(),
          supply.stockUnit,
          component.unit,
        );
      } else {
        final nestedProduct =
            await (db.select(db.products)
                  ..where((p) => p.id.equals(component.componentProductId!)))
                .getSingle();
        label = nestedProduct.name;
        final nestedMax = await _maxProducibleRecursive(
          component.componentProductId!,
          componentLimitsOut,
          nextVisited,
        );
        availableInComponentUnit = nestedMax.isInfinite
            ? double.infinity
            : UnitConverter.convert(
                nestedMax,
                nestedProduct.unit,
                component.unit,
              );
      }

      final maxFromThisComponent = availableInComponentUnit.isInfinite
          ? double.infinity
          : availableInComponentUnit / perOutputUnit;

      // If the same component name appears more than once in a tree
      // (e.g. two sub-recipes both use coffee beans), keep the
      // stricter (lower) limit for display purposes.
      final existing = componentLimitsOut[label];
      componentLimitsOut[label] = existing == null
          ? maxFromThisComponent
          : (maxFromThisComponent < existing ? maxFromThisComponent : existing);

      if (overallMax == null || maxFromThisComponent < overallMax) {
        overallMax = maxFromThisComponent;
      }
    }

    return overallMax ?? double.infinity;
  }

  // ------------------------------------------------------------
  // "This many were just sold/produced — deduct the ingredients."
  // ------------------------------------------------------------

  /// Deducts every raw-material requirement for producing [quantity]
  /// units of [productId], recursing through nested product
  /// components down to actual supply stock. Wrapped in a single
  /// transaction, so a shortage partway through never leaves stock
  /// half-deducted.
  Future<void> sellProduct({
    required String productId,
    required double quantity,
    required String paymentAccountId,
    String? referenceId,
    String? notes,
  }) async {
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();

    if (product == null) {
      throw StateError('Product not found.');
    }
    if (product.sellPrice == null) {
      throw StateError('Product "$productId" has no sell price set.');
    }
    if (quantity <= 0) {
      throw ArgumentError('Sale quantity must be greater than zero.');
    }

    await db.transaction(() async {
      await _deductRecursive(
        productId,
        quantity,
        'product_sale',
        referenceId,
        notes,
      );

      final saleAmountCents = (product.sellPrice! * quantity).round();
      await db
          .into(db.incomeTransactions)
          .insert(
            IncomeTransactionsCompanion.insert(
              id: const Uuid().v4(),
              businessId: 'biz_001',
              txnDate: DateTime.now(),
              categoryId: 'sale_biz_001',
              amount: saleAmountCents,
              paymentAccountId: Value(paymentAccountId),
              description: Value(product.name),
              reference: Value(productId),
              notes: Value(notes),
              status: const Value('completed'),
            ),
          );
    });
  }

  Future<void> recordProduction({
    required String productId,
    required double quantity,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    await db.transaction(() async {
      await _deductRecursive(
        productId,
        quantity,
        referenceType,
        referenceId,
        notes,
      );
    });
  }

  Future<void> _deductRecursive(
    String productId,
    double quantity,
    String? referenceType,
    String? referenceId,
    String? notes,
  ) async {
    final recipe = await (db.select(
      db.recipes,
    )..where((r) => r.productId.equals(productId))).getSingleOrNull();
    if (recipe == null) return; // no BOM for this product — nothing to deduct

    final components = await (db.select(
      db.recipeComponents,
    )..where((c) => c.recipeId.equals(recipe.id))).get();

    final batches = quantity / recipe.yieldQuantity;

    for (final component in components) {
      final requiredInComponentUnit = component.quantityRequired * batches;

      if (component.componentType == 'supply') {
        final supply = await (db.select(
          db.supplies,
        )..where((s) => s.id.equals(component.supplyId!))).getSingle();

        final requiredInStockUnit = UnitConverter.convert(
          requiredInComponentUnit,
          component.unit,
          supply.stockUnit,
        );

        final newStock = supply.currentStock - requiredInStockUnit;
        if (newStock < 0) {
          throw StateError(
            'Not enough "${supply.name}" in stock — need '
            '${requiredInStockUnit.toStringAsFixed(1)} ${supply.stockUnit}, '
            'have ${supply.currentStock} ${supply.stockUnit}.',
          );
        }

        await (db.update(db.supplies)..where((s) => s.id.equals(supply.id)))
            .write(SuppliesCompanion(currentStock: Value(newStock)));

        await db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: const Uuid().v4(),
                supplyId: supply.id,
                movementType: 'production_consumption',
                quantity: -requiredInStockUnit,
                referenceType: Value(referenceType),
                referenceId: Value(referenceId),
                notes: Value(notes),
                unit: '',
              ),
            );
      } else {
        // Nested product: consuming this much of it means producing
        // (and thus deducting) that much of ITS own recipe. This
        // models make-to-order production — there's no separate
        // "Espresso Base inventory" sitting around; it's made fresh
        // as needed, all the way down to raw supplies.
        await _deductRecursive(
          component.componentProductId!,
          requiredInComponentUnit,
          referenceType,
          referenceId,
          notes,
        );
      }
    }
  }

  // ------------------------------------------------------------
  // "What raw materials would N units of this need?" (no deduction —
  // a dry-run, useful for a shopping-list / planning view.)
  // ------------------------------------------------------------

  Future<Map<String, double>> computeRequiredSupplies({
    required String productId,
    required double quantity,
  }) async {
    final result = <String, double>{};
    await _accumulateRequirements(productId, quantity, result);
    return result;
  }

  Future<void> _accumulateRequirements(
    String productId,
    double quantity,
    Map<String, double> result,
  ) async {
    final recipe = await (db.select(
      db.recipes,
    )..where((r) => r.productId.equals(productId))).getSingleOrNull();
    if (recipe == null) return;

    final components = await (db.select(
      db.recipeComponents,
    )..where((c) => c.recipeId.equals(recipe.id))).get();
    final batches = quantity / recipe.yieldQuantity;

    for (final component in components) {
      final required = component.quantityRequired * batches;

      if (component.componentType == 'supply') {
        final supply = await (db.select(
          db.supplies,
        )..where((s) => s.id.equals(component.supplyId!))).getSingle();
        final inStockUnit = UnitConverter.convert(
          required,
          component.unit,
          supply.stockUnit,
        );
        final key = '${supply.name} (${supply.stockUnit})';
        result[key] = (result[key] ?? 0) + inStockUnit;
      } else {
        await _accumulateRequirements(
          component.componentProductId!,
          required,
          result,
        );
      }
    }
  }
}
