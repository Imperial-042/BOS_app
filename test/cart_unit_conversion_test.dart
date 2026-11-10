import 'package:bos_application/core/business/current_business.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/transactions/domain/costing_service.dart';
import 'package:bos_application/features/transactions/domain/production_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_draft_cart_service.dart';
import 'package:bos_application/features/transactions/domain/purchase_line_pricing.dart';
import 'package:bos_application/features/transactions/domain/purchase_stock_conversion.dart';
import 'package:bos_application/features/transactions/domain/purchase_unit_options.dart';
import 'package:bos_application/features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/purchase_line_editor_dialog.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A "Coke"-style supply: stocked in pieces, purchased by the case of 12,
/// catalog price ₱160.00 per case.
Supply makeCokeSupply({
  String id = 'supply-coke',
  int currentPrice = 16000,
  double unitsPerPurchase = 12,
}) {
  final now = DateTime(2024, 1, 1);
  return Supply(
    id: id,
    businessId: 'business-1',
    name: 'Coke',
    brand: 'Coca-Cola',
    unitQuantity: unitsPerPurchase,
    unit: 'case',
    lastStoreName: null,
    lastStoreAddress: null,
    currentPrice: currentPrice,
    notes: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    currentStock: 100,
    minimumStock: 0,
    maximumStock: 500,
    lowStockThreshold: 12,
    stockUnit: 'piece',
    purchaseUnit: 'case',
    unitsPerPurchase: unitsPerPurchase,
    costPerBaseUnit: 1333,
    sku: null,
    barcode: null,
    categoryId: null,
    isSoldByWeight: false,
    imagePath: null,
    sortOrder: 0,
  );
}

