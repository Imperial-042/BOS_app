// lib/features/production/presentation/screens/pos_sell_limit.dart
//
// "How many of this product can the cashier sell right now?" for EVERY kind
// of product, using Products.trackingType:
//
//   recipe       -> limited by the supplies in its recipe (producibility)
//   stocked      -> limited by Products.currentStock (resale items)
//   non_stocked  -> no limit (services, untracked items)
//
// A recipe product with no ingredients is still blocked (noRecipe).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/producibility_ext.dart';
import 'products_page.dart' show producibilityProvider;

class SellLimit {
  /// null = no limit.
  final int? maxUnits;

  /// Recipe bottleneck, used in "out of ..." messages.
  final String? limiting;

  /// Recipe product that has no ingredients yet.
  final bool noRecipe;

  const SellLimit({this.maxUnits, this.limiting, this.noRecipe = false});
}

/// Live copy of one product row, so stocked quantities refresh the moment a
/// sale, void or restock changes them.
final posProductLiveProvider = StreamProvider.family<Product?, String>((
  ref,
  id,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.products,
  )..where((p) => p.id.equals(id))).watchSingleOrNull();
});

final sellLimitProvider = FutureProvider.family<SellLimit, String>((
  ref,
  productId,
) async {
  final product = await ref.watch(posProductLiveProvider(productId).future);
  if (product == null) return const SellLimit(maxUnits: 0);

  switch (product.trackingType) {
    case 'stocked':
      return SellLimit(maxUnits: product.currentStock.floor());
    case 'non_stocked':
      return const SellLimit();
    default:
      final r = await ref.watch(producibilityProvider(productId).future);
      if (!r.hasRecipe) return const SellLimit(noRecipe: true);
      return SellLimit(maxUnits: r.maxUnits, limiting: r.limitingComponentName);
  }
});
