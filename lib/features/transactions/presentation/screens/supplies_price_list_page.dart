import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/auth/authorization_service.dart'
    show PermissionDeniedException;
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/permission_gate.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/auth/authorization_providers.dart'
    show selectedBusinessIdProvider, authorizationServiceProvider, canProvider;
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/transactions/domain/costing_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_draft_cart_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_cart_search.dart';
import 'package:bos_application/features/transactions/domain/purchase_line_pricing.dart';
import 'package:bos_application/features/transactions/domain/purchase_stock_conversion.dart';
import 'package:bos_application/features/transactions/domain/purchase_unit_options.dart';
import 'package:bos_application/features/transactions/domain/supply_catalog_service.dart';
import 'package:bos_application/features/transactions/domain/unit_options.dart';
import 'package:bos_application/features/transactions/presentation/screens/products_page.dart'
    hide costingServiceProvider;
import 'package:bos_application/features/transactions/presentation/screens/purchase_entry_sheet.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/purchase_line_editor_dialog.dart';
import 'package:bos_application/features/transactions/presentation/widgets/supply_catalog_filters.dart';
import 'package:bos_application/features/transactions/presentation/widgets/supply_detail_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/supply_identity_fields.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui show TextDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../transactions/presentation/screens/transaction_page.dart'
    show
        ledgerVersionProvider,
        kCurrentBusinessId,
        paymentAccountsProvider,
        ExpensePaymentSplit;

// ============================================================================
// HELPERS
// ============================================================================

String _qty(double v) {
  final r = double.parse(v.toStringAsFixed(4)); // hides 0.30000000000000004
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

String _peso(int cents) {
  return '₱${NumberFormat('#,##0.00').format(cents / 100)}';
}

String _formatDate(DateTime date) {
  return DateFormat('MMM d, yyyy').format(date);
}

String _formatDateShort(DateTime date) {
  return DateFormat('MMM d').format(date);
}

/// Store labels written as placeholders when the user left store blank.
/// Hide these in UI so history tiles show only a real store or just the date.
String? _displayStoreName(String? storeName) {
  final trimmed = (storeName ?? '').trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower == 'unspecified' || lower == 'initial price') {
    return null;
  }
  return trimmed;
}

/// The unit the user actually thinks in for a supply's stock quantities:
/// its purchase unit (e.g. "pack") when one is configured, falling back to
/// the tracked/base stock unit (e.g. "kg") otherwise.
String _displayStockUnit(Supply supply) {
  final purchaseUnit = supply.purchaseUnit?.trim() ?? '';
  if (purchaseUnit.isNotEmpty && supply.unitsPerPurchase > 0) {
    return purchaseUnit;
  }
  return supply.stockUnit;
}

/// Converts a base-unit stock quantity (kg, ml, piece...) into the
/// purchase-unit quantity (packs, sacks...) the user thinks in, when a
/// purchase unit/ratio is configured. All storage and cost math continues
/// to use the raw base-unit quantity — this is a display-only conversion.
double _displayStockQuantity(Supply supply, double baseQuantity) {
  final purchaseUnit = supply.purchaseUnit?.trim() ?? '';
  if (purchaseUnit.isNotEmpty && supply.unitsPerPurchase > 0) {
    return baseQuantity / supply.unitsPerPurchase;
  }
  return baseQuantity;
}

/// Cart + checkout. Purchasing group: the Permissions screen describes
/// purchasing.create as "Build carts and record purchases".
const _kCartPermission = BosPermission.purchasingCreate;

/// UI-side guard. Returns true when the signed-in member has [permission];
/// otherwise shows why and returns false.
bool _allowed(BuildContext context, WidgetRef ref, BosPermission permission) {
  try {
    ref
        .read(authorizationServiceProvider)
        .require(permission, businessId: kCurrentBusinessId);
    return true;
  } on PermissionDeniedException catch (e) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(e.message)),
      );
    return false;
  }
}

class _NoAccessView extends StatelessWidget {
  final String title;
  final String message;

  const _NoAccessView({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 44, color: scheme.outline),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SUPPLIES PROVIDERS
// ============================================================================
final stockAdjustmentHistoryProvider =
    StreamProvider.family<List<InventoryMovement>, String>((ref, supplyId) {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final branchId = ref.watch(selectedBranchIdProvider);
      final businessId = ref.watch(selectedBusinessIdProvider);

      return (db.select(db.inventoryMovements)
            ..where(
              (movement) =>
                  movement.supplyId.equals(supplyId) &
                  movement.movementType.equals('manual_adjustment') &
                  inventoryMovementInBranch(movement, businessId, branchId) &
                  (movement.referenceType.isNull() |
                      movement.referenceType.isNotIn(const [
                        'pos_void',
                        'pos_restore',
                      ])),
            )
            ..orderBy([
              (movement) => OrderingTerm(
                expression: movement.movementDate,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();
    });

final costingServiceProvider = Provider<CostingService>((ref) {
  return CostingService(
    ref.watch(databaseProvider),
    branchId: ref.watch(selectedBranchIdProvider),
    guard: (permission) => ref
        .read(authorizationServiceProvider)
        .require(permission, businessId: kCurrentBusinessId),
  );
});

final suppliesProvider = StreamProvider<List<Supply>>((ref) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  return (db.select(db.supplies)
        ..where(
          (s) =>
              s.businessId.equals(kCurrentBusinessId) & s.isActive.equals(true),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch();
});

class PurchaseHistoryCheckout {
  final ShoppingCart cart;
  final List<ShoppingCartItem> items;

  const PurchaseHistoryCheckout({required this.cart, required this.items});
}

final purchaseHistoryProvider = StreamProvider<List<PurchaseHistoryCheckout>>((
  ref,
) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  final branchId = ref.watch(selectedBranchIdProvider);
  final cartInBranch = branchId == AppDatabase.mainBranchId(kCurrentBusinessId)
      ? (db.shoppingCarts.branchId.equals(branchId) |
            db.shoppingCarts.branchId.isNull())
      : db.shoppingCarts.branchId.equals(branchId);
  final query =
      db.select(db.shoppingCarts).join([
          innerJoin(
            db.shoppingCartItems,
            db.shoppingCartItems.cartId.equalsExp(db.shoppingCarts.id),
          ),
        ])
        ..where(
          db.shoppingCarts.businessId.equals(kCurrentBusinessId) &
              cartInBranch &
              db.shoppingCarts.expenseId.isNotNull(),
        )
        ..orderBy([
          OrderingTerm(
            expression: db.shoppingCarts.cartDate,
            mode: OrderingMode.desc,
          ),
          OrderingTerm(
            expression: db.shoppingCarts.createdAt,
            mode: OrderingMode.desc,
          ),
        ]);

  return query.watch().map((rows) {
    final grouped = <String, PurchaseHistoryCheckout>{};

    for (final row in rows) {
      final cart = row.readTable(db.shoppingCarts);
      final item = row.readTable(db.shoppingCartItems);
      final checkout = grouped[cart.id];

      if (checkout == null) {
        grouped[cart.id] = PurchaseHistoryCheckout(cart: cart, items: [item]);
      } else {
        grouped[cart.id] = PurchaseHistoryCheckout(
          cart: checkout.cart,
          items: [...checkout.items, item],
        );
      }
    }

    return grouped.values.toList();
  });
});

class PurchasePaymentDetail {
  final Account account;
  final int amount;

  const PurchasePaymentDetail({required this.account, required this.amount});
}

final purchasePaymentDetailsProvider =
    FutureProvider.family<List<PurchasePaymentDetail>, String?>((
      ref,
      expenseId,
    ) async {
      ref.watch(ledgerVersionProvider);

      if (expenseId == null || expenseId.trim().isEmpty) {
        return const <PurchasePaymentDetail>[];
      }

      final db = ref.watch(databaseProvider);

      final expense = await (db.select(
        db.expenses,
      )..where((expense) => expense.id.equals(expenseId))).getSingleOrNull();

      if (expense == null) {
        return const <PurchasePaymentDetail>[];
      }

      if (expense.journalEntryId == null) {
        final paymentAccountId = expense.paymentAccountId;
        if (paymentAccountId == null || paymentAccountId.trim().isEmpty) {
          return const <PurchasePaymentDetail>[];
        }

        final account = await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(paymentAccountId))).getSingleOrNull();

        if (account == null) {
          return const <PurchasePaymentDetail>[];
        }

        return <PurchasePaymentDetail>[
          PurchasePaymentDetail(account: account, amount: expense.amount),
        ];
      }

      final rows =
          await (db.select(db.ledgerLines).join([
                  innerJoin(
                    db.accounts,
                    db.accounts.id.equalsExp(db.ledgerLines.accountId),
                  ),
                ])
                ..where(
                  db.ledgerLines.journalEntryId.equals(
                        expense.journalEntryId!,
                      ) &
                      db.ledgerLines.credit.isBiggerThanValue(0) &
                      db.accounts.isPaymentAccount.equals(true) &
                      db.accounts.isActive.equals(true),
                )
                ..orderBy([
                  OrderingTerm(
                    expression: db.accounts.name,
                    mode: OrderingMode.asc,
                  ),
                ]))
              .get();

      if (rows.isNotEmpty) {
        return rows
            .map(
              (row) => PurchasePaymentDetail(
                account: row.readTable(db.accounts),
                amount: row.readTable(db.ledgerLines).credit,
              ),
            )
            .toList(growable: false);
      }

      // Fallback for older single-payment records whose journal still exists
      // but the payment line cannot be resolved from the joined accounts.
      final paymentAccountId = expense.paymentAccountId;
      if (paymentAccountId == null || paymentAccountId.trim().isEmpty) {
        return const <PurchasePaymentDetail>[];
      }

      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(paymentAccountId))).getSingleOrNull();

      if (account == null) {
        return const <PurchasePaymentDetail>[];
      }

      return <PurchasePaymentDetail>[
        PurchasePaymentDetail(account: account, amount: expense.amount),
      ];
    });

// ============================================================================
// ALL STOCK ADJUSTMENTS (ACROSS THE WHOLE CATALOG)
// ============================================================================
//
// InventoryMovements stores the write-off's reason/note text in its
// `notes` column (nullable) — the same column CostingService.adjustStock()
// writes into via its `reason:` parameter — so every helper below reads
// and writes `movement.notes`.

class StockAdjustmentRecord {
  final InventoryMovement movement;
  final Supply supply;

  const StockAdjustmentRecord({required this.movement, required this.supply});

  /// How much stock this adjustment is still keeping off the shelf, right
  /// now. A write-off starts negative in `movement.quantity`; editing or
  /// restoring it moves this back toward (and eventually to) zero.
  double get outstandingRemoved =>
      movement.quantity < 0 ? -movement.quantity : 0;

  /// True once this write-off has been fully restored (quantity is 0 or
  /// positive — nothing is currently being kept off the shelf by it).
  bool get isFullyRestored => movement.quantity >= 0;
}

final allStockAdjustmentsProvider = StreamProvider<List<StockAdjustmentRecord>>(
  (ref) {
    ref.watch(ledgerVersionProvider);
    final branchId = ref.watch(selectedBranchIdProvider);
    final db = ref.watch(databaseProvider);

    final query =
        db.select(db.inventoryMovements).join([
            innerJoin(
              db.supplies,
              db.supplies.id.equalsExp(db.inventoryMovements.supplyId),
            ),
          ])
          ..where(
            db.inventoryMovements.movementType.equals('manual_adjustment') &
                (db.inventoryMovements.referenceType.isNull() |
                    db.inventoryMovements.referenceType.isNotIn(const [
                      'pos_void',
                      'pos_restore',
                    ])) &
                inventoryMovementInBranch(
                  db.inventoryMovements,
                  kCurrentBusinessId,
                  branchId,
                ) &
                db.supplies.businessId.equals(kCurrentBusinessId),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.inventoryMovements.movementDate,
              mode: OrderingMode.desc,
            ),
          ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => StockAdjustmentRecord(
              movement: row.readTable(db.inventoryMovements),
              supply: row.readTable(db.supplies),
            ),
          )
          .toList(),
    );
  },
);

_AdjustmentReason _adjustmentCategoryFor(String? reason) {
  final trimmed = (reason ?? '').trim();
  for (final r in _AdjustmentReason.values) {
    if (trimmed.startsWith(r.label)) return r;
  }
  return _AdjustmentReason.other;
}

String _adjustmentNoteFor(String? reason, _AdjustmentReason category) {
  var trimmed = (reason ?? '').trim();
  const restoredSuffix = '(Restored)';
  if (trimmed.endsWith(restoredSuffix)) {
    trimmed = trimmed
        .substring(0, trimmed.length - restoredSuffix.length)
        .trim();
  }
  if (trimmed.startsWith(category.label)) {
    trimmed = trimmed.substring(category.label.length).trim();
    if (trimmed.startsWith('—') || trimmed.startsWith('-')) {
      trimmed = trimmed.substring(1).trim();
    }
  }
  return trimmed;
}

String _markReasonRestored(String? reason) {
  final trimmed = (reason ?? '').trim();
  if (trimmed.endsWith('(Restored)')) return trimmed;
  return '$trimmed (Restored)';
}

/// Shared write path for both the quick "Restore" action and the edit sheet
/// below: moves the movement's quantity to `newOutstandingRemoved` (0 means
/// fully restored) and applies the resulting delta to the supply's current
/// stock, all inside one transaction.
Future<void> _applyAdjustmentEdit({
  required WidgetRef ref,
  required StockAdjustmentRecord record,
  required double newOutstandingRemoved,
  required String newReason,
}) async {
  ref
      .read(authorizationServiceProvider)
      .require(BosPermission.inventoryAdjust, businessId: kCurrentBusinessId);
  final db = ref.read(databaseProvider);
  final audit = ref.read(auditLogServiceProvider);
  final viewBranchId = ref.read(selectedBranchIdProvider);

  final oldQuantity = record.movement.quantity;
  final newQuantity = newOutstandingRemoved <= 0 ? 0.0 : -newOutstandingRemoved;
  final delta = newQuantity - oldQuantity;

  await db.transaction(() async {
    final supply = await (db.select(
      db.supplies,
    )..where((s) => s.id.equals(record.supply.id))).getSingleOrNull();

    if (supply == null) {
      throw StateError('This supply no longer exists.');
    }

    final branchId =
        record.movement.branchId ?? AppDatabase.mainBranchId(supply.businessId);
    if (branchId != viewBranchId) {
      throw StateError(
        'This adjustment belongs to another branch. Switch to that branch to edit it.',
      );
    }
    final currentQty = await StockService(
      db,
      viewBranchId: viewBranchId,
    ).supplyQty(branchId, supply.id);
    final updatedStock = currentQty + delta;
    if (updatedStock < 0) {
      throw StateError(
        'That change would make stock negative for "${supply.name}".',
      );
    }

    await (db.update(
      db.inventoryMovements,
    )..where((movement) => movement.id.equals(record.movement.id))).write(
      InventoryMovementsCompanion(
        quantity: Value(newQuantity),
        notes: Value(newReason.trim().isEmpty ? null : newReason.trim()),
      ),
    );

    await StockService.recompute(
      db,
      businessId: supply.businessId,
      branchId: branchId,
    );
    final restoring = newOutstandingRemoved <= 0;
    final cleanReason = newReason.trim().isEmpty
        ? 'Stock adjustment edited'
        : newReason.trim();
    await audit.record(
      AuditEvent(
        businessId: supply.businessId,
        module: AuditModule.inventory,
        actionType: AuditActionType.adjustment,
        action: restoring
            ? 'inventory.write_off_restored'
            : 'inventory.write_off_edited',
        entityType: 'supplies',
        entityId: supply.id,
        entityLabel: supply.name,
        reason: cleanReason,
        before: {
          'stockWrittenOff': record.outstandingRemoved,
          'stock': currentQty,
        },
        after: {
          'stockWrittenOff': restoring ? 0.0 : newOutstandingRemoved,
          'stock': updatedStock,
        },
        details: {'unit': supply.stockUnit, 'movementId': record.movement.id},
      ),
    );
  });

  ref.read(ledgerVersionProvider.notifier).state++;
}

