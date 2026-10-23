// Pure sales analytics for the Sales page. No Flutter widgets in here.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

// ============================================================================
// PROVIDERS
// ============================================================================

/// User id -> display name (falls back to email).
final cashierNamesProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.users).watch().map((rows) {
    return {
      for (final u in rows)
        u.id: u.displayName.trim().isNotEmpty ? u.displayName.trim() : u.email,
    };
  });
});

final allPosSaleItemsProvider = StreamProvider<List<PosSaleItem>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.posSaleItems).watch();
});

// ============================================================================
// ADAPTERS — the only places that depend on exact column names.
// ============================================================================

bool saleIsVoided(PosSale s) => s.isVoided;

String? saleCashierId(PosSale s) => s.cashierUserId;

/// Snapshot name first, then the local Users table, then a fallback.
String cashierLabel(PosSale s, Map<String, String> names) {
  final snapshot = s.cashierName?.trim();
  if (snapshot != null && snapshot.isNotEmpty) return snapshot;
  final id = s.cashierUserId;
  if (id == null || id.isEmpty) return 'Unknown cashier';
  return names[id] ?? 'Staff member';
}

const kUnknownCashierKey = '_unknown';
const kUncategorizedKey = '_none';

// ============================================================================
// MODELS
// ============================================================================

enum RankBy { revenue, units }

int _compareProducts(RankBy by, ProductSales a, ProductSales b) {
  final c = by == RankBy.revenue
      ? b.revenueCents.compareTo(a.revenueCents)
      : b.qty.compareTo(a.qty);
  return c != 0 ? c : b.revenueCents.compareTo(a.revenueCents);
}

class ProductSales {
  ProductSales({
    required this.key,
    required this.name,
    required this.unit,
    required this.categoryName,
  });
  final String key;
  final String name;
  final String unit;
  final String categoryName;
  double qty = 0;
  int revenueCents = 0;
}

class CategorySales {
  CategorySales({required this.key, required this.name});
  final String key;
  final String name;
  final Map<String, ProductSales> _products = {};
  int revenueCents = 0;

  int get productCount => _products.length;

  /// Best seller first. Ties fall back to revenue.
  List<ProductSales> ranked(RankBy by) =>
      _products.values.toList()..sort((a, b) => _compareProducts(by, a, b));
}

class CashierSales {
  CashierSales({required this.key, required this.name});
  final String key;
  final String name;
  int salesCount = 0;
  int revenueCents = 0;
  double itemsSold = 0;

  int get averageCents =>
      salesCount == 0 ? 0 : (revenueCents / salesCount).round();
}

class SalesReport {
  const SalesReport({
    required this.revenueCents,
    required this.salesCount,
    required this.voidedCount,
    required this.itemsSold,
    required this.cashiers,
    required this.categories,
    required this.daily,
    required this.hourly,
  });

  final int revenueCents;
  final int salesCount;
  final int voidedCount;
  final double itemsSold;

  /// Sorted by revenue, highest first.
  final List<CashierSales> cashiers;
  final List<CategorySales> categories;

  /// Revenue per calendar day (days with no sales are absent).
  final Map<DateTime, int> daily;

  /// Revenue per hour of day (0–23).
  final Map<int, int> hourly;

  int get averageSaleCents =>
      salesCount == 0 ? 0 : (revenueCents / salesCount).round();

  MapEntry<DateTime, int>? get bestDay => daily.isEmpty
      ? null
      : daily.entries.reduce((a, b) => b.value > a.value ? b : a);

  int? get peakHour => hourly.isEmpty
      ? null
      : hourly.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  /// Best sellers across every category.
  List<ProductSales> topProducts(RankBy by, {int limit = 10}) {
    final all = [for (final c in categories) ...c.ranked(by)]
      ..sort((a, b) => _compareProducts(by, a, b));
    return all.take(limit).toList();
  }
}

// ============================================================================
// BUILDER
// ============================================================================

/// [sales] must already be limited to the chosen period. Stock-only and voided
/// sales are excluded here.
SalesReport buildSalesReport({
  required List<PosSale> sales,
  required List<PosSaleItem> items,
  required Map<String, String?> productCategory,
  required Map<String, String> categoryNames,
  required Map<String, String> cashierNames,
}) {
  final voided = sales.where((s) => !s.isStockOnly && saleIsVoided(s)).length;
  final counted = sales
      .where((s) => !s.isStockOnly && !saleIsVoided(s))
      .toList();
  final saleIds = {for (final s in counted) s.id};

  final itemsBySale = <String, List<PosSaleItem>>{};
  for (final i in items) {
    if (saleIds.contains(i.saleId)) {
      (itemsBySale[i.saleId] ??= []).add(i);
    }
  }

  var revenue = 0;
  var itemsSold = 0.0;
  final cashiers = <String, CashierSales>{};
  final categories = <String, CategorySales>{};
  final daily = <DateTime, int>{};
  final hourly = <int, int>{};

  for (final s in counted) {
    revenue += s.totalAmount;

    final day = DateTime(s.saleDate.year, s.saleDate.month, s.saleDate.day);
    daily[day] = (daily[day] ?? 0) + s.totalAmount;
    hourly[s.saleDate.hour] = (hourly[s.saleDate.hour] ?? 0) + s.totalAmount;

    final cid = saleCashierId(s);
    final ckey = (cid == null || cid.isEmpty) ? kUnknownCashierKey : cid;
    final cashier = cashiers.putIfAbsent(
      ckey,
      () => CashierSales(key: ckey, name: cashierLabel(s, cashierNames)),
    );
    cashier.salesCount++;
    cashier.revenueCents += s.totalAmount;

    for (final item in itemsBySale[s.id] ?? const <PosSaleItem>[]) {
      itemsSold += item.quantity;
      cashier.itemsSold += item.quantity;

      final productKey = item.productId ?? 'name:${item.productName}';
      final catId = item.productId == null
          ? null
          : productCategory[item.productId];
      final catKey = catId ?? kUncategorizedKey;
      final category = categories.putIfAbsent(
        catKey,
        () => CategorySales(
          key: catKey,
          name: categoryNames[catId] ?? 'Uncategorized',
        ),
      );
      category.revenueCents += item.lineTotal;

      final product = category._products.putIfAbsent(
        productKey,
        () => ProductSales(
          key: productKey,
          name: item.productName,
          unit: item.unit,
          categoryName: category.name,
        ),
      );
      product.qty += item.quantity;
      product.revenueCents += item.lineTotal;
    }
  }

  return SalesReport(
    revenueCents: revenue,
    salesCount: counted.length,
    voidedCount: voided,
    itemsSold: itemsSold,
    cashiers: cashiers.values.toList()
      ..sort((a, b) => b.revenueCents.compareTo(a.revenueCents)),
    categories: categories.values.toList()
      ..sort((a, b) => b.revenueCents.compareTo(a.revenueCents)),
    daily: daily,
    hourly: hourly,
  );
}
