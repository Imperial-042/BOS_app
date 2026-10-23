// lib/features/transactions/domain/product_catalog_service.dart
//
// The one place product master data is written and searched from.
// Keeping normalisation + uniqueness here (instead of in each form)
// means a SKU typed in the product sheet, imported from a CSV, or
// created by a POS quick-add all end up in the same shape.

import 'package:bos_application/core/stock/stock_service.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

// ============================================================
// ENUMS — stored as short stable strings, never as indexes,
// so reordering the enum can't corrupt existing rows.
// ============================================================

enum ProductType { finished, intermediate, merchandise, service }

extension ProductTypeX on ProductType {
  String get wire => switch (this) {
    ProductType.finished => 'finished',
    ProductType.intermediate => 'intermediate',
    ProductType.merchandise => 'merchandise',
    ProductType.service => 'service',
  };

  String get label => switch (this) {
    ProductType.finished => 'Finished product',
    ProductType.intermediate => 'Recipe component',
    ProductType.merchandise => 'Stocked merchandise',
    ProductType.service => 'Service',
  };

  String get hint => switch (this) {
    ProductType.finished => 'Made in-house and sold to customers.',
    ProductType.intermediate => 'Used inside other recipes, never sold alone.',
    ProductType.merchandise => 'Bought ready-made and resold as-is.',
    ProductType.service => 'Labour or time — nothing physical to stock.',
  };

  /// The tracking mode that makes sense by default for this type.
  TrackingType get defaultTracking => switch (this) {
    ProductType.finished => TrackingType.recipe,
    ProductType.intermediate => TrackingType.recipe,
    ProductType.merchandise => TrackingType.stocked,
    ProductType.service => TrackingType.nonStocked,
  };

  static ProductType parse(String? raw) => switch (raw) {
    'intermediate' => ProductType.intermediate,
    'merchandise' => ProductType.merchandise,
    'service' => ProductType.service,
    _ => ProductType.finished,
  };
}

enum TrackingType { recipe, stocked, nonStocked }

extension TrackingTypeX on TrackingType {
  String get wire => switch (this) {
    TrackingType.recipe => 'recipe',
    TrackingType.stocked => 'stocked',
    TrackingType.nonStocked => 'non_stocked',
  };

  String get label => switch (this) {
    TrackingType.recipe => 'Recipe / produced',
    TrackingType.stocked => 'Stocked',
    TrackingType.nonStocked => 'Not stocked',
  };

  String get hint => switch (this) {
    TrackingType.recipe =>
      'Availability comes from the supplies in its recipe.',
    TrackingType.stocked => 'BOS counts units on hand for this product.',
    TrackingType.nonStocked => 'No quantity is tracked.',
  };

  static TrackingType parse(String? raw) => switch (raw) {
    'stocked' => TrackingType.stocked,
    'non_stocked' => TrackingType.nonStocked,
    _ => TrackingType.recipe,
  };
}

enum ProductSort { manual, nameAsc, nameDesc, priceAsc, priceDesc, newest }

extension ProductSortX on ProductSort {
  String get label => switch (this) {
    ProductSort.manual => 'Custom order',
    ProductSort.nameAsc => 'Name (A–Z)',
    ProductSort.nameDesc => 'Name (Z–A)',
    ProductSort.priceAsc => 'Price (low to high)',
    ProductSort.priceDesc => 'Price (high to low)',
    ProductSort.newest => 'Newest first',
  };
}

// ============================================================
// QUERY + RESULT SHAPES
// ============================================================

/// Everything the catalog screen can filter on. Immutable so it can
/// sit in a StateProvider and be compared cheaply.
class ProductQuery {
  final String search;
  final String? categoryId;
  final Set<ProductType> types;
  final Set<TrackingType> tracking;

  /// null = both, true = sellable only, false = components only.
  final bool? sellableOnly;
  final bool includeArchived;
  final bool lowStockOnly;
  final ProductSort sort;

