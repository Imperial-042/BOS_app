import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String businessId;
  late String supplyId;
  late String activeBranchId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final business = await BusinessService(
      db,
      const AuthorizationService(
        userId: 'branch-test-owner',
        businessId: null,
        membership: null,
      ),
    ).createBusiness(name: 'Branch test', setAsCurrent: false);
    businessId = business.id;
    supplyId = 'branch-test-supply';
    activeBranchId = 'branch-test-active';

    await db
        .into(db.supplies)
        .insert(
          SuppliesCompanion.insert(
            id: supplyId,
            businessId: businessId,
            name: 'Test supply',
            currentPrice: 100,
          ),
        );
    await db
        .into(db.branches)
        .insert(
          BranchesCompanion.insert(
            id: activeBranchId,
            businessId: businessId,
            name: 'Active branch',
          ),
        );
  });

  tearDown(() async => db.close());

  test('stock movements reject branches outside the supply business', () async {
    final stock = StockService(db);

    await expectLater(
      stock.moveSupply(
        branchId: AppDatabase.mainBranchId('another-business'),
        supplyId: supplyId,
        type: 'restock',
        quantity: 1,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
  });

  test('stock movements reject non-finite quantities', () async {
    final stock = StockService(db);

    await expectLater(
      stock.moveSupply(
        branchId: activeBranchId,
        supplyId: supplyId,
        type: 'restock',
        quantity: double.nan,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
  });

  test(
    'stock movements accept an active branch in the same business',
    () async {
      await StockService(db).moveSupply(
        branchId: activeBranchId,
        supplyId: supplyId,
        type: 'restock',
        quantity: 2,
        unit: 'piece',
      );

      final movements = await db.select(db.inventoryMovements).get();
      expect(movements, hasLength(1));
      expect(movements.single.branchId, activeBranchId);
    },
  );
}
