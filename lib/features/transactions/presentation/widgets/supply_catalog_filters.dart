import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/auth/authorization_providers.dart'
    show selectedBusinessIdProvider, authorizationServiceProvider;
import 'package:bos_application/features/transactions/domain/costing_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_draft_cart_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_cart_search.dart';
import 'package:bos_application/features/transactions/domain/purchase_line_pricing.dart';
import 'package:bos_application/features/transactions/domain/purchase_unit_options.dart';
import 'package:bos_application/features/transactions/domain/purchase_stock_conversion.dart';
import 'package:bos_application/features/transactions/domain/supply_catalog_service.dart';
import 'package:bos_application/features/transactions/domain/unit_options.dart';
import 'package:bos_application/features/transactions/presentation/screens/products_page.dart'
    hide costingServiceProvider;
import 'package:bos_application/features/transactions/presentation/screens/purchase_entry_sheet.dart';
import 'package:bos_application/features/transactions/presentation/widgets/supply_identity_fields.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/purchase_line_editor_dialog.dart';
import 'package:flutter/material.dart';
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
        transactionServiceProvider;

// ============================================================================
// HELPERS
// ============================================================================

String _peso(int cents) {
  return '₱${NumberFormat('#,##0.00').format(cents / 100)}';
}

String _formatDate(DateTime date) {
  return DateFormat('MMM d, yyyy').format(date);
}

String _formatDateShort(DateTime date) {
  return DateFormat('MMM d').format(date);
}

// ============================================================================
// SUPPLIES PROVIDERS
// ============================================================================

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

