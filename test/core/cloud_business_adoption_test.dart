import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _cloudBusiness({Map<String, dynamic> overrides = const {}}) {
  return {
    'id': '11111111-1111-4111-8111-111111111111',
    'owner_user_id': '22222222-2222-4222-8222-222222222222',
    'name': 'Acme Bakery',
    'currency_code': 'PHP',
    'timezone': 'Asia/Manila',
    'created_at': '2026-10-01T00:00:00Z',
    'updated_at': '2026-10-02T00:00:00Z',
    ...overrides,
  };
}

void main() {
  group('businessCompanionFromCloud', () {
    test('carries the profile saved on another device', () {
      final companion = businessCompanionFromCloud(
        _cloudBusiness(
          overrides: {
            'owner_name': 'Maria Santos',
            'manager_name': 'Jun',
            'business_category': 'Food',
            'industry': 'Food',
            'business_type': 'retailer',
            'address_country': 'Philippines',
            'address_city': 'Cebu City',
            'starting_capital': 500000,
            'starting_capital_account_id':
                '33333333-3333-4333-8333-333333333333',
          },
        ),
      );

      expect(companion.ownerName.value, 'Maria Santos');
      expect(companion.managerName.value, 'Jun');
      expect(companion.businessCategory.value, 'Food');
      expect(companion.businessType.value, 'retailer');
      expect(companion.addressCountry.value, 'Philippines');
      expect(companion.addressCity.value, 'Cebu City');
      expect(companion.startingCapital.value, 500000);
      expect(
        companion.startingCapitalAccountId.value,
        '33333333-3333-4333-8333-333333333333',
      );
    });

    test('a cloud business never looks unfinished to onboarding', () {
      final companion = businessCompanionFromCloud(_cloudBusiness());

      // Onboarding triggers on null; both must be non-null.
      expect(companion.ownerName.value, isNotNull);
      expect(companion.businessCategory.value, isNotNull);
    });

    test('falls back to the owner profile name and legacy columns', () {
      final companion = businessCompanionFromCloud(
        _cloudBusiness(overrides: {'industry': 'Retail', 'city': 'Davao'}),
        ownerName: 'Profile Name',
      );

      expect(companion.ownerName.value, 'Profile Name');
      expect(companion.businessCategory.value, 'Retail');
      expect(companion.addressCity.value, 'Davao');
    });

    test('inserts into the local database', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.into(db.businesses).insert(businessCompanionFromCloud(_cloudBusiness()));

      final row = await db.select(db.businesses).getSingle();
      expect(row.name, 'Acme Bakery');
      expect(row.ownerName, '');
      expect(row.businessCategory, '');
    });
  });
}
