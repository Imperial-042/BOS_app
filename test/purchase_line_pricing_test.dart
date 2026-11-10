import 'package:bos_application/core/business/current_business.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/transactions/domain/costing_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_draft_cart_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_cart_search.dart';
import 'package:bos_application/features/transactions/domain/purchase_line_pricing.dart';
import 'package:bos_application/features/transactions/domain/purchase_unit_options.dart';
import 'package:bos_application/features/transactions/domain/purchase_stock_conversion.dart';
import 'package:bos_application/features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/purchase_line_editor_dialog.dart';
import 'package:bos_application/features/transactions/presentation/widgets/supply_catalog_filters.dart'
    show supplyMatchesSearch;
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Supply makeSupply({
  String id = 'supply-1',
  String name = 'Coffee Beans',
  int currentPrice = 9900,
}) {
  final now = DateTime(2024, 1, 1);

  return Supply(
    id: id,
    businessId: 'business-1',
    name: name,
    brand: 'BOS',
    unitQuantity: 1,
    unit: 'kg',
    lastStoreName: null,
    lastStoreAddress: null,
    currentPrice: currentPrice,
    notes: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    currentStock: 10,
    minimumStock: 0,
    maximumStock: 20,
    lowStockThreshold: 2,
    stockUnit: 'kg',
    purchaseUnit: 'bag',
    unitsPerPurchase: 1,
    costPerBaseUnit: 10000,
    sku: null,
    barcode: null,
    categoryId: null,
    isSoldByWeight: false,
    imagePath: null,
    sortOrder: 0,
  );
}