final priceHistoryProvider =
    StreamProvider.family<List<SupplyPriceHistoryData>, String>((
      ref,
      supplyId,
    ) {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);

      return (db.select(db.supplyPriceHistory)
            ..where((history) => history.supplyId.equals(supplyId))
            ..orderBy([
              (history) => OrderingTerm(
                expression: history.recordedDate,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();
    });

class CartItem {
  final String id;
  final String? supplyId;
  final String name;
  final String? brand;
  final double? unitQuantity;
  final String? unit;
  final double stockUnitsPerUnit;
  final int unitPrice;
  final int quantity;
  final int totalPriceCents;
  final int grossTotalCents;
  final String discountType;
  final double discountValue;
  final int discountAmountCents;
  final bool checked;
  final bool isWeighted;
  final double weightQuantity;

  /// The original stored unit price (cents) this line's price derives from.
  /// Unit switching always converts from this anchor — never from an
  /// already converted/rounded price. Null for legacy rows; falls back to
  /// [unitPrice].
  final int? originalUnitPrice;

  /// Conversion factor of the unit [originalUnitPrice] is for, in stock
  /// units per unit. Null falls back to [stockUnitsPerUnit].
  final double? originalStockUnitsPerUnit;

  const CartItem({
    required this.id,
    this.supplyId,
    required this.name,
    this.brand,
    this.unitQuantity,
    this.unit,
    this.stockUnitsPerUnit = 1,
    required this.unitPrice,
    required this.quantity,
    required this.totalPriceCents,
    this.grossTotalCents = 0,
    this.discountType = PurchaseLinePricing.noDiscount,
    this.discountValue = 0,
    this.discountAmountCents = 0,
    this.checked = false,
    this.isWeighted = false,
    this.weightQuantity = 1.0,
    this.originalUnitPrice,
    this.originalStockUnitsPerUnit,
  });

  int get lineTotal => totalPriceCents;

  /// Anchor price the line's unit conversions derive from.
  int get anchorUnitPriceCents => originalUnitPrice ?? unitPrice;

  /// Conversion factor of the unit the anchor price is for.
  double get anchorStockUnitsPerUnit {
    final original = originalStockUnitsPerUnit;
    if (original != null && original.isFinite && original > 0) {
      return original;
    }
    return stockUnitsPerUnit.isFinite && stockUnitsPerUnit > 0
        ? stockUnitsPerUnit
        : 1.0;
  }

  /// Unrounded price per selected unit in cents. Line totals are computed
  /// from this so currency rounding happens once, on the monetary total.
  double get preciseUnitPriceCents {
    final factor = stockUnitsPerUnit.isFinite && stockUnitsPerUnit > 0
        ? stockUnitsPerUnit
        : 1.0;
    return anchorUnitPriceCents * factor / anchorStockUnitsPerUnit;
  }

  CartItem copyWith({
    String? id,
    String? supplyId,
    String? name,
    String? brand,
    double? unitQuantity,
    String? unit,
    double? stockUnitsPerUnit,
    int? unitPrice,
    int? quantity,
    int? totalPriceCents,
    int? grossTotalCents,
    String? discountType,
    double? discountValue,
    int? discountAmountCents,
    bool? checked,
    bool? isWeighted,
    double? weightQuantity,
    int? originalUnitPrice,
    double? originalStockUnitsPerUnit,
  }) {
    final nextTotal = totalPriceCents ?? this.totalPriceCents;
    final nextUnitPrice = unitPrice ?? this.unitPrice;
    return CartItem(
      id: id ?? this.id,
      supplyId: supplyId ?? this.supplyId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      unitQuantity: unitQuantity ?? this.unitQuantity,
      unit: unit ?? this.unit,
      stockUnitsPerUnit: stockUnitsPerUnit ?? this.stockUnitsPerUnit,
      unitPrice: nextUnitPrice,
      quantity: quantity ?? this.quantity,
      totalPriceCents: nextTotal,
      grossTotalCents: grossTotalCents ?? this.grossTotalCents,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      discountAmountCents: discountAmountCents ?? this.discountAmountCents,
      checked: checked ?? this.checked,
      isWeighted: isWeighted ?? this.isWeighted,
      weightQuantity: weightQuantity ?? this.weightQuantity,
      originalUnitPrice: originalUnitPrice ?? this.originalUnitPrice,
      originalStockUnitsPerUnit:
          originalStockUnitsPerUnit ?? this.originalStockUnitsPerUnit,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  final PurchaseDraftCartService _draftCartService;
  final String businessId;
  String? storeName;
  String? storeAddress;
  Future<void>? _loadFuture;
  Future<void> _writeQueue = Future<void>.value();

  /// Throws PermissionDeniedException when the member may not build
  /// purchases. Supplied by cartProvider so it reads the CURRENT role.
  final void Function()? _requireCartAccess;

  CartNotifier(
    this._draftCartService,
    this.businessId, {
    void Function()? requireCartAccess,
  }) : _requireCartAccess = requireCartAccess,
       super([]);

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    final draft = await _draftCartService.load(businessId);
    if (draft == null) return;
    storeName = draft.header.storeName;
    storeAddress = draft.header.storeAddress;
    state = [
      for (final line in draft.lines)
        CartItem(
          id: line.id,
          supplyId: line.supplyId,
          name: line.itemName,
          brand: line.brand,
          unitQuantity: line.unitQuantity,
          unit: line.unit,
          stockUnitsPerUnit: line.stockUnitsPerUnit,
          unitPrice: line.unitPrice,
          quantity: line.quantity,
          totalPriceCents: line.lineTotal,
          grossTotalCents: line.grossLineTotal,
          discountType: line.discountType,
          discountValue: line.discountValue,
          discountAmountCents: line.discountAmount,
          isWeighted: line.isWeighted,
          weightQuantity: line.weightQuantity ?? 1.0,
          originalUnitPrice: line.originalUnitPrice,
          originalStockUnitsPerUnit: line.originalStockUnitsPerUnit,
        ),
    ];
  }

  Future<void> _mutate(
    List<CartItem> Function(List<CartItem>) transform, {
    bool system = false,
  }) {
    final operation = _writeQueue.then((_) async {
      // User actions need cart access. System syncs (catalog name/brand
      // mirroring) never do.
      if (!system) _requireCartAccess?.call();
      await load();
      final next = transform(state);
      await _draftCartService.save(
        businessId: businessId,
        lines: [
          for (final item in next)
            PurchaseDraftCartLine(
              id: item.id,
              supplyId: item.supplyId,
              itemName: item.name,
              brand: item.brand,
              unitQuantity: item.unitQuantity,
              unit: item.unit,
              stockUnitsPerUnit: item.stockUnitsPerUnit,
              unitPrice: item.unitPrice,
              quantity: item.isWeighted ? 1 : item.quantity,
              isWeighted: item.isWeighted,
              weightQuantity: item.isWeighted ? item.weightQuantity : null,
              grossLineTotal: item.grossTotalCents,
              discountType: item.discountType,
              discountValue: item.discountValue,
              discountAmount: item.discountAmountCents,
              lineTotal: item.lineTotal,
              originalUnitPrice: item.originalUnitPrice,
              originalStockUnitsPerUnit: item.originalStockUnitsPerUnit,
            ),
        ],
        totalAmount: next.fold<int>(0, (sum, item) => sum + item.lineTotal),
        storeName: Value(storeName),
        storeAddress: Value(storeAddress),
      );
      state = next;
    });
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> updateDraftMetadata({
    required String? storeName,
    required String? storeAddress,
  }) {
    final operation = _writeQueue.then((_) async {
      _requireCartAccess?.call();
      await load();
      await _draftCartService.updateMetadata(
        businessId: businessId,
        storeName: storeName,
        storeAddress: storeAddress,
      );
      this.storeName = storeName;
      this.storeAddress = storeAddress;
    });
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  CartItem _withQuantity(CartItem item, {int? quantity, double? weight}) {
    final nextQuantity = item.isWeighted
        ? (weight ?? item.weightQuantity)
        : (quantity ?? item.quantity).toDouble();
    // Totals derive from the unrounded anchor-converted price so currency
    // rounding is applied once on the total, never per unit.
    final gross = (item.preciseUnitPriceCents * nextQuantity).round();
    final discount = PurchaseLinePricing.discountAmountCents(
      grossTotalCents: gross,
      discountType: item.discountType,
      discountValue: item.discountValue,
    );
    return item.copyWith(
      quantity: quantity ?? item.quantity,
      weightQuantity: weight ?? item.weightQuantity,
      grossTotalCents: gross,
      discountAmountCents: discount,
      totalPriceCents: gross - discount,
    );
  }

  Future<void> addOrIncrement(Supply supply) {
    return _mutate((current) {
      final initialFactor =
          supply.purchaseUnit?.trim().isNotEmpty == true &&
              supply.unitsPerPurchase > 0
          ? supply.unitsPerPurchase
          : 1.0;
      return [
        ...current,
        CartItem(
          id: const Uuid().v4(),
          supplyId: supply.id,
          name: supply.name,
          brand: supply.brand,
          unitQuantity:
              supply.unitQuantity ??
              (supply.unitsPerPurchase > 0 ? supply.unitsPerPurchase : null),
          unit: (supply.purchaseUnit ?? '').trim().isNotEmpty
              ? supply.purchaseUnit!.trim()
              : supply.stockUnit,
          stockUnitsPerUnit: initialFactor,
          unitPrice: supply.currentPrice,
          quantity: 1,
          totalPriceCents: supply.currentPrice,
          grossTotalCents: supply.currentPrice,
          isWeighted: supply.isSoldByWeight,
          weightQuantity: 1.0,
          originalUnitPrice: supply.currentPrice,
          originalStockUnitsPerUnit: initialFactor,
        ),
      ];
    });
  }

  Future<void> updateWeight(String id, double weight) {
    if (weight <= 0) return removeItem(id);
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.id == id) _withQuantity(item, weight: weight) else item,
      ],
    );
  }

  Future<List<String>> removeMissingSupplies(
    List<Supply> activeSupplies,
  ) async {
    final activeIds = activeSupplies.map((s) => s.id).toSet();
    final removedNames = <String>[];
    await _mutate((current) {
      final kept = <CartItem>[];
      for (final item in current) {
        if (item.supplyId != null && !activeIds.contains(item.supplyId)) {
          removedNames.add(item.name);
        } else {
          kept.add(item);
        }
      }
      return kept;
    }, system: true);
    return removedNames;
  }

  Future<void> addCustomItem({
    required String name,
    required int unitPrice,
    String? brand,
    double? unitQuantity,
    String? unit,
  }) {
    return _mutate(
      (current) => [
        ...current,
        CartItem(
          id: const Uuid().v4(),
          name: name,
          brand: brand,
          unitQuantity: unitQuantity,
          unit: unit,
          unitPrice: unitPrice,
          quantity: 1,
          totalPriceCents: unitPrice,
          grossTotalCents: unitPrice,
          originalUnitPrice: unitPrice,
          originalStockUnitsPerUnit: 1,
        ),
      ],
    );
  }

  Future<void> updateQuantity(String id, int quantity) {
    if (quantity <= 0) return removeItem(id);
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.id == id) _withQuantity(item, quantity: quantity) else item,
      ],
    );
  }

  Future<void> updatePrice(String id, int actualTotalPriceCents) {
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.id == id)
            item.copyWith(
              totalPriceCents: actualTotalPriceCents,
              grossTotalCents: actualTotalPriceCents,
              discountType: PurchaseLinePricing.noDiscount,
              discountValue: 0,
              discountAmountCents: 0,
              unitPrice: () {
                final quantityForPricing = item.isWeighted
                    ? (item.weightQuantity > 0 ? item.weightQuantity : 1.0)
                    : item.quantity.toDouble();
                return quantityForPricing > 0
                    ? (actualTotalPriceCents / quantityForPricing).round()
                    : 0;
              }(),
              // A manual total override becomes the line's new price anchor.
              originalUnitPrice: () {
                final quantityForPricing = item.isWeighted
                    ? (item.weightQuantity > 0 ? item.weightQuantity : 1.0)
                    : item.quantity.toDouble();
                return quantityForPricing > 0
                    ? (actualTotalPriceCents / quantityForPricing).round()
                    : 0;
              }(),
              originalStockUnitsPerUnit: item.stockUnitsPerUnit,
            )
          else
            item,
      ],
    );
  }

  Future<void> updateLinePricing(
    String id,
    PurchaseLinePricingResult pricing, {
    required bool isWeighted,
  }) {
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.id == id)
            _applyLinePricing(item, pricing, isWeighted: isWeighted)
          else
            item,
      ],
    );
  }

  /// A unit switch converts from the line's stored anchor. The editor's
  /// numbers are only trusted when the user really typed a different price
  /// or total.
  CartItem _applyLinePricing(
    CartItem item,
    PurchaseLinePricingResult pricing, {
    required bool isWeighted,
  }) {
    final factor =
        pricing.stockUnitsPerUnit.isFinite && pricing.stockUnitsPerUnit > 0
        ? pricing.stockUnitsPerUnit
        : 1.0;
    final quantity = pricing.quantity.toDouble();

    // Unit price implied by the existing anchor, in the newly selected unit.
    final impliedUnitPrice =
        item.anchorUnitPriceCents * factor / item.anchorStockUnitsPerUnit;

    final grossFromAnchor = (impliedUnitPrice * quantity).round();
    final discountFromAnchor = PurchaseLinePricing.discountAmountCents(
      grossTotalCents: grossFromAnchor,
      discountType: pricing.discountType,
      discountValue: pricing.discountValue,
    );
    final totalFromAnchor = grossFromAnchor - discountFromAnchor;

    // More than 1 cent off means the user typed their own price or total.
    final manual =
        (pricing.unitPriceCents - impliedUnitPrice).abs() > 1 ||
        (pricing.finalTotalCents - totalFromAnchor).abs() > 1;

    if (manual) {
      // The typed value becomes the new anchor, as a matched pair.
      return item.copyWith(
        quantity: isWeighted ? item.quantity : pricing.quantity.toInt(),
        weightQuantity: isWeighted ? pricing.quantity : item.weightQuantity,
        unit: pricing.unitName,
        stockUnitsPerUnit: factor,
        unitPrice: pricing.unitPriceCents,
        grossTotalCents: pricing.grossTotalCents,
        discountType: pricing.discountType,
        discountValue: pricing.discountValue,
        discountAmountCents: pricing.discountAmountCents,
        totalPriceCents: pricing.finalTotalCents,
        originalUnitPrice: pricing.unitPriceCents,
        originalStockUnitsPerUnit: factor,
      );
    }

    // Plain unit switch or quantity change: keep the anchor pair untouched.
    return item.copyWith(
      quantity: isWeighted ? item.quantity : pricing.quantity.toInt(),
      weightQuantity: isWeighted ? pricing.quantity : item.weightQuantity,
      unit: pricing.unitName,
      stockUnitsPerUnit: factor,
      unitPrice: impliedUnitPrice.round(),
      grossTotalCents: grossFromAnchor,
      discountType: pricing.discountType,
      discountValue: pricing.discountValue,
      discountAmountCents: discountFromAnchor,
      totalPriceCents: totalFromAnchor,
      // Set explicitly. Otherwise the fallbacks would re-anchor to the new unit.
      originalUnitPrice: item.anchorUnitPriceCents,
      originalStockUnitsPerUnit: item.anchorStockUnitsPerUnit,
    );
  }

  Future<void> updatePricesForSupply(String supplyId, int unitPriceCents) {
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.supplyId == supplyId && item.totalPriceCents == 0)
            item.copyWith(
              unitPrice: unitPriceCents,
              totalPriceCents: item.quantity * unitPriceCents,
            )
          else
            item,
      ],
    );
  }

  Future<void> applyPurchaseEntry({
    required String supplyId,
    required int priceCents,
    required String name,
    String? brand,
    String? unit,
    double? unitQuantity,
    double? stockUnitsPerUnit,
    int? previousPriceCents,
    double? previousUnitsPerPurchase,
    bool? isSoldByWeight,
  }) {
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.supplyId == supplyId)
            () {
              final lineQuantity = item.isWeighted
                  ? item.weightQuantity
                  : item.quantity.toDouble();
              final oldPurchaseFactor =
                  previousUnitsPerPurchase != null &&
                      previousUnitsPerPurchase > 0
                  ? previousUnitsPerPurchase
                  : 1.0;
              final newPurchaseFactor = unitQuantity != null && unitQuantity > 0
                  ? unitQuantity
                  : oldPurchaseFactor;
              final oldCatalogUnitPrice = previousPriceCents == null
                  ? null
                  : PurchaseLinePricing.convertPriceCents(
                      priceCents: previousPriceCents,
                      fromStockUnitsPerUnit: oldPurchaseFactor,
                      toStockUnitsPerUnit: item.stockUnitsPerUnit,
                    );
              final followsCatalogPrice =
                  oldCatalogUnitPrice != null &&
                  item.unitPrice == oldCatalogUnitPrice &&
                  (item.grossTotalCents ==
                          (oldCatalogUnitPrice * lineQuantity).round() ||
                      (item.grossTotalCents == 0 &&
                          item.discountAmountCents == 0 &&
                          item.lineTotal ==
                              (oldCatalogUnitPrice * lineQuantity).round()));
              final nextUnitPrice = followsCatalogPrice
                  ? PurchaseLinePricing.convertPriceCents(
                      priceCents: priceCents,
                      fromStockUnitsPerUnit: newPurchaseFactor,
                      toStockUnitsPerUnit: item.stockUnitsPerUnit,
                    )
                  : item.unitPrice;
              final nextGrossTotal = followsCatalogPrice
                  ? (nextUnitPrice * lineQuantity).round()
                  : item.grossTotalCents;
              final nextDiscount = followsCatalogPrice
                  ? PurchaseLinePricing.discountAmountCents(
                      grossTotalCents: nextGrossTotal,
                      discountType: item.discountType,
                      discountValue: item.discountValue,
                    )
                  : item.discountAmountCents;
              return CartItem(
                id: item.id,
                supplyId: item.supplyId,
                name: name,
                brand: brand,
                unitQuantity: item.unitQuantity ?? unitQuantity,
                unit:
                    item.unit ??
                    ((unit != null && unit.trim().isNotEmpty)
                        ? unit.trim()
                        : null),
                stockUnitsPerUnit: item.unit != null
                    ? item.stockUnitsPerUnit
                    : (stockUnitsPerUnit ?? item.stockUnitsPerUnit),
                unitPrice: nextUnitPrice,
                quantity: item.quantity,
                totalPriceCents: followsCatalogPrice
                    ? nextGrossTotal - nextDiscount
                    : item.totalPriceCents,
                grossTotalCents: followsCatalogPrice
                    ? nextGrossTotal
                    : item.grossTotalCents,
                discountType: item.discountType,
                discountValue: item.discountValue,
                discountAmountCents: nextDiscount,
                checked: item.checked,
                isWeighted: isSoldByWeight ?? item.isWeighted,
                weightQuantity: item.weightQuantity,
                // Lines that follow the catalog price re-anchor to the new
                // catalog price; manually priced lines keep their anchor.
                originalUnitPrice: followsCatalogPrice
                    ? priceCents
                    : item.originalUnitPrice,
                originalStockUnitsPerUnit: followsCatalogPrice
                    ? newPurchaseFactor
                    : item.originalStockUnitsPerUnit,
              );
            }()
          else
            item,
      ],
      system: true,
    );
  }

  Future<void> syncPricesFromSupplies(List<Supply> supplies) {
    final byId = {for (final supply in supplies) supply.id: supply};
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.supplyId != null && byId.containsKey(item.supplyId))
            () {
              final supply = byId[item.supplyId]!;
              return item.copyWith(name: supply.name, brand: supply.brand);
            }()
          else
            item,
      ],
      system: true,
    );
  }

  Future<void> updateName(String id, String name) {
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.id == id) item.copyWith(name: name) else item,
      ],
    );
  }

  Future<void> toggleChecked(String id) {
    return _mutate(
      (current) => [
        for (final item in current)
          if (item.id == id) item.copyWith(checked: !item.checked) else item,
      ],
    );
  }

  Future<void> removeItem(String id) {
    return _mutate(
      (current) => current.where((item) => item.id != id).toList(),
    );
  }

  Future<void> clear() {
    return _mutate((_) => []);
  }

  void clearAfterCheckout() => state = [];

  int get total {
    return state.fold<int>(0, (sum, item) => sum + item.lineTotal);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  return CartNotifier(
    PurchaseDraftCartService(db),
    businessId,
    requireCartAccess: () => ref
        .read(authorizationServiceProvider)
        .require(_kCartPermission, businessId: businessId),
  );
});

final cartReadyProvider = FutureProvider<void>((ref) {
  return ref.watch(cartProvider.notifier).load();
});

// Live catalog metadata used by the cart search and item tiles.
// The tile uses a direct Supply -> categoryId -> Categories lookup so the
// displayed category always comes from the relationship actually stored on
// the supply record.
class CartSupplyMetadata {
  final Supply supply;
  final String? categoryName;

  const CartSupplyMetadata({required this.supply, required this.categoryName});
}

final cartSupplyProvider = FutureProvider.family<CartSupplyMetadata?, String>((
  ref,
  supplyId,
) async {
  ref.watch(ledgerVersionProvider);

  final db = ref.watch(databaseProvider);

  final supply = await (db.select(
    db.supplies,
  )..where((row) => row.id.equals(supplyId))).getSingleOrNull();

  if (supply == null) {
    return null;
  }

  String? categoryName;
  final categoryId = supply.categoryId?.trim();

  if (categoryId != null && categoryId.isNotEmpty) {
    final category =
        await (db.select(db.productCategories)..where(
              (row) =>
                  row.id.equals(categoryId) &
                  row.businessId.equals(supply.businessId),
            ))
            .getSingleOrNull();

    final name = category?.name.trim();
    if (name != null && name.isNotEmpty) {
      categoryName = name;
    }
  }

  return CartSupplyMetadata(supply: supply, categoryName: categoryName);
});

// ============================================================================
// PRICE TREND
// ============================================================================

enum _Trend { up, down, same, none }

_Trend _trendFor(List<SupplyPriceHistoryData> history) {
  if (history.length < 2) {
    return _Trend.none;
  }

  final latest = history[0].price;
  final previous = history[1].price;

  if (latest > previous) return _Trend.up;
  if (latest < previous) return _Trend.down;

  return _Trend.same;
}

// ============================================================================
// MAIN PAGE
// ============================================================================

class SuppliesPriceListPage extends ConsumerStatefulWidget {
  const SuppliesPriceListPage({super.key});

  @override
  ConsumerState<SuppliesPriceListPage> createState() =>
      _SuppliesPriceListPageState();
}

class _SuppliesPriceListPageState extends ConsumerState<SuppliesPriceListPage> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  bool _filtersExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Supply> _filterSupplies(List<Supply> supplies) {
    final filter = ref.watch(supplyCatalogFilterProvider);
    final query = _query.trim().toLowerCase();
    final categoryNames =
        ref.watch(supplyCategoryNamesProvider).asData?.value ??
        const <String, String>{};
    final textMatches = supplies
        .where(
          (supply) =>
              supplyMatchesSearch(supply, query, categoryNames: categoryNames),
        )
        .toList();

    // 2. then apply stock/unit/store/sort filters on top
    final filtered = applySupplyFilters(textMatches, filter);

    // 3. Low-stock backfill.
    // applySupplyFilters may only look at minimumStock. Users configure
    // "Low-stock alert" via lowStockThreshold. Any item that is low by
    // either field must still show when the active filter is the
    // low-stock chip. Detect that chip via the filter's string form /
    // common properties, then rebuild the list with our predicate.
    if (!_filterRequestsLowStock(filter)) {
      return filtered;
    }

    return textMatches.where(_isSupplyLowStock).toList();
  }

  bool _filterRequestsLowStock(Object filter) {
    final asText = filter.toString().toLowerCase();
    if (asText.contains('lowstock') ||
        asText.contains('low_stock') ||
        asText.contains('low stock')) {
      return true;
    }

    try {
      final dynamic f = filter;
      final candidates = <Object?>[];
      try {
        candidates.add(f.stockStatus);
      } catch (_) {}
      try {
        candidates.add(f.stockFilter);
      } catch (_) {}
      try {
        candidates.add(f.stockLevel);
      } catch (_) {}
      try {
        candidates.add(f.inventoryStatus);
      } catch (_) {}
      try {
        candidates.add(f.status);
      } catch (_) {}
      try {
        final statuses = f.stockStatuses;
        if (statuses is Iterable) {
          candidates.addAll(List<Object?>.from(statuses));
        }
      } catch (_) {}
      try {
        final statuses = f.selectedStockStatuses;
        if (statuses is Iterable) {
          candidates.addAll(List<Object?>.from(statuses));
        }
      } catch (_) {}

      for (final value in candidates) {
        if (value == null) continue;
        final label = value.toString().toLowerCase();
        if (label.contains('low')) return true;
      }
    } catch (_) {}

    return false;
  }

  Future<void> _refresh() async {
    ref.invalidate(suppliesProvider);

    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _openAddSupplySheet() {
    if (!_allowed(context, ref, BosPermission.inventoryCreate)) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupplyForm(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!ref.watch(canProvider(BosPermission.inventoryView))) {
      return const _NoAccessView(
        title: 'Inventory is restricted',
        message: 'Your role can\'t view inventory. Ask the owner for access.',
      );
    }

    final cartRestore = ref.watch(cartReadyProvider);
    if (cartRestore.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Restoring purchase...'),
            ],
          ),
        ),
      );
    }
    if (cartRestore.hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not restore the saved purchase.'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(cartReadyProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final suppliesAsync = ref.watch(suppliesProvider);
    final cart = ref.watch(cartProvider);

    // Sync cart prices whenever the catalog changes, even if CartPage
    // is not currently on screen.
    ref.listen<AsyncValue<List<Supply>>>(suppliesProvider, (previous, next) {
      final supplies = next.asData?.value;
      if (supplies == null) return;
      ref
          .read(cartProvider.notifier)
          .syncPricesFromSupplies(supplies)
          .catchError((Object _) {});
    });

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Supplies',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Prices & suppliers',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          PermissionGate(
            permission: BosPermission.purchasingView,
            child: IconButton(
              tooltip: 'Purchase history',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PurchaseHistoryPage(),
                  ),
                );
              },
              icon: const Icon(Icons.history_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Stock adjustments',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AllStockAdjustmentsPage(),
                ),
              );
            },
            icon: const Icon(Icons.remove_shopping_cart_outlined),
          ),
          PermissionGate(
            permission: _kCartPermission,
            child: _CartHeaderButton(
              itemCount: cart.length,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartPage()),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: suppliesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorState(
          message: 'Unable to load supplies.',
          onRetry: () => ref.invalidate(suppliesProvider),
        ),
        data: (supplies) {
          final filteredSupplies = _filterSupplies(supplies);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (supplies.isEmpty)
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.62,
                          child: _EmptyState(onAdd: _openAddSupplySheet),
                        )
                      else ...[
                        _SupplyOverviewCard(
                          totalSupplies: supplies.length,
                          visibleSupplies: filteredSupplies.length,
                          cartCount: cart.length,
                          totalStockWorthCents: supplies
                              .fold<double>(
                                0,
                                (sum, s) =>
                                    sum + (s.currentStock * s.costPerBaseUnit),
                              )
                              .round(),
                        ),
                        const SizedBox(height: 16),
                        _SearchField(
                          controller: _searchController,
                          hintText:
                              'Search name, price, category, brand, barcode, or store',
                          onChanged: (value) {
                            setState(() {
                              _query = value;
                            });
                          },
                          onClear: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // ── Filters: hidden by default behind a dropdown
                        // toggle bar; tap to reveal stock/category/store/sort.
                        _FiltersToggleBar(
                          expanded: _filtersExpanded,
                          hasActiveFilters: ref
                              .watch(supplyCatalogFilterProvider)
                              .hasActiveFilters,
                          onTap: () => setState(
                            () => _filtersExpanded = !_filtersExpanded,
                          ),
                        ),
                        if (_filtersExpanded) ...[
                          const SizedBox(height: 10),
                          SupplyFilterBar(allSupplies: supplies),
                        ],

                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                _query.trim().isEmpty &&
                                        !ref
                                            .watch(supplyCatalogFilterProvider)
                                            .hasActiveFilters
                                    ? 'Price catalog'
                                    : 'Filtered results',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${filteredSupplies.length}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (filteredSupplies.isEmpty)
                          _NoSearchResults(
                            query: _query,
                            onClear: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                              });
                            },
                          )
                        else
                          ...filteredSupplies.map(
                            (supply) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SupplyCard(supply: supply),
                            ),
                          ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: PermissionGate(
        permission: BosPermission.inventoryCreate,
        child: FloatingActionButton(
          onPressed: _openAddSupplySheet,
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }
}

// ============================================================================
// PURCHASE HISTORY
// ============================================================================

class PurchaseHistoryPage extends ConsumerStatefulWidget {
  const PurchaseHistoryPage({super.key});

