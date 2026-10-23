bool matchesPurchaseCartSearch({
  required String query,
  required String itemName,
  String? brand,
  String? category,
  String? barcode,
  String? store,
  String? address,
  String? unit,
  int? finalTotalCents,
  int? unitPriceCents,
  int? grossTotalCents,
  int? discountCents,
  int? catalogPriceCents,
}) {
  final normalizedQuery = query
      .trim()
      .toLowerCase()
      .replaceAll(',', '')
      .replaceAll('₱', '');
  if (normalizedQuery.isEmpty) return true;

  String priceText(int? cents) =>
      cents == null ? '' : '${(cents / 100).toStringAsFixed(2)} $cents';

  final values = [
    itemName,
    brand ?? '',
    category ?? '',
    barcode ?? '',
    store ?? '',
    address ?? '',
    unit ?? '',
    priceText(finalTotalCents),
    priceText(unitPriceCents),
    priceText(grossTotalCents),
    priceText(discountCents),
    priceText(catalogPriceCents),
  ];

  return values.any(
    (value) =>
        value.toLowerCase().replaceAll(',', '').contains(normalizedQuery),
  );
}
