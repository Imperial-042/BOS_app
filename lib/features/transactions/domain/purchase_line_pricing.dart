class PurchaseLinePricingResult {
  final double quantity;
  final int unitPriceCents;
  final int grossTotalCents;
  final String discountType;
  final double discountValue;
  final int discountAmountCents;
  final int finalTotalCents;
  final String unitName;
  final double stockUnitsPerUnit;

  /// The original stored unit price this line's price derives from, in cents.
  /// Unit switches always convert from this anchor — never from an already
  /// converted/rounded price — so switching back restores the exact original.
  final int? originalUnitPriceCents;

  /// Conversion factor of the unit the [originalUnitPriceCents] is for,
  /// expressed in stock units per unit.
  final double? originalStockUnitsPerUnit;

  const PurchaseLinePricingResult({
    required this.quantity,
    required this.unitPriceCents,
    required this.grossTotalCents,
    required this.discountType,
    required this.discountValue,
    required this.discountAmountCents,
    required this.finalTotalCents,
    required this.unitName,
    required this.stockUnitsPerUnit,
    this.originalUnitPriceCents,
    this.originalStockUnitsPerUnit,
  });
}

/// Result of converting an anchored unit price to a different unit.
class ConvertedUnitPrice {
  /// The converted price rounded to whole cents for display and storage.
  final int unitPriceCents;

  /// The unrounded converted price in cents. Line totals must be computed
  /// from this value so currency rounding happens only once, on the total.
  final double preciseUnitPriceCents;

  const ConvertedUnitPrice({
    required this.unitPriceCents,
    required this.preciseUnitPriceCents,
  });
}

class PurchaseLinePricing {
  static const noDiscount = 'none';
  static const fixedDiscount = 'fixed';
  static const percentageDiscount = 'percent';

  static int convertPriceCents({
    required int priceCents,
    required double fromStockUnitsPerUnit,
    required double toStockUnitsPerUnit,
  }) {
    if (!fromStockUnitsPerUnit.isFinite ||
        !toStockUnitsPerUnit.isFinite ||
        fromStockUnitsPerUnit <= 0 ||
        toStockUnitsPerUnit <= 0) {
      throw ArgumentError('Unit conversion factors must be positive.');
    }
    return (priceCents * toStockUnitsPerUnit / fromStockUnitsPerUnit).round();
  }

  /// Unrounded converted unit price in cents, derived from the original
  /// stored price and conversion factor:
  ///
  /// `originalPriceCents * selectedFactor / originalFactor`
  ///
  /// Throws [ArgumentError] when the original price is negative or any
  /// conversion factor is not a positive finite number.
  static double precisePriceCents({
    required int originalPriceCents,
    required double originalStockUnitsPerUnit,
    required double selectedStockUnitsPerUnit,
  }) {
    if (originalPriceCents < 0) {
      throw ArgumentError('Original price must not be negative.');
    }
    if (!originalStockUnitsPerUnit.isFinite ||
        !selectedStockUnitsPerUnit.isFinite ||
        originalStockUnitsPerUnit <= 0 ||
        selectedStockUnitsPerUnit <= 0) {
      throw ArgumentError('Unit conversion factors must be positive.');
    }
    final precise =
        originalPriceCents *
        selectedStockUnitsPerUnit /
        originalStockUnitsPerUnit;
    if (!precise.isFinite) {
      throw ArgumentError('Converted price is not finite.');
    }
    return precise;
  }

  /// Converts the original (anchor) unit price to the price for the
  /// selected unit. Always derive from the original stored price — never
  /// chain conversions from an already converted, rounded price.
  static ConvertedUnitPrice priceForUnit({
    required int originalPriceCents,
    required double originalStockUnitsPerUnit,
    required double selectedStockUnitsPerUnit,
  }) {
    final precise = precisePriceCents(
      originalPriceCents: originalPriceCents,
      originalStockUnitsPerUnit: originalStockUnitsPerUnit,
      selectedStockUnitsPerUnit: selectedStockUnitsPerUnit,
    );
    return ConvertedUnitPrice(
      unitPriceCents: precise.round(),
      preciseUnitPriceCents: precise,
    );
  }

  static int discountAmountCents({
    required int grossTotalCents,
    required String discountType,
    required double discountValue,
  }) {
    if (grossTotalCents <= 0 || discountValue <= 0) return 0;
    if (discountType == fixedDiscount) {
      return discountValue.round().clamp(0, grossTotalCents);
    }
    if (discountType == percentageDiscount) {
      return (grossTotalCents * discountValue / 100).round().clamp(
        0,
        grossTotalCents,
      );
    }
    return 0;
  }

  static PurchaseLinePricingResult calculate({
    required double quantity,
    required int unitPriceCents,
    required String discountType,
    required double discountValue,
    String unitName = '',
    double stockUnitsPerUnit = 1,
    double? preciseUnitPriceCents,
    int? originalUnitPriceCents,
    double? originalStockUnitsPerUnit,
  }) {
    // Totals use the unrounded converted price when available so currency
    // rounding is applied once, on the monetary total — not per unit.
    final effectiveUnitPrice =
        preciseUnitPriceCents != null &&
            preciseUnitPriceCents.isFinite &&
            preciseUnitPriceCents >= 0
        ? preciseUnitPriceCents
        : unitPriceCents.toDouble();
    final grossTotalCents = (quantity * effectiveUnitPrice).round();
    final validDiscountType = discountValue <= 0 ? noDiscount : discountType;
    final discountAmount = discountAmountCents(
      grossTotalCents: grossTotalCents,
      discountType: validDiscountType,
      discountValue: discountValue,
    );
    return PurchaseLinePricingResult(
      quantity: quantity,
      unitPriceCents: unitPriceCents,
      grossTotalCents: grossTotalCents,
      discountType: validDiscountType,
      discountValue: validDiscountType == noDiscount ? 0 : discountValue,
      discountAmountCents: discountAmount,
      finalTotalCents: grossTotalCents - discountAmount,
      unitName: unitName,
      stockUnitsPerUnit: stockUnitsPerUnit,
      originalUnitPriceCents: originalUnitPriceCents,
      originalStockUnitsPerUnit: originalStockUnitsPerUnit,
    );
  }
}