  const ProductQuery({
    this.search = '',
    this.categoryId,
    this.types = const {},
    this.tracking = const {},
    this.sellableOnly,
    this.includeArchived = false,
    this.lowStockOnly = false,
    this.sort = ProductSort.nameAsc,
  });

  bool get hasActiveFilters =>
      categoryId != null ||
      types.isNotEmpty ||
      tracking.isNotEmpty ||
      sellableOnly != null ||
      includeArchived ||
      lowStockOnly;

  int get activeFilterCount => [
    categoryId != null,
    types.isNotEmpty,
    tracking.isNotEmpty,
    sellableOnly != null,
    includeArchived,
    lowStockOnly,
  ].where((f) => f).length;

  ProductQuery copyWith({
    String? search,
    Object? categoryId = _unset,
    Set<ProductType>? types,
    Set<TrackingType>? tracking,
    Object? sellableOnly = _unset,
    bool? includeArchived,
    bool? lowStockOnly,
    ProductSort? sort,
  }) {
    return ProductQuery(
      search: search ?? this.search,
      categoryId: categoryId == _unset
          ? this.categoryId
          : categoryId as String?,
      types: types ?? this.types,
      tracking: tracking ?? this.tracking,
      sellableOnly: sellableOnly == _unset
          ? this.sellableOnly
          : sellableOnly as bool?,
      includeArchived: includeArchived ?? this.includeArchived,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      sort: sort ?? this.sort,
    );
  }

  /// Clears filters but keeps whatever is typed in the search box —
  /// "Clear filters" shouldn't wipe the user's search term too.
  ProductQuery cleared() => ProductQuery(search: search, sort: sort);

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.search == search &&
      other.categoryId == categoryId &&
      _setEq(other.types, types) &&
      _setEq(other.tracking, tracking) &&
      other.sellableOnly == sellableOnly &&
      other.includeArchived == includeArchived &&
      other.lowStockOnly == lowStockOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    search,
    categoryId,
    Object.hashAllUnordered(types),
    Object.hashAllUnordered(tracking),
    sellableOnly,
    includeArchived,
    lowStockOnly,
    sort,
  );

  static bool _setEq<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}

/// A product plus its (optional) category, so list tiles don't each
/// fire their own lookup.
class ProductListing {
  final Product product;
  final ProductCategory? category;

  const ProductListing({required this.product, this.category});

  ProductType get type => ProductTypeX.parse(product.productType);
  TrackingType get tracking => TrackingTypeX.parse(product.trackingType);

  bool get isLowStock =>
      tracking == TrackingType.stocked &&
      product.lowStockThreshold != null &&
      product.currentStock <= product.lowStockThreshold!;
}

/// Thrown when a SKU or barcode collides with another product in the
/// same business. Carries the conflicting product so the UI can say
/// *which* item already owns the code.
class DuplicateProductCodeException implements Exception {
  final String field; // 'SKU' | 'barcode'
  final String value;
  final Product existing;

  DuplicateProductCodeException({
    required this.field,
    required this.value,
    required this.existing,
  });

  @override
  String toString() => '$field "$value" is already used by ${existing.name}.';
}

// ============================================================
// SERVICE
// ============================================================

class ProductCatalogService {
  final AppDatabase db;
  final String businessId;
  final String branchId;
  final _uuid = const Uuid();

  ProductCatalogService(
    this.db, {
    required this.businessId,
    required this.branchId,
  });

  // ---------- normalisation ----------

  /// SKUs are compared case-insensitively in practice, so we store one
  /// canonical form: trimmed, upper-cased, inner whitespace collapsed
  /// to a single dash.
  static String? normalizeSku(String? raw) {
    final v = (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '-');
    return v.isEmpty ? null : v;
  }

