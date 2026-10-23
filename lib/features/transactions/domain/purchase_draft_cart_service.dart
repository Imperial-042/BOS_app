import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class PurchaseDraftCartLine {
  final String id;
  final String? supplyId;
  final String itemName;
  final String? brand;
  final double? unitQuantity;
  final String? unit;
  final double stockUnitsPerUnit;
  final int unitPrice;
  final int quantity;
  final bool isWeighted;
  final double? weightQuantity;
  final int grossLineTotal;
  final String discountType;
  final double discountValue;
  final int discountAmount;
  final int lineTotal;
  final int? originalUnitPrice;
  final double? originalStockUnitsPerUnit;

  const PurchaseDraftCartLine({
    required this.id,
    required this.supplyId,
    required this.itemName,
    required this.brand,
    required this.unitQuantity,
    required this.unit,
    required this.stockUnitsPerUnit,
    required this.unitPrice,
    required this.quantity,
    required this.isWeighted,
    required this.weightQuantity,
    required this.grossLineTotal,
    required this.discountType,
    required this.discountValue,
    required this.discountAmount,
    required this.lineTotal,
    this.originalUnitPrice,
    this.originalStockUnitsPerUnit,
  });

  factory PurchaseDraftCartLine.fromRow(ShoppingCartItem row) {
    return PurchaseDraftCartLine(
      id: row.id,
      supplyId: row.supplyId,
      itemName: row.itemName,
      brand: row.brand,
      unitQuantity: row.unitQuantity,
      unit: row.unit,
      stockUnitsPerUnit: row.stockUnitsPerUnit,
      unitPrice: row.unitPrice,
      quantity: row.quantity,
      isWeighted: row.isWeighted,
      weightQuantity: row.weightQuantity,
      grossLineTotal: row.grossLineTotal,
      discountType: row.discountType,
      discountValue: row.discountValue,
      discountAmount: row.discountAmount,
      lineTotal: row.lineTotal,
      originalUnitPrice: row.originalUnitPrice,
      originalStockUnitsPerUnit: row.originalStockUnitsPerUnit,
    );
  }

  ShoppingCartItemsCompanion toCompanion(String cartId) {
    return ShoppingCartItemsCompanion.insert(
      id: id,
      cartId: cartId,
      supplyId: Value(supplyId),
      itemName: itemName,
      brand: Value(brand),
      unitQuantity: Value(unitQuantity),
      unit: Value(unit),
      stockUnitsPerUnit: Value(stockUnitsPerUnit),
      unitPrice: unitPrice,
      quantity: Value(quantity),
      isWeighted: Value(isWeighted),
      weightQuantity: Value(weightQuantity),
      grossLineTotal: Value(grossLineTotal),
      discountType: Value(discountType),
      discountValue: Value(discountValue),
      discountAmount: Value(discountAmount),
      lineTotal: lineTotal,
      originalUnitPrice: Value(originalUnitPrice),
      originalStockUnitsPerUnit: Value(originalStockUnitsPerUnit),
    );
  }
}

class PurchaseDraftCart {
  final ShoppingCart header;
  final List<PurchaseDraftCartLine> lines;

  const PurchaseDraftCart({required this.header, required this.lines});
}

class PurchaseDraftCartService {
  final AppDatabase db;

  const PurchaseDraftCartService(this.db);

  Future<PurchaseDraftCart?> load(String businessId) async {
    final draft = await _findDraft(businessId);
    if (draft == null) return null;

    final rows = await (db.select(
      db.shoppingCartItems,
    )..where((item) => item.cartId.equals(draft.id))).get();
    return PurchaseDraftCart(
      header: draft,
      lines: rows.map(PurchaseDraftCartLine.fromRow).toList(),
    );
  }

