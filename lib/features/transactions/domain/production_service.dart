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

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/ledger/ledger_service.dart';
import 'package:bos_application/features/transactions/domain/costing_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:uuid/uuid.dart';
import 'pos_session_service.dart'
    show PosSessionService, SaleTenderInput, isCashAccount;
import 'package:bos_application/core/stock/stock_service.dart';

import '../../../core/database/app_database.dart';
import 'product_variants.dart';

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

class SaleLineInput {
  final String productId;
  final String productName;
  final String unit;
  final int unitPriceCents;
  final double quantity;
  final List<ProductOptionSelection> options;

  const SaleLineInput({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.unitPriceCents,
    required this.quantity,
    this.options = const [],
  });
}

// ============================================================
// PRODUCTION SERVICE
// ============================================================

class StockShortage {
  final String supplyName;
  final String unit;
  final double required;
  final double available;

  const StockShortage({
    required this.supplyName,
    required this.unit,
    required this.required,
    required this.available,
  });

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String get message =>
      '$supplyName (need ${_n(required)} $unit, have ${_n(available)})';
}

class ProductionService {
  final AppDatabase db;
  final LedgerService ledgerService;

  /// The branch whose stock this service reads and changes.
  final String branchId;
  late final StockService _stock = StockService(db, viewBranchId: branchId);

  ProductionService(this.db, this.ledgerService, {required this.branchId});
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

  // ------------------------------------------------------------
  // POS CHECKOUT — the whole order (every line's deduction, the
  // receipt, and the income entry) in ONE transaction. If any line
  // is short on stock, nothing in the order is applied.
  //
  // [proof] is the optional payment screenshot data (reference no.,
  // amount paid, date, photo). Income posted to the ledger is always
  // the ORDER total; the amount actually paid is stored separately.
  // ------------------------------------------------------------

  // ------------------------------------------------------------
  // POS CHECKOUT — stock deduction + receipt + payment tenders in ONE
  // transaction. Nothing is posted to the ledger here; the shift's sales
  // are posted when the shift is CLOSED (PosSessionService.closeSession).
  // ------------------------------------------------------------