final cartLineSupplyProvider = FutureProvider.family<Supply?, String>((
  ref,
  supplyId,
) async {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.supplies,
  )..where((row) => row.id.equals(supplyId))).getSingleOrNull();
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
  final query =
      db.select(db.shoppingCarts).join([
          innerJoin(
            db.shoppingCartItems,
            db.shoppingCartItems.cartId.equalsExp(db.shoppingCarts.id),
          ),
        ])
        ..where(
          db.shoppingCarts.businessId.equals(kCurrentBusinessId) &
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

final priceHistoryProvider =
    StreamProvider.family<List<SupplyPriceHistoryData>, String>((
      ref,
      supplyId,
    ) {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);

      return (db.select(db.supplyPriceHistory)
            ..where((h) => h.supplyId.equals(supplyId))
            ..orderBy([
              (h) => OrderingTerm(
                expression: h.recordedDate,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();
    });

// ============================================================================
// SUPPLY LIST FILTERS (INLINE)
// ============================================================================

/// Sentinel used by the category filter for supplies that have no category.
const String kUncategorizedSupplyFilter = '__uncategorized__';

enum SupplyStockStatus { all, inStock, lowStock, outOfStock }

enum SupplySort { nameAsc, priceAsc, priceDesc, stockAsc, stockDesc }

class SupplyCatalogFilter {
  final SupplyStockStatus stockStatus;
  final String? categoryId;
  final String? storeName;
  final SupplySort sort;

  const SupplyCatalogFilter({
    this.stockStatus = SupplyStockStatus.all,
    this.categoryId,
    this.storeName,
    this.sort = SupplySort.nameAsc,
  });

  bool get hasActiveFilters =>
      stockStatus != SupplyStockStatus.all ||
      categoryId != null ||
      (storeName != null && storeName!.isNotEmpty);

  SupplyCatalogFilter copyWith({
    SupplyStockStatus? stockStatus,
    String? categoryId,
    bool clearCategory = false,
    String? storeName,
    bool clearStore = false,
    SupplySort? sort,
  }) {
    return SupplyCatalogFilter(
      stockStatus: stockStatus ?? this.stockStatus,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      storeName: clearStore ? null : (storeName ?? this.storeName),
      sort: sort ?? this.sort,
    );
  }
}

class SupplyCatalogFilterNotifier extends StateNotifier<SupplyCatalogFilter> {
  SupplyCatalogFilterNotifier() : super(const SupplyCatalogFilter());

  void setStockStatus(SupplyStockStatus status) {
    state = state.copyWith(stockStatus: status);
  }

  void setCategory(String? categoryId) {
    state = categoryId == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(categoryId: categoryId);
  }

  void setStore(String? storeName) {
    state = storeName == null || storeName.isEmpty
        ? state.copyWith(clearStore: true)
        : state.copyWith(storeName: storeName);
  }

  void setSort(SupplySort sort) {
    state = state.copyWith(sort: sort);
  }

  void clear() {
    state = const SupplyCatalogFilter();
  }
}

final supplyCatalogFilterProvider =
    StateNotifierProvider<SupplyCatalogFilterNotifier, SupplyCatalogFilter>(
      (ref) => SupplyCatalogFilterNotifier(),
    );

List<Supply> applySupplyFilters(
  List<Supply> supplies,
  SupplyCatalogFilter filter,
) {
  var result = supplies;

  switch (filter.stockStatus) {
    case SupplyStockStatus.all:
      break;
    case SupplyStockStatus.inStock:
      result = result.where((s) => s.currentStock > 0).toList();
      break;
    case SupplyStockStatus.lowStock:
      // Match items that are still on hand but at/below the configured
      // low level. Prefer lowStockThreshold (Low-stock alert); fall back
      // to minimumStock so either field works.
      result = result.where((s) {
        if (s.currentStock <= 0) return false;

        final alert = s.lowStockThreshold;
        if (alert != null && alert > 0 && s.currentStock <= alert) {
          return true;
        }

        if (s.minimumStock > 0 && s.currentStock <= s.minimumStock) {
          return true;
        }

        return false;
      }).toList();
      break;
    case SupplyStockStatus.outOfStock:
      result = result.where((s) => s.currentStock <= 0).toList();
      break;
  }

  final categoryId = filter.categoryId;
  if (categoryId != null) {
    if (categoryId == kUncategorizedSupplyFilter) {
      result = result
          .where((s) => s.categoryId == null || s.categoryId!.trim().isEmpty)
          .toList();
    } else {
      result = result.where((s) => s.categoryId == categoryId).toList();
    }
  }

  final store = filter.storeName?.trim();
  if (store != null && store.isNotEmpty) {
    result = result
        .where(
          (s) =>
              (s.lastStoreName ?? '').trim().toLowerCase() ==
              store.toLowerCase(),
        )
        .toList();
  }

  result.sort((a, b) {
    switch (filter.sort) {
      case SupplySort.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case SupplySort.priceAsc:
        return a.currentPrice.compareTo(b.currentPrice);
      case SupplySort.priceDesc:
        return b.currentPrice.compareTo(a.currentPrice);
      case SupplySort.stockAsc:
        return a.currentStock.compareTo(b.currentStock);
      case SupplySort.stockDesc:
        return b.currentStock.compareTo(a.currentStock);
    }
  });

  return result;
}

final supplyCategoryNamesProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final db = ref.watch(databaseProvider);

  final rows =
      await (db.select(db.productCategories)
            ..where(
              (category) => category.businessId.equals(kCurrentBusinessId),
            )
            ..orderBy([
              (category) => OrderingTerm.asc(category.sortOrder),
              (category) => OrderingTerm.asc(category.name),
            ]))
          .get();

  return <String, String>{
    for (final category in rows)
      category.id: category.name.trim().isEmpty
          ? 'Unnamed category'
          : category.name.trim(),
  };
});

bool supplyMatchesSearch(
  Supply supply,
  String rawQuery, {
  Map<String, String> categoryNames = const {},
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;

  final normalizedQuery = query.replaceAll(',', '').replaceAll('₱', '').trim();
  final categoryName = categoryNames[supply.categoryId] ?? '';
  final pricePesos = supply.currentPrice / 100;
  final formattedPrice = NumberFormat('#,##0.00').format(pricePesos);
  final compactPrice = formattedPrice.replaceAll(',', '');
  final wholePrice = pricePesos == pricePesos.roundToDouble()
      ? pricePesos.toInt().toString()
      : '';
  final fields = <String>[
    supply.name,
    supply.brand ?? '',
    categoryName,
    supply.barcode ?? '',
    supply.lastStoreName ?? '',
    supply.lastStoreAddress ?? '',
    supply.unit ?? '',
    supply.purchaseUnit ?? '',
    supply.stockUnit,
    '${supply.unitQuantity ?? ''}',
    formattedPrice,
    compactPrice,
    wholePrice,
    '${supply.currentPrice}',
  ];

  return fields.any((field) => field.toLowerCase().contains(query)) ||
      fields.any(
        (field) =>
            field.replaceAll(',', '').toLowerCase().contains(normalizedQuery),
      );
}

class SupplyFilterBar extends ConsumerWidget {
  final List<Supply> allSupplies;

  const SupplyFilterBar({super.key, required this.allSupplies});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(supplyCatalogFilterProvider);
    final notifier = ref.read(supplyCatalogFilterProvider.notifier);

    final categoryNamesAsync = ref.watch(supplyCategoryNamesProvider);
    final categoryNames = categoryNamesAsync.value ?? const <String, String>{};

    String categoryLabel(String categoryId) {
      final name = categoryNames[categoryId]?.trim();

      if (name == null || name.isEmpty) {
        // This prevents an orphaned category ID from being displayed directly.
        return 'Unknown category';
      }

      return name;
    }

    final stores =
        allSupplies
            .map((s) => (s.lastStoreName ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final usedCategoryIds = allSupplies
        .map((s) => s.categoryId)
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    usedCategoryIds.sort((a, b) {
      return categoryLabel(
        a,
      ).toLowerCase().compareTo(categoryLabel(b).toLowerCase());
    });

    final categoryItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('All categories'),
      ),
      for (final id in usedCategoryIds)
        DropdownMenuItem<String?>(
          value: id,
          child: Text(categoryLabel(id), overflow: TextOverflow.ellipsis),
        ),
      if (allSupplies.any(
        (s) => s.categoryId == null || s.categoryId!.trim().isEmpty,
      ))
        const DropdownMenuItem<String?>(
          value: kUncategorizedSupplyFilter,
          child: Text('Uncategorized'),
        ),
    ];

    final currentCategory =
        categoryItems.any((item) => item.value == filter.categoryId)
        ? filter.categoryId
        : null;
    debugPrint(
      'Supply category IDs: ${allSupplies.map((s) => s.categoryId).toList()}',
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
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
              Icon(Icons.filter_list_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 7),
              Text(
                'Filters',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (filter.hasActiveFilters)
                TextButton(
                  onPressed: notifier.clear,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              ChoiceChip(
                label: const Text('All stock'),
                selected: filter.stockStatus == SupplyStockStatus.all,
                onSelected: (_) =>
                    notifier.setStockStatus(SupplyStockStatus.all),
              ),
              ChoiceChip(
                label: const Text('In stock'),
                selected: filter.stockStatus == SupplyStockStatus.inStock,
                onSelected: (_) =>
                    notifier.setStockStatus(SupplyStockStatus.inStock),
              ),
              ChoiceChip(
                label: const Text('Low stock'),
                selected: filter.stockStatus == SupplyStockStatus.lowStock,
                onSelected: (_) =>
                    notifier.setStockStatus(SupplyStockStatus.lowStock),
              ),
              ChoiceChip(
                label: const Text('Out of stock'),
                selected: filter.stockStatus == SupplyStockStatus.outOfStock,
                onSelected: (_) =>
                    notifier.setStockStatus(SupplyStockStatus.outOfStock),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final width = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 10) / 2;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String?>(
                      initialValue: currentCategory,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: categoryItems,
                      onChanged: notifier.setCategory,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String?>(
                      initialValue: filter.storeName,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Store / supplier',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All stores'),
                        ),
                        for (final store in stores)
                          DropdownMenuItem<String?>(
                            value: store,
                            child: Text(store, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: notifier.setStore,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<SupplySort>(
                      initialValue: filter.sort,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sort',
                        prefixIcon: Icon(Icons.sort_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SupplySort.nameAsc,
                          child: Text('Name A–Z'),
                        ),
                        DropdownMenuItem(
                          value: SupplySort.priceAsc,
                          child: Text('Price: low to high'),
                        ),
                        DropdownMenuItem(
                          value: SupplySort.priceDesc,
                          child: Text('Price: high to low'),
                        ),
                        DropdownMenuItem(
                          value: SupplySort.stockAsc,
                          child: Text('Stock: low to high'),
                        ),
                        DropdownMenuItem(
                          value: SupplySort.stockDesc,
                          child: Text('Stock: high to low'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) notifier.setSort(value);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CART
// ============================================================================

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
  });

  int get lineTotal => totalPriceCents;

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

  CartNotifier(this._draftCartService, this.businessId) : super([]);

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
        ),
    ];
  }

  Future<void> _mutate(List<CartItem> Function(List<CartItem>) transform) {
    final operation = _writeQueue.then((_) async {
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
    final gross = (item.unitPrice * nextQuantity).round();
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
    return _mutate(
      (current) => [
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
          stockUnitsPerUnit:
              supply.purchaseUnit?.trim().isNotEmpty == true &&
                  supply.unitsPerPurchase > 0
              ? supply.unitsPerPurchase
              : 1,
          unitPrice: supply.currentPrice,
          quantity: 1,
          totalPriceCents: supply.currentPrice,
          grossTotalCents: supply.currentPrice,
          isWeighted: supply.isSoldByWeight,
          weightQuantity: 1.0,
        ),
      ],
    );
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
            item.copyWith(
              quantity: isWeighted ? item.quantity : pricing.quantity.toInt(),
              unit: pricing.unitName,
              stockUnitsPerUnit: pricing.stockUnitsPerUnit,
              weightQuantity: isWeighted
                  ? pricing.quantity
                  : item.weightQuantity,
              unitPrice: pricing.unitPriceCents,
              grossTotalCents: pricing.grossTotalCents,
              discountType: pricing.discountType,
              discountValue: pricing.discountValue,
              discountAmountCents: pricing.discountAmountCents,
              totalPriceCents: pricing.finalTotalCents,
            )
          else
            item,
      ],
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
  return CartNotifier(PurchaseDraftCartService(db), businessId);
});

final cartReadyProvider = FutureProvider<void>((ref) {
  return ref.watch(cartProvider.notifier).load();
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
    return applySupplyFilters(textMatches, filter);
  }

  Future<void> _refresh() async {
    ref.invalidate(suppliesProvider);

    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _openAddSupplySheet() {
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

    final suppliesAsync = ref.watch(suppliesProvider);
    final cart = ref.watch(cartProvider);

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
          IconButton(
            tooltip: 'Purchase history',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PurchaseHistoryPage()),
              );
            },
            icon: const Icon(Icons.history_rounded),
          ),
          _CartHeaderButton(
            itemCount: cart.length,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartPage()),
              );
            },
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

                        // ── Filters: stock status, categories, store, sort ──
                        SupplyFilterBar(allSupplies: supplies),

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
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddSupplySheet,
        child: const Icon(Icons.add_rounded),
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
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final historyAsync = ref.watch(purchaseHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Purchase history',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('Review items bought by date', style: TextStyle(fontSize: 11)),
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _SearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      _selectedDate == null
                          ? 'All dates'
                          : _formatDate(_selectedDate!),
                    ),
                  ),
                  if (_selectedDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Clear date filter',
                      onPressed: () => setState(() => _selectedDate = null),
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${filtered.length} checkout${filtered.length == 1 ? '' : 's'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                        Icons.history_rounded,
                        size: 42,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        records.isEmpty
                            ? 'No purchases recorded yet.'
                            : 'No purchases match these filters.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...filtered.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PurchaseHistoryCard(
                      checkout: record,
                      onDelete: () => _deleteCheckout(record),
                    ),
                  ),
                ),
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
          'This removes the checkout and its linked transaction from purchase history and the ledger.',
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
      final db = ref.read(databaseProvider);
      final expenseId = checkout.cart.expenseId;

      if (expenseId != null) {
        await ref.read(transactionServiceProvider).deleteExpense(expenseId);
      }

      await (db.delete(
        db.shoppingCarts,
      )..where((cart) => cart.id.equals(checkout.cart.id))).go();

      if (!mounted) return;

      ref.read(ledgerVersionProvider.notifier).state++;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Checkout deleted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete checkout: $error')),
      );
    }
  }
}