  @override
  ConsumerState<PurchaseHistoryPage> createState() =>
      _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends ConsumerState<PurchaseHistoryPage> {
  final _searchController = TextEditingController();
  String _query = '';
  DateTime? _selectedDate;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  List<PurchaseHistoryCheckout> _filter(List<PurchaseHistoryCheckout> records) {
    final query = _query.trim().toLowerCase();
    return records.where((record) {
      final date = record.cart.cartDate;
      final matchesDate =
          _selectedDate == null ||
          (date.year == _selectedDate!.year &&
              date.month == _selectedDate!.month &&
              date.day == _selectedDate!.day);
      if (!matchesDate) return false;

      if (query.isEmpty) return true;

      final searchable = [
        for (final item in record.items) ...[
          item.itemName,
          item.brand ?? '',
          item.unit ?? '',
          '${item.unitQuantity ?? ''}',
        ],
        record.cart.storeName ?? '',
        record.cart.storeAddress ?? '',
        _formatDate(record.cart.cartDate),
        DateFormat('h:mm a').format(record.cart.createdAt),
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
 
    if (!ref.watch(canProvider(BosPermission.purchasingView))) {
      return const _NoAccessView(
        title: 'Purchases are restricted',
        message: 'Your role can\'t view purchase history.',
      );
    }
 
    final historyAsync = ref.watch(purchaseHistoryProvider);
 
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 4,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Purchase history',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
            Text(
              'Receipts from every checkout',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorState(
          message: 'Unable to load purchase history.',
          onRetry: () => ref.invalidate(purchaseHistoryProvider),
        ),
        data: (records) {
          final filtered = _filter(records);
          final groups = _groupPurchasesByDay(filtered);
          final isFiltered = _query.trim().isNotEmpty || _selectedDate != null;
 
          void clearFilters() {
            _searchController.clear();
            setState(() {
              _query = '';
              _selectedDate = null;
            });
          }
 
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _PurchaseSummaryHero(
                all: records,
                visible: filtered,
                isFiltered: isFiltered,
              ),
              const SizedBox(height: 16),
              _SearchField(
                controller: _searchController,
                hintText: 'Search store, item, brand or date',
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  InputChip(
                    avatar: Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: _selectedDate == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSecondaryContainer,
                    ),
                    label: Text(
                      _selectedDate == null
                          ? 'Any date'
                          : _formatDate(_selectedDate!),
                    ),
                    selected: _selectedDate != null,
                    showCheckmark: false,
                    onPressed: _pickDate,
                    onDeleted: _selectedDate == null
                        ? null
                        : () => setState(() => _selectedDate = null),
                    deleteButtonTooltipMessage: 'Clear date filter',
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} of ${records.length} receipt'
                    '${records.length == 1 ? '' : 's'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (filtered.isEmpty)
                _PurchaseEmptyState(
                  hasRecords: records.isNotEmpty,
                  onClear: clearFilters,
                )
              else
                for (final group in groups) ...[
                  _DayHeader(day: group.key, receipts: group.value),
                  for (final record in group.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PurchaseHistoryCard(
                        checkout: record,
                        onDelete: () => _deleteCheckout(record),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteCheckout(PurchaseHistoryCheckout checkout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete checkout?'),
        content: const Text(
          'This will delete the checkout, reverse its stock additions, '
          'and remove its linked expense and ledger entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete checkout'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      if (confirmed != true || !mounted) return;
      // NEW: permission gate
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.financeVoid, businessId: kCurrentBusinessId);

      final db = ref.read(databaseProvider);
      final cart = checkout.cart;
      final cartBranch =
          cart.branchId ?? AppDatabase.mainBranchId(cart.businessId);
      if (cartBranch != ref.read(selectedBranchIdProvider)) {
        throw StateError(
          'This purchase belongs to another branch. Switch to that branch to delete it.',
        );
      }
      final expenseId = cart.expenseId;
      final ledgerNotifier = ref.read(ledgerVersionProvider.notifier);
      debugPrint('[delete-checkout] cart=${cart.id} expense=$expenseId');
      final audit = ref.read(auditLogServiceProvider);
      final reversals = <String>[];

      await db.transaction(() async {
        // ------------------------------------------------------------
        // 1. Reverse every linked supply purchase.
        // ------------------------------------------------------------
        for (final cartItem in checkout.items) {
          final supplyId = cartItem.supplyId;

          if (supplyId == null) {
            continue;
          }

          final supply = await (db.select(
            db.supplies,
          )..where((s) => s.id.equals(supplyId))).getSingleOrNull();

          if (supply == null) {
            continue;
          }

          final purchasedQuantity = cartItem.isWeighted
              ? (cartItem.weightQuantity ?? 0)
              : cartItem.quantity.toDouble();

          final unitsPerLine = cartItem.stockUnitsPerUnit > 0
              ? cartItem.stockUnitsPerUnit
              : 1.0;
          final purchasedStock = purchasedQuantity * unitsPerLine;

          // THE FIX: find the price-history entry created for this EXACT cart
          // item first, by id — this can never collide with another purchase
          // of the same supply at the same price/quantity/date. Only fall back
          // to the old value-based match for rows created before this link
          // existed (shoppingCartItemId is null on those).
          final matchingHistory =
              await (db.select(db.supplyPriceHistory)..where(
                    (history) => history.shoppingCartItemId.equals(cartItem.id),
                  ))
                  .getSingleOrNull() ??
              await (db.select(db.supplyPriceHistory)
                    ..where(
                      (history) =>
                          history.supplyId.equals(supplyId) &
                          history.shoppingCartItemId.isNull() &
                          history.price.equals(cartItem.unitPrice) &
                          history.purchaseQuantity.equals(purchasedQuantity) &
                          history.recordedDate.equals(cart.cartDate),
                    )
                    ..orderBy([
                      (history) => OrderingTerm(
                        expression: history.createdAt,
                        mode: OrderingMode.desc,
                      ),
                    ])
                    ..limit(1))
                  .getSingleOrNull();

          if (matchingHistory != null) {
            await (db.delete(
              db.supplyPriceHistory,
            )..where((h) => h.id.equals(matchingHistory.id))).go();
          }

          // Same fix for the matching inventory 'restock' movement: prefer the
          // exact cart-item link, fall back to value-matching only for rows
          // created before the link existed.
          final deletedByLink =
              await (db.delete(db.inventoryMovements)..where(
                    (movement) =>
                        movement.supplyId.equals(supplyId) &
                        movement.movementType.equals('restock') &
                        movement.shoppingCartItemId.equals(cartItem.id),
                  ))
                  .go();

          if (deletedByLink == 0) {
            await (db.delete(db.inventoryMovements)..where(
                  (movement) =>
                      movement.supplyId.equals(supplyId) &
                      movement.movementType.equals('restock') &
                      movement.shoppingCartItemId.isNull() &
                      movement.quantity.equals(purchasedStock) &
                      movement.movementDate.equals(cart.cartDate),
                ))
                .go();
          }

          // Recalculate the weighted average cost from the remaining history.
          final remainingHistory = await (db.select(
            db.supplyPriceHistory,
          )..where((h) => h.supplyId.equals(supplyId))).get();

          double newCostPerBaseUnit = 0;

          if (remainingHistory.isNotEmpty) {
            double totalCost = 0;
            double totalBaseUnits = 0;

            for (final history in remainingHistory) {
              final units = history.unitsPerPurchaseAtTime > 0
                  ? history.unitsPerPurchaseAtTime
                  : 1.0;

              final quantity = history.purchaseQuantity > 0
                  ? history.purchaseQuantity
                  : 1.0;

              final baseUnits = quantity * units;

              totalCost += history.price * quantity;
              totalBaseUnits += baseUnits;
            }

            if (totalBaseUnits > 0) {
              newCostPerBaseUnit = totalCost / totalBaseUnits;
            }
          }

          await (db.update(
            db.supplies,
          )..where((s) => s.id.equals(supplyId))).write(
            SuppliesCompanion(
              costPerBaseUnit: Value(newCostPerBaseUnit),
              updatedAt: Value(DateTime.now()),
            ),
          );

          reversals.add(
            '${cartItem.itemName}: -${_qty(purchasedStock)} ${supply.stockUnit}',
          );
        }
        await StockService.recompute(
          db,
          businessId: cart.businessId,
          branchId: cart.branchId ?? AppDatabase.mainBranchId(cart.businessId),
        );
        // ------------------------------------------------------------
        // 2. Remove the linked expense and journal entry safely.
        // ------------------------------------------------------------
        // ------------------------------------------------------------
        // 2. Remove the linked expense and every journal posting for it.
        // ------------------------------------------------------------
        if (expenseId != null) {
          final expense = await (db.select(
            db.expenses,
          )..where((e) => e.id.equals(expenseId))).getSingleOrNull();

          // Find the posting by the expense's link AND by source, so the
          // deduction is reversed even if the link column is missing.
          final journalIds = <String>{};
          final linkedId = expense?.journalEntryId;
          if (linkedId != null) journalIds.add(linkedId);

          final bySource =
              await (db.select(db.journalEntries)..where(
                    (j) =>
                        j.sourceType.equals('expense') &
                        j.sourceId.equals(expenseId),
                  ))
                  .get();
          journalIds.addAll(bySource.map((j) => j.id));

          // Detach the cart from the expense first.
          await (db.update(db.shoppingCarts)
                ..where((c) => c.expenseId.equals(expenseId)))
              .write(const ShoppingCartsCompanion(expenseId: Value(null)));

          if (expense != null) {
            await (db.update(db.expenses)..where((e) => e.id.equals(expenseId)))
                .write(const ExpensesCompanion(journalEntryId: Value(null)));
            await (db.delete(
              db.expenses,
            )..where((e) => e.id.equals(expenseId))).go();
          }

          if (journalIds.isNotEmpty) {
            // Lines first, while the journal entry still exists. The sync
            // triggers need the parent row to work out the business id.
            await (db.delete(
              db.ledgerLines,
            )..where((l) => l.journalEntryId.isIn(journalIds))).go();
            await (db.delete(
              db.journalEntries,
            )..where((j) => j.id.isIn(journalIds))).go();
          }
        }

        // shoppingCartItems.cartId has ON DELETE CASCADE.
        await (db.delete(
          db.shoppingCarts,
        )..where((c) => c.id.equals(cart.id))).go();

        final shortId = cart.id.substring(0, 8).toUpperCase();
        await audit.record(
          AuditEvent(
            businessId: cart.businessId,
            module: AuditModule.inventory,
            actionType: AuditActionType.delete,
            action: 'inventory.purchase_deleted',
            entityType: 'shopping_carts',
            entityId: cart.id,
            entityLabel:
                'Checkout $shortId'
                '${(cart.storeName ?? '').trim().isEmpty ? '' : ' · ${cart.storeName!.trim()}'}',
            before: {
              'total': cart.totalAmount,
              'date': cart.cartDate,
              'store': cart.storeName,
              'expenseId': expenseId,
            },
            details: {
              'items': [
                for (final i in checkout.items)
                  '${i.isWeighted ? _qty(i.weightQuantity ?? 0) : i.quantity} '
                      '${i.unit ?? ''} ${i.itemName} — ${_peso(i.lineTotal)}',
              ],
              'stockReversals': reversals,
            },
          ),
        );
      });

      // Refresh the dashboard and ledger even if this page was closed meanwhile.
      ledgerNotifier.state++;

      if (!mounted) return;
      if (expenseId != null) {
        final remaining = await db
            .customSelect(
              "SELECT (SELECT COUNT(*) FROM journal_entries WHERE source_type = 'expense' AND source_id = ?) AS je, "
              '(SELECT COUNT(*) FROM expenses WHERE id = ?) AS ex',
              variables: [
                Variable.withString(expenseId),
                Variable.withString(expenseId),
              ],
            )
            .getSingle();
        debugPrint(
          '[delete-checkout] after: journals=${remaining.read<int>('je')} '
          'expenses=${remaining.read<int>('ex')}',
        );
      }

      ref.invalidate(purchaseHistoryProvider);
      ref.invalidate(suppliesProvider);
      ref.invalidate(purchasePaymentDetailsProvider(expenseId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Checkout deleted and stock restored.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to delete checkout: $error'),
        ),
      );
    }
  }
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
 
String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(d.year == now.year ? 'EEEE, MMM d' : 'MMM d, yyyy').format(d);
}
 
List<MapEntry<DateTime, List<PurchaseHistoryCheckout>>> _groupPurchasesByDay(
  List<PurchaseHistoryCheckout> records,
) {
  final map = <DateTime, List<PurchaseHistoryCheckout>>{};
  for (final r in records) {
    final d = r.cart.cartDate;
    final key = DateTime(d.year, d.month, d.day);
    (map[key] ??= []).add(r);
  }
  return map.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
}
 
String _storeLabelFor(ShoppingCart cart) {
  final name = cart.storeName?.trim();
  return (name != null && name.isNotEmpty) ? name : 'Store not specified';
}
 
// ----------------------------------------------------------------------------
// Summary hero: the one expressive element on the list screen.
// ----------------------------------------------------------------------------
 
class _PurchaseSummaryHero extends StatelessWidget {
  final List<PurchaseHistoryCheckout> all;
  final List<PurchaseHistoryCheckout> visible;
  final bool isFiltered;
 
  const _PurchaseSummaryHero({
    required this.all,
    required this.visible,
    required this.isFiltered,
  });
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onTop = scheme.onPrimary;
 
    final total = visible.fold<int>(0, (s, r) => s + r.cart.totalAmount);
    final items = visible.fold<int>(0, (s, r) => s + r.items.length);
    final average = visible.isEmpty ? 0 : (total / visible.length).round();
 
    // Spend per day for the last 7 days (always from ALL receipts, so the
    // chart stays a stable overview while the user filters the list).
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final dayTotals = List<int>.filled(7, 0);
    for (final r in all) {
      final d = r.cart.cartDate;
      final day = DateTime.utc(d.year, d.month, d.day);
      final index = 6 - today.difference(day).inDays;
      if (index >= 0 && index < 7) dayTotals[index] += r.cart.totalAmount;
    }
    final maxDay = dayTotals.reduce((a, b) => a > b ? a : b);
 
    // Cap the system font scale inside the hero so large accessibility
    // sizes can't push the fixed-height chart past its box.
    final mq = MediaQuery.of(context);
    final scaler = mq.textScaler.clamp(maxScaleFactor: 1.25);
 
    return MediaQuery(
      data: mq.copyWith(textScaler: scaler),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final compact = width < 340;
          final padding = compact ? 14.0 : 20.0;
          final chartHeight = compact ? 56.0 : 68.0;
 
          return Container(
            padding: EdgeInsets.fromLTRB(padding, padding, padding, padding - 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 22 : 28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  Color.alphaBlend(
                    scheme.tertiary.withValues(alpha: 0.55),
                    scheme.primary,
                  ),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.26),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isFiltered ? 'Spent in this view' : 'Total spent on supplies',
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onTop.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _peso(total),
                    maxLines: 1,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: compact ? 30 : null,
                      color: onTop,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 12 : 16),
                Row(
                  children: [
                    _HeroStat(label: 'Receipts', value: '${visible.length}'),
                    _HeroStat(label: 'Items bought', value: '$items'),
                    _HeroStat(label: 'Avg. receipt', value: _peso(average)),
                  ],
                ),
                if (maxDay > 0) ...[
                  SizedBox(height: compact ? 12 : 16),
                  Container(height: 1, color: onTop.withValues(alpha: 0.18)),
                  const SizedBox(height: 12),
                  Text(
                    'Last 7 days',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: onTop.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: chartHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: _DayBar(
                              fraction: dayTotals[i] / maxDay,
                              hasSpend: dayTotals[i] > 0,
                              isToday: i == 6,
                              label: DateFormat('E').format(
                                today.subtract(Duration(days: 6 - i)),
                              )[0],
                              color: onTop,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
 
class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
 
  const _HeroStat({required this.label, required this.value});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTop = theme.colorScheme.onPrimary;
 
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                color: onTop,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: onTop.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
 
class _DayBar extends StatelessWidget {
  final double fraction;
  final bool hasSpend;
  final bool isToday;
  final String label;
  final Color color;
 
  const _DayBar({
    required this.fraction,
    required this.hasSpend,
    required this.isToday,
    required this.label,
    required this.color,
  });
 
  @override
  Widget build(BuildContext context) {
    const labelHeight = 16.0;
    const gap = 4.0;
 
    return LayoutBuilder(
      builder: (context, constraints) {
        // The bar can only use what is left after the label, so the column
        // can never overflow whatever height or font scale it is given.
        final maxBar = (constraints.maxHeight - labelHeight - gap).clamp(
          4.0,
          double.infinity,
        );
        final barHeight = hasSpend ? (4 + (maxBar - 4) * fraction) : 4.0;
 
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              width: (constraints.maxWidth * 0.55).clamp(8.0, 22.0),
              height: barHeight,
              decoration: BoxDecoration(
                color: color.withValues(
                  alpha: isToday ? 1 : (hasSpend ? 0.55 : 0.2),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: gap),
            SizedBox(
              height: labelHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: color.withValues(alpha: isToday ? 1 : 0.7),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
 
// ----------------------------------------------------------------------------
// Day header + empty state
// ----------------------------------------------------------------------------
 
class _DayHeader extends StatelessWidget {
  final DateTime day;
  final List<PurchaseHistoryCheckout> receipts;
 
  const _DayHeader({required this.day, required this.receipts});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = receipts.fold<int>(0, (s, r) => s + r.cart.totalAmount);
 
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayLabel(day),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            _peso(total),
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
 
class _PurchaseEmptyState extends StatelessWidget {
  final bool hasRecords;
  final VoidCallback onClear;
 
  const _PurchaseEmptyState({required this.hasRecords, required this.onClear});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
 
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasRecords
                  ? Icons.search_off_rounded
                  : Icons.receipt_long_outlined,
              size: 32,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasRecords ? 'No receipts match' : 'No purchases yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasRecords
                ? 'Try a different search or clear the date filter.'
                : 'Receipts show up here after you check out a cart.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (hasRecords) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onClear,
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }
}
 
// ----------------------------------------------------------------------------
// Receipt card (list item)
// ----------------------------------------------------------------------------
 
class _PurchaseHistoryCard extends ConsumerWidget {
  final PurchaseHistoryCheckout checkout;
  final VoidCallback onDelete;
 
  const _PurchaseHistoryCard({required this.checkout, required this.onDelete});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cart = checkout.cart;
    final items = checkout.items;
    final paymentAsync = ref.watch(
      purchasePaymentDetailsProvider(cart.expenseId),
    );
    final canDelete = ref.watch(canProvider(BosPermission.financeVoid));
 
    final time = DateFormat('h:mm a').format(cart.createdAt);
    final shown = items.take(3).toList();
    final extra = items.length - shown.length;
 
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PurchaseCheckoutDetailPage(checkout: checkout),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StoreAvatar(name: cart.storeName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _storeLabelFor(cart),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$time · ${items.length} item'
                          '${items.length == 1 ? '' : 's'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: EdgeInsets.only(right: canDelete ? 0 : 8, top: 2),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.34,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _peso(cart.totalAmount),
                          maxLines: 1,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canDelete)
                    SizedBox(
                      width: 36,
                      height: 28,
                      child: PopupMenuButton<String>(
                        tooltip: 'Checkout actions',
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        onSelected: (value) {
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 10),
                                const Text('Delete checkout'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in shown)
                      _MiniPill(
                        text: item.itemName.trim().isEmpty
                            ? 'Item'
                            : item.itemName.trim(),
                      ),
                    if (extra > 0) _MiniPill(text: '+$extra more', muted: true),
                  ],
                ),
              ),
              paymentAsync.maybeWhen(
                data: (payments) => payments.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10, right: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                payments.length == 1
                                    ? 'Paid with ${payments.first.account.name}'
                                    : 'Split: ${payments.map((p) => p.account.name).join(' + ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
 
/// Tonal rounded-square avatar. The tint is picked from the store name so
/// the same store always looks the same.
class _StoreAvatar extends StatelessWidget {
  final String? name;
  final double size;
 
  const _StoreAvatar({required this.name, this.size = 46});
 
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = (name ?? '').trim();
    final palettes = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    final (bg, fg) = trimmed.isEmpty
        ? (scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : palettes[trimmed.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b) %
              palettes.length];
 
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: trimmed.isEmpty
          ? Icon(Icons.storefront_outlined, color: fg, size: size * 0.5)
          : Text(
              trimmed[0].toUpperCase(),
              style: TextStyle(
                color: fg,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
 
class _MiniPill extends StatelessWidget {
  final String text;
  final bool muted;
 
  const _MiniPill({required this.text, this.muted = false});
 
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
 
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: muted
            ? Colors.transparent
            : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: muted
            ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7))
            : null,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
 
// ----------------------------------------------------------------------------
// Receipt detail page: a paper receipt with a torn bottom edge.
// ----------------------------------------------------------------------------
 
class PurchaseCheckoutDetailPage extends ConsumerWidget {
  final PurchaseHistoryCheckout checkout;
 
  const PurchaseCheckoutDetailPage({super.key, required this.checkout});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cart = checkout.cart;
    final paymentAsync = ref.watch(
      purchasePaymentDetailsProvider(cart.expenseId),
    );
 
    final storeAddress = cart.storeAddress?.trim();
    final itemCount = checkout.items.length;
    final saved = checkout.items.fold<int>(
      0,
      (s, i) => s + (i.discountAmount > 0 ? i.discountAmount : 0),
    );
 
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Receipt',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          ClipPath(
            clipper: const _ReceiptEdgeClipper(),
            child: Container(
              color: scheme.surface,
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 360 ? 16 : 22,
                26,
                MediaQuery.sizeOf(context).width < 360 ? 16 : 22,
                34,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Store + total ───────────────────────────────────
                  Center(child: _StoreAvatar(name: cart.storeName, size: 56)),
                  const SizedBox(height: 12),
                  Text(
                    _storeLabelFor(cart),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (storeAddress != null && storeAddress.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      storeAddress,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _peso(cart.totalAmount),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$itemCount item${itemCount == 1 ? '' : 's'} purchased',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (saved > 0) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'You saved ${_peso(saved)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
 
                  const SizedBox(height: 22),
                  _DashedLine(color: scheme.outlineVariant),
                  const SizedBox(height: 16),
 
                  // ── When ────────────────────────────────────────────
                  _ReceiptInfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: _formatDate(cart.cartDate),
                  ),
                  const SizedBox(height: 10),
                  _ReceiptInfoRow(
                    icon: Icons.schedule_outlined,
                    label: 'Time',
                    value: DateFormat('h:mm a').format(cart.createdAt),
                  ),
                  const SizedBox(height: 10),
                  _ReceiptInfoRow(
                    icon: Icons.tag_rounded,
                    label: 'Checkout',
                    value: cart.id.substring(0, 8).toUpperCase(),
                  ),
 
                  const SizedBox(height: 16),
                  _DashedLine(color: scheme.outlineVariant),
                  const SizedBox(height: 8),
 
                  // ── Items ───────────────────────────────────────────
                  for (final item in checkout.items) _ReceiptItemRow(item: item),
 
                  const SizedBox(height: 8),
                  _DashedLine(color: scheme.outlineVariant),
                  const SizedBox(height: 16),
 
                  // ── Total + payment ─────────────────────────────────
                  Row(
                    children: [
                      Text(
                        'Total',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _peso(cart.totalAmount),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ReceiptPaymentDetail(paymentAsync: paymentAsync),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Recorded in BOS inventory and accounting.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
 
class _ReceiptInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
 
  const _ReceiptInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
 
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: scheme.onSurfaceVariant),
        const SizedBox(width: 9),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
 
class _ReceiptPaymentDetail extends StatelessWidget {
  final AsyncValue<List<PurchasePaymentDetail>> paymentAsync;
 
  const _ReceiptPaymentDetail({required this.paymentAsync});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
 
    Widget shell(Widget child) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
 
    return paymentAsync.when(
      loading: () => shell(
        Text(
          'Loading payment…',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
      error: (_, __) => shell(
        Text(
          'Payment details unavailable',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
      data: (payments) {
        if (payments.isEmpty) {
          return shell(
            Text(
              'Payment not recorded',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }
 
        return shell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payments.length == 1 ? 'Paid with' : 'Paid with (split)',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < payments.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 17,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        payments[i].account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _peso(payments[i].amount),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
 
class _ReceiptItemRow extends StatelessWidget {
  final ShoppingCartItem item;
 
  const _ReceiptItemRow({required this.item});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
 
    final unit = (item.unit ?? '').trim();
    final qtyBadge = item.isWeighted
        ? '${_qty(item.weightQuantity ?? 0)}${unit.isEmpty ? '' : ' $unit'}'
        : '${item.quantity}×';
    final detail = item.isWeighted
        ? '${_peso(item.unitPrice)}${unit.isEmpty ? '' : ' / $unit'}'
        : '${_peso(item.unitPrice)} each${unit.isEmpty ? '' : ' · $unit'}';
    final brand = (item.brand ?? '').trim();
 
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              qtyBadge,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (brand.isNotEmpty)
                  Text(
                    brand,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (item.discountAmount > 0)
                  Text(
                    'Discount −${_peso(item.discountAmount)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _peso(item.lineTotal),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
 
// ----------------------------------------------------------------------------
// Receipt paper details
// ----------------------------------------------------------------------------
 
/// Rounded top corners, zig-zag torn bottom edge.
class _ReceiptEdgeClipper extends CustomClipper<Path> {
  const _ReceiptEdgeClipper();
 
  @override
  Path getClip(Size size) {
    const radius = 22.0;
    const tooth = 10.0;
    final count = (size.width / 14).floor().clamp(4, 80);
    final w = size.width / count;
 
    final path = Path()
      ..moveTo(0, radius)
      ..arcToPoint(
        const Offset(radius, 0),
        radius: const Radius.circular(radius),
      )
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(
        Offset(size.width, radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(size.width, size.height - tooth);
 
    for (var i = count; i > 0; i--) {
      path
        ..lineTo(w * i - w / 2, size.height)
        ..lineTo(w * (i - 1), size.height - tooth);
    }
 
    return path..close();
  }
 
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
 
class _DashedLine extends StatelessWidget {
  final Color color;
 
  const _DashedLine({required this.color});
 
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedLinePainter(color)),
    );
  }
}
 
class _DashedLinePainter extends CustomPainter {
  final Color color;
 
  _DashedLinePainter(this.color);
 
  @override
  void paint(Canvas canvas, Size size) {
    const dash = 6.0;
    const gap = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }
 
  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
 

// ============================================================================
// ALL STOCK ADJUSTMENTS PAGE — every damaged/expired/corrected write-off
// across the whole supply catalog, with a worth summary and the ability to
// edit or fully/partially restore each entry, just like the per-item
// adjustment history does for a single supply.
// ============================================================================

class AllStockAdjustmentsPage extends ConsumerStatefulWidget {
  const AllStockAdjustmentsPage({super.key});

  @override
  ConsumerState<AllStockAdjustmentsPage> createState() =>
      _AllStockAdjustmentsPageState();
}

class _AllStockAdjustmentsPageState
    extends ConsumerState<AllStockAdjustmentsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _AdjustmentReason? _reasonFilter;
  bool _showRestoredEntries = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _trimQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  List<StockAdjustmentRecord> _filter(List<StockAdjustmentRecord> records) {
    final query = _query.trim().toLowerCase();

    return records.where((record) {
      if (!_showRestoredEntries && record.isFullyRestored) {
        return false;
      }

      if (_reasonFilter != null &&
          _adjustmentCategoryFor(record.movement.notes) != _reasonFilter) {
        return false;
      }

      if (query.isEmpty) return true;

      final searchable = [
        record.supply.name,
        record.supply.brand ?? '',
        record.movement.notes,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  Future<void> _openEditSheet(StockAdjustmentRecord record) {
    if (!_allowed(context, ref, BosPermission.inventoryAdjust)) {
      return Future<void>.value();
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditAdjustmentSheet(record: record),
    );
  }

  Future<void> _quickRestore(StockAdjustmentRecord record) async {
    if (!_allowed(context, ref, BosPermission.inventoryAdjust)) return;
    if (record.isFullyRestored) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Restore this stock?'),
        content: Text(
          'This adds ${_trimQty(record.outstandingRemoved)} '
          '${record.supply.stockUnit} back to "${record.supply.name}" and '
          'marks this write-off as fully restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _applyAdjustmentEdit(
        ref: ref,
        record: record,
        newOutstandingRemoved: 0,
        newReason: _markReasonRestored(record.movement.notes),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${record.supply.name} stock restored.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to restore stock: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final adjustmentsAsync = ref.watch(allStockAdjustmentsProvider);
    final canAdjust = ref.watch(canProvider(BosPermission.inventoryAdjust));

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock adjustments',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Damaged, expired & corrected stock',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      body: adjustmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorState(
          message: 'Unable to load stock adjustments.',
          onRetry: () => ref.invalidate(allStockAdjustmentsProvider),
        ),
        data: (records) {
          final filtered = _filter(records);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _AdjustmentSummaryCard(records: records),
              const SizedBox(height: 18),
              _SearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ReasonFilterChip(
                      label: 'All reasons',
                      selected: _reasonFilter == null,
                      onSelected: () => setState(() => _reasonFilter = null),
                    ),
                    const SizedBox(width: 8),
                    ..._AdjustmentReason.values.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _ReasonFilterChip(
                          label: r.label,
                          icon: r.icon,
                          selected: _reasonFilter == r,
                          onSelected: () => setState(() => _reasonFilter = r),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: _showRestoredEntries,
                    onChanged: (value) =>
                        setState(() => _showRestoredEntries = value ?? true),
                  ),
                  const Expanded(
                    child: Text(
                      'Show restored entries',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${filtered.length} of ${records.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 42,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        records.isEmpty
                            ? 'No stock has been written off yet.'
                            : 'No adjustments match these filters.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...filtered.map((record) {
                  final category = _adjustmentCategoryFor(
                    record.movement.notes,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AdjustmentCard(
                      record: record,
                      category: category,
                      note: _adjustmentNoteFor(record.movement.notes, category),
                      onEdit: canAdjust ? () => _openEditSheet(record) : null,
                      onRestore: canAdjust ? () => _quickRestore(record) : null,
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// ADJUSTMENT SUMMARY CARD — worth of everything still written off, broken
// down by reason, plus how many entries are outstanding vs. restored.
// ============================================================================

class _AdjustmentSummaryCard extends StatelessWidget {
  final List<StockAdjustmentRecord> records;

  const _AdjustmentSummaryCard({required this.records});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final worthByCategory = <_AdjustmentReason, int>{
      for (final r in _AdjustmentReason.values) r: 0,
    };

    int totalWorth = 0;
    int outstandingCount = 0;
    int restoredCount = 0;

    for (final record in records) {
      if (record.isFullyRestored) {
        restoredCount++;
        continue;
      }

      outstandingCount++;

      final worth = (record.outstandingRemoved * record.supply.costPerBaseUnit)
          .round();
      totalWorth += worth;

      final category = _adjustmentCategoryFor(record.movement.notes);
      worthByCategory[category] = (worthByCategory[category] ?? 0) + worth;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.errorContainer,
            scheme.errorContainer.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.onErrorContainer.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.remove_shopping_cart_outlined,
                  color: scheme.onErrorContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Worth of stock currently written off',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _peso(totalWorth),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _AdjustmentReason.values.map((r) {
              final worth = worthByCategory[r] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.onErrorContainer.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(r.icon, size: 14, color: scheme.onErrorContainer),
                    const SizedBox(width: 6),
                    Text(
                      '${r.label}: ${_peso(worth)}',
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: scheme.onErrorContainer.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.pending_actions_outlined,
                size: 15,
                color: scheme.onErrorContainer.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Text(
                '$outstandingCount outstanding · $restoredCount restored',
                style: TextStyle(
                  color: scheme.onErrorContainer.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// REASON FILTER CHIP
// ============================================================================

class _ReasonFilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onSelected;

  const _ReasonFilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: 15),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary.withValues(alpha: 0.16),
    );
  }
}

// ============================================================================
// ADJUSTMENT CARD (LIST ITEM)
// ============================================================================

class _AdjustmentCard extends StatelessWidget {
  final StockAdjustmentRecord record;
  final _AdjustmentReason category;
  final String note;
  final VoidCallback? onEdit;
  final VoidCallback? onRestore;

  const _AdjustmentCard({
    required this.record,
    required this.category,
    required this.note,
    required this.onEdit,
    required this.onRestore,
  });

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final supply = record.supply;
    final movement = record.movement;
    final restored = record.isFullyRestored;

    final worthCents = (record.outstandingRemoved * supply.costPerBaseUnit)
        .round();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: restored ? Colors.green.shade50 : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: restored
              ? Colors.green.shade200
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: restored
                      ? Colors.green.shade100
                      : scheme.errorContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(
                  restored ? Icons.check_rounded : category.icon,
                  size: 20,
                  color: restored ? Colors.green.shade800 : scheme.error,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supply.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (restored)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Restored',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(movement.movementDate),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    restored
                        ? 'Restored'
                        : '-${_trim(record.outstandingRemoved)} ${supply.stockUnit}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: restored ? Colors.green.shade800 : scheme.error,
                    ),
                  ),
                  if (!restored) ...[
                    const SizedBox(height: 2),
                    Text(
                      _peso(worthCents),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (onEdit != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(38),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                if (!restored && onRestore != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onRestore,
                      icon: const Icon(
                        Icons.settings_backup_restore_rounded,
                        size: 16,
                      ),
                      label: const Text('Restore'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(38),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// EDIT / RESTORE SHEET — lets the user correct the reason/note, and change
// how much of the original write-off is still outstanding. Dragging the
// quantity down to 0 (or tapping "Restore all") fully restores the stock,
// same effect as the quick Restore action on the card.
// ============================================================================

class _EditAdjustmentSheet extends ConsumerStatefulWidget {
  final StockAdjustmentRecord record;

  const _EditAdjustmentSheet({required this.record});

  @override
  ConsumerState<_EditAdjustmentSheet> createState() =>
      _EditAdjustmentSheetState();
}

class _EditAdjustmentSheetState extends ConsumerState<_EditAdjustmentSheet> {
  late _AdjustmentReason _reason;
  late final TextEditingController _quantityController;
  late final TextEditingController _noteController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final movement = widget.record.movement;
    _reason = _adjustmentCategoryFor(movement.notes);
    _noteController = TextEditingController(
      text: _adjustmentNoteFor(movement.notes, _reason),
    );
    _quantityController = TextEditingController(
      text: _trim(widget.record.outstandingRemoved),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Future<void> _save() async {
    final qty = double.tryParse(_quantityController.text);

    if (qty == null || qty < 0) {
      setState(() => _error = 'Enter a valid quantity (0 or more).');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final note = _noteController.text.trim();
    var reasonText = '${_reason.label}${note.isEmpty ? '' : ' — $note'}';
    if (qty == 0) {
      reasonText = _markReasonRestored(reasonText);
    }

    try {
      await _applyAdjustmentEdit(
        ref: ref,
        record: widget.record,
        newOutstandingRemoved: qty,
        newReason: reasonText,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              qty == 0
                  ? '${widget.record.supply.name} adjustment fully restored.'
                  : '${widget.record.supply.name} adjustment updated.',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      // Intentionally empty. _saving is reset explicitly in the success and
      // error paths before this State can begin disposing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final supply = widget.record.supply;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit adjustment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${supply.name} · currently ${_trim(supply.currentStock)} ${supply.stockUnit} in stock',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),

              Text(
                'Reason',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _AdjustmentReason.values
                    .map(
                      (r) => ChoiceChip(
                        label: Text(r.label),
                        avatar: Icon(r.icon, size: 16),
                        selected: _reason == r,
                        onSelected: (_) => setState(() => _reason = r),
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.16,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity still removed',
                  helperText: 'Set to 0 to fully restore this stock.',
                  suffixText: supply.stockUnit,
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 14),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              _quantityController.text = '0';
                              setState(() {});
                            },
                      icon: const Icon(Icons.settings_backup_restore_rounded),
                      label: const Text('Restore all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HEADER CART BUTTON
// ============================================================================

class _CartHeaderButton extends StatelessWidget {
  final int itemCount;
  final VoidCallback onPressed;

  const _CartHeaderButton({required this.itemCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Shopping cart',
          onPressed: onPressed,
          icon: const Icon(Icons.shopping_cart_outlined),
        ),
        if (itemCount > 0)
          Positioned(
            top: 4,
            right: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.error,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Text(
                itemCount > 99 ? '99+' : '$itemCount',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onError,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// OVERVIEW CARD
// ============================================================================

class _SupplyOverviewCard extends StatelessWidget {
  final int totalSupplies;
  final int visibleSupplies;
  final int cartCount;
  final int totalStockWorthCents;

  const _SupplyOverviewCard({
    required this.totalSupplies,
    required this.visibleSupplies,
    required this.cartCount,
    required this.totalStockWorthCents,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bool isSearching = visibleSupplies != totalSupplies;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          // Use the available width of THIS CARD.
          // This is more reliable than MediaQuery for nested layouts.
          final bool compact = width < 380;
          final bool ultraCompact = width < 330;

          final double padding = ultraCompact
              ? 12
              : compact
              ? 14
              : 18;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ============================================================
                // HEADER
                // ============================================================

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Container(
                      width: compact ? 40 : 44,
                      height: compact ? 40 : 44,
                      decoration: BoxDecoration(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: compact ? 20 : 22,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),

                    SizedBox(width: compact ? 8 : 12),

                    // Text MUST be constrained.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isSearching
                                ? '$visibleSupplies matching supplies'
                                : '$totalSupplies supply items',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: compact ? 16 : null,
                              fontWeight: FontWeight.w900,
                              color: scheme.onPrimaryContainer,
                              letterSpacing: -0.4,
                            ),
                          ),

                          const SizedBox(height: 3),

                          Text(
                            'Keep your frequently purchased prices in one place.',
                            maxLines: compact ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: compact ? 10.5 : null,
                              color: scheme.onPrimaryContainer.withValues(
                                alpha: 0.78,
                              ),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: compact ? 14 : 18),

                // ============================================================
                // METRICS
                // ============================================================
                if (ultraCompact)
                  // ----------------------------------------------------------
                  // VERY SMALL PHONE
                  // ----------------------------------------------------------
                  Column(
                    children: [
                      _OverviewMetric(
                        icon: Icons.sell_outlined,
                        label: 'Catalog',
                        value: '$totalSupplies',
                        foreground: scheme.onPrimaryContainer,
                        vertical: true,
                      ),

                      const SizedBox(height: 10),

                      Container(
                        width: double.infinity,
                        height: 1,
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.12,
                        ),
                      ),

                      const SizedBox(height: 10),

                      _OverviewMetric(
                        icon: Icons.payments_outlined,
                        label: 'Stock worth',
                        value: _peso(totalStockWorthCents),
                        foreground: scheme.onPrimaryContainer,
                        vertical: true,
                      ),

                      const SizedBox(height: 10),

                      Container(
                        width: double.infinity,
                        height: 1,
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.12,
                        ),
                      ),

                      const SizedBox(height: 10),

                      _OverviewMetric(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Cart',
                        value: '$cartCount',
                        foreground: scheme.onPrimaryContainer,
                        vertical: true,
                      ),
                    ],
                  )
                else
                  // ----------------------------------------------------------
                  // NORMAL PHONE
                  // ----------------------------------------------------------
                  Row(
                    children: [
                      Expanded(
                        child: _OverviewMetric(
                          icon: Icons.sell_outlined,
                          label: 'Catalog',
                          value: '$totalSupplies',
                          foreground: scheme.onPrimaryContainer,
                        ),
                      ),

                      Container(
                        width: 1,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.12,
                        ),
                      ),

                      Expanded(
                        child: _OverviewMetric(
                          icon: Icons.payments_outlined,
                          label: 'Stock worth',
                          value: _peso(totalStockWorthCents),
                          foreground: scheme.onPrimaryContainer,
                        ),
                      ),

                      Container(
                        width: 1,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.12,
                        ),
                      ),

                      Expanded(
                        child: _OverviewMetric(
                          icon: Icons.shopping_cart_outlined,
                          label: 'Cart',
                          value: '$cartCount',
                          foreground: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// OVERVIEW METRIC
// ============================================================================

class _OverviewMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color foreground;
  final bool vertical;

  const _OverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.foreground,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground.withValues(alpha: 0.72)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$value $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground.withValues(alpha: 0.72)),

          const SizedBox(width: 6),

          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.68),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================================
// FILTERS TOGGLE BAR — filters stay hidden by default; tapping this reveals
// the stock/category/store/sort filter bar underneath.
// ============================================================================

class _FiltersToggleBar extends StatelessWidget {
  final bool expanded;
  final bool hasActiveFilters;
  final VoidCallback onTap;

  const _FiltersToggleBar({
    required this.expanded,
    required this.hasActiveFilters,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: hasActiveFilters
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 18,
                color: hasActiveFilters
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Filters',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: hasActiveFilters
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (hasActiveFilters) ...[
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: hasActiveFilters
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SEARCH
// ============================================================================

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hintText;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hintText = 'Search name, brand, store, unit...',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ============================================================================
// SUPPLY CARD
// ============================================================================

class _SupplyCard extends ConsumerWidget {
  final Supply supply;

  const _SupplyCard({required this.supply});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canAdjust = ref.watch(canProvider(BosPermission.inventoryAdjust));
    final canCart = ref.watch(canProvider(_kCartPermission));

    final historyAsync = ref.watch(priceHistoryProvider(supply.id));

    final cart = ref.watch(cartProvider);

    final inCart = cart.where((item) => item.supplyId == supply.id);

    final quantityInCart = inCart.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Slidable(
      key: ValueKey(supply.id),
      enabled: canAdjust,
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.26,
        children: [
          SlidableAction(
            onPressed: (_) => _openStockAdjustmentSheet(context, ref),
            backgroundColor: scheme.tertiaryContainer,
            foregroundColor: scheme.onTertiaryContainer,
            icon: Icons.tune_rounded,
            label: 'Adjust stock',
            borderRadius: BorderRadius.circular(14),
          ),
        ],
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SupplyDetailPage(supply: supply),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                _SupplyAvatar(name: supply.name),
                const SizedBox(width: 13),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 220;
                      final brand = (supply.brand ?? '').trim();
                      final unitParts = <String>[
                        if (supply.unitQuantity != null)
                          '${supply.unitQuantity}',
                        if (supply.unit != null &&
                            supply.unit!.trim().isNotEmpty)
                          supply.unit!.trim(),
                      ];
                      final unitLabel = unitParts.isEmpty
                          ? ''
                          : 'per ${unitParts.join(' ')}';

                      // Left: name · brand · per unit
                      // Right: Same/Lower/Higher label + price (side by side)
                      final detailStyle = theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 11 : 12,
                      );
                      final nameStyle = theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        fontSize: compact ? 13 : null,
                      );
                      final priceStyle = theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.primary,
                        letterSpacing: -0.2,
                        fontSize: compact ? 13 : 15,
                      );

                      final priceText = Text(
                        _peso(supply.currentPrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: priceStyle,
                      );

                      final trendBadge = historyAsync.when(
                        data: (history) {
                          final trend = _trendFor(history);
                          return trend == _Trend.none
                              ? const SizedBox.shrink()
                              : _TrendBadge(trend: trend);
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                      final priceAndTrend = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (historyAsync.asData != null &&
                              _trendFor(historyAsync.asData!.value) !=
                                  _Trend.none) ...[
                            trendBadge,
                            const SizedBox(width: 6),
                          ],
                          priceText,
                        ],
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: supply.name,
                                        style: nameStyle,
                                      ),
                                      if (brand.isNotEmpty) ...[
                                        TextSpan(
                                          text: ' · ',
                                          style: detailStyle,
                                        ),
                                        TextSpan(
                                          text: brand,
                                          style: detailStyle,
                                        ),
                                      ],
                                      if (unitLabel.isNotEmpty) ...[
                                        TextSpan(
                                          text: ' · ',
                                          style: detailStyle,
                                        ),
                                        TextSpan(
                                          text: unitLabel,
                                          style: detailStyle,
                                        ),
                                      ],
                                    ],
                                  ),
                                  maxLines: compact ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Trend + price on the right; FittedBox scales
                              // down on narrow widths so the Row never overflows.
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: priceAndTrend,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _StockBadge(supply: supply),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canCart)
                      IconButton.filled(
                        tooltip: 'Add to cart',
                        onPressed: () async {
                          try {
                            await ref
                                .read(cartProvider.notifier)
                                .addOrIncrement(supply);
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Could not save cart line: $error',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(milliseconds: 1100),
                                content: Text('${supply.name} added to cart'),
                              ),
                            );
                        },
                        icon: const Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 20,
                        ),
                      ),
                    if (canCart && quantityInCart > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$quantityInCart in cart',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openStockAdjustmentSheet(BuildContext context, WidgetRef ref) {
    if (!_allowed(context, ref, BosPermission.inventoryAdjust)) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StockAdjustmentSheet(supply: supply),
    );
  }
}

// ============================================================================
// SUPPLY AVATAR
// ============================================================================

class _SupplyAvatar extends StatelessWidget {
  final String name;

  const _SupplyAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ============================================================================
// TREND BADGE
// ============================================================================

// ============================================================
// INVENTORY STOCK STATUS
// ============================================================

enum _InventoryStockStatus { noLimits, outOfStock, lowStock, normal, overstock }

/// True when on-hand stock is still positive but at/below the configured
/// low-stock level. Prefers [Supply.lowStockThreshold] (set via the
/// "Low-stock alert" action) and falls back to [Supply.minimumStock] so
/// either field — whichever the user actually filled in — drives both the
/// badge and any catalog "Low stock" filter that keys off the same rules.
bool _isSupplyLowStock(Supply supply) {
  final stock = supply.currentStock;
  if (stock <= 0) return false;

  final threshold = supply.lowStockThreshold;
  if (threshold != null && threshold > 0 && stock <= threshold) {
    return true;
  }

  if (supply.minimumStock > 0 && stock <= supply.minimumStock) {
    return true;
  }

  return false;
}

_InventoryStockStatus _stockStatus({
  required double stock,
  required double minimumStock,
  required double maximumStock,
  double? lowStockThreshold,
}) {
  if (stock <= 0) return _InventoryStockStatus.outOfStock;

  // Prefer the explicit low-stock alert threshold; fall back to minimumStock.
  final effectiveLow = (lowStockThreshold != null && lowStockThreshold > 0)
      ? lowStockThreshold
      : (minimumStock > 0 ? minimumStock : 0.0);

  if (effectiveLow > 0 && stock <= effectiveLow) {
    return _InventoryStockStatus.lowStock;
  }
  if (maximumStock > 0 && stock > maximumStock) {
    return _InventoryStockStatus.overstock;
  }
  if (effectiveLow <= 0 && maximumStock <= 0) {
    return _InventoryStockStatus.noLimits;
  }
  return _InventoryStockStatus.normal;
}

String _stockStatusLabel(_InventoryStockStatus status) {
  return switch (status) {
    _InventoryStockStatus.noLimits => 'No limits',
    _InventoryStockStatus.outOfStock => 'Out of stock',
    _InventoryStockStatus.lowStock => 'Low stock',
    _InventoryStockStatus.normal => 'Normal',
    _InventoryStockStatus.overstock => 'Overstock',
  };
}

// ============================================================
// STOCK BADGE — current quantity (shown in the supply's purchase unit,
// e.g. "packs", when one is configured) + configured inventory status.
// Status thresholds are still compared in base stock units internally,
// since minimumStock/maximumStock are stored that way too — only the
// number shown to the user is converted.
// ============================================================

class _StockBadge extends StatelessWidget {
  final Supply supply;

  const _StockBadge({required this.supply});

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _stockStatus(
      stock: supply.currentStock,
      minimumStock: supply.minimumStock,
      maximumStock: supply.maximumStock,
      lowStockThreshold: supply.lowStockThreshold,
    );

    final Color color;
    final Color background;
    final IconData icon;

    switch (status) {
      case _InventoryStockStatus.outOfStock:
        color = scheme.error;
        background = scheme.errorContainer.withValues(alpha: 0.72);
        icon = Icons.inventory_2_outlined;
      case _InventoryStockStatus.lowStock:
        color = Colors.orange.shade800;
        background = Colors.orange.withValues(alpha: 0.12);
        icon = Icons.warning_amber_rounded;
      case _InventoryStockStatus.overstock:
        color = Colors.amber.shade900;
        background = Colors.amber.withValues(alpha: 0.15);
        icon = Icons.trending_up_rounded;
      case _InventoryStockStatus.normal:
        color = scheme.primary;
        background = scheme.primaryContainer.withValues(alpha: 0.58);
        icon = Icons.check_circle_outline_rounded;
      case _InventoryStockStatus.noLimits:
        color = scheme.onSurfaceVariant;
        background = scheme.surfaceContainerHighest;
        icon = Icons.inventory_2_outlined;
    }

    final displayUnit = _displayStockUnit(supply);
    final displayStock = _displayStockQuantity(supply, supply.currentStock);
    final quantityLabel = supply.currentStock <= 0
        ? '0 $displayUnit'.trim()
        : '${_trim(displayStock)} $displayUnit'.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            quantityLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _stockStatusLabel(status),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final _Trend trend;

  const _TrendBadge({required this.trend});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    late final IconData icon;
    late final String label;
    late final Color color;

    switch (trend) {
      case _Trend.up:
        icon = Icons.trending_up_rounded;
        label = 'Higher';
        color = scheme.error;
        break;

      case _Trend.down:
        icon = Icons.trending_down_rounded;
        label = 'Lower';
        color = Colors.green;
        break;

      case _Trend.same:
        icon = Icons.trending_flat_rounded;
        label = 'Same';
        color = scheme.onSurfaceVariant;
        break;

      case _Trend.none:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// NO SEARCH RESULTS
// ============================================================================

class _NoSearchResults extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _NoSearchResults({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              color: scheme.onSurfaceVariant,
              size: 27,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No supplies found',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Nothing matches "$query".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 15),
          OutlinedButton(onPressed: onClear, child: const Text('Clear search')),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _ScannedSupplyDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ScannedSupplyDetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 9),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 34,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No supplies yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Create your first supply item to start building your price catalog.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            PermissionGate(
              permission: BosPermission.inventoryCreate,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add supply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ERROR STATE
// ============================================================================

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 46, color: scheme.error),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ADD SUPPLY FORM
// ============================================================================

class _SupplyForm extends ConsumerStatefulWidget {
  const _SupplyForm();

  @override
  ConsumerState<_SupplyForm> createState() => _SupplyFormState();
}

// ============================================================================
// ADD SUPPLY FORM  (replaces `_SupplyForm` + `_SupplyFormState`)
//
// Paste this over the old classes in supplies_price_list_page.dart.
// Nothing else in the file needs to change: it is still opened with
//   showModalBottomSheet(... builder: (_) => const _SupplyForm())
// and uses the same imports, providers and save logic as before.
//
// What's new:
//   * Live preview card that shows the item as you type
//   * Numbered sections with plain-language hints
//   * Inline validation (no more surprise snackbars)
//   * Catalog codes (SKU / barcode / category) tucked into an optional section
//   * Sticky action bar with Cancel, Save for now, and Save & add stock
//   * "Discard this supply?" confirmation when Cancel/back is used with data
// ============================================================================

class _SupplyFormState extends ConsumerState<_SupplyForm> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _unitQuantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();

  String? _categoryId;
  String? _selectedUnit;

  bool _saving = false;
  bool _savingAddStock = false;

  late final Listenable _formListenable = Listenable.merge([
    _nameController,
    _brandController,
    _unitQuantityController,
    _priceController,
    _skuController,
    _barcodeController,
  ]);

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _unitQuantityController.dispose();
    _priceController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // helpers
  // --------------------------------------------------------------------------

  bool get _dirty =>
      _nameController.text.trim().isNotEmpty ||
      _brandController.text.trim().isNotEmpty ||
      _unitQuantityController.text.trim().isNotEmpty ||
      _priceController.text.trim().isNotEmpty ||
      _skuController.text.trim().isNotEmpty ||
      _barcodeController.text.trim().isNotEmpty ||
      _selectedUnit != null ||
      _categoryId != null;

  double? _parseNumber(String text) {
    final cleaned = text.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<String?> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (!mounted || barcode == null || barcode.trim().isEmpty) {
      return null;
    }

    return barcode.trim();
  }

  Future<void> _cancel() async {
    if (_saving) return;

    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_sweep_outlined, size: 30),
        title: const Text('Discard this supply?'),
        content: const Text(
          'What you typed so far will be lost. Nothing has been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // --------------------------------------------------------------------------
  // save (same behavior as before)
  // --------------------------------------------------------------------------

  Future<void> _save({required bool addStock}) async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Please fix the highlighted fields.'),
          ),
        );
      return;
    }

    final unitQuantity = _parseNumber(_unitQuantityController.text);
    final enteredPrice = _parseNumber(_priceController.text);

    setState(() {
      _saving = true;
      _savingAddStock = addStock;
    });

    try {
      final auth = ref.read(authorizationServiceProvider);
      auth.require(
        BosPermission.inventoryCreate,
        businessId: kCurrentBusinessId,
      );
      // 'Save & add stock' also records the first purchase.
      if (addStock) {
        auth.require(_kCartPermission, businessId: kCurrentBusinessId);
      }

      final db = ref.read(databaseProvider);
      final catalog = ref.read(supplyCatalogServiceProvider);
      final audit = ref.read(auditLogServiceProvider);

      // Normalise then check for collisions BEFORE inserting, so the user
      // gets "SKU FLR-001 is already used by Flour" instead of a raw SQLite
      // constraint error.
      final sku = SupplyCatalogService.normalizeSku(_skuController.text);
      final barcode = SupplyCatalogService.normalizeBarcode(
        _barcodeController.text,
      );
      await catalog.assertCodesFree(sku: sku, barcode: barcode);

      final supplyId = const Uuid().v4();
      final now = DateTime.now();
      final priceCents = enteredPrice == null
          ? 0
          : (enteredPrice * 100).round();

      await db.transaction(() async {
        await db
            .into(db.supplies)
            .insert(
              SuppliesCompanion.insert(
                id: supplyId,
                businessId: kCurrentBusinessId,
                name: _nameController.text.trim(),
                brand: Value(
                  _brandController.text.trim().isEmpty
                      ? null
                      : _brandController.text.trim(),
                ),
                unitQuantity: Value(unitQuantity),
                unit: Value(_selectedUnit),
                sku: Value(sku),
                barcode: Value(barcode),
                categoryId: Value(_categoryId),
                currentPrice: priceCents,
                stockUnit: Value(_selectedUnit ?? 'piece'),
                currentStock: const Value(0),
                costPerBaseUnit: const Value(0),
                updatedAt: Value(now),
                isActive: const Value(true),
              ),
            );

        // Record the entered price in price history immediately for
        // "Save for now". (When adding stock, the purchase sheet records it.)
        if (!addStock && enteredPrice != null) {
          await db
              .into(db.supplyPriceHistory)
              .insert(
                SupplyPriceHistoryCompanion.insert(
                  id: const Uuid().v4(),
                  supplyId: supplyId,
                  price: priceCents,
                  storeName: 'Initial price',
                  storeAddress: const Value(null),
                  recordedDate: now,
                ),
              );
        }

        await audit.record(
          AuditEvent(
            businessId: kCurrentBusinessId,
            module: AuditModule.inventory,
            actionType: AuditActionType.create,
            action: 'inventory.supply_created',
            entityType: 'supplies',
            entityId: supplyId,
            entityLabel: _nameController.text.trim(),
            after: {
              'name': _nameController.text.trim(),
              'brand': _brandController.text.trim(),
              'stockUnit': _selectedUnit ?? 'piece',
              'price': priceCents,
              'sku': sku,
              'barcode': barcode,
            },
          ),
        );
      });

      ref.invalidate(suppliesProvider);

      if (!mounted) return;

      final createdSupply = addStock
          ? await (db.select(
              db.supplies,
            )..where((s) => s.id.equals(supplyId))).getSingle()
          : null;
      final savedName = _nameController.text.trim();

      if (!mounted) return;
      Navigator.pop(context);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            addStock
                ? '$savedName added. Now record your first purchase.'
                : '$savedName saved to your catalog.',
          ),
        ),
      );

      if (addStock && context.mounted && createdSupply != null) {
        await showPurchaseEntrySheet(context, supply: createdSupply);
      }
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(e.message)),
      );
    } on DuplicateSupplyCodeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(e.toString()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to save supply: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingAddStock = false;
        });
      }
    }
  }

  // --------------------------------------------------------------------------
  // build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.96;

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle ───────────────────────────────────────────────
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),

              // ── Header ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.primary,
                            scheme.primary.withValues(alpha: 0.72),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        Icons.add_box_rounded,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add supply item',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            'Fill in the basics. Everything else is optional.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _saving ? null : _cancel,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),

              // ── Scrollable form ──────────────────────────────────────
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pad = constraints.maxWidth < 360 ? 14.0 : 20.0;

                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(pad, 10, pad, 20),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Live preview
                            ListenableBuilder(
                              listenable: _formListenable,
                              builder: (context, _) => _buildPreview(),
                            ),
                            const SizedBox(height: 16),

                            // ── 1. What is it? ───────────────────────
                            _FormSectionCard(
                              step: 1,
                              title: 'What is it?',
                              subtitle: 'The name you and your team will see.',
                              requiredBadge: true,
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _nameController,
                                    enabled: !_saving,
                                    autofocus: true,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Supply name *',
                                      hintText: 'e.g. Rice fertilizer',
                                      prefixIcon: Icon(
                                        Icons.inventory_2_outlined,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Enter a supply name';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _brandController,
                                    enabled: !_saving,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Brand (optional)',
                                      hintText: 'e.g. NutriGrow',
                                      prefixIcon: Icon(
                                        Icons.branding_watermark_outlined,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── 2. How is it measured? ───────────────
                            _FormSectionCard(
                              step: 2,
                              title: 'How is it measured?',
                              subtitle:
                                  'Pick the unit BOS counts this item in, '
                                  'then how much one pack holds.',
                              requiredBadge: true,
                              child: Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedUnit,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Counted in *',
                                      helperText:
                                          'Stock levels and recipes use this unit.',
                                      helperMaxLines: 2,
                                      prefixIcon: Icon(
                                        Icons.straighten_outlined,
                                      ),
                                    ),
                                    items: kStockUnitOptions
                                        .map(
                                          (unit) => DropdownMenuItem<String>(
                                            value: unit,
                                            child: Text(
                                              kStockUnitLabels[unit] ?? unit,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    validator: (value) =>
                                        value == null ? 'Choose a unit' : null,
                                    onChanged: _saving
                                        ? null
                                        : (value) {
                                            setState(() {
                                              _selectedUnit = value;
                                            });
                                          },
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _unitQuantityController,
                                    enabled: !_saving,
                                    textInputAction: TextInputAction.next,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Amount per pack (optional)',
                                      hintText: 'e.g. 25',
                                      helperText:
                                          'Example: a 25 kg sack → choose '
                                          'Kilogram above and enter 25.',
                                      helperMaxLines: 2,
                                      prefixIcon: Icon(Icons.numbers_outlined),
                                    ),
                                    validator: (value) {
                                      final text = (value ?? '').trim();
                                      if (text.isEmpty) return null;
                                      final n = _parseNumber(text);
                                      if (n == null || !n.isFinite || n <= 0) {
                                        return 'Enter a number greater than 0';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── 3. Price ─────────────────────────────
                            _FormSectionCard(
                              step: 3,
                              title: 'What does it cost?',
                              subtitle:
                                  'You can skip this and set the price when '
                                  'you record a purchase.',
                              child: TextFormField(
                                controller: _priceController,
                                enabled: !_saving,
                                textInputAction: TextInputAction.done,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Current price (optional)',
                                  hintText: 'e.g. 1200',
                                  prefixText: '₱ ',
                                  prefixIcon: Icon(Icons.payments_outlined),
                                  helperText:
                                      'Leave blank if you don\'t know it yet.',
                                ),
                                validator: (value) {
                                  final text = (value ?? '').trim();
                                  if (text.isEmpty) return null;
                                  final n = _parseNumber(text);
                                  if (n == null || !n.isFinite || n < 0) {
                                    return 'Enter a valid price';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── 4. Catalog codes (collapsed) ─────────
                            Theme(
                              data: theme.copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ExpansionTile(
                                  maintainState: true,
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 2,
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  leading: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 17,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  title: Text(
                                    'Catalog codes',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'SKU, barcode & category · optional',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  children: [
                                    SupplyIdentityFields(
                                      skuController: _skuController,
                                      barcodeController: _barcodeController,
                                      categoryId: _categoryId,
                                      onCategoryChanged: (id) {
                                        setState(() {
                                          _categoryId = id;
                                        });
                                      },
                                      onScan: _saving ? null : _scanBarcode,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── Sticky action bar ────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _save(addStock: true),
                            icon: _saving && _savingAddStock
                                ? const SizedBox(
                                    width: 19,
                                    height: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_rounded),
                            label: const Text(
                              'Save & add stock',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Next, you\'ll record your first purchase.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 46,
                                child: OutlinedButton(
                                  onPressed: _saving ? null : _cancel,
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 46,
                                child: FilledButton.tonal(
                                  onPressed: _saving
                                      ? null
                                      : () => _save(addStock: false),
                                  child: _saving && !_savingAddStock
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Save for now',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "How it will look in your catalog", updated as the user types.
  Widget _buildPreview() {
    final name = _nameController.text.trim();
    final brand = _brandController.text.trim();
    final qty = _parseNumber(_unitQuantityController.text);
    final price = _parseNumber(_priceController.text);
    final unitLabel = _selectedUnit == null
        ? null
        : (kStockUnitLabels[_selectedUnit] ?? _selectedUnit);

    final String unitLine;
    if (unitLabel == null) {
      unitLine = 'Choose a unit';
    } else if (qty != null && qty > 0) {
      unitLine = 'per ${_qty(qty)} $unitLabel';
    } else {
      unitLine = 'Counted in $unitLabel';
    }

    return _SupplyPreviewCard(
      name: name,
      brand: brand,
      unitLine: unitLine,
      priceText: price != null && price >= 0
          ? _peso((price * 100).round())
          : 'No price yet',
      hasPrice: price != null && price >= 0,
    );
  }
}

// ============================================================================
// FORM SECTION CARD — numbered card with a title, hint and optional badge
// ============================================================================

class _FormSectionCard extends StatelessWidget {
  final int step;
  final String title;
  final String subtitle;
  final bool requiredBadge;
  final Widget child;

  const _FormSectionCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
    this.requiredBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (requiredBadge) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer.withValues(
                                alpha: 0.7,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Required',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ============================================================================
// LIVE PREVIEW — mirrors how the item appears in the price catalog
// ============================================================================

class _SupplyPreviewCard extends StatelessWidget {
  final String name;
  final String brand;
  final String unitLine;
  final String priceText;
  final bool hasPrice;

  const _SupplyPreviewCard({
    required this.name,
    required this.brand,
    required this.unitLine,
    required this.priceText,
    required this.hasPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasName = name.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.65),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              hasName ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PREVIEW',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasName ? name : 'Your supply name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onPrimaryContainer.withValues(
                      alpha: hasName ? 1 : 0.5,
                    ),
                  ),
                ),
                Text(
                  [if (brand.isNotEmpty) brand, unitLine].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            priceText,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onPrimaryContainer.withValues(
                alpha: hasPrice ? 1 : 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================================
// SECTION LABEL
// ============================================================================

// class _SectionLabel extends StatelessWidget {
//   final String title;
//   final IconData icon;

//   const _SectionLabel({required this.title, required this.icon});

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final scheme = theme.colorScheme;

//     return Row(
//       children: [
//         Icon(icon, size: 17, color: scheme.primary),
//         const SizedBox(width: 7),
//         Text(
//           title,
//           style: theme.textTheme.labelLarge?.copyWith(
//             fontWeight: FontWeight.w800,
//             color: scheme.onSurface,
//           ),
//         ),
//       ],
//     );
//   }
// }

// ============================================================================
// SUPPLY DETAIL
// ============================================================================

// ============================================================
// USED IN PRODUCTS — surfaces which recipes depend on this
// supply, so a price spike or stock-out shows its real impact
// before it becomes a surprise.
// ============================================================

final _productsUsingSupplyProvider =
    FutureProvider.family<List<Product>, String>((ref, supplyId) {
      ref.watch(ledgerVersionProvider);
      return ref
          .watch(costingServiceProvider)
          .findProductsUsingSupply(supplyId);
    });

class _UsedInProductsSection extends ConsumerWidget {
  final Supply supply;
  const _UsedInProductsSection({required this.supply});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final productsAsync = ref.watch(_productsUsingSupplyProvider(supply.id));

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Used in ${products.length} product${products.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: products
                    .map(
                      (p) => ActionChip(
                        label: Text(p.name),
                        avatar: const Icon(
                          Icons.restaurant_menu_outlined,
                          size: 15,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailPage(product: p),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class SupplyDetailPage extends ConsumerWidget {
  final Supply supply;

  const SupplyDetailPage({super.key, required this.supply});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          title: const Text('Archive supply?'),
          content: Text(
            '"${supply.name}" will be hidden from the supplies catalog. '
            'It will also be removed from any recipes that currently use it. '
            'Purchase history, price history, and inventory records will be preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.inventoryEdit, businessId: kCurrentBusinessId);

      final db = ref.read(databaseProvider);
      final audit = ref.read(auditLogServiceProvider);

      await db.transaction(() async {
        final usedIn = await (db.select(
          db.recipeComponents,
        )..where((c) => c.supplyId.equals(supply.id))).get();
        // Remove this supply from all recipes.
        await (db.delete(
          db.recipeComponents,
        )..where((component) => component.supplyId.equals(supply.id))).go();

        // Archive the supply instead of physically deleting it.
        await (db.update(
          db.supplies,
        )..where((item) => item.id.equals(supply.id))).write(
          SuppliesCompanion(
            isActive: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await audit.record(
          AuditEvent(
            businessId: supply.businessId,
            module: AuditModule.inventory,
            actionType: AuditActionType.delete,
            action: 'inventory.supply_archived',
            entityType: 'supplies',
            entityId: supply.id,
            entityLabel: supply.name,
            before: {'isActive': true, 'stock': supply.currentStock},
            after: {'isActive': false},
            details: {'removedFromRecipes': usedIn.length},
          ),
        );
      });

      ref.invalidate(suppliesProvider);
      ref.invalidate(priceHistoryProvider(supply.id));

      // Refresh recipes, costing, and producibility.
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${supply.name} archived and removed from recipes.'),
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to archive supply: $error'),
        ),
      );
    }
  }

  Future<void> _setLowStockThreshold(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (!_allowed(context, ref, BosPermission.inventoryEdit)) return;

    final controller = TextEditingController(
      text: supply.lowStockThreshold != null
          ? (supply.lowStockThreshold ==
                    supply.lowStockThreshold!.roundToDouble()
                ? supply.lowStockThreshold!.toInt().toString()
                : supply.lowStockThreshold.toString())
          : '',
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Low-stock alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Get notified when ${supply.name} drops to or below this amount.',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Threshold',
                suffixText: supply.stockUnit,
              ),
            ),
          ],
        ),
        actions: [
          if (supply.lowStockThreshold != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, -1.0), // sentinel: clear
              child: const Text(
                'Clear Alert',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final db = ref.read(databaseProvider);
    final newThreshold = result == -1.0 ? null : result;

    // Keep minimumStock in sync with the alert threshold so the catalog
    // "Low stock" filter (which typically compares against minimumStock)
    // and the stock badge agree on what "low" means.
    await (db.update(db.supplies)..where((s) => s.id.equals(supply.id))).write(
      SuppliesCompanion(
        lowStockThreshold: Value(newThreshold),
        minimumStock: Value(newThreshold ?? 0),
      ),
    );
    await ref
        .read(auditLogServiceProvider)
        .tryRecord(
          AuditEvent(
            businessId: supply.businessId,
            module: AuditModule.inventory,
            actionType: AuditActionType.update,
            action: 'inventory.low_stock_alert_changed',
            entityType: 'supplies',
            entityId: supply.id,
            entityLabel: supply.name,
            before: {'lowStockThreshold': supply.lowStockThreshold},
            after: {'lowStockThreshold': newThreshold},
          ),
        );
    ref.invalidate(suppliesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final liveSupply = ref
        .watch(suppliesProvider)
        .maybeWhen(
          data: (supplies) => supplies.firstWhere(
            (item) => item.id == supply.id,
            orElse: () => supply,
          ),
          orElse: () => supply,
        );

    final historyAsync = ref.watch(priceHistoryProvider(supply.id));
    final canEdit = ref.watch(canProvider(BosPermission.inventoryEdit));
    final canAdjust = ref.watch(canProvider(BosPermission.inventoryAdjust));
    final canBuy = ref.watch(canProvider(_kCartPermission));

    final menuItems = <PopupMenuEntry<String>>[
      if (canEdit)
        const PopupMenuItem(
          value: 'set_threshold',
          child: Row(
            children: [
              Icon(Icons.notifications_outlined),
              SizedBox(width: 10),
              Text('Set low-stock alert'),
            ],
          ),
        ),
      if (canAdjust)
        const PopupMenuItem(
          value: 'adjust_stock',
          child: Row(
            children: [
              Icon(Icons.remove_shopping_cart_outlined),
              SizedBox(width: 10),
              Text('Adjust stock (damaged/expired)'),
            ],
          ),
        ),
      if (canEdit)
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded),
              SizedBox(width: 10),
              Text('Archive supply'),
            ],
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              supply.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              supply.unit == null
                  ? 'Price history'
                  : 'Price per ${supply.unit}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (canBuy)
            IconButton(
              tooltip: 'Record purchase',
              onPressed: () {
                if (!_allowed(context, ref, _kCartPermission)) return;
                showPurchaseEntrySheet(context, supply: supply);
              },
              icon: const Icon(Icons.add_chart_rounded),
            ),
          IconButton(
            tooltip: 'Adjustment history',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      StockAdjustmentHistoryPage(supply: liveSupply),
                ),
              );
            },
            icon: const Icon(Icons.history_rounded),
          ),

          if (menuItems.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDelete(context, ref);
                } else if (value == 'adjust_stock') {
                  if (!_allowed(context, ref, BosPermission.inventoryAdjust)) {
                    return;
                  }
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => StockAdjustmentSheet(supply: supply),
                  );
                } else if (value == 'set_threshold') {
                  _setLowStockThreshold(context, ref);
                }
              },
              itemBuilder: (_) => menuItems,
            ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorState(
          message: 'Unable to load price history.',
          onRetry: () {
            ref.invalidate(priceHistoryProvider(supply.id));
          },
        ),
        data: (history) {
          final cheapest = history.isEmpty
              ? null
              : history.reduce((a, b) => a.price <= b.price ? a : b);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _CurrentPriceCard(supply: liveSupply, history: history),
              if (cheapest != null) ...[
                const SizedBox(height: 12),
                _CheapestPriceCard(
                  price: cheapest.price,
                  store: cheapest.storeName,
                  date: cheapest.recordedDate,
                ),
              ],
              if (history.length >= 2) ...[
                const SizedBox(height: 12),
                _PriceHistoryChartCard(history: history),
              ],
              const SizedBox(height: 16),
              _UsedInProductsSection(supply: liveSupply),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Price history',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${history.length} record${history.length == 1 ? '' : 's'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'No price history recorded yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                ...history.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _PriceHistoryCard(entry: entry),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PriceRecordDialog extends StatefulWidget {
  final Supply supply;
  final AppDatabase db;

  const _PriceRecordDialog({required this.supply, required this.db});

  @override
  State<_PriceRecordDialog> createState() => _PriceRecordDialogState();
}

class _PriceRecordDialogState extends State<_PriceRecordDialog> {
  final _priceController = TextEditingController();
  final _storeController = TextEditingController();
  final _addressController = TextEditingController();

  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _priceController.dispose();
    _storeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final normalized = _priceController.text.replaceAll(',', '').trim();
    final price = double.tryParse(normalized);

    if (price == null || price < 0) {
      setState(() {
        _errorMessage = 'Please enter a valid price.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final now = DateTime.now();
    final cents = (price * 100).round();

    try {
      await widget.db.transaction(() async {
        final currentSupply = await (widget.db.select(
          widget.db.supplies,
        )..where((s) => s.id.equals(widget.supply.id))).getSingleOrNull();

        if (currentSupply == null) {
          throw StateError('This supply no longer exists.');
        }

        if (currentSupply.currentPrice != cents) {
          await widget.db
              .into(widget.db.supplyPriceHistory)
              .insert(
                SupplyPriceHistoryCompanion.insert(
                  id: const Uuid().v4(),
                  supplyId: widget.supply.id,
                  price: cents,
                  storeName: _storeController.text.trim().isEmpty
                      ? 'Unknown store'
                      : _storeController.text.trim(),
                  storeAddress: Value(
                    _addressController.text.trim().isEmpty
                        ? null
                        : _addressController.text.trim(),
                  ),
                  recordedDate: now,
                ),
              );
        }

        await (widget.db.update(
          widget.db.supplies,
        )..where((s) => s.id.equals(widget.supply.id))).write(
          SuppliesCompanion(
            currentPrice: Value(cents),
            lastStoreName: Value(
              _storeController.text.trim().isEmpty
                  ? null
                  : _storeController.text.trim(),
            ),
            lastStoreAddress: Value(
              _addressController.text.trim().isEmpty
                  ? null
                  : _addressController.text.trim(),
            ),
            updatedAt: Value(now),
          ),
        );
      });

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'Unable to update price: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Record new price'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.supply.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixText: '₱ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _storeController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Store / supplier',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save price'),
        ),
      ],
    );
  }
}

// ============================================================================
// CURRENT PRICE CARD
// ============================================================================

class _CurrentPriceCard extends StatelessWidget {
  final Supply supply;
  final List<SupplyPriceHistoryData> history;

  const _CurrentPriceCard({required this.supply, required this.history});

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final trend = _trendFor(history);
    final displayUnit = _displayStockUnit(supply);
    final displayStock = _displayStockQuantity(supply, supply.currentStock);
    final stockWorthCents = (supply.currentStock * supply.costPerBaseUnit)
        .round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sell_outlined,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 7),
              Text(
                'CURRENT PRICE',
                style: TextStyle(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.70),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (trend != _Trend.none) _TrendBadge(trend: trend),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _peso(supply.currentPrice),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          if (supply.unit != null) ...[
            const SizedBox(height: 3),
            Text(
              'per ${supply.unit}',
              style: TextStyle(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 15,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  supply.currentStock <= 0
                      ? 'Out of stock'
                      : '${_trim(displayStock)} $displayUnit in stock',
                  style: TextStyle(
                    color: supply.currentStock <= 0
                        ? Colors.redAccent
                        : scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
              ),
              const SizedBox(width: 7),
              Text(
                'Stock worth',
                style: TextStyle(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _peso(stockWorthCents),
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CHEAPEST PRICE
// ============================================================================

class _CheapestPriceCard extends StatelessWidget {
  final int price;
  final String? store;
  final DateTime date;

  const _CheapestPriceCard({
    required this.price,
    required this.store,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.savings_outlined, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BEST RECORDED PRICE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _peso(price),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (_displayStoreName(store) != null)
                      _displayStoreName(store)!,
                    _formatDateShort(date),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PRICE HISTORY CARD
// ============================================================================

// ============================================================================
// PRICE HISTORY CHART
// ============================================================================

class _PriceHistoryChartCard extends StatelessWidget {
  final List<SupplyPriceHistoryData> history;

  const _PriceHistoryChartCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Provider returns newest-first; chart needs chronological order.
    final points = history.toList()
      ..sort((a, b) {
        final byDate = a.recordedDate.compareTo(b.recordedDate);
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });

    final prices = points.map((p) => p.price).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final first = points.first;
    final last = points.last;
    final delta = last.price - first.price;
    final deltaLabel = delta == 0
        ? 'No change'
        : '${delta > 0 ? '+' : ''}${_peso(delta)} overall';

    final Color accent = delta > 0
        ? scheme.error
        : delta < 0
        ? Colors.green.shade700
        : scheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Price trend',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  deltaLabel,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatDateShort(first.recordedDate)} → ${_formatDateShort(last.recordedDate)} · ${points.length} points',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            width: double.infinity,
            child: _PriceHistoryChart(
              points: points,
              lineColor: accent,
              gridColor: scheme.outlineVariant.withValues(alpha: 0.55),
              fillColor: accent.withValues(alpha: 0.14),
              labelColor: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ChartStatChip(
                  label: 'Low',
                  value: _peso(minPrice),
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChartStatChip(
                  label: 'High',
                  value: _peso(maxPrice),
                  color: scheme.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChartStatChip(
                  label: 'Latest',
                  value: _peso(last.price),
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ChartStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceHistoryChart extends StatelessWidget {
  final List<SupplyPriceHistoryData> points;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;
  final Color labelColor;

  const _PriceHistoryChart({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PriceHistoryChartPainter(
        points: points,
        lineColor: lineColor,
        gridColor: gridColor,
        fillColor: fillColor,
        labelColor: labelColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PriceHistoryChartPainter extends CustomPainter {
  final List<SupplyPriceHistoryData> points;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;
  final Color labelColor;

  _PriceHistoryChartPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 44.0;
    const rightPad = 8.0;
    const topPad = 10.0;
    const bottomPad = 28.0;

    final chart = Rect.fromLTRB(
      leftPad,
      topPad,
      size.width - rightPad,
      size.height - bottomPad,
    );

    if (chart.width <= 0 || chart.height <= 0) return;

    final prices = points.map((p) => p.price.toDouble()).toList();
    var minY = prices.reduce((a, b) => a < b ? a : b);
    var maxY = prices.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      minY = minY * 0.9;
      maxY = maxY * 1.1 + 1;
    }
    // Small padding so the line doesn't touch edges.
    final yPad = (maxY - minY) * 0.08;
    minY -= yPad;
    maxY += yPad;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final labelStyle = TextStyle(
      color: labelColor,
      fontSize: 9,
      fontWeight: FontWeight.w600,
    );

    // Horizontal grid + Y labels (3 levels).
    for (var i = 0; i < 3; i++) {
      final t = i / 2;
      final y = chart.bottom - t * chart.height;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = minY + (maxY - minY) * t;
      final label = _peso(value.round());
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: leftPad - 4);
      tp.paint(canvas, Offset(chart.left - tp.width - 6, y - tp.height / 2));
    }

    Offset pointFor(int index) {
      final x = points.length == 1
          ? chart.left + chart.width / 2
          : chart.left + (index / (points.length - 1)) * chart.width;
      final price = points[index].price.toDouble();
      final t = (price - minY) / (maxY - minY);
      final y = chart.bottom - t * chart.height;
      return Offset(x, y);
    }

    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final p = pointFor(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
        fillPath.moveTo(p.dx, chart.bottom);
        fillPath.lineTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
        fillPath.lineTo(p.dx, p.dy);
      }
    }
    fillPath.lineTo(pointFor(points.length - 1).dx, chart.bottom);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor,
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );

    final dotPaint = Paint()..color = lineColor;
    final dotInner = Paint()..color = Colors.white;
    for (var i = 0; i < points.length; i++) {
      final p = pointFor(i);
      canvas.drawCircle(p, 4.2, dotPaint);
      canvas.drawCircle(p, 2.0, dotInner);
    }

    // X labels: first, middle (if enough points), last.
    final xIndexes = <int>{0, points.length - 1};
    if (points.length >= 3) {
      xIndexes.add(points.length ~/ 2);
    }
    for (final i in xIndexes) {
      final p = pointFor(i);
      final label = _formatDateShort(points[i].recordedDate);
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();
      var dx = p.dx - tp.width / 2;
      dx = dx.clamp(chart.left, chart.right - tp.width);
      tp.paint(canvas, Offset(dx, chart.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _PriceHistoryChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.labelColor != labelColor;
  }
}

class _PriceHistoryCard extends StatelessWidget {
  final SupplyPriceHistoryData entry;

  const _PriceHistoryCard({required this.entry});

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final quantity = _formatQuantity(entry.purchaseQuantity);

    final unitsPerPurchase = entry.unitsPerPurchaseAtTime > 0
        ? _formatQuantity(entry.unitsPerPurchaseAtTime)
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _peso(entry.price),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  'Qty $quantity'
                  '${unitsPerPurchase != null ? ' · $unitsPerPurchase units each' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  [
                    if (_displayStoreName(entry.storeName) != null)
                      _displayStoreName(entry.storeName)!,
                    _formatDate(entry.recordedDate),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),

                if (entry.storeAddress != null &&
                    entry.storeAddress!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.storeAddress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================================
// CART PAGE
// ============================================================================

enum _CheckoutPaymentMode { single, split }

class _PaymentLineDraft {
  String? accountId;
  final TextEditingController amountController;

  _PaymentLineDraft({this.accountId, required String amountText})
    : amountController = TextEditingController(text: amountText);

  void dispose() {
    amountController.dispose();
  }
}

class _CheckoutSelectionDialog extends ConsumerStatefulWidget {
  final int total;
  final int itemCount;
  final int totalQuantity;
  final String? storeName;
  final List<CartItem> items;

  const _CheckoutSelectionDialog({
    required this.total,
    required this.itemCount,
    required this.totalQuantity,
    required this.storeName,
    required this.items,
  });

  @override
  ConsumerState<_CheckoutSelectionDialog> createState() =>
      _CheckoutSelectionDialogState();
}

class _CheckoutSelectionDialogState
    extends ConsumerState<_CheckoutSelectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<_PaymentLineDraft> _paymentLines = [];

  DateTime _purchaseDate = DateTime.now();
  _CheckoutPaymentMode _paymentMode = _CheckoutPaymentMode.single;
  bool _initialized = false;

  int _parsePesos(String value) {
    final parsed = double.tryParse(
      value.replaceAll(',', '').replaceAll('₱', '').trim(),
    );
    if (parsed == null || parsed < 0) return 0;
    return (parsed * 100).round();
  }

  int get _paidCents => _paymentLines.fold<int>(
    0,
    (sum, line) => sum + _parsePesos(line.amountController.text),
  );

  int get _remainingCents => widget.total - _paidCents;

  @override
  void dispose() {
    for (final line in _paymentLines) {
      line.dispose();
    }
    super.dispose();
  }

  String _paymentAccountLabel(Account account) {
    final name = account.name.trim().isEmpty
        ? 'Payment account'
        : account.name.trim();
    final type = _paymentTypeLabel(account);
    return '$type • $name';
  }

  String _paymentTypeLabel(Account account) {
    final haystack = '${account.id} ${account.name}'
        .toLowerCase()
        .replaceAll('-', '')
        .replaceAll('_', ' ');

    if (haystack.contains('ewallet') ||
        haystack.contains('e wallet') ||
        haystack.contains('gcash') ||
        haystack.contains('maya') ||
        haystack.contains('gotyme')) {
      return 'E-Wallet';
    }

    if (haystack.contains('bank') ||
        haystack.contains('bdo') ||
        haystack.contains('bpi') ||
        haystack.contains('metrobank') ||
        haystack.contains('unionbank') ||
        haystack.contains('landbank') ||
        haystack.contains('rcbc') ||
        haystack.contains('security bank') ||
        haystack.contains('chinabank') ||
        haystack.contains('eastwest') ||
        haystack.contains('pnb') ||
        haystack.contains('aub')) {
      return 'Bank';
    }

    if (haystack.contains('cash')) return 'Cash';

    return 'Other';
  }

  IconData _paymentTypeIcon(Account account) {
    switch (_paymentTypeLabel(account)) {
      case 'Cash':
        return Icons.payments_outlined;
      case 'Bank':
        return Icons.account_balance_outlined;
      case 'E-Wallet':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  bool _isSupportedPaymentAccount(Account account) {
    final type = _paymentTypeLabel(account);
    return type == 'Cash' || type == 'Bank' || type == 'E-Wallet';
  }

  List<Account> _supportedAccounts(List<Account> accounts) {
    return accounts.where(_isSupportedPaymentAccount).toList(growable: false);
  }

  void _initializeLines(List<Account> accounts) {
    if (_initialized || accounts.isEmpty) return;

    _initialized = true;
    _paymentLines.add(
      _PaymentLineDraft(
        accountId: accounts.first.id,
        amountText: (widget.total / 100).toStringAsFixed(2),
      ),
    );
  }

  void _setPaymentMode(_CheckoutPaymentMode mode, List<Account> accounts) {
    if (mode == _CheckoutPaymentMode.single) {
      final first = accounts.first;
      setState(() {
        _paymentMode = mode;
        for (final line in _paymentLines.skip(1)) {
          line.dispose();
        }
        _paymentLines.removeRange(1, _paymentLines.length);
        _paymentLines.first
          ..accountId = first.id
          ..amountController.text = (widget.total / 100).toStringAsFixed(2);
      });
      return;
    }

    setState(() => _paymentMode = mode);
  }

  void _addPaymentLine(List<Account> accounts) {
    final usedAccountIds = _paymentLines
        .map((line) => line.accountId)
        .whereType<String>()
        .toSet();

    Account? nextAccount;
    for (final account in accounts) {
      if (!usedAccountIds.contains(account.id)) {
        nextAccount = account;
        break;
      }
    }

    if (nextAccount == null) return;

    final remaining = _remainingCents > 0 ? _remainingCents : 0;

    setState(() {
      _paymentLines.add(
        _PaymentLineDraft(
          accountId: nextAccount!.id,
          amountText: (remaining / 100).toStringAsFixed(2),
        ),
      );
    });
  }

  void _removePaymentLine(int index) {
    if (_paymentLines.length <= 1) return;

    setState(() {
      final removed = _paymentLines.removeAt(index);
      removed.dispose();
      if (_paymentLines.length == 1) {
        _paymentMode = _CheckoutPaymentMode.single;
        _paymentLines.first.amountController.text = (widget.total / 100)
            .toStringAsFixed(2);
      }
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null && mounted) {
      setState(() => _purchaseDate = selected);
    }
  }

  String _quantityText(CartItem item) {
    if (item.isWeighted) {
      final weight = NumberFormat('#,##0.###').format(item.weightQuantity);
      final unit = item.unit?.trim();
      return '$weight ${unit?.isNotEmpty == true ? unit : 'kg'}';
    }

    final quantity = item.quantity;
    final unit = item.unit?.trim();
    return '$quantity${unit?.isNotEmpty == true ? ' × $unit' : ''}';
  }

  String _unitPriceText(CartItem item) {
    final unit = item.unit?.trim();
    if (item.isWeighted) {
      return '${_peso(item.unitPrice)}/${unit?.isNotEmpty == true ? unit : 'kg'}';
    }
    return _peso(item.unitPrice);
  }

  Widget _receiptItem(CartItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quantity = _quantityText(item);
    final unitPrice = _unitPriceText(item);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(
              item.isWeighted
                  ? Icons.scale_outlined
                  : Icons.inventory_2_outlined,
              size: 19,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name.trim().isEmpty ? 'Item' : item.name.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.brand?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.brand!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '$quantity · $unitPrice each',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _peso(item.lineTotal),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentLineCard({
    required List<Account> accounts,
    required int index,
    required bool allowRemove,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = _paymentLines[index];
    final selectedAccount = accounts.cast<Account?>().firstWhere(
      (account) => account?.id == line.accountId,
      orElse: () => null,
    );

    final selectedAccountId = selectedAccount?.id;
    final alreadyUsedIds = _paymentLines
        .where((other) => !identical(other, line))
        .map((other) => other.accountId)
        .whereType<String>()
        .toSet();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  allowRemove ? 'Payment ${index + 1}' : 'Payment method',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (allowRemove)
                IconButton(
                  tooltip: 'Remove payment',
                  onPressed: () => _removePaymentLine(index),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: selectedAccountId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              helperText: 'Cash, Bank, or E-Wallet account',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            items: accounts.map((account) {
              final alreadyUsedElsewhere = alreadyUsedIds.contains(account.id);

              return DropdownMenuItem<String>(
                value: account.id,
                enabled: !alreadyUsedElsewhere,
                child: Row(
                  children: [
                    Icon(
                      _paymentTypeIcon(account),
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _paymentAccountLabel(account),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => line.accountId = value);
            },
            validator: (value) =>
                value == null ? 'Select a payment method' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: line.amountController,
            readOnly: _paymentMode == _CheckoutPaymentMode.single,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₱ ',
              suffixText: _paymentMode == _CheckoutPaymentMode.single
                  ? 'Full total'
                  : null,
            ),
            validator: (value) {
              final amount = _parsePesos(value ?? '');
              return amount <= 0 ? 'Enter an amount' : null;
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryRow({
    required String label,
    required int amount,
    bool emphasize = false,
    Color? foreground,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          _peso(amount),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
            color: foreground,
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_remainingCents != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _remainingCents > 0
                ? 'Payment is short by ${_peso(_remainingCents)}.'
                : 'Payment exceeds the total by ${_peso(-_remainingCents)}.',
          ),
        ),
      );
      return;
    }

    final ids = <String>{};
    final payments = <ExpensePaymentSplit>[];

    for (final line in _paymentLines) {
      final accountId = line.accountId;
      if (accountId == null || !ids.add(accountId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Choose a different payment account for each split.'),
          ),
        );
        return;
      }

      final amount = _parsePesos(line.amountController.text);
      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Each payment amount must be greater than zero.'),
          ),
        );
        return;
      }

      payments.add(
        ExpensePaymentSplit(paymentAccountId: accountId, amount: amount),
      );
    }

    Navigator.pop(context, (payments: payments, date: _purchaseDate));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: accountsAsync.when(
            loading: () => const SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => SizedBox(
              height: 320,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to load payment accounts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ),
            data: (accounts) {
              final supportedAccounts = _supportedAccounts(accounts);

              if (supportedAccounts.isEmpty) {
                return SizedBox(
                  height: 320,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add an active Cash, Bank, or E-Wallet payment account before checkout.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ),
                );
              }

              _initializeLines(supportedAccounts);

              final paid = _paidCents;
              final remaining = _remainingCents;
              final overpaid = remaining < 0;
              final isFullyPaid = remaining == 0;
              final canSplit = supportedAccounts.length > 1;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.shopping_cart_checkout_rounded,
                            color: scheme.onPrimaryContainer,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Review & pay',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                '${widget.itemCount} line${widget.itemCount == 1 ? '' : 's'} · Review before confirming',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Purchase review',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '${widget.items.length} item${widget.items.length == 1 ? '' : 's'}',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                              if (widget.storeName != null &&
                                  widget.storeName!.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  widget.storeName!.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const Divider(height: 22),
                              ...widget.items.map(_receiptItem),
                              const Divider(height: 22),
                              _summaryRow(
                                label: 'Purchase total',
                                amount: widget.total,
                                emphasize: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Payment',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose how this purchase was paid. Split only when more than one account was used.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<_CheckoutPaymentMode>(
                          segments: const [
                            ButtonSegment(
                              value: _CheckoutPaymentMode.single,
                              icon: Icon(Icons.payments_outlined),
                              label: Text('Single payment'),
                            ),
                            ButtonSegment(
                              value: _CheckoutPaymentMode.split,
                              icon: Icon(Icons.call_split_rounded),
                              label: Text('Split payment'),
                            ),
                          ],
                          selected: {_paymentMode},
                          onSelectionChanged: canSplit
                              ? (selection) {
                                  _setPaymentMode(
                                    selection.first,
                                    supportedAccounts,
                                  );
                                }
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              ...List.generate(
                                _paymentLines.length,
                                (index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _paymentLineCard(
                                    accounts: supportedAccounts,
                                    index: index,
                                    allowRemove:
                                        _paymentMode ==
                                            _CheckoutPaymentMode.split &&
                                        _paymentLines.length > 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_paymentMode == _CheckoutPaymentMode.split) ...[
                          OutlinedButton.icon(
                            onPressed:
                                _paymentLines.length >=
                                        supportedAccounts.length ||
                                    _remainingCents <= 0
                                ? null
                                : () => _addPaymentLine(supportedAccounts),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add another payment'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isFullyPaid
                                ? scheme.primaryContainer.withValues(
                                    alpha: 0.62,
                                  )
                                : scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              _summaryRow(
                                label: 'Purchase total',
                                amount: widget.total,
                              ),
                              const SizedBox(height: 10),
                              _summaryRow(label: 'Paid', amount: paid),
                              const Divider(height: 24),
                              _summaryRow(
                                label: overpaid ? 'Overpayment' : 'Remaining',
                                amount: overpaid ? -remaining : remaining,
                                emphasize: true,
                                foreground: overpaid
                                    ? scheme.error
                                    : isFullyPaid
                                    ? scheme.primary
                                    : scheme.onSurface,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            'Purchase date · ${DateFormat('MMMM d, yyyy').format(_purchaseDate)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'TOTAL TO PAY',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.9,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _peso(widget.total),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: isFullyPaid && !overpaid ? _submit : null,
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text(
                            'Confirm payment',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  static const _addSeparateScannedLine = '__add_separate_scanned_line__';
  final _cartSearchController = TextEditingController();
  String _cartSearchQuery = '';

  Future<String?> _chooseScannedCartLine(
    Supply supply,
    List<CartItem> matchingLines,
  ) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Existing ${supply.name} lines'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final line in matchingLines)
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: Text(
                    line.isWeighted
                        ? '${line.weightQuantity} ${line.unit ?? ''}'.trim()
                        : '${line.quantity} ${line.unit ?? ''}'.trim(),
                  ),
                  subtitle: Text(_peso(line.lineTotal)),
                  onTap: () => Navigator.pop(dialogContext, line.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, _addSeparateScannedLine),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add separate line'),
          ),
        ],
      ),
    );
  }

  Future<void> _editScannedCartLine(CartItem line) async {
    final unitOptions = await PurchaseUnitOptions.load(
      db: ref.read(databaseProvider),
      supplyId: line.supplyId,
      currentUnit: line.unit,
      currentStockUnitsPerUnit: line.stockUnitsPerUnit,
    );
    if (!mounted || !context.mounted) return;
    final pricing = await showPurchaseLineEditorDialog(
      context,
      itemName: line.name,
      quantityLabel: line.isWeighted ? 'Weight' : 'Quantity',
      unit: line.unit ?? '',
      stockUnitsPerUnit: line.stockUnitsPerUnit,
      unitOptions: unitOptions,
      quantity: line.isWeighted
          ? line.weightQuantity
          : line.quantity.toDouble(),
      isWeighted: line.isWeighted,
      unitPriceCents: line.unitPrice,
      grossTotalCents: line.grossTotalCents,
      finalTotalCents: line.lineTotal,
      discountType: line.discountType,
      discountValue: line.discountValue,
      originalUnitPriceCents: line.anchorUnitPriceCents,
      originalStockUnitsPerUnit: line.anchorStockUnitsPerUnit,
    );
    if (!mounted || pricing == null) return;
    await ref
        .read(cartProvider.notifier)
        .updateLinePricing(line.id, pricing, isWeighted: line.isWeighted);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanned purchase line updated')),
    );
  }

  bool _saving = false;

  @override
  void dispose() {
    _cartSearchController.dispose();
    super.dispose();
  }

  Future<void> _confirmClearCart() async {
    if (ref.read(cartProvider).isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all items from this purchase?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear Cart'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await ref.read(cartProvider.notifier).clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not clear cart: $error')));
    }
  }

  Future<bool?> _showScannedSupplyConfirmation(
    BuildContext context, {
    required Supply supply,
    required String barcode,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final unitLabel = [
      if (supply.unitQuantity != null) '${supply.unitQuantity}',
      if (supply.unit != null && supply.unit!.trim().isNotEmpty) supply.unit!,
    ].join(' ');

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add item to cart?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.10,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          supply.name.trim().isEmpty
                              ? '?'
                              : supply.name.trim()[0].toUpperCase(),
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              supply.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (supply.brand != null &&
                                supply.brand!.trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                supply.brand!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onPrimaryContainer.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _ScannedSupplyDetailRow(
                  label: 'Price',
                  value: _peso(supply.currentPrice),
                  icon: Icons.payments_outlined,
                ),

                if (unitLabel.isNotEmpty)
                  _ScannedSupplyDetailRow(
                    label: 'Unit',
                    value: unitLabel,
                    icon: Icons.straighten_outlined,
                  ),

                _ScannedSupplyDetailRow(
                  label: 'Available stock',
                  value: '${supply.currentStock} ${supply.stockUnit}',
                  icon: Icons.inventory_2_outlined,
                ),

                _ScannedSupplyDetailRow(
                  label: 'Barcode',
                  value: barcode,
                  icon: Icons.qr_code_2_outlined,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Add to cart'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _scanSupplyBarcode() async {
    final scannedBarcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (!mounted || scannedBarcode == null) {
      return;
    }

    final normalizedBarcode = SupplyCatalogService.normalizeBarcode(
      scannedBarcode,
    );

    if (normalizedBarcode!.trim().isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No valid barcode was detected.'),
        ),
      );
      return;
    }

    final db = ref.read(databaseProvider);

    final supply =
        await (db.select(db.supplies)..where(
              (supply) =>
                  supply.businessId.equals(kCurrentBusinessId) &
                  supply.barcode.equals(normalizedBarcode) &
                  supply.isActive.equals(true),
            ))
            .getSingleOrNull();

    if (!mounted) {
      return;
    }

    if (supply == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'No catalog item was found for barcode $normalizedBarcode.',
          ),
        ),
      );
      return;
    }

    final cartNotifier = ref.read(cartProvider.notifier);
    await cartNotifier.load();
    if (!mounted || !context.mounted) return;
    final matchingLines = ref
        .read(cartProvider)
        .where((line) => line.supplyId == supply.id)
        .toList();
    if (matchingLines.isNotEmpty) {
      final selectedLineId = await _chooseScannedCartLine(
        supply,
        matchingLines,
      );
      if (!mounted || selectedLineId == null) return;
      if (selectedLineId != _addSeparateScannedLine) {
        final selectedLine = matchingLines.firstWhere(
          (line) => line.id == selectedLineId,
        );
        try {
          await _editScannedCartLine(selectedLine);
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update cart line: $error')),
          );
        }
        return;
      }
    }

    final confirmed = await _showScannedSupplyConfirmation(
      context,
      supply: supply,
      barcode: normalizedBarcode,
    );

    if (!mounted || !context.mounted || confirmed != true) {
      return;
    }

    try {
      await ref.read(cartProvider.notifier).addOrIncrement(supply);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not save cart line: $error'),
        ),
      );
      return;
    }

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${supply.name} added to cart'),
        ),
      );
  }

  Future<void> _addCustomItem() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _AddCustomItemDialog(),
    );
  }

  Future<void> _saveCart() async {
    if (_saving) return;

    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    if (!_allowed(context, ref, _kCartPermission)) return;

    final total = ref.read(cartProvider.notifier).total;
    final draftNotifier = ref.read(cartProvider.notifier);
    final storeName = (draftNotifier.storeName ?? '').trim();
    final storeAddress = (draftNotifier.storeAddress ?? '').trim();

    // Payment selection happens before _saving is enabled and before any
    // database transaction starts. Closing/canceling checkout leaves the cart
    // completely untouched.
    final checkout =
        await showModalBottomSheet<
          ({List<ExpensePaymentSplit> payments, DateTime date})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _CheckoutSelectionDialog(
            total: total,
            itemCount: cart.length,
            totalQuantity: cart.fold<int>(
              0,
              (sum, item) => sum + item.quantity,
            ),
            storeName: storeName.isEmpty ? null : storeName,
            items: List<CartItem>.unmodifiable(cart),
          ),
        );

    if (!mounted || !context.mounted || checkout == null) return;

    setState(() => _saving = true);

    final payments = checkout.payments;
    final cartDate = checkout.date;
    final cartId = const Uuid().v4();

    try {
      final db = ref.read(databaseProvider);
      final audit = ref.read(auditLogServiceProvider);
      final branchId = ref.read(selectedBranchIdProvider);

      await db.transaction(() async {
        // ── Expense category ─────────────────────────────────────
        final allCategories =
            await (db.select(db.categories)..where(
                  (c) =>
                      c.businessId.equals(kCurrentBusinessId) &
                      c.txnType.equals('expense'),
                ))
                .get();

        if (allCategories.isEmpty) {
          throw StateError('No expense categories exist for this business.');
        }

        // Prefer the dedicated Supplies category; retain the existing first
        // expense-category fallback for databases created with older seeds.
        final category = allCategories.firstWhere(
          (c) => c.name.toLowerCase().contains('suppl'),
          orElse: () => allCategories.first,
        );
        final categoryId = category.id;

        // ── Validate the selected payment split again inside the same
        // transaction, immediately before writing anything. ────────────────
        if (payments.isEmpty) {
          throw StateError('At least one payment method is required.');
        }

        final selectedAccountIds = payments
            .map((payment) => payment.paymentAccountId)
            .toSet();

        if (selectedAccountIds.length != payments.length) {
          throw StateError(
            'A payment account cannot be used more than once in the same split.',
          );
        }

        final paidTotal = payments.fold<int>(
          0,
          (sum, payment) => sum + payment.amount,
        );

        if (paidTotal != total) {
          throw StateError(
            'Payment total (${_peso(paidTotal)}) does not match purchase total (${_peso(total)}).',
          );
        }

        if (payments.any((payment) => payment.amount <= 0)) {
          throw StateError('Each payment amount must be greater than zero.');
        }

        final selectedAccounts =
            await (db.select(db.accounts)..where(
                  (a) =>
                      a.businessId.equals(kCurrentBusinessId) &
                      a.isPaymentAccount.equals(true) &
                      a.isActive.equals(true) &
                      a.id.isIn(selectedAccountIds),
                ))
                .get();

        final selectedAccountIdSet = selectedAccounts
            .map((account) => account.id)
            .toSet();

        if (selectedAccountIdSet.length != selectedAccountIds.length) {
          throw StateError(
            'One or more selected payment accounts are no longer available.',
          );
        }

        // 1. Create cart header.
        await db
            .into(db.shoppingCarts)
            .insert(
              ShoppingCartsCompanion.insert(
                id: cartId,
                branchId: Value(branchId),
                businessId: kCurrentBusinessId,
                cartDate: cartDate,
                storeName: Value(storeName.isEmpty ? null : storeName),
                storeAddress: Value(storeAddress.isEmpty ? null : storeAddress),
                totalAmount: total,
              ),
            );

        // 2. Cart lines + stock.
        final costingService = ref.read(costingServiceProvider);
        for (final item in cart) {
          final purchasedItemId = const Uuid().v4();
          final purchasedQty = item.isWeighted
              ? item.weightQuantity
              : item.quantity.toDouble();

          await db
              .into(db.shoppingCartItems)
              .insert(
                ShoppingCartItemsCompanion.insert(
                  id: purchasedItemId,
                  cartId: cartId,
                  supplyId: Value(item.supplyId),
                  itemName: item.name,
                  brand: Value(item.brand),
                  unitQuantity: Value(item.unitQuantity),
                  unit: Value(item.unit),
                  unitPrice: item.unitPrice,
                  quantity: Value(item.isWeighted ? 1 : item.quantity),
                  isWeighted: Value(item.isWeighted),
                  weightQuantity: Value(
                    item.isWeighted ? item.weightQuantity : null,
                  ),
                  stockUnitsPerUnit: Value(item.stockUnitsPerUnit),
                  grossLineTotal: Value(item.grossTotalCents),
                  discountType: Value(item.discountType),
                  discountValue: Value(item.discountValue),
                  discountAmount: Value(item.discountAmountCents),
                  lineTotal: item.lineTotal,
                  originalUnitPrice: Value(item.originalUnitPrice),
                  originalStockUnitsPerUnit: Value(
                    item.originalStockUnitsPerUnit,
                  ),
                ),
              );

          if (item.supplyId != null) {
            final supply = await (db.select(
              db.supplies,
            )..where((s) => s.id.equals(item.supplyId!))).getSingleOrNull();

            if (supply != null) {
              final lineUnit = (item.unit ?? '').trim().isNotEmpty
                  ? item.unit!.trim()
                  : ((supply.purchaseUnit ?? '').trim().isNotEmpty
                        ? supply.purchaseUnit!.trim()
                        : supply.stockUnit);
              final unitsPerPurchase = item.stockUnitsPerUnit > 0
                  ? item.stockUnitsPerUnit
                  : PurchaseStockConversion.baseUnitsPerLineUnit(
                      lineUnit: lineUnit,
                      stockUnit: supply.stockUnit,
                      purchaseUnit: supply.purchaseUnit,
                      configuredUnitsPerPurchase: supply.unitsPerPurchase > 0
                          ? supply.unitsPerPurchase
                          : 1.0,
                    );
              final updateSupplyReference =
                  PurchaseStockConversion.usesConfiguredPurchaseUnit(
                    lineUnit: lineUnit,
                    purchaseUnit: supply.purchaseUnit,
                  ) &&
                  (supply.unitsPerPurchase <= 0 ||
                      (unitsPerPurchase - supply.unitsPerPurchase).abs() <
                          0.0000001);

              await costingService.recordPurchase(
                supplyId: supply.id,
                pricePerPurchaseUnitCents: item.unitPrice,
                purchaseQuantity: purchasedQty,
                unitsPerPurchase: unitsPerPurchase,
                purchaseUnit: lineUnit,
                storeName: storeName.isEmpty ? 'Unspecified' : storeName,
                date: cartDate,
                notes: 'Cart checkout',
                shoppingCartItemId: purchasedItemId,
                actualTotalPriceCents: item.lineTotal,
                updateSupplyReferenceFields: updateSupplyReference,
              );
            }
          }
        }

        // 3. Post one journal entry with one expense debit and one credit
        // line per selected payment account. This preserves split payments
        // as one balanced financial transaction.
        final expenseId = const Uuid().v4();
        final journalId = const Uuid().v4();

        await db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: journalId,
                businessId: kCurrentBusinessId,
                entryDate: cartDate,
                description: const Value('Supplies purchase'),
                sourceType: 'expense',
                sourceId: Value(expenseId),
                status: const Value('completed'),
              ),
            );

        await db
            .into(db.ledgerLines)
            .insert(
              LedgerLinesCompanion.insert(
                id: const Uuid().v4(),
                journalEntryId: journalId,
                accountId: category.ledgerAccountId,
                debit: Value(total),
                credit: const Value(0),
              ),
            );

        for (final payment in payments) {
          await db
              .into(db.ledgerLines)
              .insert(
                LedgerLinesCompanion.insert(
                  id: const Uuid().v4(),
                  journalEntryId: journalId,
                  accountId: payment.paymentAccountId,
                  debit: const Value(0),
                  credit: Value(payment.amount),
                ),
              );
        }

        await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: expenseId,
                businessId: kCurrentBusinessId,
                expenseDate: cartDate,
                description: Value(
                  storeName.isEmpty
                      ? 'Supplies purchase'
                      : 'Supplies – $storeName',
                ),
                categoryId: categoryId,
                amount: total,
                paymentAccountId: Value(
                  payments.length == 1 ? payments.first.paymentAccountId : null,
                ),
                status: const Value('completed'),
                journalEntryId: Value(journalId),
              ),
            );

        await (db.update(db.shoppingCarts)..where((c) => c.id.equals(cartId)))
            .write(ShoppingCartsCompanion(expenseId: Value(expenseId)));
        await PurchaseDraftCartService(
          db,
        ).deleteDraftInTransaction(kCurrentBusinessId);

        final accountNames = {for (final a in selectedAccounts) a.id: a.name};
        await audit.record(
          AuditEvent(
            businessId: kCurrentBusinessId,
            module: AuditModule.inventory,
            actionType: AuditActionType.create,
            action: 'inventory.purchase_recorded',
            entityType: 'shopping_carts',
            entityId: cartId,
            entityLabel: storeName.isEmpty
                ? 'Supplies purchase'
                : 'Supplies – $storeName',
            after: {
              'total': total,
              'date': cartDate,
              'store': storeName,
              'expenseId': expenseId,
            },
            details: {
              'items': [
                for (final i in cart)
                  '${i.isWeighted ? _qty(i.weightQuantity) : i.quantity} '
                      '${i.unit ?? ''} ${i.name} — ${_peso(i.lineTotal)}',
              ],
              'payments': [
                for (final p in payments)
                  '${accountNames[p.paymentAccountId] ?? p.paymentAccountId}: '
                      '${_peso(p.amount)}',
              ],
            },
          ),
        );
      });

      if (!mounted || !context.mounted) return;

      // Reset _saving before any provider refresh or navigation. Never call
      // setState from finally after Navigator.pop() starts route teardown.
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Purchase recorded and stock updated.'),
        ),
      );

      ref.read(cartProvider.notifier).clearAfterCheckout();
      ref.read(ledgerVersionProvider.notifier).state++;
      ref.invalidate(suppliesProvider);
      ref.invalidate(purchaseHistoryProvider);

      Navigator.pop(context);
    } catch (error, stack) {
      debugPrint('Save cart failed: $error\n$stack');
      if (!mounted || !context.mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to save cart: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(canProvider(_kCartPermission))) {
      return const _NoAccessView(
        title: 'Purchasing is restricted',
        message: 'Your role can\'t build or record purchases.',
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final cartRestore = ref.watch(cartReadyProvider);
    if (cartRestore.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Restoring purchase...'),
            ],
          ),
        ),
      );
    }
    if (cartRestore.hasError) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => ref.invalidate(cartReadyProvider),
            child: const Text('Could not restore purchase. Retry'),
          ),
        ),
      );
    }

    ref.listen<AsyncValue<List<Supply>>>(suppliesProvider, (previous, next) {
      if (!mounted) return;

      final supplies = next.asData?.value;
      if (supplies == null) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          ref
              .read(cartProvider.notifier)
              .syncPricesFromSupplies(supplies)
              .catchError((Object _) {});
        } catch (_) {
          return;
        }
      });
    });

    final cart = ref.watch(cartProvider);
    final savedStoreName = ref.read(cartProvider.notifier).storeName;
    final savedStoreAddress = ref.read(cartProvider.notifier).storeAddress;

    final total = cart.fold<int>(0, (sum, item) => sum + item.lineTotal);

    final totalQuantity = cart.fold<int>(0, (sum, item) => sum + item.quantity);

    final visibleCart = <CartItem>[];
    for (final item in cart) {
      final metadata = item.supplyId == null
          ? null
          : ref.watch(cartSupplyProvider(item.supplyId!)).asData?.value;
      final supply = metadata?.supply;
      if (matchesPurchaseCartSearch(
        query: _cartSearchQuery,
        itemName: item.name,
        brand: item.brand ?? supply?.brand,
        category: metadata?.categoryName,
        barcode: supply?.barcode,
        store: savedStoreName ?? supply?.lastStoreName,
        address: savedStoreAddress ?? supply?.lastStoreAddress,
        unit: item.unit,
        finalTotalCents: item.lineTotal,
        unitPriceCents: item.unitPrice,
        grossTotalCents: item.grossTotalCents,
        discountCents: item.discountAmountCents,
        catalogPriceCents: supply?.currentPrice,
      )) {
        visibleCart.add(item);
      }
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shopping cart',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 2),
            Text(
              'Review your purchase',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear cart',
            onPressed: cart.isEmpty ? null : _confirmClearCart,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_cart_rounded,
                      size: 16,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${cart.length}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: cart.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shopping_cart_outlined,
                        size: 35,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your cart is empty',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Add supplies from your price catalog to build a purchase.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Browse supplies'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 170),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primaryContainer,
                        scheme.primaryContainer.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _CartSummaryMetric(
                          icon: Icons.shopping_basket_outlined,
                          label: 'Lines',
                          value: '${cart.length}',
                        ),
                      ),
                      _CartSummaryDivider(color: scheme.onPrimaryContainer),
                      Expanded(
                        child: _CartSummaryMetric(
                          icon: Icons.layers_outlined,
                          label: 'Quantity',
                          value: '$totalQuantity',
                        ),
                      ),
                      _CartSummaryDivider(color: scheme.onPrimaryContainer),
                      Expanded(
                        child: _CartSummaryMetric(
                          icon: Icons.payments_outlined,
                          label: 'Total',
                          value: _peso(total),
                          emphasize: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SizedBox(height: 8),
                TextField(
                  controller: _cartSearchController,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) =>
                      setState(() => _cartSearchQuery = value),
                  decoration: InputDecoration(
                    labelText: 'Search cart',
                    hintText: 'Name, price, category, brand, barcode, or store',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _cartSearchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear cart search',
                            onPressed: () => setState(() {
                              _cartSearchController.clear();
                              _cartSearchQuery = '';
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                if (visibleCart.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      _cartSearchQuery.trim().isEmpty
                          ? 'No purchase lines.'
                          : 'No cart lines match "${_cartSearchQuery.trim()}".',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ...visibleCart.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CartItemTile(
                      key: ValueKey(
                        '${item.id}|${item.name}|${item.brand}|${item.unit}',
                      ),
                      item: item,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _addCustomItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add custom item'),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _scanSupplyBarcode,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan item'),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _peso(total),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveCart,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _saving ? 'Saving...' : 'Save & Record',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ============================================================================
// TEXT ENTRY DIALOG — owns its own TextEditingController so disposal
// is tied to this State's lifecycle (framework disposes it only once
// the dialog route is actually removed), instead of a caller manually
// calling controller.dispose() right after `await showDialog(...)`
// resolves — which races the dialog's close animation and can leave
// the still-rendering TextField pointed at an already-disposed
// controller (FlutterError: "used after being disposed").
// ============================================================================

class _TextEntryDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initialText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  /// Returns an error message to show (and block save) or null if valid.
  final String? Function(String value)? validate;

  const _TextEntryDialog({
    required this.title,
    required this.label,
    required this.initialText,
    this.keyboardType,
    this.validate,
  }) : textCapitalization = TextCapitalization.none;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validate?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: widget.label, errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

// ============================================================================
// ADD CUSTOM ITEM DIALOG — owns its own controllers (see _TextEntryDialog
// for why manual dispose-after-await is unsafe).
// ============================================================================

class _AddCustomItemDialog extends ConsumerStatefulWidget {
  const _AddCustomItemDialog();

  @override
  ConsumerState<_AddCustomItemDialog> createState() =>
      _AddCustomItemDialogState();
}

class _AddCustomItemDialogState extends ConsumerState<_AddCustomItemDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _unitController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final normalized = _priceController.text.replaceAll(',', '').trim();
    final price = double.tryParse(normalized);

    if (name.isEmpty || price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid item name and price.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      await ref
          .read(cartProvider.notifier)
          .addCustomItem(
            name: name,
            unitPrice: (price * 100).round(),
            unit: _unitController.text.trim().isEmpty
                ? null
                : _unitController.text.trim(),
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save cart line: $error')),
      );
      return;
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add custom item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Item name',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Unit price',
                prefixText: '₱ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Unit',
                hintText: 'Optional',
                prefixIcon: Icon(Icons.straighten_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

// ============================================================================
// CART SUMMARY HELPERS
// ============================================================================

class _CartSummaryDivider extends StatelessWidget {
  final Color color;

  const _CartSummaryDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: color.withValues(alpha: 0.18),
    );
  }
}

class _CartSummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;

  const _CartSummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: scheme.onPrimaryContainer),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontSize: emphasize ? 15 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: scheme.onPrimaryContainer.withValues(alpha: 0.72),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CART ITEM TILE
// ============================================================================

class _CartItemTile extends ConsumerStatefulWidget {
  final CartItem item;

  const _CartItemTile({super.key, required this.item});

  @override
  ConsumerState<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends ConsumerState<_CartItemTile> {
  // Controls whether category / current stock / unit price are shown
  // on this tile. Defaults to hidden for a more compact card; the user
  // can reveal them per item via the dropdown toggle.
  bool _showDetails = false;

  CartItem get item => widget.item;

  Future<void> _updatePurchaseRecord(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final supplyId = item.supplyId;

    if (supplyId == null || item.checked) {
      return;
    }

    final db = ref.read(databaseProvider);

    final supply = await (db.select(
      db.supplies,
    )..where((supply) => supply.id.equals(supplyId))).getSingleOrNull();

    if (!context.mounted) {
      return;
    }

    if (supply == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('This supply is no longer available.'),
        ),
      );
      return;
    }

    final result = await showPurchaseEntrySheet(context, supply: supply);

    // Force catalog providers to refetch after the sheet closes.
    ref.invalidate(cartSupplyProvider(supplyId));
    ref.invalidate(suppliesProvider);
    ref.invalidate(priceHistoryProvider(supplyId));
    ref.read(ledgerVersionProvider.notifier).state++;

    if (result != null) {
      await ref
          .read(cartProvider.notifier)
          .applyPurchaseEntry(
            supplyId: result.supplyId,
            priceCents: result.priceCents,
            name: result.name,
            brand: result.brand,
            unit: result.purchaseUnit,
            unitQuantity: result.unitsPerPurchase,
            stockUnitsPerUnit: result.unitsPerPurchase,
            previousPriceCents: supply.currentPrice,
            previousUnitsPerPurchase: supply.unitsPerPurchase,
            isSoldByWeight: result.isSoldByWeight,
          );
    } else {
      // Saved without a typed result (or sheet dismissed after save).
      final updated = await (db.select(
        db.supplies,
      )..where((s) => s.id.equals(supplyId))).getSingleOrNull();
      if (updated != null) {
        final resolvedUnit = () {
          final u = (updated.unit ?? '').trim();
          if (u.isNotEmpty) return u;
          final purchase = (updated.purchaseUnit ?? '').trim();
          if (purchase.isNotEmpty) return purchase;
          final stock = updated.stockUnit.trim();
          return stock.isEmpty ? null : stock;
        }();
        await ref
            .read(cartProvider.notifier)
            .applyPurchaseEntry(
              supplyId: updated.id,
              priceCents: updated.currentPrice,
              name: updated.name,
              brand: updated.brand,
              unit: resolvedUnit,
              unitQuantity:
                  updated.unitQuantity ??
                  (updated.unitsPerPurchase > 0
                      ? updated.unitsPerPurchase
                      : null),
              stockUnitsPerUnit: updated.unitsPerPurchase,
              previousPriceCents: supply.currentPrice,
              previousUnitsPerPurchase: supply.unitsPerPurchase,
              isSoldByWeight: updated.isSoldByWeight,
            );
      }
    }
  }

  Future<void> _editPrice(BuildContext context, WidgetRef ref) async {
    if (item.checked) return;
    final unitOptions = await PurchaseUnitOptions.load(
      db: ref.read(databaseProvider),
      supplyId: item.supplyId,
      currentUnit: item.unit,
      currentStockUnitsPerUnit: item.stockUnitsPerUnit,
    );
    if (!context.mounted) return;
    final pricing = await showPurchaseLineEditorDialog(
      context,
      itemName: item.name,
      quantityLabel: item.isWeighted ? 'Weight' : 'Quantity',
      unit: item.unit ?? '',
      stockUnitsPerUnit: item.stockUnitsPerUnit,
      unitOptions: unitOptions,
      quantity: item.isWeighted
          ? item.weightQuantity
          : item.quantity.toDouble(),
      isWeighted: item.isWeighted,
      unitPriceCents: item.unitPrice,
      grossTotalCents: item.grossTotalCents,
      finalTotalCents: item.lineTotal,
      discountType: item.discountType,
      discountValue: item.discountValue,
      originalUnitPriceCents: item.anchorUnitPriceCents,
      originalStockUnitsPerUnit: item.anchorStockUnitsPerUnit,
    );
    if (pricing == null) return;
    await ref
        .read(cartProvider.notifier)
        .updateLinePricing(item.id, pricing, isWeighted: item.isWeighted);
  }

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    await _editPrice(context, ref);
  }

  Future<void> _editWeight(BuildContext context, WidgetRef ref) async {
    if (item.checked) return;

    final cartNotifier = ref.read(cartProvider.notifier);
    final itemId = item.id;

    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextEntryDialog(
        title: 'Edit weight',
        label: 'Weight',
        initialText: item.weightQuantity == item.weightQuantity.roundToDouble()
            ? item.weightQuantity.toInt().toString()
            : item.weightQuantity.toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validate: (value) {
          final weight = double.tryParse(value.replaceAll(',', ''));
          if (weight == null || weight <= 0) return 'Enter a valid weight';
          return null;
        },
      ),
    );

    if (result != null) {
      await cartNotifier.updateWeight(
        itemId,
        double.parse(result.replaceAll(',', '')),
      );
    }
  }

  /// Asks the user to confirm removing this line. Returns true only if the
  /// line was actually removed.
  Future<bool> _confirmRemoveItem(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove this item?'),
        content: Text('Remove "${item.name}" from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await ref.read(cartProvider.notifier).removeItem(item.id);
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove cart line: $error')),
        );
      }
      return false;
    }
  }

  Widget _buildCartCard(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLocked = item.checked;

    // The selected unit and conversion belong to this cart line.
    if (item.supplyId != null) {
      ref.listen(cartSupplyProvider(item.supplyId!), (previous, next) {
        final supply = next.asData?.value?.supply;
        if (supply == null) return;

        final needsUpdate =
            supply.name != item.name || supply.brand != item.brand;

        if (needsUpdate) {
          ref
              .read(cartProvider.notifier)
              .applyPurchaseEntry(
                supplyId: supply.id,
                priceCents: item.unitPrice, // preserve the cart's own price
                name: supply.name,
                brand: supply.brand,
                isSoldByWeight: supply.isSoldByWeight,
              );
        }
      });
    }

    final lockedBackground = Colors.green.shade50;
    final lockedBorder = Colors.green.shade400;
    final lockedIconBackground = Colors.green.shade100;
    final lockedIconForeground = Colors.green.shade800;
    final lockedText = Colors.green.shade900;
    final lockedSubtle = Colors.green.shade800.withValues(alpha: 0.78);

    final liveMetaAsync = item.supplyId == null
        ? null
        : ref.watch(cartSupplyProvider(item.supplyId!));
    final liveSupply = liveMetaAsync?.asData?.value?.supply;

    final displayName = liveSupply?.name ?? item.name;
    final displayBrand = (liveSupply?.brand ?? item.brand)?.trim() ?? '';
    final displayLineTotal =
        item.lineTotal; // respects isWeighted + weightQuantity
    final displayQuantity = item.isWeighted
        ? item.weightQuantity
        : item.quantity.toDouble();
    final displayUnitPrice = displayQuantity > 0
        ? (displayLineTotal / displayQuantity).round()
        : 0;

    // Keep cart state aligned with catalog name/brand drift only — price
    // is never overwritten by this.
    if (liveSupply != null) {
      final drift =
          liveSupply.name != item.name || liveSupply.brand != item.brand;
      if (drift) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final resolvedUnit = () {
            final u = (liveSupply.unit ?? '').trim();
            if (u.isNotEmpty) return u;
            final purchase = (liveSupply.purchaseUnit ?? '').trim();
            if (purchase.isNotEmpty) return purchase;
            final stock = liveSupply.stockUnit.trim();
            return stock.isEmpty ? null : stock;
          }();
          ref
              .read(cartProvider.notifier)
              .applyPurchaseEntry(
                supplyId: liveSupply.id,
                priceCents: item.unitPrice,
                name: liveSupply.name,
                brand: liveSupply.brand,
                unit: resolvedUnit,
                unitQuantity:
                    liveSupply.unitQuantity ??
                    (liveSupply.unitsPerPurchase > 0
                        ? liveSupply.unitsPerPurchase
                        : null),
              );
        });
      }
    }

    final initials = displayName.trim().isEmpty
        ? '?'
        : displayName.trim()[0].toUpperCase();

    final metadataAsync = item.supplyId == null
        ? null
        : ref.watch(cartSupplyProvider(item.supplyId!));
    final metadata = metadataAsync?.asData?.value;
    final supply = metadata?.supply;
    final categoryName = item.supplyId == null
        ? 'Custom item'
        : (metadata?.categoryName?.isNotEmpty == true
              ? metadata!.categoryName!
              : 'Uncategorized');

    final resolvedUnitQty =
        item.unitQuantity ??
        supply?.unitQuantity ??
        (supply != null &&
                supply.unitsPerPurchase > 0 &&
                (supply.purchaseUnit?.trim().isNotEmpty ?? false)
            ? supply.unitsPerPurchase
            : null);
    final resolvedUnit = () {
      final fromItem = (item.unit ?? '').trim();
      if (fromItem.isNotEmpty) return fromItem;
      if (supply == null) return '';
      final purchase = (supply.purchaseUnit ?? '').trim();
      if (purchase.isNotEmpty) return purchase;
      final catalogUnit = (supply.unit ?? '').trim();
      if (catalogUnit.isNotEmpty) return catalogUnit;
      return _displayStockUnit(supply).trim();
    }();
    final packParts = <String>[
      if (resolvedUnitQty != null)
        (resolvedUnitQty == resolvedUnitQty.roundToDouble()
            ? resolvedUnitQty.toInt().toString()
            : resolvedUnitQty.toString()),
      if (resolvedUnit.isNotEmpty) resolvedUnit,
    ];
    final packLabel = packParts.isEmpty
        ? ''
        : (packParts.length == 1 && resolvedUnit.isNotEmpty
              ? 'per $resolvedUnit'
              : 'per ${packParts.join(' ')}');

    final resolvedBrand = displayBrand.isNotEmpty
        ? displayBrand
        : (() {
            final fromItem = (item.brand ?? '').trim();
            if (fromItem.isNotEmpty) return fromItem;
            final fromSupply = (supply?.brand ?? '').trim();
            return fromSupply;
          })();

    final stockUnit = supply == null ? '' : _displayStockUnit(supply);
    final currentStock = supply == null
        ? null
        : _displayStockQuantity(supply, supply.currentStock);
    final stockShort =
        supply != null && supply.currentStock <= supply.minimumStock;
    final stockKnown = item.supplyId == null || metadataAsync?.hasValue == true;

    // Price trend vs catalog history (same / higher / lower)
    final historyAsync = item.supplyId == null
        ? null
        : ref.watch(priceHistoryProvider(item.supplyId!));
    final cartTrend =
        historyAsync?.maybeWhen(
          data: (history) => _trendFor(history),
          orElse: () => _Trend.none,
        ) ??
        _Trend.none;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLocked
              ? [lockedBackground, lockedBackground]
              : [
                  scheme.surface,
                  scheme.primaryContainer.withValues(alpha: 0.22),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isLocked
              ? lockedBorder.withValues(alpha: 0.85)
              : scheme.outlineVariant.withValues(alpha: 0.55),
          width: isLocked ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isLocked
                ? Colors.green.withValues(alpha: 0.08)
                : scheme.shadow.withValues(alpha: 0.035),
            blurRadius: isLocked ? 16 : 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 390;

          final identitySection = Row(
            crossAxisAlignment: CrossAxisAlignment.center, // was: .start
            children: [
              Checkbox(
                value: item.checked,
                visualDensity: VisualDensity.compact,
                onChanged: (_) async {
                  await ref.read(cartProvider.notifier).toggleChecked(item.id);
                },
              ),
              const SizedBox(width: 3),
              Container(
                width: narrow ? 44 : 48,
                height: narrow ? 44 : 48,
                decoration: BoxDecoration(
                  color: isLocked
                      ? lockedIconBackground
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(narrow ? 13 : 15),
                ),
                alignment: Alignment.center,
                child: isLocked
                    ? Icon(
                        Icons.check_rounded,
                        color: lockedIconForeground,
                        size: narrow ? 23 : 25,
                      )
                    : Text(
                        initials,
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                          fontSize: narrow ? 17 : 18,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              // was: titleSmall
                              color: isLocked ? lockedText : null,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              fontSize: narrow
                                  ? 15
                                  : 17, // was: narrow ? 13 : null
                            ),
                          ),
                          if (resolvedBrand.isNotEmpty) ...[
                            TextSpan(
                              text: ' · ',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                // was: bodySmall
                                color: isLocked
                                    ? lockedSubtle
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: resolvedBrand,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                // was: bodySmall
                                color: isLocked
                                    ? lockedSubtle
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: narrow
                                    ? 12
                                    : 13, // was: narrow ? 11 : null
                              ),
                            ),
                          ],
                          if (packLabel.isNotEmpty) ...[
                            TextSpan(
                              text: ' · ',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isLocked
                                    ? lockedSubtle
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: packLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                // was: labelMedium
                                color: isLocked
                                    ? lockedSubtle
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: narrow
                                    ? 12
                                    : 13, // was: narrow ? 11 : null
                              ),
                            ),
                          ],
                        ],
                      ),
                      maxLines: narrow ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.isWeighted) ...[
                      const SizedBox(height: 4),
                      _WeightBadge(
                        unit: resolvedUnit.isEmpty
                            ? (item.unit ?? '')
                            : resolvedUnit,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final lockedBadge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: lockedIconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 12, color: lockedIconForeground),
                const SizedBox(width: 4),
                Text(
                  'Locked',
                  style: TextStyle(
                    color: lockedIconForeground,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );

          // Price/trend line — its own row, under identity, always visible.
          final priceLine = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isLocked) ...[lockedBadge, const SizedBox(width: 8)],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (cartTrend != _Trend.none) ...[
                        _TrendBadge(trend: cartTrend),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _peso(displayLineTotal),
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.titleLarge?.copyWith(
                          // was: titleMedium
                          color: isLocked ? lockedText : null,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          fontSize: narrow ? 17 : 19, // was: narrow ? 15 : null
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'line total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isLocked ? lockedSubtle : scheme.onSurfaceVariant,
                      fontSize: narrow ? 10 : null,
                    ),
                  ),
                  if (item.discountAmountCents > 0)
                    Text(
                      'Gross ${_peso(item.grossTotalCents)} · Discount -${_peso(item.discountAmountCents)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isLocked
                            ? lockedSubtle
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          );

          // Unit price — now lives behind the details toggle. Tapping it
          // opens the same edit dialog as before.
          Widget unitPriceRow() {
            final foreground = isLocked ? lockedText : scheme.onSurface;
            final background = isLocked
                ? Colors.green.shade50
                : scheme.surfaceContainerLow;
            final border = isLocked
                ? Colors.green.shade200
                : scheme.outlineVariant.withValues(alpha: 0.45);

            return Opacity(
              opacity: isLocked ? 0.62 : 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLocked ? null : () => _editPrice(context, ref),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 16,
                          color: foreground.withValues(alpha: 0.72),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Effective unit cost',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _peso(displayUnitPrice),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit_outlined,
                          size: 15,
                          color: foreground.withValues(alpha: 0.85),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              narrow ? 10 : 12,
              narrow ? 10 : 12,
              narrow ? 10 : 12,
              narrow ? 11 : 13,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Line 1 — identity only.
                identitySection,

                // Line 2 — trend + total, always visible.
                const SizedBox(height: 10),
                priceLine,

                // Tappable divider (dropdown) — reveals category, stock,
                // and unit price.
                const SizedBox(height: 4),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() => _showDetails = !_showDetails);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: isLocked
                                  ? Colors.green.shade200
                                  : scheme.outlineVariant.withValues(
                                      alpha: 0.55,
                                    ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _showDetails
                                      ? 'Hide details'
                                      : 'Details & price',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isLocked
                                        ? lockedSubtle
                                        : scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                AnimatedRotation(
                                  turns: _showDetails ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Icon(
                                    Icons.expand_more_rounded,
                                    size: 20,
                                    color: isLocked
                                        ? lockedSubtle
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: isLocked
                                  ? Colors.green.shade200
                                  : scheme.outlineVariant.withValues(
                                      alpha: 0.55,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_showDetails) ...[
                  const SizedBox(height: 6),
                  if (narrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CartDetailChip(
                          icon: Icons.category_outlined,
                          label: 'Category',
                          value: categoryName,
                          locked: isLocked,
                        ),
                        const SizedBox(height: 7),
                        _CartDetailChip(
                          icon: Icons.inventory_2_outlined,
                          label: stockShort ? 'Stock short' : 'Current stock',
                          value: !stockKnown
                              ? 'Loading…'
                              : currentStock == null
                              ? 'Not tracked'
                              : '${currentStock.toStringAsFixed(currentStock == currentStock.roundToDouble() ? 0 : 1)}${stockUnit.isEmpty ? '' : ' $stockUnit'}',
                          locked: isLocked,
                          warning: stockShort,
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _CartDetailChip(
                          icon: Icons.category_outlined,
                          label: 'Category',
                          value: categoryName,
                          locked: isLocked,
                        ),
                        _CartDetailChip(
                          icon: Icons.inventory_2_outlined,
                          label: stockShort ? 'Stock short' : 'Current stock',
                          value: !stockKnown
                              ? 'Loading…'
                              : currentStock == null
                              ? 'Not tracked'
                              : '${currentStock.toStringAsFixed(currentStock == currentStock.roundToDouble() ? 0 : 1)}${stockUnit.isEmpty ? '' : ' $stockUnit'}',
                          locked: isLocked,
                          warning: stockShort,
                        ),
                      ],
                    ),

                  const SizedBox(height: 10),
                  unitPriceRow(),

                  if (item.supplyId != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: isLocked
                          ? null
                          : () => _updatePurchaseRecord(context, ref),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(
                        isLocked
                            ? 'Purchase record locked'
                            : 'Update purchase record',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                ],

                Divider(
                  height: 1,
                  color: isLocked
                      ? Colors.green.shade200
                      : scheme.outlineVariant.withValues(alpha: 0.45),
                ),
                const SizedBox(height: 12),

                // Quantity — always visible, independent of the toggle.
                Opacity(
                  opacity: isLocked ? 0.62 : 1,
                  child: IgnorePointer(
                    ignoring: isLocked,
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isLocked
                              ? null
                              : () => _editPrice(context, ref),
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Edit line'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (item.isWeighted)
                          _WeightControl(
                            weight: item.weightQuantity,
                            unit: resolvedUnit.isEmpty
                                ? (item.unit ?? '')
                                : resolvedUnit,
                            onDecrease: () async {
                              final next = item.weightQuantity - 0.10;
                              if (next <= 0) {
                                await _confirmRemoveItem(context, ref);
                                return;
                              }
                              await ref
                                  .read(cartProvider.notifier)
                                  .updateWeight(item.id, next);
                            },
                            onIncrease: () async {
                              await ref
                                  .read(cartProvider.notifier)
                                  .updateWeight(
                                    item.id,
                                    item.weightQuantity + 0.25,
                                  );
                            },
                            onTapWeight: () => _editWeight(context, ref),
                          )
                        else
                          _QuantityControl(
                            quantity: item.quantity,
                            onDecrease: () async {
                              // At 1, reducing would delete the line, so ask first.
                              if (item.quantity <= 1) {
                                await _confirmRemoveItem(context, ref);
                                return;
                              }
                              await ref
                                  .read(cartProvider.notifier)
                                  .updateQuantity(item.id, item.quantity - 1);
                            },
                            onIncrease: () async {
                              await ref
                                  .read(cartProvider.notifier)
                                  .updateQuantity(item.id, item.quantity + 1);
                            },
                            onTapQuantity: () => _editQuantity(context, ref),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = _buildCartCard(context, ref);

    // A checked cart item is locked: it can only be unchecked or left alone.
    // It cannot be edited, updated, or removed by swipe.
    if (item.checked) {
      return card;
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Remove this item?'),
            content: Text('Remove "${item.name}" from your cart?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;
        try {
          await ref.read(cartProvider.notifier).removeItem(item.id);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not remove cart line: $error')),
            );
          }
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: scheme.onErrorContainer,
          size: 27,
        ),
      ),
      child: card,
    );
  }
}
// ============================================================================
// CART DETAIL CHIP
// ============================================================================

class _CartDetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool locked;
  final bool warning;

  const _CartDetailChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.locked,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = warning
        ? scheme.error
        : locked
        ? Colors.green.shade900
        : scheme.onSurfaceVariant;
    final background = warning
        ? scheme.errorContainer.withValues(alpha: 0.72)
        : locked
        ? Colors.green.shade50
        : scheme.surfaceContainerLow;

    return Container(
      constraints: const BoxConstraints(minWidth: 125),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: warning
              ? scheme.error.withValues(alpha: 0.2)
              : locked
              ? Colors.green.shade200
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.72),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// QUANTITY CONTROL
// ============================================================================

class _QuantityControl extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onTapQuantity;

  const _QuantityControl({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    required this.onTapQuantity,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease',
            visualDensity: VisualDensity.compact,
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          InkWell(
            onTap: onTapQuantity,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Text(
                '$quantity',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase',
            visualDensity: VisualDensity.compact,
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _WeightBadge extends StatelessWidget {
  final String unit;
  const _WeightBadge({required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.scale_outlined, size: 11, color: Colors.blue.shade800),
          const SizedBox(width: 4),
          Text(
            unit.isEmpty ? 'Sold by weight' : 'Sold by weight ($unit)',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.blue.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightControl extends StatelessWidget {
  final double weight;
  final String unit;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onTapWeight;

  const _WeightControl({
    required this.weight,
    required this.unit,
    required this.onDecrease,
    required this.onIncrease,
    required this.onTapWeight,
  });

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease',
            visualDensity: VisualDensity.compact,
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          InkWell(
            onTap: onTapWeight,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Text(
                '${_trim(weight)}${unit.isEmpty ? '' : ' $unit'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase',
            visualDensity: VisualDensity.compact,
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// STOCK ADJUSTMENT SHEET — the "pull-out edit": write off stock
// that's no longer sellable (damaged, expired, miscounted) without
// touching cost-per-unit, only quantity on hand.
// ============================================================

enum _AdjustmentReason { damaged, expired, miscount, other }

extension on _AdjustmentReason {
  String get label => switch (this) {
    _AdjustmentReason.damaged => 'Damaged',
    _AdjustmentReason.expired => 'Expired',
    _AdjustmentReason.miscount => 'Count correction',
    _AdjustmentReason.other => 'Other',
  };
  IconData get icon => switch (this) {
    _AdjustmentReason.damaged => Icons.broken_image_outlined,
    _AdjustmentReason.expired => Icons.event_busy_outlined,
    _AdjustmentReason.miscount => Icons.fact_check_outlined,
    _AdjustmentReason.other => Icons.help_outline_rounded,
  };
}

class StockAdjustmentSheet extends ConsumerStatefulWidget {
  final Supply supply;
  const StockAdjustmentSheet({super.key, required this.supply});

  @override
  ConsumerState<StockAdjustmentSheet> createState() =>
      _StockAdjustmentSheetState();
}

class _StockAdjustmentSheetState extends ConsumerState<StockAdjustmentSheet> {
  _AdjustmentReason _reason = _AdjustmentReason.damaged;
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final qty = double.tryParse(_quantityController.text);
    final resultingStock = qty == null
        ? null
        : widget.supply.currentStock - qty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Adjust Stock',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${widget.supply.name} · currently ${_trim(widget.supply.currentStock)} ${widget.supply.stockUnit} in stock',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),

              Text(
                'Reason',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _AdjustmentReason.values
                    .map(
                      (r) => ChoiceChip(
                        label: Text(r.label),
                        avatar: Icon(r.icon, size: 16),
                        selected: _reason == r,
                        onSelected: (_) => setState(() => _reason = r),
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.16,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity to remove',
                  suffixText: widget.supply.stockUnit,
                  prefixIcon: const Icon(Icons.remove_circle_outline),
                ),
                onChanged: (_) => setState(() {}),
              ),

              if (resultingStock != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        (resultingStock < 0
                                ? Colors.redAccent
                                : AppColors.primary)
                            .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    resultingStock < 0
                        ? 'That\'s more than what\'s currently in stock.'
                        : 'New stock after this: ${_trim(resultingStock)} ${widget.supply.stockUnit}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: resultingStock < 0
                          ? Colors.redAccent
                          : AppColors.primary,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Write Off Stock',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final qty = double.tryParse(_quantityController.text);
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a valid quantity.');
      return;
    }
    if (qty > widget.supply.currentStock) {
      setState(() => _error = 'Cannot remove more than what\'s in stock.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      ref
          .read(authorizationServiceProvider)
          .require(
            BosPermission.inventoryAdjust,
            businessId: kCurrentBusinessId,
          );
      final note = _noteController.text.trim();
      final reason = '${_reason.label}${note.isEmpty ? '' : ' — $note'}';

      // THE FIX (#4): capture what the Undo action needs BEFORE
      // popping this sheet — same "don't touch ref after the widget
      // might be gone" rule as the cart edit crash fix. The captured
      // service/notifier objects stay valid regardless of what
      // happens to this widget.
      final costingService = ref.read(costingServiceProvider);
      final ledgerNotifier = ref.read(ledgerVersionProvider.notifier);
      final messenger = ScaffoldMessenger.of(context);

      await costingService.adjustStock(
        supplyId: widget.supply.id,
        deltaBaseUnits: -qty,
        reason: reason,
      );
      ledgerNotifier.state++;

      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            content: Text(
              '${_trim(qty)} ${widget.supply.stockUnit} written off (${_reason.label})',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                await costingService.adjustStock(
                  supplyId: widget.supply.id,
                  deltaBaseUnits: qty, // reverse the write-off
                  reason: 'Undo: $reason',
                );
                ledgerNotifier.state++;
              },
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