  Future<String> recordSale({
    required String businessId,
    required List<SaleLineInput> lines,
    required bool stockOnly,
    required String sessionId,
    List<SaleTenderInput> tenders = const [],
    String? notes,
    String? cashierUserId,
    String? cashierName,
    String? orderType,
    String? idempotencyKey,
    int discountCents = 0,
    String? discountLabel,
    String? customerId,
    String? newCustomerName,
    String? newCustomerAddress,
    String? newCustomerTin,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('No items to sell.');
    }
    if (!stockOnly && tenders.isEmpty) {
      throw ArgumentError(
        'At least one payment is required unless this is a stock-only sale.',
      );
    }

    // NEW: every sale must belong to a cashier.
    if (cashierUserId == null || cashierUserId.isEmpty) {
      throw StateError('No signed-in cashier. Sign in again to sell.');
    }

    var resolvedName = cashierName?.trim();
    if (resolvedName == null || resolvedName.isEmpty) {
      final u = await (db.select(
        db.users,
      )..where((x) => x.id.equals(cashierUserId))).getSingleOrNull();
      if (u != null) {
        resolvedName = u.displayName.trim().isNotEmpty
            ? u.displayName.trim()
            : u.email;
      }
    }

    final saleId = idempotencyKey ?? const Uuid().v4();
    // Same key sent twice (double tap, retry): already saved, nothing to do.
    if (idempotencyKey != null) {
      final existing = await (db.select(
        db.posSales,
      )..where((s) => s.id.equals(saleId))).getSingleOrNull();
      if (existing != null) return saleId;
    }
    var totalCents = 0;

    await db.transaction(() async {
      final session = await (db.select(
        db.posSessions,
      )..where((s) => s.id.equals(sessionId))).getSingleOrNull();
      if (session == null || session.status != 'open') {
        throw StateError('The shift is closed. Open a shift to sell.');
      }
      if (session.branchId != null && session.branchId != branchId) {
        throw StateError('This shift belongs to another branch.');
      }
      final costing = CostingService(db, branchId: branchId);
      final unitCosts = <String, int>{};

      for (final line in lines) {
        // Cost snapshot for profit reports. Never blocks a sale.
        try {
          unitCosts[line.productId] = (await costing.computeProductCost(
            line.productId,
          )).totalCostCents;
        } catch (_) {
          unitCosts[line.productId] = 0;
        }

        await _deductForSale(
          line,
          stockOnly ? 'pos_stock_only' : 'pos_sale',
          saleId,
          notes,
        );
        for (final option in line.options) {
          final inventoryProductId = option.inventoryProductId;
          final inventorySupplyId = option.inventorySupplyId;
          if (option.inventoryQuantity <= 0) {
            continue;
          }
          if (inventorySupplyId != null) {
            await _deductSupplyForOption(
              supplyId: inventorySupplyId,
              quantity: line.quantity * option.inventoryQuantity,
              referenceType: stockOnly
                  ? 'pos_stock_only_option'
                  : 'pos_sale_option',
              saleId: saleId,
              notes: notes,
            );
          } else if (inventoryProductId != null) {
            await _deductForSale(
              SaleLineInput(
                productId: inventoryProductId,
                productName: option.choiceName,
                unit: line.unit,
                unitPriceCents: 0,
                quantity: line.quantity * option.inventoryQuantity,
              ),
              stockOnly ? 'pos_stock_only_option' : 'pos_sale_option',
              saleId,
              notes,
            );
          }
        }
        totalCents += (line.unitPriceCents * line.quantity).round();
      }

      final discount = stockOnly ? 0 : discountCents;
      if (discount < 0 || discount > totalCents) {
        throw StateError('The discount is more than the order total.');
      }
      final netCents = totalCents - discount;

      if (!stockOnly) {
        final paid = tenders.fold<int>(0, (s, t) => s + t.amountCents);
        if (paid != netCents) {
          throw StateError(
            'Payments add up to ${(paid / 100).toStringAsFixed(2)} but the '
            'order total is ${(netCents / 100).toStringAsFixed(2)}.',
          );
        }
      }

      // Customer: an existing one, or a new one saved together with this sale.
      String? resolvedCustomerId;
      if (!stockOnly) {
        if (customerId != null) {
          final c =
              await (db.select(db.customers)..where(
                    (x) =>
                        x.id.equals(customerId) &
                        x.businessId.equals(businessId) &
                        x.isActive.equals(true),
                  ))
                  .getSingleOrNull();
          if (c == null) throw StateError('That customer is not available.');
          resolvedCustomerId = c.id;
        } else if ((newCustomerName ?? '').trim().isNotEmpty) {
          resolvedCustomerId = await _saveCustomerForSale(
            businessId,
            newCustomerName!,
            newCustomerAddress,
            newCustomerTin,
          );
        }
      }

      // Credit: any tender posted to Accounts Receivable needs a customer.
      String? arId;
      try {
        arId = (await ledgerService.receivableAccount(businessId)).id;
      } on LedgerException {
        arId = null;
      }
      final hasCredit =
          !stockOnly && arId != null && tenders.any((t) => t.accountId == arId);
      if (hasCredit && resolvedCustomerId == null) {
        throw StateError('Choose the customer to charge this credit to.');
      }
      // Receipt number: shift code + running number within the shift.n the shift.
      final countRow = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM pos_sales WHERE session_id = ?',
            variables: [Variable.withString(sessionId)],
          )
          .getSingle();
      final branch = await (db.select(
        db.branches,
      )..where((b) => b.id.equals(branchId))).getSingleOrNull();
      final branchCode = (branch?.code ?? '').trim().toUpperCase();
      final receiptNo =
          '${branchCode.isEmpty ? '' : '$branchCode-'}'
          '${sessionId.substring(0, 4).toUpperCase()}-'
          '${(countRow.read<int>('c') + 1).toString().padLeft(3, '0')}';

      // Cash always goes to THIS branch's drawer.
      var payTenders = tenders;
      final cashId = branch?.cashAccountId;
      if (!stockOnly && cashId != null) {
        final accs =
            await (db.select(db.accounts)..where(
                  (a) => a.id.isIn(tenders.map((t) => t.accountId).toList()),
                ))
                .get();
        final accNames = {for (final a in accs) a.id: a.name};
        payTenders = [
          for (final t in tenders)
            (t.accountId != cashId &&
                    isCashAccount(t.accountId, accNames[t.accountId] ?? ''))
                ? SaleTenderInput(
                    accountId: cashId,
                    amountCents: t.amountCents,
                    tenderedCents: t.tenderedCents,
                    changeCents: t.changeCents,
                    provider: t.provider,
                    proof: t.proof,
                  )
                : t,
        ];
      }

      await db
          .into(db.posSales)
          .insert(
            PosSalesCompanion.insert(
              id: saleId,
              businessId: businessId,
              totalAmount: Value(stockOnly ? 0 : netCents),
              discountAmount: Value(discount),
              discountLabel: Value(discount > 0 ? discountLabel : null),
              receiptNo: Value(receiptNo),
              customerId: Value(resolvedCustomerId),
              isStockOnly: Value(stockOnly),
              // Kept for older screens; the real breakdown is in tenders.
              paymentAccountId: Value(
                stockOnly ? null : payTenders.first.accountId,
              ),
              sessionId: Value(sessionId),
              branchId: Value(branchId),
              notes: Value(notes),
              cashierUserId: Value(cashierUserId),
              cashierName: Value(resolvedName),
              orderType: Value(
                (orderType ?? '').trim().isEmpty ? null : orderType!.trim(),
              ),
            ),
          );

      if (!stockOnly) {
        // Reject reused references (new tenders table + legacy payments).
        for (final t in tenders) {
          final reference = t.proof?.referenceNo;
          if (reference == null) continue;
          if (await PosSessionService.referenceInUse(db, reference)) {
            throw StateError(
              'Reference $reference was already used on a previous sale.',
            );
          }
        }
        await PosSessionService.insertTenders(db, saleId, payTenders);
      }

      for (final line in lines) {
        final saleItemId = const Uuid().v4();
        await db
            .into(db.posSaleItems)
            .insert(
              PosSaleItemsCompanion.insert(
                id: saleItemId,
                saleId: saleId,
                productId: Value(line.productId),
                productName: line.productName,
                unit: line.unit,
                unitPrice: line.unitPriceCents,
                quantity: line.quantity,
                unitCost: Value(unitCosts[line.productId] ?? 0),
                lineTotal: (line.unitPriceCents * line.quantity).round(),
              ),
            );
        for (final option in line.options) {
          await db.customStatement(
            'INSERT INTO pos_sale_item_options '
            '(id, sale_item_id, group_id, choice_id, group_name, choice_name, '
            'price_delta_cents, quantity) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
              const Uuid().v4(),
              saleItemId,
              option.groupId,
              option.choiceId,
              option.groupName,
              option.choiceName,
              option.priceDeltaCents,
              option.inventoryQuantity,
            ],
          );
        }
      }

      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: cashierUserId,
        actorName: resolvedName,
        action: stockOnly ? 'sales.stock_only_sale' : 'sales.sale_recorded',
        module: AuditModule.sales,
        // A stock-only sale removes stock with no revenue: treat as an
        // adjustment so it is visible in that filter.
        actionType: stockOnly
            ? AuditActionType.adjustment
            : AuditActionType.create,
        entityType: 'pos_sales',
        entityId: saleId,
        entityLabel: 'Sale ${saleId.substring(0, 8).toUpperCase()}',
        reason: stockOnly ? notes : null,
        after: {
          'total': stockOnly ? 0 : netCents,
          'discount': discount,
          'itemCount': lines.length,
          'sessionId': sessionId,
          'stockOnly': stockOnly,
        },
        details: {
          'items': [
            for (final l in lines)
              {
                'name': l.productName,
                'qty': l.quantity,
                'unitPrice': l.unitPriceCents,
              },
          ],
          'tenders': [
            for (final t in tenders)
              {'accountId': t.accountId, 'amount': t.amountCents},
          ],
        },
      );
    });

    return saleId;
  }

  /// Saves a customer typed in at the POS. A name that already exists is
  /// reused (blank address / TIN are filled in) instead of duplicated.
  Future<String> _saveCustomerForSale(
    String businessId,
    String name,
    String? address,
    String? tin,
  ) async {
    final clean = name.trim();
    final addr = (address ?? '').trim();
    final t = (tin ?? '').trim();

    final matches =
        await (db.select(db.customers)..where(
              (c) =>
                  c.businessId.equals(businessId) &
                  c.isActive.equals(true) &
                  c.name.lower().equals(clean.toLowerCase()),
            ))
            .get();

    if (matches.isNotEmpty) {
      final existing = matches.first;
      final fillAddress = (existing.address ?? '').isEmpty && addr.isNotEmpty;
      final fillTin = (existing.tin ?? '').isEmpty && t.isNotEmpty;
      if (fillAddress || fillTin) {
        await (db.update(
          db.customers,
        )..where((c) => c.id.equals(existing.id))).write(
          CustomersCompanion(
            address: fillAddress ? Value(addr) : const Value.absent(),
            tin: fillTin ? Value(t) : const Value.absent(),
          ),
        );
      }
      return existing.id;
    }

    final id = const Uuid().v4();
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            businessId: businessId,
            name: clean,
            address: Value(addr.isEmpty ? null : addr),
            tin: Value(t.isEmpty ? null : t),
          ),
        );
    return id;
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
        final onHand = await _stock.supplyQty(branchId, supply.id);
        availableInComponentUnit = UnitConverter.convert(
          onHand,
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
    if (product == null) throw StateError('Product not found.');
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

      final saleCategory =
          await (db.select(db.categories)..where(
                (c) =>
                    c.businessId.equals(product.businessId) &
                    c.txnType.equals('income') &
                    c.name.equals('Sale') &
                    c.isActive.equals(true),
              ))
              .getSingleOrNull();

      if (saleCategory == null) {
        throw StateError('No "Sale" income category found for this business.');
      }

      final saleAmountCents = (product.sellPrice! * quantity).round();

      final journalEntryId = await ledgerService.postEntry(
        businessId: product.businessId,
        categoryId: saleCategory.id,
        amount: saleAmountCents,
        paymentAccountId: paymentAccountId,
        sourceType: 'income',
        sourceId: referenceId ?? productId,
        description: product.name,
      );

      await db
          .into(db.incomeTransactions)
          .insert(
            IncomeTransactionsCompanion.insert(
              id: const Uuid().v4(),
              businessId: product.businessId,
              txnDate: DateTime.now(),
              categoryId: saleCategory.id,
              amount: saleAmountCents,
              paymentAccountId: Value(paymentAccountId),
              description: Value(product.name),
              reference: Value(productId),
              notes: Value(notes),
              status: const Value('completed'),
              journalEntryId: Value(journalEntryId),
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
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull();
      await AuditWriter.write(
        db,
        businessId: product?.businessId ?? kCurrentBusinessId,
        userId: null,
        action: 'inventory.production_recorded',
        module: AuditModule.inventory,
        actionType: AuditActionType.create,
        entityType: 'products',
        entityId: productId,
        entityLabel: product?.name,
        after: {'quantity': quantity},
        details: {'referenceType': referenceType, 'referenceId': referenceId},
        reason: notes,
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

        final onHand = await _stock.supplyQty(branchId, supply.id);
        if (onHand - requiredInStockUnit < -1e-9) {
          throw StateError(
            'Not enough "${supply.name}" in stock — need '
            '${requiredInStockUnit.toStringAsFixed(1)} ${supply.stockUnit}, '
            'have ${onHand.toStringAsFixed(1)} ${supply.stockUnit}.',
          );
        }
        await _stock.moveSupply(
          branchId: branchId,
          supplyId: supply.id,
          type: 'production_consumption',
          quantity: -requiredInStockUnit,
          referenceType: referenceType,
          referenceId: referenceId,
          notes: notes,
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

  /// Dry-run for a whole order. Adds up every supply all lines need together
  /// (nested recipes included) and returns each supply that would run short.
  Future<List<StockShortage>> checkOrderStock(List<SaleLineInput> lines) async {
    final need = <String, double>{}; // supplyId -> quantity in stockUnit
    for (final l in lines) {
      await _accumulateBySupplyId(
        l.productId,
        l.quantity,
        need,
        const <String>{},
      );
    }
    if (need.isEmpty) return const [];

    final supplies = await (db.select(
      db.supplies,
    )..where((s) => s.id.isIn(need.keys.toList()))).get();

    final out = <StockShortage>[];
    for (final s in supplies) {
      final required = need[s.id]!;
      final available = await _stock.supplyQty(branchId, s.id);
      if (required > available + 1e-9) {
        out.add(
          StockShortage(
            supplyName: s.name,
            unit: s.stockUnit,
            required: required,
            available: available,
          ),
        );
      }
    }
    return out;
  }

  Future<void> _accumulateBySupplyId(
    String productId,
    double quantity,
    Map<String, double> out,
    Set<String> visited,
  ) async {
    if (visited.contains(productId)) {
      throw StateError(
        'Circular recipe reference detected — a recipe eventually '
        'requires itself as an ingredient.',
      );
    }
    final next = {...visited, productId};

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
        out[supply.id] = (out[supply.id] ?? 0) + inStockUnit;
      } else {
        await _accumulateBySupplyId(
          component.componentProductId!,
          required,
          out,
          next,
        );
      }
    }
  }

  /// Deducts one POS line according to how the product is tracked.
  ///   recipe      -> deduct its supplies (recursive)
  ///   stocked     -> deduct Products.currentStock
  ///   non_stocked -> nothing to deduct
  Future<void> _deductForSale(
    SaleLineInput line,
    String referenceType,
    String saleId,
    String? notes,
  ) async {
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(line.productId))).getSingleOrNull();
    if (product == null || !product.isActive) {
      throw StateError('"${line.productName}" is no longer available.');
    }

    switch (product.trackingType) {
      case 'non_stocked':
        return;
      case 'stocked':
        final onHand = await _stock.productQty(branchId, product.id);
        if (onHand - line.quantity < -1e-9) {
          throw StateError(
            'Not enough "${product.name}" in stock — need '
            '${StockShortage._n(line.quantity)}, have '
            '${StockShortage._n(onHand)}.',
          );
        }
        await _stock.moveProduct(
          branchId: branchId,
          productId: product.id,
          businessId: product.businessId,
          type: 'pos_sale',
          quantity: -line.quantity,
          referenceType: referenceType,
          referenceId: saleId,
          notes: notes,
        );
        return;
      default:
        await _deductRecursive(
          line.productId,
          line.quantity,
          referenceType,
          saleId,
          notes,
        );
    }
  }

  Future<void> _deductSupplyForOption({
    required String supplyId,
    required double quantity,
    required String referenceType,
    required String saleId,
    required String? notes,
  }) async {
    final supply = await (db.select(
      db.supplies,
    )..where((item) => item.id.equals(supplyId))).getSingleOrNull();
    if (supply == null || !supply.isActive) {
      throw StateError('The selected ingredient is no longer available.');
    }
    final onHand = await _stock.supplyQty(branchId, supplyId);
    if (onHand - quantity < -1e-9) {
      throw StateError(
        'Not enough "${supply.name}" in stock — need '
        '${StockShortage._n(quantity)} ${supply.stockUnit}, have '
        '${StockShortage._n(onHand)} ${supply.stockUnit}.',
      );
    }
    await _stock.moveSupply(
      branchId: branchId,
      supplyId: supplyId,
      type: 'pos_sale_option',
      quantity: -quantity,
      referenceType: referenceType,
      referenceId: saleId,
      notes: notes,
    );
  }

  /// Whole-order check before saving. Returns plain-language problems
  /// (empty list = OK to sell). Covers recipe, stocked and untracked
  /// products, and ingredients shared between products in the same order.
  Future<List<String>> checkOrder(List<SaleLineInput> lines) async {
    final problems = <String>[];
    final recipeLines = <SaleLineInput>[];
    final optionSupplyNeed = <String, double>{};

    for (final l in lines) {
      final p = await (db.select(
        db.products,
      )..where((x) => x.id.equals(l.productId))).getSingleOrNull();
      if (p == null || !p.isActive) {
        problems.add('"${l.productName}" is no longer available.');
        continue;
      }
      for (final option in l.options) {
        if (option.inventorySupplyId != null && option.inventoryQuantity > 0) {
          optionSupplyNeed.update(
            option.inventorySupplyId!,
            (value) => value + l.quantity * option.inventoryQuantity,
            ifAbsent: () => l.quantity * option.inventoryQuantity,
          );
        }
      }

      switch (p.trackingType) {
        case 'non_stocked':
          break;
        case 'stocked':
          final onHand = await _stock.productQty(branchId, p.id);
          if (l.quantity > onHand + 1e-9) {
            problems.add(
              'Not enough ${p.name}: only '
              '${StockShortage._n(onHand)} ${p.unit} left.',
            );
          }
        default:
          final r = await computeMaxProducible(p.id);
          final hasRecipe =
              r.limitingComponentName != null || r.componentMaxUnits.isNotEmpty;
          if (!hasRecipe) {
            problems.add(
              '${p.name} has no ingredients attached, so stock can\'t be '
              'deducted. Remove it, or add a recipe in Products & Recipes.',
            );
          } else if (l.quantity > r.maxUnits) {
            problems.add(
              'Not enough stock: ${p.name} (only ${r.maxUnits} left).',
            );
          } else {
            recipeLines.add(l);
          }
      }
    }

    if (problems.isEmpty && recipeLines.isNotEmpty) {
      for (final s in await checkOrderStock(recipeLines)) {
        problems.add(
          'Shared ingredient is short for the whole order: ${s.message}',
        );
      }
    }
    if (problems.isEmpty && optionSupplyNeed.isNotEmpty) {
      final supplies = await (db.select(
        db.supplies,
      )..where((s) => s.id.isIn(optionSupplyNeed.keys.toList()))).get();
      for (final supply in supplies) {
        final required = optionSupplyNeed[supply.id]!;
        final available = await _stock.supplyQty(branchId, supply.id);
        if (required > available + 1e-9) {
          problems.add(
            'Not enough ${supply.name} for add-ons: only '
            '${StockShortage._n(available)} ${supply.stockUnit} left.',
          );
        }
      }
    }
    return problems;
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

  Future<void> sellMultiple({
    required List<({String productId, double quantity})> lines,
    required String paymentAccountId,
    String? referenceId,
    String? notes,
  }) async {
    await db.transaction(() async {
      var totalCents = 0;
      for (final line in lines) {
        final product = await (db.select(
          db.products,
        )..where((p) => p.id.equals(line.productId))).getSingleOrNull();
        if (product == null) throw StateError('Product not found.');
        if (product.sellPrice == null) {
          throw StateError('"${product.name}" has no sell price set.');
        }
        await _deductRecursive(
          line.productId,
          line.quantity,
          'product_sale',
          referenceId,
          notes,
        );
        totalCents += (product.sellPrice! * line.quantity).round();
      }

      final saleCategory =
          await (db.select(db.categories)..where(
                (c) =>
                    c.businessId.equals(kCurrentBusinessId) &
                    c.txnType.equals('income') &
                    c.name.equals('Sale') &
                    c.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (saleCategory == null) {
        throw StateError('No "Sale" income category found.');
      }

      await db
          .into(db.incomeTransactions)
          .insert(
            IncomeTransactionsCompanion.insert(
              id: const Uuid().v4(),
              businessId: kCurrentBusinessId,
              txnDate: DateTime.now(),
              categoryId: saleCategory.id,
              amount: totalCents,
              paymentAccountId: Value(paymentAccountId),
              description: const Value('POS sale'),
              notes: Value(notes),
              status: const Value('completed'),
            ),
          );
    });
  }
}