void main() {
  late AppDatabase database;

  setUp(() async {
    setCurrentBusinessIdForTest('business-1');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database
        .into(database.businesses)
        .insert(
          BusinessesCompanion.insert(
            id: 'business-1',
            name: 'Test business',
            ownerUserId: 'owner-1',
          ),
        );
    await database
        .into(database.businesses)
        .insert(
          BusinessesCompanion.insert(
            id: 'business-2',
            name: 'Second business',
            ownerUserId: 'owner-2',
          ),
        );
    for (final businessId in ['business-1', 'business-2']) {
      await database
          .into(database.branches)
          .insert(
            BranchesCompanion.insert(
              id: AppDatabase.mainBranchId(businessId),
              businessId: businessId,
              name: 'Main Branch',
              isHeadquarters: const Value(true),
            ),
          );
    }
    await database.into(database.supplies).insert(makeSupply());
    final branchId = AppDatabase.mainBranchId('business-1');
    await StockService(database, viewBranchId: branchId).moveSupply(
      branchId: branchId,
      supplyId: 'supply-1',
      type: 'opening_balance',
      quantity: 10,
      unit: 'kg',
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('purchase line pricing', () {
    test('cart search matches every purchase review field', () {
      final fields = {
        'itemName': 'Coke Zero',
        'brand': 'Coca-Cola',
        'category': 'Beverages',
        'barcode': '89012345',
        'store': 'Corner Market',
        'address': '12 Market Road',
        'unit': 'piece',
        'finalTotalCents': 1400,
        'unitPriceCents': 1400,
        'grossTotalCents': 1500,
        'discountCents': 100,
        'catalogPriceCents': 14000,
      };

      for (final query in [
        'coke zero',
        'coca-cola',
        'beverages',
        '89012345',
        'corner market',
        'market road',
        'piece',
        '14.00',
        '15.00',
      ]) {
        expect(
          matchesPurchaseCartSearch(
            query: query,
            itemName: fields['itemName'] as String,
            brand: fields['brand'] as String,
            category: fields['category'] as String,
            barcode: fields['barcode'] as String,
            store: fields['store'] as String,
            address: fields['address'] as String,
            unit: fields['unit'] as String,
            finalTotalCents: fields['finalTotalCents'] as int,
            unitPriceCents: fields['unitPriceCents'] as int,
            grossTotalCents: fields['grossTotalCents'] as int,
            discountCents: fields['discountCents'] as int,
            catalogPriceCents: fields['catalogPriceCents'] as int,
          ),
          isTrue,
          reason: query,
        );
      }
      expect(
        matchesPurchaseCartSearch(
          query: 'unknown item',
          itemName: fields['itemName'] as String,
        ),
        isFalse,
      );
    });

    test('catalog search matches price, category, barcode, and store', () {
      final supply = makeSupply().copyWith(
        name: 'Rice',
        brand: const Value('Harvest'),
        barcode: const Value('89012345'),
        lastStoreName: const Value('Corner Market'),
      );
      const categories = {'category-rice': 'Grains'};
      final categorizedSupply = supply.copyWith(
        categoryId: const Value('category-rice'),
      );

      expect(supplyMatchesSearch(categorizedSupply, 'rice'), isTrue);
      expect(supplyMatchesSearch(categorizedSupply, 'harvest'), isTrue);
      expect(supplyMatchesSearch(categorizedSupply, '99.00'), isTrue);
      expect(
        supplyMatchesSearch(
          categorizedSupply,
          'grains',
          categoryNames: categories,
        ),
        isTrue,
      );
      expect(supplyMatchesSearch(categorizedSupply, '89012345'), isTrue);
      expect(supplyMatchesSearch(categorizedSupply, 'corner market'), isTrue);
      expect(supplyMatchesSearch(categorizedSupply, 'wheat'), isFalse);
    });

    test('converts purchase prices consistently across unit families', () {
      final conversions = [
        (
          name: 'sack to kg',
          priceCents: 80000,
          fromFactor: 10.0,
          toFactor: 1.0,
          expectedCents: 8000,
        ),
        (
          name: 'case to piece',
          priceCents: 14000,
          fromFactor: 1.0,
          toFactor: 0.1,
          expectedCents: 1400,
        ),
        (
          name: 'box to bottle',
          priceCents: 24000,
          fromFactor: 1.0,
          toFactor: 1 / 24,
          expectedCents: 1000,
        ),
        (
          name: 'liter to milliliter',
          priceCents: 10000,
          fromFactor: 1.0,
          toFactor: 0.001,
          expectedCents: 10,
        ),
        (
          name: 'kilogram to gram',
          priceCents: 20000,
          fromFactor: 1.0,
          toFactor: 0.001,
          expectedCents: 20,
        ),
        (
          name: 'drum to liter',
          priceCents: 50000,
          fromFactor: 200.0,
          toFactor: 1.0,
          expectedCents: 250,
        ),
      ];

      for (final conversion in conversions) {
        expect(
          PurchaseLinePricing.convertPriceCents(
            priceCents: conversion.priceCents,
            fromStockUnitsPerUnit: conversion.fromFactor,
            toStockUnitsPerUnit: conversion.toFactor,
          ),
          conversion.expectedCents,
          reason: conversion.name,
        );
      }
    });

    test('purchase-record price updates case and piece line prices', () async {
      final cart = CartNotifier(
        PurchaseDraftCartService(database),
        'business-1',
      );
      final supply = makeSupply().copyWith(
        unit: const Value('case'),
        stockUnit: 'case',
        purchaseUnit: const Value('case'),
        unitsPerPurchase: 1,
        currentPrice: 14000,
      );
      await cart.addOrIncrement(supply);
      final caseLine = cart.state.single;
      await cart.applyPurchaseEntry(
        supplyId: supply.id,
        priceCents: 80000,
        name: supply.name,
        unit: 'case',
        unitQuantity: 1,
        previousPriceCents: 14000,
        previousUnitsPerPurchase: 1,
      );
      expect(cart.state.single.id, caseLine.id);
      expect(cart.state.single.unitPrice, 80000);
      expect(cart.state.single.lineTotal, 80000);

      final piecePricing = PurchaseLinePricing.calculate(
        quantity: 1,
        unitPriceCents: 8000,
        discountType: PurchaseLinePricing.noDiscount,
        discountValue: 0,
        unitName: 'piece',
        stockUnitsPerUnit: 0.1,
      );
      await cart.updateLinePricing(
        caseLine.id,
        piecePricing,
        isWeighted: false,
      );
      await cart.applyPurchaseEntry(
        supplyId: supply.id,
        priceCents: 100000,
        name: supply.name,
        unit: 'case',
        unitQuantity: 1,
        previousPriceCents: 80000,
        previousUnitsPerPurchase: 1,
      );
      expect(cart.state.single.unit, 'piece');
      expect(cart.state.single.unitPrice, 10000);
      expect(cart.state.single.lineTotal, 10000);
    });

    test(
      'purchase-record price does not overwrite a manually-priced line',
      () async {
        final cart = CartNotifier(
          PurchaseDraftCartService(database),
          'business-1',
        );
        final supply = makeSupply(currentPrice: 9900);
        await cart.addOrIncrement(supply);
        final item = cart.state.single;
        await cart.updatePrice(item.id, 8000);
        await cart.applyPurchaseEntry(
          supplyId: supply.id,
          priceCents: 12000,
          name: supply.name,
          previousPriceCents: 9900,
          previousUnitsPerPurchase: 1,
        );

        expect(cart.state.single.lineTotal, 8000);
      },
    );

    testWidgets('switching a case line to one piece converts its price', (
      tester,
    ) async {
      PurchaseLinePricingResult? savedPricing;
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pageContext = context;
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      savedPricing = await showPurchaseLineEditorDialog(
                        pageContext,
                        itemName: 'Coke',
                        quantityLabel: 'Quantity',
                        unit: 'case',
                        stockUnitsPerUnit: 1,
                        unitOptions: const [
                          PurchaseUnitOption(
                            name: 'case',
                            stockUnitsPerUnit: 1,
                          ),
                          PurchaseUnitOption(
                            name: 'piece',
                            stockUnitsPerUnit: 0.1,
                          ),
                        ],
                        quantity: 1,
                        isWeighted: false,
                        unitPriceCents: 14000,
                        grossTotalCents: 14000,
                        finalTotalCents: 14000,
                        discountType: PurchaseLinePricing.noDiscount,
                        discountValue: 0,
                        originalUnitPriceCents: 14000,
                        originalStockUnitsPerUnit: 1,
                      );
                    },
                    child: const Text('Edit line'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Edit line'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('piece').last);
      await tester.pumpAndSettle();

      TextField field(String label) => tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
      );
      expect(field('Quantity').controller!.text, '10');
      expect(field('Total Purchase Price').controller!.text, '140.00');

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(savedPricing!.unitName, 'piece');
      expect(savedPricing!.quantity, 10);
      expect(savedPricing!.stockUnitsPerUnit, closeTo(0.1, 0.000001));
      expect(savedPricing!.unitPriceCents, 1400);
      expect(savedPricing!.finalTotalCents, 14000);
    });

    test('keeps separate same-product lines through database reload', () async {
      final store = PurchaseDraftCartService(database);
      final cart = CartNotifier(store, 'business-1');
      final supply = makeSupply();

      await cart.addOrIncrement(supply);
      await cart.addOrIncrement(supply);
      await cart.updatePrice(cart.state.first.id, 18900);
      await cart.updateQuantity(cart.state.last.id, 2);

      expect(cart.state.length, 2);

      final restored = CartNotifier(store, 'business-1');
      await restored.load();

      expect(restored.state.length, 2);
      expect(restored.state.map((item) => item.lineTotal), [18900, 19800]);
      expect(restored.state.map((item) => item.quantity), [1, 2]);
      expect(restored.state.first.id, cart.state.first.id);
    });

    test('persists edited quantity and total before updating state', () async {
      final store = PurchaseDraftCartService(database);
      final cart = CartNotifier(store, 'business-1');
      await cart.addOrIncrement(makeSupply(currentPrice: 9900));

      final item = cart.state.single;
      await cart.updatePrice(item.id, 12000);
      await cart.updateQuantity(item.id, 2);

      expect(cart.state.single.lineTotal, 24000);
      final persisted = await store.load('business-1');
      expect(persisted!.lines.single.lineTotal, 24000);
      expect(persisted.lines.single.quantity, 2);
    });

    test(
      'deletes only the selected line and explicit clear removes draft',
      () async {
        final store = PurchaseDraftCartService(database);
        final cart = CartNotifier(store, 'business-1');
        await cart.addOrIncrement(makeSupply());
        await cart.addOrIncrement(makeSupply());
        final keptLineId = cart.state.last.id;

        await cart.removeItem(cart.state.first.id);
        final restored = CartNotifier(store, 'business-1');
        await restored.load();
        expect(restored.state.map((line) => line.id), [keptLineId]);

        await restored.clear();
        expect(await store.load('business-1'), isNull);
      },
    );

    test('draft carts are isolated by business', () async {
      final store = PurchaseDraftCartService(database);
      final firstBusinessCart = CartNotifier(store, 'business-1');
      final secondBusinessCart = CartNotifier(store, 'business-2');
      await firstBusinessCart.addCustomItem(name: 'A item', unitPrice: 1000);
      await secondBusinessCart.addCustomItem(name: 'B item', unitPrice: 2000);

      final restoredFirst = CartNotifier(store, 'business-1');
      final restoredSecond = CartNotifier(store, 'business-2');
      await restoredFirst.load();
      await restoredSecond.load();

      expect(restoredFirst.state.single.name, 'A item');
      expect(restoredSecond.state.single.name, 'B item');
    });

    test(
      'persists fixed discount and store/address metadata on reload',
      () async {
        final store = PurchaseDraftCartService(database);
        final cart = CartNotifier(store, 'business-1');
        await cart.addOrIncrement(makeSupply());
        final line = cart.state.single;
        final pricing = PurchaseLinePricing.calculate(
          quantity: 2,
          unitPriceCents: 9900,
          discountType: PurchaseLinePricing.fixedDiscount,
          discountValue: 900,
        );
        await cart.updateLinePricing(line.id, pricing, isWeighted: false);
        await cart.updateDraftMetadata(
          storeName: 'Fresh Mart',
          storeAddress: '12 Market Road',
        );

        final restored = CartNotifier(store, 'business-1');
        await restored.load();
        final persisted = await store.load('business-1');

        expect(restored.state.single.quantity, 2);
        expect(restored.state.single.lineTotal, 18900);
        expect(persisted!.lines.single.grossLineTotal, 19800);
        expect(persisted.lines.single.discountAmount, 900);
        expect(persisted.header.storeName, 'Fresh Mart');
        expect(persisted.header.storeAddress, '12 Market Road');
      },
    );

    test('percentage discount calculates against gross only once', () {
      final pricing = PurchaseLinePricing.calculate(
        quantity: 2,
        unitPriceCents: 9900,
        discountType: PurchaseLinePricing.percentageDiscount,
        discountValue: 5,
      );

      expect(pricing.grossTotalCents, 19800);
      expect(pricing.discountAmountCents, 990);
      expect(pricing.finalTotalCents, 18810);
    });

    test('failed line persistence leaves provider state unchanged', () async {
      final cart = CartNotifier(
        PurchaseDraftCartService(database),
        'business-1',
      );

      await expectLater(
        cart.addOrIncrement(makeSupply(id: 'missing-supply')),
        throwsA(anything),
      );

      expect(cart.state, isEmpty);
      expect(
        await PurchaseDraftCartService(database).load('business-1'),
        isNull,
      );
    });

    test('uses weighted-average cost with actual purchase value', () {
      final result = CostingService.calculateWeightedAverageCost(
        existingQuantity: 10,
        existingValueCents: 100000,
        incomingQuantity: 3,
        incomingValueCents: 28800,
      );

      expect(result, closeTo(9907.6923076923, 0.01));
    });

    test('converts from the cart line unit instead of the catalog package', () {
      expect(
        PurchaseStockConversion.baseUnitsPerLineUnit(
          lineUnit: 'kg',
          stockUnit: 'kg',
          purchaseUnit: 'sack',
          configuredUnitsPerPurchase: 10,
        ),
        1,
      );
      expect(
        PurchaseStockConversion.baseUnitsPerLineUnit(
          lineUnit: 'sack',
          stockUnit: 'kg',
          purchaseUnit: 'sack',
          configuredUnitsPerPurchase: 10,
        ),
        10,
      );
      expect(
        PurchaseStockConversion.baseUnitsPerLineUnit(
          lineUnit: 'g',
          stockUnit: 'kg',
          purchaseUnit: 'sack',
          configuredUnitsPerPurchase: 10,
        ),
        closeTo(0.001, 0.000001),
      );
    });

    test('kg purchase does not overwrite sack catalog conversion', () async {
      await (database.update(
        database.supplies,
      )..where((supply) => supply.id.equals('supply-1'))).write(
        const SuppliesCompanion(
          purchaseUnit: Value('sack'),
          unitsPerPurchase: Value(10),
        ),
      );

      final conversion = PurchaseStockConversion.baseUnitsPerLineUnit(
        lineUnit: 'kg',
        stockUnit: 'kg',
        purchaseUnit: 'sack',
        configuredUnitsPerPurchase: 10,
      );
      await CostingService(
        database,
        branchId: AppDatabase.mainBranchId('business-1'),
      ).recordPurchase(
        supplyId: 'supply-1',
        pricePerPurchaseUnitCents: 9000,
        purchaseQuantity: 1,
        unitsPerPurchase: conversion,
        purchaseUnit: 'kg',
        storeName: 'Test store',
        date: DateTime(2026, 10, 1),
        actualTotalPriceCents: 9000,
        updateSupplyReferenceFields: false,
      );

      final supply = await (database.select(
        database.supplies,
      )..where((row) => row.id.equals('supply-1'))).getSingle();
      expect(supply.currentStock, 11);
      expect(supply.purchaseUnit, 'sack');
      expect(supply.unitsPerPurchase, 10);
    });

    test('case and piece options use their own stock conversion', () async {
      await (database.update(
        database.supplies,
      )..where((supply) => supply.id.equals('supply-1'))).write(
        const SuppliesCompanion(
          stockUnit: Value('case'),
          purchaseUnit: Value('case'),
          unitsPerPurchase: Value(1),
          currentPrice: Value(14000),
        ),
      );
      await database
          .into(database.supplyUnitConversions)
          .insert(
            SupplyUnitConversionsCompanion.insert(
              supplyId: 'supply-1',
              unitName: 'piece',
              unitsPerStockUnit: 10,
            ),
          );

      final options = await PurchaseUnitOptions.load(
        db: database,
        supplyId: 'supply-1',
        currentUnit: 'case',
      );
      final factorByName = {
        for (final option in options) option.name: option.stockUnitsPerUnit,
      };
      expect(factorByName['case'], 1);
      expect(factorByName['piece'], closeTo(0.1, 0.000001));

      final cart = CartNotifier(
        PurchaseDraftCartService(database),
        'business-1',
      );
      await cart.addOrIncrement(
        makeSupply().copyWith(
          stockUnit: 'case',
          purchaseUnit: const Value('case'),
          unitsPerPurchase: 1,
          currentPrice: 14000,
        ),
      );
      final line = cart.state.single;
      await cart.updateLinePricing(
        line.id,
        PurchaseLinePricing.calculate(
          quantity: 1,
          unitPriceCents: 1400,
          discountType: PurchaseLinePricing.noDiscount,
          discountValue: 0,
          unitName: 'piece',
          stockUnitsPerUnit: factorByName['piece']!,
        ),
        isWeighted: false,
      );

      final restored = CartNotifier(
        PurchaseDraftCartService(database),
        'business-1',
      );
      await restored.load();
      expect(restored.state.single.unit, 'piece');
      expect(restored.state.single.stockUnitsPerUnit, closeTo(0.1, 0.000001));

      final costing = CostingService(
        database,
        branchId: AppDatabase.mainBranchId('business-1'),
      );
      await costing.recordPurchase(
        supplyId: 'supply-1',
        pricePerPurchaseUnitCents: 1400,
        purchaseQuantity: 1,
        unitsPerPurchase: factorByName['piece']!,
        purchaseUnit: 'piece',
        storeName: 'Test store',
        date: DateTime(2026, 10, 1),
        actualTotalPriceCents: 1400,
        updateSupplyReferenceFields: false,
      );
      var supplyAfterPiece = await (database.select(
        database.supplies,
      )..where((row) => row.id.equals('supply-1'))).getSingle();
      expect(supplyAfterPiece.currentStock, closeTo(10.1, 0.000001));
      expect(supplyAfterPiece.purchaseUnit, 'case');

      await costing.recordPurchase(
        supplyId: 'supply-1',
        pricePerPurchaseUnitCents: 14000,
        purchaseQuantity: 1,
        unitsPerPurchase: factorByName['case']!,
        purchaseUnit: 'case',
        storeName: 'Test store',
        date: DateTime(2026, 10, 1),
        actualTotalPriceCents: 14000,
      );
      supplyAfterPiece = await (database.select(
        database.supplies,
      )..where((row) => row.id.equals('supply-1'))).getSingle();
      expect(supplyAfterPiece.currentStock, closeTo(11.1, 0.000001));
      expect(supplyAfterPiece.purchaseUnit, 'case');
      expect(supplyAfterPiece.unitsPerPurchase, 1);
    });
  });
}