class _PurchaseHistoryCard extends StatelessWidget {
  final PurchaseHistoryCheckout checkout;
  final VoidCallback onDelete;

  const _PurchaseHistoryCard({required this.checkout, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cart = checkout.cart;
    final store = cart.storeName?.trim();
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PurchaseCheckoutDetailPage(checkout: checkout),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.receipt_long_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checkout ${cart.id.substring(0, 8).toUpperCase()}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${checkout.items.length} item${checkout.items.length == 1 ? '' : 's'} · ${_peso(cart.totalAmount)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _formatDate(cart.cartDate),
                        if (store != null && store.isNotEmpty) store,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Checkout actions',
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete checkout'),
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

class PurchaseCheckoutDetailPage extends StatelessWidget {
  final PurchaseHistoryCheckout checkout;

  const PurchaseCheckoutDetailPage({super.key, required this.checkout});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cart = checkout.cart;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Checkout ${cart.id.substring(0, 8).toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            [
              _formatDate(cart.cartDate),
              if (cart.storeName != null) cart.storeName!,
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ...checkout.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PurchaseHistoryItemCard(item: item),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total ${_peso(cart.totalAmount)}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseHistoryItemCard extends StatelessWidget {
  final ShoppingCartItem item;

  const _PurchaseHistoryItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unitLabel = [
      if (item.unitQuantity != null) '${item.unitQuantity}',
      if (item.unit != null && item.unit!.trim().isNotEmpty) item.unit!,
    ].join(' ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.brand != null && item.brand!.trim().isNotEmpty)
                  Text(item.brand!, style: theme.textTheme.bodySmall),
                Text(
                  '${item.quantity} × ${_peso(item.unitPrice)}${unitLabel.isEmpty ? '' : ' · $unitLabel'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _peso(item.lineTotal),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
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

  const _SupplyOverviewCard({
    required this.totalSupplies,
    required this.visibleSupplies,
    required this.cartCount,
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

    final historyAsync = ref.watch(priceHistoryProvider(supply.id));

    final cart = ref.watch(cartProvider);

    final inCart = cart.where((item) => item.supplyId == supply.id);

    final quantityInCart = inCart.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Slidable(
      key: ValueKey(supply.id),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supply.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (supply.brand != null &&
                          supply.brand!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          supply.brand!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (supply.unit != null &&
                              supply.unit!.trim().isNotEmpty) ...[
                            Icon(
                              Icons.straighten_outlined,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'per ${supply.unitQuantity != null ? '${supply.unitQuantity} ' : ''}${supply.unit}',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                          historyAsync.when(
                            data: (history) {
                              final trend = _trendFor(history);

                              if (trend == _Trend.none) {
                                return const SizedBox.shrink();
                              }

                              return Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _TrendBadge(trend: trend),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            _peso(supply.currentPrice),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StockBadge(
                            stock: supply.currentStock,
                            unit: supply.stockUnit,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                              content: Text('Could not save cart line: $error'),
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
                    if (quantityInCart > 0) ...[
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
// STOCK BADGE — shows how much is currently on hand, at a glance.
// ============================================================

class _StockBadge extends StatelessWidget {
  final double stock;
  final String unit;
  const _StockBadge({required this.stock, required this.unit});

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final isOut = stock <= 0;
    final color = isOut
        ? Colors.redAccent
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOut
            ? Colors.redAccent.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            isOut ? 'Out of stock' : '${_trim(stock)} $unit',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
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
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add supply'),
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

class _SupplyFormState extends ConsumerState<_SupplyForm> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _unitQuantityController = TextEditingController();
  final _priceController = TextEditingController();

  // ── NEW: catalog identity ────────────────────────────────
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  String? _categoryId;

  String? _selectedUnit;
  bool _saving = false;

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

  Future<String?> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || barcode == null || barcode.trim().isEmpty) return null;
    return SupplyCatalogService.normalizeBarcode(barcode);
  }

  Future<void> _save({required bool addStock}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final normalizedUnitQuantity = _unitQuantityController.text
        .replaceAll(',', '')
        .trim();
    final unitQuantity = normalizedUnitQuantity.isEmpty
        ? null
        : double.tryParse(normalizedUnitQuantity);

    final normalizedPrice = _priceController.text.replaceAll(',', '').trim();
    final enteredPrice = normalizedPrice.isEmpty
        ? null
        : double.tryParse(normalizedPrice);

    if (enteredPrice != null && (!enteredPrice.isFinite || enteredPrice < 0)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid price.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (unitQuantity != null && unitQuantity <= 0) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = ref.read(databaseProvider);
      final catalog = ref.read(supplyCatalogServiceProvider);

      // Normalise then check for collisions BEFORE inserting, so the
      // user gets "SKU FLR-001 is already used by Flour" instead of a
      // raw SQLite constraint error.
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
                // Price is optional. When supplied, store it immediately
                // as the catalog's current price (stored in cents, matching
                // the rest of the supply pricing code). Leave it at 0 when
                // the user chooses not to enter a price yet.
                currentPrice: priceCents,
                stockUnit: Value(_selectedUnit ?? 'piece'),
                currentStock: const Value(0),
                costPerBaseUnit: const Value(0),
                updatedAt: Value(now),
                isActive: const Value(true),
              ),
            );

        // When the user enters an initial price, record it immediately in
        // the same price-history table used by later price/purchase records.
        // This applies to both "Save for now" and "Next: Add Stock".
        if (enteredPrice != null) {
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
                ? '$savedName added — now record your first purchase'
                : '$savedName saved to your catalog',
          ),
        ),
      );

      if (addStock && context.mounted && createdSupply != null) {
        await showPurchaseEntrySheet(context, supply: createdSupply);
      }
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
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 360 ? 14.0 : 20.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                10,
                horizontalPadding,
                24,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Sheet handle ──────────────────────────────
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Header ────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.add_box_outlined,
                            color: scheme.onPrimaryContainer,
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
                              const SizedBox(height: 3),
                              Text(
                                'Set an optional current price for this supply.',
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
                          tooltip: 'Cancel',
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),

                    // ── SECTION 1: Item details ───────────────────
                    const _SectionLabel(
                      title: 'Item details',
                      icon: Icons.inventory_2_outlined,
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Supply name',
                        hintText: 'e.g. Rice fertilizer',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a supply name';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _brandController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Product brand',
                        hintText: 'e.g. NutriGrow',
                        prefixIcon: Icon(Icons.branding_watermark_outlined),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _unitQuantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Quantity per unit',
                        hintText: 'e.g. 25',
                        prefixIcon: Icon(Icons.numbers_outlined),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _priceController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Current price (optional)',
                        hintText: 'e.g. 1200',
                        prefixText: '₱ ',
                        prefixIcon: Icon(Icons.payments_outlined),
                        helperText:
                            'Leave blank if the price is not known yet.',
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Base unit — a dropdown, not free text, so every
                    // downstream recipe/costing calculation can trust it.
                    DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tracked in',
                        helperText:
                            'The unit BOS uses to track this item\'s stock',
                        prefixIcon: Icon(Icons.straighten_outlined),
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
                      onChanged: (value) {
                        setState(() {
                          _selectedUnit = value;
                        });
                      },
                    ),

                    const SizedBox(height: 26),

                    // ── SECTION 2: Catalog identity (NEW) ─────────
                    const _SectionLabel(
                      title: 'Catalog identity',
                      icon: Icons.badge_outlined,
                    ),

                    const SizedBox(height: 12),

                    // SKU + generate, barcode + scan, category + add.
                    SupplyIdentityFields(
                      skuController: _skuController,
                      barcodeController: _barcodeController,
                      categoryId: _categoryId,
                      onCategoryChanged: (id) =>
                          setState(() => _categoryId = id),
                      onScan: _saving ? null : _scanBarcode,
                    ),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You can save this item now, or continue to add stock. The price above will be saved as the current catalog price.',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Save choices ────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => _save(addStock: false),
                              child: Text(
                                _saving ? 'Saving...' : 'Save for now',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _save(addStock: true),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                              label: const Text(
                                'Next: Add Stock',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
// ============================================================================
// SECTION LABEL
// ============================================================================

class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionLabel({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.primary),
        const SizedBox(width: 7),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

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
    // THE FIX (#1): check whether this supply is used in any recipe
    // before deleting it — same reference-check pattern as Products.
    final affectedProducts = await ref
        .read(costingServiceProvider)
        .findProductsUsingSupply(supply.id);

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete supply?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will remove "${supply.name}" and its recorded price history.',
              ),
              if (affectedProducts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'It\'s used in: ${affectedProducts.map((p) => p.name).join(', ')}.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Those recipes will lose this ingredient — you\'ll need to replace it if you still want to make them.',
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final db = ref.read(databaseProvider);

    // Remove this supply from any recipe that references it, so
    // nothing is left pointing at a deleted supply.
    await (db.delete(
      db.recipeComponents,
    )..where((c) => c.supplyId.equals(supply.id))).go();

    await (db.delete(
      db.supplyPriceHistory,
    )..where((h) => h.supplyId.equals(supply.id))).go();

    await (db.delete(db.supplies)..where((s) => s.id.equals(supply.id))).go();

    ref.invalidate(suppliesProvider);
    ref.invalidate(priceHistoryProvider(supply.id));
    ref
        .read(ledgerVersionProvider.notifier)
        .state++; // affected recipes need to recompute

    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _setLowStockThreshold(
    BuildContext context,
    WidgetRef ref,
  ) async {
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

    await (db.update(db.supplies)..where((s) => s.id.equals(supply.id))).write(
      SuppliesCompanion(lowStockThreshold: Value(newThreshold)),
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
          IconButton(
            tooltip: 'Record purchase',
            onPressed: () => showPurchaseEntrySheet(context, supply: supply),
            icon: const Icon(Icons.add_chart_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete(context, ref);
              } else if (value == 'adjust_stock') {
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
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'set_threshold',
                child: Row(
                  children: [
                    Icon(Icons.notifications_outlined),
                    SizedBox(width: 10),
                    Text('Set low-stock alert'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'adjust_stock',
                child: Row(
                  children: [
                    Icon(Icons.remove_shopping_cart_outlined),
                    SizedBox(width: 10),
                    Text('Adjust stock (damaged/expired)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded),
                    SizedBox(width: 10),
                    Text('Delete supply'),
                  ],
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final trend = _trendFor(history);

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
                      : '${supply.currentStock == supply.currentStock.roundToDouble() ? supply.currentStock.toInt() : supply.currentStock.toStringAsFixed(1)} ${supply.stockUnit} in stock',
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
                    if (store != null && store!.trim().isNotEmpty) store!,
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
                    if (entry.storeName.trim().isNotEmpty) entry.storeName,
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

class _CheckoutSelectionDialog extends ConsumerStatefulWidget {
  const _CheckoutSelectionDialog();

  @override
  ConsumerState<_CheckoutSelectionDialog> createState() =>
      _CheckoutSelectionDialogState();
}

class _CheckoutSelectionDialogState
    extends ConsumerState<_CheckoutSelectionDialog> {
  String? _paymentAccountId;
  DateTime _purchaseDate = DateTime.now();

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    return AlertDialog(
      title: const Text('Checkout purchase'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how and when this purchase was paid.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            const Text(
              'Payment account',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            accountsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(
                'Unable to load payment accounts.',
                style: TextStyle(color: scheme.error),
              ),
              data: (accounts) {
                if (accounts.isEmpty) {
                  return Text(
                    'Add a Cash, Bank, or E-Wallet account before checkout.',
                    style: TextStyle(color: scheme.error),
                  );
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: accounts.map((account) {
                    return ChoiceChip(
                      label: Text(account.name),
                      selected: _paymentAccountId == account.id,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _paymentAccountId = account.id);
                        }
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            const Text(
              'Checkout date',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat('MMMM d, yyyy').format(_purchaseDate)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _paymentAccountId == null
              ? null
              : () => Navigator.pop(context, (
                  paymentAccountId: _paymentAccountId!,
                  date: _purchaseDate,
                )),
          child: const Text('Checkout'),
        ),
      ],
    );
  }
}

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  final _cartSearchController = TextEditingController();
  String _cartSearchQuery = '';

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

  Future<void> _addCustomItem() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _AddCustomItemDialog(),
    );
  }

  Future<void> _saveCart() async {
    final cart = ref.read(cartProvider);
    final draftMetadata = ref.read(cartProvider.notifier);

    if (cart.isEmpty) {
      return;
    }

    final checkout =
        await showDialog<({String paymentAccountId, DateTime date})>(
          context: context,
          builder: (_) => const _CheckoutSelectionDialog(),
        );

    if (checkout == null || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = ref.read(databaseProvider);

      // ----------------------------------------------------------------------
      // Find the "Supplies" expense category using the current categories
      // table/API.
      // ----------------------------------------------------------------------

      final categories =
          await (db.select(db.categories)..where(
                (c) =>
                    c.businessId.equals(kCurrentBusinessId) &
                    c.txnType.equals('expense') &
                    c.isActive.equals(true),
              ))
              .get();

      Category? suppliesCategory;

      for (final category in categories) {
        if (category.name.trim().toLowerCase() == 'supplies') {
          suppliesCategory = category;
          break;
        }
      }

      if (suppliesCategory == null) {
        throw Exception('The "Supplies" expense category was not found.');
      }

      // ----------------------------------------------------------------------
      // Find an active payment account.
      //
      // The current Account schema does not expose "isDefault", so we use
      // the first active payment account.
      // ----------------------------------------------------------------------

      final paymentAccount =
          await (db.select(db.accounts)..where(
                (a) =>
                    a.id.equals(checkout.paymentAccountId) &
                    a.businessId.equals(kCurrentBusinessId) &
                    a.isPaymentAccount.equals(true) &
                    a.isActive.equals(true),
              ))
              .getSingleOrNull();

      if (paymentAccount == null) {
        throw Exception('The selected payment account is no longer available.');
      }

      final total = cart.fold<int>(0, (sum, item) => sum + item.lineTotal);

      // ----------------------------------------------------------------------
      // Record the purchase through the same transaction service used by
      // the normal Expense screen.
      // ----------------------------------------------------------------------

      await db.transaction(() async {
        final transactionService = ref.read(transactionServiceProvider);

        final purchaseDate = checkout.date;

        final expenseId = await transactionService.saveExpense(
          date: purchaseDate,
          categoryId: suppliesCategory!.id,
          amount: total,
          paymentAccountId: paymentAccount.id,
          description: 'Supplies purchase',
          markAsPending: false,
        );

        // ----------------------------------------------------------------------
        // Save the shopping cart record.
        // ----------------------------------------------------------------------

        final cartId = const Uuid().v4();

        final storeName = draftMetadata.storeName;
        final storeAddress = draftMetadata.storeAddress;

        await db
            .into(db.shoppingCarts)
            .insert(
              ShoppingCartsCompanion.insert(
                id: cartId,
                businessId: kCurrentBusinessId,
                cartDate: purchaseDate,
                storeName: Value(storeName),
                storeAddress: Value(storeAddress),
                totalAmount: total,
                expenseId: Value(expenseId),
              ),
            );

        // ----------------------------------------------------------------------
        // Save each cart line, and — for lines linked to an existing supply —
        // record the purchase against it so currentStock, costPerBaseUnit,
        // and price history reflect this cart's quantity/price too, the
        // same way the standalone "Record Purchase" sheet does.
        // ----------------------------------------------------------------------

        final costingService = ref.read(costingServiceProvider);

        for (final item in cart) {
          await db
              .into(db.shoppingCartItems)
              .insert(
                ShoppingCartItemsCompanion.insert(
                  id: const Uuid().v4(),
                  cartId: cartId,
                  supplyId: Value(item.supplyId),
                  itemName: item.name,
                  brand: Value(item.brand),
                  unitQuantity: Value(item.unitQuantity),
                  unit: Value(item.unit),
                  unitPrice: item.unitPrice,
                  quantity: Value(item.quantity),
                  stockUnitsPerUnit: Value(item.stockUnitsPerUnit),
                  grossLineTotal: Value(item.grossTotalCents),
                  discountType: Value(item.discountType),
                  discountValue: Value(item.discountValue),
                  discountAmount: Value(item.discountAmountCents),
                  lineTotal: item.lineTotal,
                ),
              );

          if (item.supplyId == null) continue;

          final supply = await (db.select(
            db.supplies,
          )..where((s) => s.id.equals(item.supplyId!))).getSingleOrNull();

          if (supply == null) continue;

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
            purchaseQuantity: item.quantity.toDouble(),
            unitsPerPurchase: unitsPerPurchase,
            purchaseUnit: lineUnit,
            storeName: storeName ?? 'Unspecified',
            date: purchaseDate,
            actualTotalPriceCents: item.lineTotal,
            updateSupplyReferenceFields: updateSupplyReference,
          );
        }

        await PurchaseDraftCartService(
          db,
        ).deleteDraftInTransaction(kCurrentBusinessId);
      });

      ref.read(cartProvider.notifier).clearAfterCheckout();

      // Force dashboard/ledger listeners to refresh.
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Purchase saved and recorded as an expense.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to save purchase: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

    final cart = ref.watch(cartProvider);
    final draftMetadata = ref.read(cartProvider.notifier);
    final total = cart.fold<int>(0, (sum, item) => sum + item.lineTotal);

    final totalQuantity = cart.fold<int>(0, (sum, item) => sum + item.quantity);
    final visibleCart = <CartItem>[];
    final categoryNames =
        ref.watch(supplyCategoryNamesProvider).asData?.value ??
        const <String, String>{};
    for (final item in cart) {
      final supply = item.supplyId == null
          ? null
          : ref.watch(cartLineSupplyProvider(item.supplyId!)).asData?.value;
      if (matchesPurchaseCartSearch(
        query: _cartSearchQuery,
        itemName: item.name,
        brand: item.brand ?? supply?.brand,
        category: categoryNames[supply?.categoryId],
        barcode: supply?.barcode,
        store: draftMetadata.storeName ?? supply?.lastStoreName,
        address: draftMetadata.storeAddress ?? supply?.lastStoreAddress,
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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shopping_basket_outlined,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$totalQuantity units · ${cart.length} line${cart.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _peso(total),
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                    child: _CartItemTile(item: item),
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
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
  final TextCapitalization textCapitalization;

  /// Returns an error message to show (and block save) or null if valid.
  final String? Function(String value)? validate;

  const _TextEntryDialog({
    required this.title,
    required this.label,
    required this.initialText,
    this.textCapitalization = TextCapitalization.none,
    this.validate,
  });

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

  Future<void> _submit() async {
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
// CART ITEM TILE
// ============================================================================

class _CartItemTile extends ConsumerWidget {
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      // THE FIX: confirmDismiss runs BEFORE the item is removed, and
      // the swipe only completes if this resolves to true. Without
      // it, any swipe past the threshold deletes immediately — easy
      // to trigger by accident while just scrolling the cart.
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Remove this item?'),
            content: Text('Remove "${item.name}" from your cart?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
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
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: scheme.onErrorContainer,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.checked
              ? scheme.secondaryContainer.withValues(alpha: 0.72)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: item.checked
                ? scheme.secondary.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 380;
            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: item.checked,
                  onChanged: (_) async {
                    await ref
                        .read(cartProvider.notifier)
                        .toggleChecked(item.id);
                  },
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.name.trim().isEmpty
                        ? '?'
                        : item.name.trim()[0].toUpperCase(),
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: _CartItemDetails(
                    item: item,
                    onEditName: () => _editName(context, ref),
                    onEditPrice: () => _editPrice(context, ref),
                  ),
                ),
              ],
            );
            final quantityControl = _QuantityControl(
              quantity: item.quantity,
              onDecrease: () async {
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
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: quantityControl,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: identity),
                const SizedBox(width: 6),
                quantityControl,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final itemId = item.id;

    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextEntryDialog(
        title: 'Edit item name',
        label: 'Item name',
        initialText: item.name,
        textCapitalization: TextCapitalization.words,
        validate: (value) => value.isEmpty ? 'Enter an item name' : null,
      ),
    );

    if (result != null && result.isNotEmpty) {
      await cartNotifier.updateName(itemId, result);
    }
  }

  Future<void> _editPrice(BuildContext context, WidgetRef ref) async {
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
      // Legacy duplicate of the cart page: anchor to the line's current
      // price so behavior matches what this file had before.
      originalUnitPriceCents: item.unitPrice,
      originalStockUnitsPerUnit: item.stockUnitsPerUnit,
    );
    if (pricing == null) return;
    await ref
        .read(cartProvider.notifier)
        .updateLinePricing(item.id, pricing, isWeighted: item.isWeighted);
  }

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    await _editPrice(context, ref);
  }
}

class _CartItemDetails extends StatelessWidget {
  final CartItem item;
  final VoidCallback onEditName;
  final VoidCallback onEditPrice;

  const _CartItemDetails({
    required this.item,
    required this.onEditName,
    required this.onEditPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final receivedQuantity = item.isWeighted
        ? item.weightQuantity
        : item.quantity.toDouble();
    final effectiveUnitCost = receivedQuantity > 0
        ? (item.lineTotal / receivedQuantity).round()
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Edit name',
              visualDensity: VisualDensity.compact,
              onPressed: onEditName,
              icon: const Icon(Icons.edit_outlined, size: 17),
            ),
          ],
        ),
        if (item.unit != null) ...[
          Text(
            'per ${item.unit}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onEditPrice,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  '${_peso(effectiveUnitCost)} / unit',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            Text('·', style: TextStyle(color: scheme.onSurfaceVariant)),
            Text(
              _peso(item.lineTotal),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        if (item.discountAmountCents > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Gross ${_peso(item.grossTotalCents)} · Discount -${_peso(item.discountAmountCents)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
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
