// lib/features/transactions/presentation/providers/product_catalog_providers.dart

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/product_catalog_service.dart';
import '../screens/transaction_page.dart' show ledgerVersionProvider;

final productCatalogServiceProvider = Provider<ProductCatalogService>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final branchId = ref.watch(selectedBranchIdProvider);
  return ProductCatalogService(db, businessId: businessId, branchId: branchId);
});

/// Live list of product categories for the current business.
final productCategoriesProvider = StreamProvider<List<ProductCategory>>((ref) {
  ref.watch(ledgerVersionProvider);
  return ref.watch(productCatalogServiceProvider).watchCategories();
});

/// How many products sit in each category (key '' = uncategorized).
final productCategoryCountsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(ledgerVersionProvider);
  return ref.watch(productCatalogServiceProvider).categoryCounts();
});

/// The catalog's current search + filter state. The UI mutates this;
/// [productListingsProvider] re-runs the query whenever it changes.
final productQueryProvider = StateProvider<ProductQuery>(
  (ref) => const ProductQuery(),
);

final productListingsProvider = StreamProvider<List<ProductListing>>((ref) {
  ref.watch(ledgerVersionProvider);
  final query = ref.watch(productQueryProvider);
  return ref.watch(productCatalogServiceProvider).watch(query);
});

/// Unfiltered count, so the header can say "12 of 40 products".
final productTotalCountProvider = StreamProvider<int>((ref) {
  ref.watch(ledgerVersionProvider);
  return ref
      .watch(productCatalogServiceProvider)
      .watch(const ProductQuery())
      .map((list) => list.length);
});

/// Barcode/SKU resolution for the scanner. Autodisposes so a scan
/// result doesn't linger in memory after the POS sheet closes.
final productScanLookupProvider = FutureProvider.autoDispose
    .family<Product?, String>((ref, scanned) {
      return ref.watch(productCatalogServiceProvider).lookupForPos(scanned);
    });