  /// Barcodes are scanned verbatim; we only strip whitespace and the
  /// stray control characters some scanners append.
  static String? normalizeBarcode(String? raw) {
    final v = (raw ?? '').trim().replaceAll(RegExp(r'[\s\u0000-\u001f]'), '');
    return v.isEmpty ? null : v;
  }

  // ---------- uniqueness ----------

  Future<Product?> findBySku(String? sku, {String? excludeId}) async {
    final value = normalizeSku(sku);
    if (value == null) return null;

    final q = db.select(db.products)
      ..where((p) => p.businessId.equals(businessId) & p.sku.equals(value));
    if (excludeId != null) {
      q.where((p) => p.id.equals(excludeId).not());
    }
    return q.getSingleOrNull();
  }

  Future<Product?> findByBarcode(String? barcode, {String? excludeId}) async {
    final value = normalizeBarcode(barcode);
    if (value == null) return null;

    final q = db.select(db.products)
      ..where((p) => p.businessId.equals(businessId) & p.barcode.equals(value));
    if (excludeId != null) {
      q.where((p) => p.id.equals(excludeId).not());
    }
    return q.getSingleOrNull();
  }

  Future<bool> isSkuAvailable(String? sku, {String? excludeId}) async =>
      await findBySku(sku, excludeId: excludeId) == null;

  Future<bool> isBarcodeAvailable(String? code, {String? excludeId}) async =>
      await findByBarcode(code, excludeId: excludeId) == null;

  Future<void> _assertCodesFree({
    String? sku,
    String? barcode,
    String? excludeId,
  }) async {
    final skuClash = await findBySku(sku, excludeId: excludeId);
    if (skuClash != null) {
      throw DuplicateProductCodeException(
        field: 'SKU',
        value: normalizeSku(sku)!,
        existing: skuClash,
      );
    }

    final barcodeClash = await findByBarcode(barcode, excludeId: excludeId);
    if (barcodeClash != null) {
      throw DuplicateProductCodeException(
        field: 'Barcode',
        value: normalizeBarcode(barcode)!,
        existing: barcodeClash,
      );
    }
  }

  /// Suggests the next free SKU for a prefix, e.g. "DRK" → "DRK-004".
  /// Purely a convenience for the form's "generate" button; the user
  /// can always overwrite it.
  Future<String> suggestSku(String prefix) async {
    final clean = normalizeSku(prefix) ?? 'SKU';
    final rows =
        await (db.select(db.products)..where(
              (p) => p.businessId.equals(businessId) & p.sku.like('$clean-%'),
            ))
            .get();

    var highest = 0;
    for (final row in rows) {
      final tail = row.sku!.split('-').last;
      final n = int.tryParse(tail);
      if (n != null && n > highest) highest = n;
    }

    return '$clean-${(highest + 1).toString().padLeft(3, '0')}';
  }

  // ---------- writes ----------

  Future<Product> createProduct({
    required String name,
    required String unit,
    String? sku,
    String? barcode,
    String? categoryId,
    String? description,
    String? imagePath,
    ProductType type = ProductType.finished,
    TrackingType? tracking,
    int? sellPrice,
    double currentStock = 0,
    double? lowStockThreshold,
    bool? isSellable,
    int? sortOrder,
  }) async {
    final normalizedSku = normalizeSku(sku);
    final normalizedBarcode = normalizeBarcode(barcode);
    await _assertCodesFree(sku: normalizedSku, barcode: normalizedBarcode);

    final resolvedTracking = tracking ?? type.defaultTracking;
    final id = _uuid.v4();
    final now = DateTime.now();

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: id,
            businessId: businessId,
            name: name.trim(),
            unit: unit.trim(),
            sku: Value(normalizedSku),
            barcode: Value(normalizedBarcode),
            categoryId: Value(categoryId),
            description: Value(_nullIfBlank(description)),
            imagePath: Value(_nullIfBlank(imagePath)),
            productType: Value(type.wire),
            trackingType: Value(resolvedTracking.wire),
            sellPrice: Value(sellPrice),
            currentStock: const Value(0),
            lowStockThreshold: Value(
              resolvedTracking == TrackingType.stocked
                  ? lowStockThreshold
                  : null,
            ),
            // Preserved behaviour: recipe components are never sellable,
            // everything else defaults to sellable unless told otherwise.
            isSellable: Value(isSellable ?? (type != ProductType.intermediate)),
            sortOrder: Value(sortOrder ?? await _nextSortOrder()),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    if (resolvedTracking == TrackingType.stocked && currentStock != 0) {
      await StockService(db, viewBranchId: branchId).moveProduct(
        branchId: branchId,
        productId: id,
        businessId: businessId,
        type: 'opening_balance',
        quantity: currentStock,
      );
    }

    return (db.select(db.products)..where((p) => p.id.equals(id))).getSingle();
  }

