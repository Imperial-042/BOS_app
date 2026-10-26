import 'dart:convert';

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/backup_service.dart';
import 'package:bos_application/core/sync/business_export_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const businessId = 'backup-business';
  const otherBusinessId = 'other-business';
  late AppDatabase db;
  late BackupService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BackupService(db);
    for (final id in [businessId, otherBusinessId]) {
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: id,
              name: id,
              ownerUserId: 'owner-$id',
            ),
          );
    }
  });

  tearDown(() async => db.close());

  String backup(Map<String, Object?> data) => jsonEncode({
    'format': 'bos-backup',
    'version': 1,
    'businessId': businessId,
    'data': data,
  });

  test('restore only counts newly inserted rows and is repeatable', () async {
    final content = backup({
      'customers': [
        {'id': 'customer-1', 'business_id': businessId, 'name': 'A Customer'},
      ],
    });

    expect(await service.restoreBusiness(businessId, content), 1);
    expect(await service.restoreBusiness(businessId, content), 0);
    expect(await db.select(db.customers).get(), hasLength(1));
  });

  test('business export includes every supported backup table', () async {
    final exported = await BusinessExportService(db).exportBusiness(businessId);

    expect(exported.keys, businessExportTables);
    expect(exported['branches'], isEmpty);
    expect(exported['product_stock_movements'], isEmpty);
    expect(exported['payroll_items'], isEmpty);
  });

  test('restore rejects unknown tables and cross-business records', () async {
    await expectLater(
      service.restoreBusiness(
        businessId,
        backup({
          'users': [
            {'id': 'not-allowed'},
          ],
        }),
      ),
      throwsA(isA<BackupException>()),
    );

    await expectLater(
      service.restoreBusiness(
        businessId,
        backup({
          'customers': [
            {
              'id': 'foreign-customer',
              'business_id': otherBusinessId,
              'name': 'Foreign',
            },
          ],
        }),
      ),
      throwsA(isA<BackupException>()),
    );
    expect(await db.select(db.customers).get(), isEmpty);
  });

  test('restore includes rows with composite primary keys', () async {
    await db
        .into(db.supplies)
        .insert(
          SuppliesCompanion.insert(
            id: 'supply-1',
            businessId: businessId,
            name: 'Test supply',
            currentPrice: 100,
          ),
        );

    final restored = await service.restoreBusiness(
      businessId,
      backup({
        'supply_unit_conversions': [
          {
            'supply_id': 'supply-1',
            'unit_name': 'case',
            'units_per_stock_unit': 12.0,
          },
        ],
      }),
    );

    expect(restored, 1);
    expect(await db.select(db.supplyUnitConversions).get(), hasLength(1));
  });
}