/// Builds the pricing result the line editor dialog would return after the
/// user switched [line] to another unit — derived from the line's anchor.
PurchaseLinePricingResult switchUnitResult({
  required double quantity,
  required String unitName,
  required double stockUnitsPerUnit,
  required int anchorPriceCents,
  required double anchorFactor,
}) {
  final converted = PurchaseLinePricing.priceForUnit(
    originalPriceCents: anchorPriceCents,
    originalStockUnitsPerUnit: anchorFactor,
    selectedStockUnitsPerUnit: stockUnitsPerUnit,
  );
  return PurchaseLinePricing.calculate(
    quantity: quantity,
    unitPriceCents: converted.unitPriceCents,
    discountType: PurchaseLinePricing.noDiscount,
    discountValue: 0,
    unitName: unitName,
    stockUnitsPerUnit: stockUnitsPerUnit,
    preciseUnitPriceCents: converted.preciseUnitPriceCents,
    originalUnitPriceCents: anchorPriceCents,
    originalStockUnitsPerUnit: anchorFactor,
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
        .into(database.branches)
        .insert(
          BranchesCompanion.insert(
            id: AppDatabase.mainBranchId('business-1'),
            businessId: 'business-1',
            name: 'Main Branch',
            isHeadquarters: const Value(true),
          ),
        );
    await database.into(database.supplies).insert(makeCokeSupply());
    final branchId = AppDatabase.mainBranchId('business-1');
    await StockService(database, viewBranchId: branchId).moveSupply(
      branchId: branchId,
      supplyId: 'supply-coke',
      type: 'opening_balance',
      quantity: 100,
      unit: 'piece',
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('unit conversion pricing', () {
    test('Test 1: original unit keeps the original price', () {
      final converted = PurchaseLinePricing.priceForUnit(
        originalPriceCents: 16000,
        originalStockUnitsPerUnit: 12,
        selectedStockUnitsPerUnit: 12,
      );
      expect(converted.unitPriceCents, 16000);
      expect(converted.preciseUnitPriceCents, 16000);

      final pricing = PurchaseLinePricing.calculate(
        quantity: 2,
        unitPriceCents: converted.unitPriceCents,
        discountType: PurchaseLinePricing.noDiscount,
        discountValue: 0,
        unitName: 'case',
        stockUnitsPerUnit: 12,
        preciseUnitPriceCents: converted.preciseUnitPriceCents,
      );
      expect(pricing.grossTotalCents, 32000);
      expect(pricing.finalTotalCents, 32000);
    });

    test('Test 2: converting to pieces rounds only the total', () {
      final converted = PurchaseLinePricing.priceForUnit(
        originalPriceCents: 16000,
        originalStockUnitsPerUnit: 12,
        selectedStockUnitsPerUnit: 1,
      );
      // Displayed unit price is rounded to cents…
      expect(converted.unitPriceCents, 1333);
      // …but the precise price keeps full precision.
      expect(converted.preciseUnitPriceCents, closeTo(1333.333333, 0.0001));

      final pricing = PurchaseLinePricing.calculate(
        quantity: 5,
        unitPriceCents: converted.unitPriceCents,
        discountType: PurchaseLinePricing.noDiscount,
        discountValue: 0,
        unitName: 'piece',
        stockUnitsPerUnit: 1,
        preciseUnitPriceCents: converted.preciseUnitPriceCents,
      );
      // 16000 / 12 * 5 = 6666.67¢ ≈ ₱66.67 — not 1333 * 5 = ₱66.65.
      expect(pricing.grossTotalCents, 6667);
      expect(pricing.finalTotalCents, 6667);
    });

    test('Test 3: switching back to the original unit restores the price', () {
      const anchorPrice = 16000;
      const anchorFactor = 12.0;

      // case → piece → case, always converting from the anchor.
      final piece = PurchaseLinePricing.priceForUnit(
        originalPriceCents: anchorPrice,
        originalStockUnitsPerUnit: anchorFactor,
        selectedStockUnitsPerUnit: 1,
      );
      expect(piece.unitPriceCents, 1333);

      final backToCase = PurchaseLinePricing.priceForUnit(
        originalPriceCents: anchorPrice,
        originalStockUnitsPerUnit: anchorFactor,
        selectedStockUnitsPerUnit: 12,
      );
      expect(backToCase.unitPriceCents, anchorPrice);

      final pricing = PurchaseLinePricing.calculate(
        quantity: 2,
        unitPriceCents: backToCase.unitPriceCents,
        discountType: PurchaseLinePricing.noDiscount,
        discountValue: 0,
        unitName: 'case',
        stockUnitsPerUnit: 12,
        preciseUnitPriceCents: backToCase.preciseUnitPriceCents,
      );
      expect(pricing.finalTotalCents, 32000);
    });

    test('Test 4: repeated unit switching never accumulates rounding', () {
      const anchorPrice = 16000;
      const anchorFactor = 12.0; // 1 case = 12 pieces
      const factors = {'case': 12.0, 'pack': 6.0, 'piece': 1.0};

      for (var i = 0; i < 10; i++) {
        for (final unit in ['piece', 'pack', 'case', 'piece', 'case']) {
          final converted = PurchaseLinePricing.priceForUnit(
            originalPriceCents: anchorPrice,
            originalStockUnitsPerUnit: anchorFactor,
            selectedStockUnitsPerUnit: factors[unit]!,
          );
          switch (unit) {
            case 'case':
              expect(converted.unitPriceCents, 16000, reason: 'cycle $i case');
            case 'pack':
              expect(converted.unitPriceCents, 8000, reason: 'cycle $i pack');
            case 'piece':
              expect(
                converted.preciseUnitPriceCents,
                closeTo(1333.333333, 0.0001),
                reason: 'cycle $i piece',
              );
          }
        }
      }
    });

    test('Test 6: different conversion ratios derive from the anchor', () {
      // Box = 24 pieces, pack = 6 pieces, piece = 1; box price ₱240.00.
      const anchorPrice = 24000;
      const anchorFactor = 24.0;

      final pack = PurchaseLinePricing.priceForUnit(
        originalPriceCents: anchorPrice,
        originalStockUnitsPerUnit: anchorFactor,
        selectedStockUnitsPerUnit: 6,
      );
      expect(pack.unitPriceCents, 6000);

      final piece = PurchaseLinePricing.priceForUnit(
        originalPriceCents: anchorPrice,
        originalStockUnitsPerUnit: anchorFactor,
        selectedStockUnitsPerUnit: 1,
      );
      expect(piece.unitPriceCents, 1000);

      final box = PurchaseLinePricing.priceForUnit(
        originalPriceCents: anchorPrice,
        originalStockUnitsPerUnit: anchorFactor,
        selectedStockUnitsPerUnit: 24,
      );
      expect(box.unitPriceCents, 24000);
    });

    test('Test 7: invalid conversion data is rejected loudly', () {
      expect(
        () => PurchaseLinePricing.priceForUnit(
          originalPriceCents: 16000,
          originalStockUnitsPerUnit: 0,
          selectedStockUnitsPerUnit: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PurchaseLinePricing.priceForUnit(
          originalPriceCents: 16000,
          originalStockUnitsPerUnit: 12,
          selectedStockUnitsPerUnit: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PurchaseLinePricing.priceForUnit(
          originalPriceCents: 16000,
          originalStockUnitsPerUnit: double.nan,
          selectedStockUnitsPerUnit: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PurchaseLinePricing.priceForUnit(
          originalPriceCents: -100,
          originalStockUnitsPerUnit: 12,
          selectedStockUnitsPerUnit: 1,
        ),
        throwsArgumentError,
      );

      // Incompatible dimensions (mass vs volume) are rejected.
      expect(UnitConverter.areCompatible('kg', 'L'), isFalse);
      expect(
        () => UnitConverter.convert(1, 'kg', 'L'),
        throwsA(isA<UnitMismatchException>()),
      );
      expect(UnitConverter.areCompatible('kg', 'g'), isTrue);
    });
  });

  group('cart integration', () {
    test('Test 5: quantity changes keep the converted unit price', () async {
      final cart = CartNotifier(
        PurchaseDraftCartService(database),
        'business-1',
      );
      await cart.addOrIncrement(makeCokeSupply());

      final line = cart.state.single;
      expect(line.unit, 'case');
      expect(line.unitPrice, 16000);
      expect(line.anchorUnitPriceCents, 16000);
      expect(line.anchorStockUnitsPerUnit, 12);

      // Switch case → piece through the same path the editor dialog uses.
      await cart.updateLinePricing(
        line.id,
        switchUnitResult(
          quantity: 1,
          unitName: 'piece',
          stockUnitsPerUnit: 1,
          anchorPriceCents: line.anchorUnitPriceCents,
          anchorFactor: line.anchorStockUnitsPerUnit,
        ),
        isWeighted: false,
      );

      var updated = cart.state.single;
      expect(updated.unit, 'piece');
      expect(updated.unitPrice, 1333);

      // Changing the quantity updates the total from the precise price…
      await cart.updateQuantity(line.id, 5);
      updated = cart.state.single;
      expect(updated.unitPrice, 1333, reason: 'unit price must not move');
      expect(updated.lineTotal, 6667, reason: '16000/12*5 ≈ ₱66.67');

      // …and switching back to case restores the exact original price.
      await cart.updateLinePricing(
        line.id,
        switchUnitResult(
          quantity: 5,
          unitName: 'case',
          stockUnitsPerUnit: 12,
          anchorPriceCents: updated.anchorUnitPriceCents,
          anchorFactor: updated.anchorStockUnitsPerUnit,
        ),
        isWeighted: false,
      );
      updated = cart.state.single;
      expect(updated.unit, 'case');
      expect(updated.unitPrice, 16000);
      expect(updated.lineTotal, 80000, reason: '5 cases × ₱160');
    });

    test('price anchor survives a cart reload from the database', () async {
      final store = PurchaseDraftCartService(database);
      final cart = CartNotifier(store, 'business-1');
      await cart.addOrIncrement(makeCokeSupply());
      final line = cart.state.single;
      await cart.updateLinePricing(
        line.id,
        switchUnitResult(
          quantity: 1,
          unitName: 'piece',
          stockUnitsPerUnit: 1,
          anchorPriceCents: line.anchorUnitPriceCents,
          anchorFactor: line.anchorStockUnitsPerUnit,
        ),
        isWeighted: false,
      );

      // Reopen the cart: a fresh notifier loads the persisted draft.
      final restored = CartNotifier(store, 'business-1');
      await restored.load();
      final restoredLine = restored.state.single;
      expect(restoredLine.unit, 'piece');
      expect(restoredLine.unitPrice, 1333);
      expect(restoredLine.anchorUnitPriceCents, 16000);
      expect(restoredLine.anchorStockUnitsPerUnit, 12);

      // Switching back to case after the reload restores ₱160 exactly.
      await restored.updateLinePricing(
        restoredLine.id,
        switchUnitResult(
          quantity: 1,
          unitName: 'case',
          stockUnitsPerUnit: 12,
          anchorPriceCents: restoredLine.anchorUnitPriceCents,
          anchorFactor: restoredLine.anchorStockUnitsPerUnit,
        ),
        isWeighted: false,
      );
      expect(restored.state.single.unitPrice, 16000);
      expect(restored.state.single.lineTotal, 16000);
    });

    test('Test 8: switching units never touches stock; checkout uses base '
        'units', () async {
      final cart = CartNotifier(
        PurchaseDraftCartService(database),
        'business-1',
      );
      await cart.addOrIncrement(makeCokeSupply());
      final line = cart.state.single;

      await cart.updateLinePricing(
        line.id,
        switchUnitResult(
          quantity: 2,
          unitName: 'piece',
          stockUnitsPerUnit: 1,
          anchorPriceCents: line.anchorUnitPriceCents,
          anchorFactor: line.anchorStockUnitsPerUnit,
        ),
        isWeighted: false,
      );
      await cart.updateLinePricing(
        line.id,
        switchUnitResult(
          quantity: 2,
          unitName: 'case',
          stockUnitsPerUnit: 12,
          anchorPriceCents: 16000,
          anchorFactor: 12,
        ),
        isWeighted: false,
      );

      // Unit switching alone must not modify inventory.
      var supply = await (database.select(
        database.supplies,
      )..where((row) => row.id.equals('supply-coke'))).getSingle();
      expect(supply.currentStock, 100);

      // At checkout the line factor converts to base (stock) units:
      // 2 cases × 12 pieces = 24 pieces.
      final item = cart.state.single;
      final baseUnits = PurchaseStockConversion.baseUnitsPerLineUnit(
        lineUnit: item.unit!,
        stockUnit: supply.stockUnit,
        purchaseUnit: supply.purchaseUnit,
        configuredUnitsPerPurchase: supply.unitsPerPurchase,
      );
      expect(baseUnits, 12);

      final branchId = AppDatabase.mainBranchId('business-1');

      await CostingService(database, branchId: branchId).recordPurchase(
        supplyId: supply.id,
        pricePerPurchaseUnitCents: item.unitPrice,
        purchaseQuantity: item.quantity.toDouble(),
        unitsPerPurchase: item.stockUnitsPerUnit,
        purchaseUnit: item.unit!,
        storeName: 'Test store',
        date: DateTime(2026, 10, 2),
        actualTotalPriceCents: item.lineTotal,
      );
      supply = await (database.select(
        database.supplies,
      )..where((row) => row.id.equals('supply-coke'))).getSingle();
      expect(supply.currentStock, 124, reason: '2 cases restock 24 pieces');
    });

    testWidgets('editor restores the original price after unit round-trip', (
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
                        stockUnitsPerUnit: 12,
                        unitOptions: const [
                          PurchaseUnitOption(
                            name: 'case',
                            stockUnitsPerUnit: 12,
                          ),
                          PurchaseUnitOption(
                            name: 'piece',
                            stockUnitsPerUnit: 1,
                          ),
                        ],
                        quantity: 1,
                        isWeighted: false,
                        unitPriceCents: 16000,
                        grossTotalCents: 16000,
                        finalTotalCents: 16000,
                        discountType: PurchaseLinePricing.noDiscount,
                        discountValue: 0,
                        originalUnitPriceCents: 16000,
                        originalStockUnitsPerUnit: 12,
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

      TextField field(String label) => tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
      );

      await tester.tap(find.text('Edit line'));
      await tester.pumpAndSettle();
      expect(field('Total Purchase Price').controller!.text, '160.00');

      // Switching units preserves the total while converting quantity and unit price.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownMenuItem<String>, 'piece'));
      await tester.pumpAndSettle();
      expect(field('Quantity').controller!.text, '12');
      expect(field('Total Purchase Price').controller!.text, '160.00');

      // Switching back restores the original unit, quantity, and unit price.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownMenuItem<String>, 'case'));
      await tester.pumpAndSettle();
      expect(field('Quantity').controller!.text, '1');
      expect(field('Total Purchase Price').controller!.text, '160.00');

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(savedPricing!.unitName, 'case');
      expect(savedPricing!.unitPriceCents, 16000);
      expect(savedPricing!.finalTotalCents, 16000);
      expect(savedPricing!.originalUnitPriceCents, 16000);
      expect(savedPricing!.originalStockUnitsPerUnit, 12);
    });
  });
}
