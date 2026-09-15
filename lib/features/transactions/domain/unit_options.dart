// lib/features/production/domain/unit_options.dart
//
// Every dropdown in the app that asks "what unit?" should read from
// here — one place to add/rename a unit instead of hunting through
// every form. Kept deliberately small and curated (not every alias
// UnitConverter understands) so the dropdowns stay easy to scan.

import 'production_service.dart';

/// The BASE units BOS tracks stock in. Deliberately just five —
/// mass, volume, and a single generic count unit. "Cups" and "lids"
/// are supply NAMES counted in pieces, not units of their own; this
/// keeps the unit model simple and unambiguous.
const List<String> kStockUnitOptions = ['g', 'kg', 'ml', 'L', 'piece'];

/// Display labels for stock units, since a plain "g" or "L" in a
/// dropdown can look terse — pairs the short unit with what it means.
const Map<String, String> kStockUnitLabels = {
  'g': 'g (grams)',
  'kg': 'kg (kilograms)',
  'ml': 'ml (milliliters)',
  'L': 'L (liters)',
  'piece': 'piece (counted individually)',
};

/// Common PURCHASE units — how something arrives from a supplier.
/// "Custom" lets an owner type something not on this list without
/// the whole field going back to free text by default.
const List<String> kPurchaseUnitOptions = [
  'pack',
  'sack',
  'case',
  'bottle',
  'box',
  'carton',
  'dozen',
  'roll',
  'tray',
  'set',
  'sleeve',
  'jar',
  'can',
];
const String kCustomUnitOption = 'Custom…';

/// Returns the curated stock units that are dimensionally compatible
/// with [referenceUnit] — e.g. passing "g" returns ["g", "kg"].
/// Falls back to all stock units if the reference unit isn't
/// recognized (shouldn't normally happen once everything is a
/// dropdown, but keeps the UI from dead-ending if it does).
List<String> compatibleStockUnits(String referenceUnit) {
  final dimension = UnitConverter.dimensionOf(referenceUnit);
  if (dimension == null) return kStockUnitOptions;
  return kStockUnitOptions
      .where((u) => UnitConverter.dimensionOf(u) == dimension)
      .toList();
}