  Future<void> save({
    required String businessId,
    required List<PurchaseDraftCartLine> lines,
    required int totalAmount,
    Value<String?> storeName = const Value.absent(),
    Value<String?> storeAddress = const Value.absent(),
  }) async {
    await db.transaction(() async {
      var draft = await _findDraft(businessId);

      if (lines.isEmpty) {
        if (draft != null) {
          await (db.delete(
            db.shoppingCarts,
          )..where((cart) => cart.id.equals(draft!.id))).go();
        }
        return;
      }

      final now = DateTime.now();
      if (draft == null) {
        final id = 'draft-${now.microsecondsSinceEpoch}-$businessId';
        await db
            .into(db.shoppingCarts)
            .insert(
              ShoppingCartsCompanion.insert(
                id: id,
                businessId: businessId,
                cartDate: now,
                storeName: storeName,
                storeAddress: storeAddress,
                totalAmount: totalAmount,
              ),
            );
        draft = await (db.select(
          db.shoppingCarts,
        )..where((cart) => cart.id.equals(id))).getSingle();
      } else {
        await (db.update(
          db.shoppingCarts,
        )..where((cart) => cart.id.equals(draft!.id))).write(
          ShoppingCartsCompanion(
            totalAmount: Value(totalAmount),
            cartDate: Value(now),
            storeName: storeName,
            storeAddress: storeAddress,
          ),
        );
      }

      final savedIds = lines.map((line) => line.id).toList();
      if (savedIds.isNotEmpty) {
        await (db.delete(db.shoppingCartItems)..where(
              (item) =>
                  item.cartId.equals(draft!.id) & item.id.isNotIn(savedIds),
            ))
            .go();
      } else {
        await (db.delete(
          db.shoppingCartItems,
        )..where((item) => item.cartId.equals(draft!.id))).go();
      }

      for (final line in lines) {
        await db
            .into(db.shoppingCartItems)
            .insertOnConflictUpdate(line.toCompanion(draft.id));
      }
    });
  }

  Future<void> updateMetadata({
    required String businessId,
    required String? storeName,
    required String? storeAddress,
  }) async {
    await db.transaction(() async {
      var draft = await _findDraft(businessId);
      final now = DateTime.now();
      if (draft == null) {
        if ((storeName ?? '').trim().isEmpty &&
            (storeAddress ?? '').trim().isEmpty) {
          return;
        }
        final id = 'draft-${now.microsecondsSinceEpoch}-$businessId';
        await db
            .into(db.shoppingCarts)
            .insert(
              ShoppingCartsCompanion.insert(
                id: id,
                businessId: businessId,
                cartDate: now,
                storeName: Value(storeName),
                storeAddress: Value(storeAddress),
                totalAmount: 0,
              ),
            );
        draft = await (db.select(
          db.shoppingCarts,
        )..where((cart) => cart.id.equals(id))).getSingle();
      } else {
        await (db.update(
          db.shoppingCarts,
        )..where((cart) => cart.id.equals(draft!.id))).write(
          ShoppingCartsCompanion(
            storeName: Value(storeName),
            storeAddress: Value(storeAddress),
            cartDate: Value(now),
          ),
        );
      }
    });
  }

  Future<void> clear(String businessId) async {
    await db.transaction(() async {
      final draft = await _findDraft(businessId);
      if (draft == null) return;
      await (db.delete(
        db.shoppingCarts,
      )..where((cart) => cart.id.equals(draft.id))).go();
    });
  }

  Future<void> deleteDraftInTransaction(String businessId) async {
    final draft = await _findDraft(businessId);
    if (draft == null) return;
    await (db.delete(
      db.shoppingCarts,
    )..where((cart) => cart.id.equals(draft.id))).go();
  }

  Future<ShoppingCart?> _findDraft(String businessId) {
    return (db.select(db.shoppingCarts)
          ..where(
            (cart) =>
                cart.businessId.equals(businessId) & cart.expenseId.isNull(),
          )
          ..orderBy([
            (cart) => OrderingTerm.desc(cart.createdAt),
            (cart) => OrderingTerm.desc(cart.cartDate),
          ])
          ..limit(1))
        .getSingleOrNull();
  }
}