  Future<void> updateProduct(
    String productId, {
    String? name,
    String? unit,
    Object? sku = _unset,
    Object? barcode = _unset,
    Object? categoryId = _unset,
    Object? description = _unset,
    Object? imagePath = _unset,
    ProductType? type,
    TrackingType? tracking,
    Object? sellPrice = _unset,
    Object? lowStockThreshold = _unset,
    bool? isSellable,
    bool? isActive,
  }) async {
    final normalizedSku = sku == _unset ? null : normalizeSku(sku as String?);
    final normalizedBarcode = barcode == _unset
        ? null
        : normalizeBarcode(barcode as String?);

    await _assertCodesFree(
      sku: normalizedSku,
      barcode: normalizedBarcode,
      excludeId: productId,
    );

    final resolvedTracking = tracking ?? (type?.defaultTracking);

    await (db.update(db.products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        unit: unit == null ? const Value.absent() : Value(unit.trim()),
        sku: sku == _unset ? const Value.absent() : Value(normalizedSku),
        barcode: barcode == _unset
            ? const Value.absent()
            : Value(normalizedBarcode),
        categoryId: categoryId == _unset
            ? const Value.absent()
            : Value(categoryId as String?),
        description: description == _unset
            ? const Value.absent()
            : Value(_nullIfBlank(description as String?)),
        imagePath: imagePath == _unset
            ? const Value.absent()
            : Value(_nullIfBlank(imagePath as String?)),
        productType: type == null ? const Value.absent() : Value(type.wire),
        trackingType: resolvedTracking == null
            ? const Value.absent()
            : Value(resolvedTracking.wire),
        sellPrice: sellPrice == _unset
            ? const Value.absent()
            : Value(sellPrice as int?),
        lowStockThreshold: lowStockThreshold == _unset
            ? const Value.absent()
            : Value(lowStockThreshold as double?),
        isSellable: isSellable == null
            ? (type == ProductType.intermediate
                  ? const Value(false)
                  : const Value.absent())
            : Value(isSellable),
        isActive: isActive == null ? const Value.absent() : Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Archive instead of delete — recipes, past sales, and reports all
  /// still point at this row.
  Future<void> setArchived(String productId, {required bool archived}) {
    return (db.update(db.products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        isActive: Value(!archived),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Persists a drag-to-reorder result.
  Future<void> reorderProducts(List<String> orderedIds) async {
    await db.batch((b) {
      for (var i = 0; i < orderedIds.length; i++) {
        b.update(
          db.products,
          ProductsCompanion(sortOrder: Value(i)),
          where: (p) => p.id.equals(orderedIds[i]),
        );
      }
    });
  }

  Future<void> adjustProductStock(String productId, double delta) {
    return StockService(db, viewBranchId: branchId).moveProduct(
      branchId: branchId,
      productId: productId,
      businessId: businessId,
      type: 'manual_adjustment',
      quantity: delta,
    );
  }

  Future<int> _nextSortOrder() async {
    final maxOrder = db.products.sortOrder.max();
    final row =
        await (db.selectOnly(db.products)
              ..addColumns([maxOrder])
              ..where(db.products.businessId.equals(businessId)))
            .getSingle();
    return (row.read(maxOrder) ?? -1) + 1;
  }

  // ---------- reads / search ----------

  /// One query builder shared by [search] and [watch], so the live list
  /// and a one-shot fetch can never drift apart.
  JoinedSelectStatement _buildQuery(ProductQuery query) {
    final select = db.select(db.products).join([
      leftOuterJoin(
        db.productCategories,
        db.productCategories.id.equalsExp(db.products.categoryId),
      ),
    ]);

    select.where(db.products.businessId.equals(businessId));

    if (!query.includeArchived) {
      select.where(db.products.isActive.equals(true));
    }

    if (query.categoryId != null) {
      select.where(db.products.categoryId.equals(query.categoryId!));
    }

    if (query.types.isNotEmpty) {
      select.where(
        db.products.productType.isIn(query.types.map((t) => t.wire).toList()),
      );
    }

    if (query.tracking.isNotEmpty) {
      select.where(
        db.products.trackingType.isIn(
          query.tracking.map((t) => t.wire).toList(),
        ),
      );
    }

    if (query.sellableOnly != null) {
      select.where(db.products.isSellable.equals(query.sellableOnly!));
    }

    if (query.lowStockOnly) {
      select.where(
        db.products.trackingType.equals(TrackingType.stocked.wire) &
            db.products.lowStockThreshold.isNotNull() &
            db.products.currentStock.isSmallerOrEqual(
              db.products.lowStockThreshold,
            ),
      );
    }

    final term = query.search.trim().toLowerCase();
    if (term.isNotEmpty) {
      final like = '%$term%';
      select.where(
        db.products.name.lower().like(like) |
            db.products.sku.lower().like(like) |
            db.products.barcode.lower().like(like) |
            db.products.description.lower().like(like) |
            db.productCategories.name.lower().like(like),
      );
    }

    select.orderBy(switch (query.sort) {
      ProductSort.manual => [
        OrderingTerm.asc(db.products.sortOrder),
        OrderingTerm.asc(db.products.name),
      ],
      ProductSort.nameAsc => [OrderingTerm.asc(db.products.name)],
      ProductSort.nameDesc => [OrderingTerm.desc(db.products.name)],
      ProductSort.priceAsc => [
        OrderingTerm.asc(db.products.sellPrice),
        OrderingTerm.asc(db.products.name),
      ],
      ProductSort.priceDesc => [
        OrderingTerm.desc(db.products.sellPrice),
        OrderingTerm.asc(db.products.name),
      ],
      ProductSort.newest => [OrderingTerm.desc(db.products.createdAt)],
    });

    return select;
  }

  List<ProductListing> _mapRows(List<TypedResult> rows) {
    return rows
        .map(
          (row) => ProductListing(
            product: row.readTable(db.products),
            category: row.readTableOrNull(db.productCategories),
          ),
        )
        .toList();
  }

  Future<List<ProductListing>> search(ProductQuery query) async =>
      _mapRows(await _buildQuery(query).get());

  Stream<List<ProductListing>> watch(ProductQuery query) =>
      _buildQuery(query).watch().map(_mapRows);

  /// Single-seek scanner path: exact barcode first (index-backed), then
  /// exact SKU, then a unique name match. Returns null when nothing —
  /// or more than one thing — matches, so the caller can prompt.
  Future<Product?> lookupForPos(String scanned) async {
    final code = scanned.trim();
    if (code.isEmpty) return null;

    final byBarcode = await findByBarcode(code);
    if (byBarcode != null) return byBarcode;

    final bySku = await findBySku(code);
    if (bySku != null) return bySku;

    final byName =
        await (db.select(db.products)..where(
              (p) =>
                  p.businessId.equals(businessId) &
                  p.isActive.equals(true) &
                  p.name.lower().equals(code.toLowerCase()),
            ))
            .get();

    return byName.length == 1 ? byName.first : null;
  }

  // ---------- categories ----------

  Stream<List<ProductCategory>> watchCategories({
    bool includeArchived = false,
  }) {
    final q = db.select(db.productCategories)
      ..where((c) => c.businessId.equals(businessId))
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.name),
      ]);
    if (!includeArchived) {
      q.where((c) => c.isActive.equals(true));
    }
    return q.watch();
  }

  Future<List<ProductCategory>> getCategories({bool includeArchived = false}) =>
      watchCategories(includeArchived: includeArchived).first;

  Future<ProductCategory> createCategory(
    String name, {
    String? description,
    String? colorHex,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Category name cannot be empty.');
    }

    final existing =
        await (db.select(db.productCategories)..where(
              (c) =>
                  c.businessId.equals(businessId) &
                  c.name.lower().equals(trimmed.toLowerCase()),
            ))
            .getSingleOrNull();

    // Re-activate rather than duplicate: re-adding an archived category
    // by the same name should bring the old one back with its products.
    if (existing != null) {
      if (!existing.isActive) {
        await (db.update(
          db.productCategories,
        )..where((c) => c.id.equals(existing.id))).write(
          ProductCategoriesCompanion(
            isActive: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return existing;
    }

    final id = _uuid.v4();
    final maxOrder = db.productCategories.sortOrder.max();
    final row =
        await (db.selectOnly(db.productCategories)
              ..addColumns([maxOrder])
              ..where(db.productCategories.businessId.equals(businessId)))
            .getSingle();

    await db
        .into(db.productCategories)
        .insert(
          ProductCategoriesCompanion.insert(
            id: id,
            businessId: businessId,
            name: trimmed,
            description: Value(_nullIfBlank(description)),
            colorHex: Value(_nullIfBlank(colorHex)),
            sortOrder: Value((row.read(maxOrder) ?? -1) + 1),
          ),
        );

    return (db.select(
      db.productCategories,
    )..where((c) => c.id.equals(id))).getSingle();
  }

  Future<void> renameCategory(String categoryId, String name) {
    return (db.update(
      db.productCategories,
    )..where((c) => c.id.equals(categoryId))).write(
      ProductCategoriesCompanion(
        name: Value(name.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Archiving a category leaves its products alone but detaches them,
  /// so nothing ends up filtered by a category the user can't see.
  Future<void> archiveCategory(String categoryId, {bool detach = true}) async {
    await db.transaction(() async {
      if (detach) {
        await (db.update(db.products)..where(
              (p) =>
                  p.businessId.equals(businessId) &
                  p.categoryId.equals(categoryId),
            ))
            .write(const ProductsCompanion(categoryId: Value(null)));
      }
      await (db.update(
        db.productCategories,
      )..where((c) => c.id.equals(categoryId))).write(
        ProductCategoriesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> reorderCategories(List<String> orderedIds) async {
    await db.batch((b) {
      for (var i = 0; i < orderedIds.length; i++) {
        b.update(
          db.productCategories,
          ProductCategoriesCompanion(sortOrder: Value(i)),
          where: (c) => c.id.equals(orderedIds[i]),
        );
      }
    });
  }

  /// How many active products sit in each category — used for the count
  /// badges on the filter chips and the category manager.
  Future<Map<String, int>> categoryCounts() async {
    final count = db.products.id.count();
    final rows =
        await (db.selectOnly(db.products)
              ..addColumns([db.products.categoryId, count])
              ..where(
                db.products.businessId.equals(businessId) &
                    db.products.isActive.equals(true),
              )
              ..groupBy([db.products.categoryId]))
            .get();

    return {
      for (final row in rows)
        row.read(db.products.categoryId) ?? '': row.read(count) ?? 0,
    };
  }

  Future<void> assignCategory(String productId, String? categoryId) {
    return (db.update(db.products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        categoryId: Value(categoryId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  static String? _nullIfBlank(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static const Object _unset = Object();
}
