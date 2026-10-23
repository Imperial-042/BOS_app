// lib/features/production/domain/producibility_ext.dart
//
// Single source of truth for "does this product have a recipe?".
// (Was copy-pasted in pos_page.dart and pos_checkout_sheet.dart.)

import 'production_service.dart' show ProducibilityResult;

extension ProducibilityResultX on ProducibilityResult {
  /// A product only counts as "having a recipe" when it has at least one
  /// ingredient. Same rule the Products page uses for "No recipe set".
  bool get hasRecipe =>
      limitingComponentName != null || componentMaxUnits.isNotEmpty;
}
