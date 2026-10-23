import 'production_service.dart';

class PurchaseStockConversion {
  static String normalize(String unit) => unit.trim().toLowerCase();

  static bool usesConfiguredPurchaseUnit({
    required String lineUnit,
    required String? purchaseUnit,
  }) {
    final normalizedLine = normalize(lineUnit);
    final normalizedPurchase = normalize(purchaseUnit ?? '');
    return normalizedPurchase.isEmpty ||
        normalizedLine.isEmpty ||
        normalizedLine == normalizedPurchase;
  }

  static double baseUnitsPerLineUnit({
    required String lineUnit,
    required String stockUnit,
    required String? purchaseUnit,
    required double configuredUnitsPerPurchase,
  }) {
    final normalizedLine = normalize(lineUnit);
    final normalizedStock = normalize(stockUnit);
    final normalizedPurchase = normalize(purchaseUnit ?? '');
    final configuredFactor = configuredUnitsPerPurchase > 0
        ? configuredUnitsPerPurchase
        : 1.0;

    if (normalizedLine.isEmpty || normalizedLine == normalizedPurchase) {
      return configuredFactor;
    }
    if (normalizedLine == normalizedStock) return 1.0;
    if (UnitConverter.areCompatible(normalizedLine, normalizedStock)) {
      return UnitConverter.convert(1, normalizedLine, normalizedStock);
    }
    return configuredFactor;
  }
}
