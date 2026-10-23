import '../../../core/database/app_database.dart';

class PurchaseUnitOption {
  final String name;
  final double stockUnitsPerUnit;

  const PurchaseUnitOption({
    required this.name,
    required this.stockUnitsPerUnit,
  });
}

class PurchaseUnitOptions {
  static Future<List<PurchaseUnitOption>> load({
    required AppDatabase db,
    required String? supplyId,
    String? currentUnit,
    double currentStockUnitsPerUnit = 1,
  }) async {
    if (supplyId == null) {
      final unit = (currentUnit ?? '').trim();
      return unit.isEmpty
          ? const []
          : [
              PurchaseUnitOption(
                name: unit,
                stockUnitsPerUnit: currentStockUnitsPerUnit,
              ),
            ];
    }
    final supply = await (db.select(
      db.supplies,
    )..where((row) => row.id.equals(supplyId))).getSingleOrNull();
    if (supply == null) return const [];

    final byNormalizedName = <String, PurchaseUnitOption>{};
    void add(String? rawName, double factor) {
      final name = (rawName ?? '').trim();
      if (name.isEmpty || factor <= 0) return;
      byNormalizedName.putIfAbsent(
        name.toLowerCase(),
        () => PurchaseUnitOption(name: name, stockUnitsPerUnit: factor),
      );
    }

    add(supply.stockUnit, 1);
    add(
      supply.purchaseUnit,
      supply.unitsPerPurchase > 0 ? supply.unitsPerPurchase : 1,
    );

    final alternates = await (db.select(
      db.supplyUnitConversions,
    )..where((row) => row.supplyId.equals(supplyId))).get();
    for (final alternate in alternates) {
      if (alternate.unitsPerStockUnit > 0) {
        add(alternate.unitName, 1 / alternate.unitsPerStockUnit);
      }
    }

    add(currentUnit, currentStockUnitsPerUnit);
    return byNormalizedName.values.toList(growable: false);
  }
}
