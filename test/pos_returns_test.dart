import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/transactions/domain/pos_return_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PosReturnService service;
  const businessId = 'return-business';
  const userId = 'return-owner';
  const saleId = 'return-sale';
  const saleItemId = 'return-sale-item';
  const accountId = 'return-cash';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.businesses)
        .insert(
          BusinessesCompanion.insert(
            id: businessId,
            name: 'Returns test',
            ownerUserId: userId,
          ),
        );
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: accountId,
            businessId: businessId,
            name: 'Cash',
            type: 'asset',
            isPaymentAccount: const Value(true),
          ),
        );
    final membership = BusinessMember(
      id: 'return-membership',
      businessId: businessId,
      userId: userId,
      role: BosRole.owner.id,
      status: 'active',
      invitedBy: null,
      joinedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db
        .into(db.businessMembers)
        .insert(
          BusinessMembersCompanion.insert(
            id: membership.id,
            businessId: businessId,
            userId: userId,
            role: membership.role,
          ),
        );
    await db
        .into(db.posSales)
        .insert(
          PosSalesCompanion.insert(
            id: saleId,
            businessId: businessId,
            totalAmount: const Value(1800),
          ),
        );
    await db
        .into(db.posSaleItems)
        .insert(
          PosSaleItemsCompanion.insert(
            id: saleItemId,
            saleId: saleId,
            productId: const Value(null),
            productName: 'Test item',
            unit: 'piece',
            unitPrice: 1000,
            quantity: 2,
            lineTotal: 2000,
          ),
        );
    service = PosReturnService(
      db,
      AuthorizationService(
        userId: userId,
        businessId: businessId,
        membership: membership,
        resolvedRole: BosRole.owner,
      ),
      AppDatabase.mainBranchId(businessId),
    );
  });

  tearDown(() async => db.close());

  test(
    'partial refunds honor sale discounts and remaining quantities',
    () async {
      await service.createReturn(
        saleId: saleId,
        refundAccountId: accountId,
        reason: 'Customer returned part of the order',
        quantitiesBySaleItemId: {saleItemId: 0.5},
      );

      var rows = await db
          .customSelect('SELECT quantity, refund_amount FROM pos_return_items')
          .get();
      expect(rows.single.read<double>('quantity'), 0.5);
      expect(rows.single.read<int>('refund_amount'), 450);

      await service.createReturn(
        saleId: saleId,
        refundAccountId: accountId,
        reason: 'Customer returned the rest',
        quantitiesBySaleItemId: {saleItemId: 1.5},
      );

      rows = await db
          .customSelect('SELECT quantity, refund_amount FROM pos_return_items')
          .get();
      expect(rows, hasLength(2));
      expect(
        rows.fold<int>(0, (sum, row) => sum + row.read<int>('refund_amount')),
        1800,
      );
      expect(await db.select(db.journalEntries).get(), isEmpty);
    },
  );

  test('a return cannot exceed the unreturned sale quantity', () async {
    await service.createReturn(
      saleId: saleId,
      refundAccountId: accountId,
      reason: 'Partial return',
      quantitiesBySaleItemId: {saleItemId: 1.5},
    );

    await expectLater(
      service.createReturn(
        saleId: saleId,
        refundAccountId: accountId,
        reason: 'Too many items',
        quantitiesBySaleItemId: {saleItemId: 0.6},
      ),
      throwsA(isA<StateError>()),
    );
    final rows = await db.customSelect('SELECT id FROM pos_returns').get();
    expect(rows, hasLength(1));
  });
}
