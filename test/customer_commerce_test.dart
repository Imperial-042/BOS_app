import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('store QR payload accepts only a valid storefront UUID', () {
    const businessId = '01234567-89ab-cdef-0123-456789abcdef';

    expect(storefrontInvitePayload(businessId), 'bosapp://store/$businessId');
    expect(
      businessIdFromStorefrontInvite(storefrontInvitePayload(businessId)),
      businessId,
    );
    expect(businessIdFromStorefrontInvite('bosapp://store/not-a-uuid'), isNull);
    expect(businessIdFromStorefrontInvite('https://store/$businessId'), isNull);
  });

  test('store QR payload can carry a branch id', () {
    const businessId = '01234567-89ab-cdef-0123-456789abcdef';
    const branchId = 'fedcba98-7654-3210-fedc-ba9876543210';
    final payload = storefrontInvitePayload(businessId, branchId: branchId);

    expect(businessIdFromStorefrontInvite(payload), businessId);
    expect(branchIdFromStorefrontInvite(payload), branchId);
    expect(
      branchIdFromStorefrontInvite(storefrontInvitePayload(businessId)),
      isNull,
    );
  });

  test(
    'local branch location columns are available after database open',
    () async {
      final branches = await db
          .customSelect('PRAGMA table_info("branches")')
          .get();
      final customerBranches = await db
          .customSelect('PRAGMA table_info("customer_store_branches")')
          .get();
      expect(
        branches.map((row) => row.read<String>('name')),
        containsAll([
          'city',
          'country',
          'province_state',
          'street_barangay',
          'postal_code',
        ]),
      );
      expect(
        customerBranches.map((row) => row.read<String>('name')),
        containsAll(['city', 'storefront_published']),
      );
    },
  );

  test(
    'customer location is saved locally for city-filtered discovery',
    () async {
      const userId = 'customer-location';
      await db
          .into(db.customerProfiles)
          .insert(
            CustomerProfilesCompanion.insert(
              id: userId,
              displayName: 'Customer',
            ),
          );

      final service = CustomerCommerceService(db);
      await service.updateCustomerLocation(
        userId: userId,
        city: '  New   York ',
        address: '123 Private Street',
      );

      final profile = await service.loadCustomerProfile(userId);
      expect(profile?.city, 'New   York');
      expect(profile?.address, '123 Private Street');
      expect(normalizeStoreCity(profile!.city!), 'new york');
    },
  );

  test(
    'store discovery returns published stores from the customer city',
    () async {
      for (final (id, city) in [
        ('nearby', 'New   York'),
        ('remote', 'Boston'),
      ]) {
        await db
            .into(db.customerStorefronts)
            .insert(
              CustomerStorefrontsCompanion.insert(
                businessId: id,
                name: id,
                city: Value(city),
                isPublished: const Value(true),
                offlineEnabled: const Value(true),
              ),
            );
        await db
            .into(db.customerStoreBranches)
            .insert(
              CustomerStoreBranchesCompanion.insert(
                id: '$id-branch',
                businessId: id,
                name: '$id pickup',
              ),
            );
        await db.customStatement(
          'UPDATE customer_store_branches '
          'SET city = ?, storefront_published = 1 WHERE id = ?',
          [city, '$id-branch'],
        );
      }

      final stores = await CustomerCommerceService(
        db,
      ).discoverStores(city: 'new york');

      expect(stores.map((store) => store.businessId), ['nearby']);
    },
  );

  test('store hours enforce opening, closing, and closed weekdays', () {
    final store = CustomerStorefrontWithHours(
      storefront: CustomerStorefront(
        businessId: 'store',
        name: 'Store',
        currencyCode: 'PHP',
        isPublished: true,
        offlineEnabled: false,
        pointsPerCurrencyUnit: 0,
        updatedAt: DateTime(2026),
      ),
      openingHoursJson: serializeStoreHours({
        1: (open: '09:00', close: '17:00'),
      }),
    );

    expect(storefrontIsOpen(store, at: DateTime(2026, 1, 5, 9)), isTrue);
    expect(storefrontIsOpen(store, at: DateTime(2026, 1, 5, 16, 59)), isTrue);
    expect(storefrontIsOpen(store, at: DateTime(2026, 1, 5, 17)), isFalse);
    expect(storefrontIsOpen(store, at: DateTime(2026, 1, 6, 12)), isFalse);
    expect(
      hoursJsonIsOpen(
        serializeStoreHours({1: (open: '17:00', close: '09:00')}),
        at: DateTime(2026, 1, 5, 23),
      ),
      isTrue,
    );
    expect(
      hoursJsonIsOpen(
        serializeStoreHours({1: (open: '17:00', close: '09:00')}),
        at: DateTime(2026, 1, 6, 8),
      ),
      isTrue,
    );
    expect(
      hoursJsonIsOpen(
        serializeStoreHours({1: (open: '17:00', close: '09:00')}),
        at: DateTime(2026, 1, 6, 10),
      ),
      isFalse,
    );
  });

  test('store hours accept the published 9 AM to 12 PM window', () {
    final hours = serializeStoreHours({7: (open: '09:00', close: '12:00')});

    expect(hoursJsonIsOpen(hours, at: DateTime(2026, 1, 11, 9)), isTrue);
    expect(hoursJsonIsOpen(hours, at: DateTime(2026, 1, 11, 11, 59)), isTrue);
    expect(hoursJsonIsOpen(hours, at: DateTime(2026, 1, 11, 12)), isFalse);
    expect(
      hoursJsonIsOpen(
        '{"7":{"open":"9:00 AM","close":"12:00 PM"}}',
        at: DateTime(2026, 1, 11, 9, 30),
      ),
      isTrue,
    );
  });

  test(
    'offline catalog reads are per branch and only when enabled by the store',
    () async {
      const businessId = 'offline-store';
      await db
          .into(db.customerStorefronts)
          .insert(
            CustomerStorefrontsCompanion.insert(
              businessId: businessId,
              name: 'Offline store',
              city: const Value('New York'),
              isPublished: Value(true),
            ),
          );
      for (final id in ['offline-branch', 'other-branch']) {
        await db
            .into(db.customerStoreBranches)
            .insert(
              CustomerStoreBranchesCompanion.insert(
                id: id,
                businessId: businessId,
                name: id,
              ),
            );
        await db.customStatement(
          'UPDATE customer_store_branches '
          'SET city = ?, storefront_published = 1 WHERE id = ?',
          ['New York', id],
        );
      }
      for (final id in ['offline-item', 'other-item']) {
        await db
            .into(db.customerCatalogItems)
            .insert(
              CustomerCatalogItemsCompanion.insert(
                id: id,
                businessId: businessId,
                name: id == 'offline-item' ? 'Published item' : 'Other item',
                unit: 'each',
                priceCents: Value(250),
              ),
            );
      }
      // Each branch sells its own product.
      await db.customStatement(
        'INSERT INTO customer_branch_catalog '
        '(branch_id, catalog_item_id, business_id) VALUES (?, ?, ?)',
        ['offline-branch', 'offline-item', businessId],
      );
      await db.customStatement(
        'INSERT INTO customer_branch_catalog '
        '(branch_id, catalog_item_id, business_id) VALUES (?, ?, ?)',
        ['other-branch', 'other-item', businessId],
      );
      final service = CustomerCommerceService(db);

      expect(
        await service.loadCatalog(
          businessId,
          city: 'New York',
          branchId: 'offline-branch',
        ),
        isEmpty,
      );

      await (db.update(
        db.customerStorefronts,
      )..where((store) => store.businessId.equals(businessId))).write(
        const CustomerStorefrontsCompanion(offlineEnabled: Value(true)),
      );

      expect(
        (await service.loadCatalog(
          businessId,
          city: 'New York',
          branchId: 'offline-branch',
        )).map((item) => item.name),
        ['Published item'],
      );
      expect(
        (await service.loadCatalog(
          businessId,
          city: 'New York',
          branchId: 'other-branch',
        )).map((item) => item.name),
        ['Other item'],
      );
      expect(
        await service.loadCatalog(
          businessId,
          city: 'Boston',
          branchId: 'offline-branch',
        ),
        isEmpty,
      );
    },
  );

  test('customer order inbox can scope orders to its POS branch', () async {
    for (final branch in ['branch-a', 'branch-b']) {
      await db
          .into(db.customerOrders)
          .insert(
            CustomerOrdersCompanion.insert(
              id: 'order-$branch',
              businessId: 'business',
              customerUserId: 'customer',
              branchId: branch,
              branchName: branch,
              status: 'accepted',
              customerName: 'Customer',
              customerPhone: '123456789',
              totalCents: 500,
            ),
          );
    }

    final orders = await CustomerCommerceService(
      db,
    ).loadOrders(businessId: 'business', branchId: 'branch-b');

    expect(orders.map((order) => order.branchId), ['branch-b']);
  });
}
