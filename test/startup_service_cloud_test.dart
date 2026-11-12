// test/startup_service_cloud_test.dart
//
// StartupService with Supabase CONFIGURED but the cloud unreachable. These pin
// down the offline-first promise: an installation that already has a local
// business always opens, a locally cached revocation is honoured with no
// network, and a brand-new device that needs the cloud creates nothing.

import 'dart:async';

import 'package:bos_application/app/startup/startup_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/business/current_business.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/device/device_identity_service.dart';
import 'package:bos_application/core/device/device_management_service.dart';
import 'package:bos_application/core/device/device_providers.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _owner = 'u_owner';

bool _active() => true;
void _noop() {}
const _hooks = StartupHooks(isActive: _active, restart: _noop);

// ---------- fakes ----------

class _FakeAuth extends Fake implements sb.GoTrueClient {
  _FakeAuth(this.currentUser);

  @override
  final sb.User? currentUser;
}

class _FakeClient extends Fake implements sb.SupabaseClient {
  _FakeClient(sb.User? user) : _auth = _FakeAuth(user);

  final _FakeAuth _auth;

  @override
  sb.GoTrueClient get auth => _auth;
}

class _Cached extends Fake implements CachedDeviceAuthorization {
  _Cached({
    required this.authorized,
    required this.status,
    this.requiresFreshLogin = false,
  });

  @override
  final bool authorized;
  @override
  final String status;
  @override
  final bool requiresFreshLogin;
}

/// A device service whose cloud is unreachable: reading the cached decision
/// works (it is local), registering the device always times out.
class _OfflineDevices extends Fake implements DeviceManagementService {
  _OfflineDevices({this.cached});

  final CachedDeviceAuthorization? cached;
  int registerCalls = 0;

  @override
  Future<CachedDeviceAuthorization?> getCachedAuthorization({
    required String userId,
  }) async => cached;

  @override
  Future<DeviceRecord> registerCurrentDevice() async {
    registerCalls++;
    throw TimeoutException('cloud unreachable');
  }

  @override
  String get authenticatedUserId => _owner;
}

sb.User _user() => sb.User(
  id: _owner,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SyncTracker.currentUserId = _owner;
    setCurrentBusinessIdForTest('biz_001');
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  ProviderContainer container({
    required _OfflineDevices devices,
    sb.User? user,
  }) {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        supabaseAvailableProvider.overrideWithValue(true),
        supabaseClientProvider.overrideWithValue(_FakeClient(user)),
        deviceManagementServiceProvider.overrideWithValue(devices),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<BusinessesData> start(ProviderContainer c) {
    return c
        .read(startupServiceProvider)
        .ensureBusinessExists(allowCreateFirstBusiness: false, hooks: _hooks);
  }

  Future<BusinessesData> createLocalBusiness() {
    return BusinessService(
      db,
      const AuthorizationService(
        userId: _owner,
        businessId: null,
        membership: null,
      ),
    ).createBusiness(name: 'Alpha', setAsCurrent: true);
  }

  group('StartupService (cloud configured, cloud unreachable)', () {
    test('opens the local business with no cached decision (legacy install)',
        () async {
      final existing = await createLocalBusiness();
      final devices = _OfflineDevices();
      final c = container(devices: devices, user: _user());

      final opened = await start(c);
      await pumpEventQueue(); // let the background reconcile finish

      expect(opened.id, existing.id);
      expect(await db.select(db.businesses).get(), hasLength(1));
      expect(c.read(authenticatedUserIdProvider), _owner);
      expect(c.read(currentBusinessIdProvider), existing.id);
      // The cloud check happens AFTER the business is open, never before.
      expect(devices.registerCalls, greaterThanOrEqualTo(1));
    });

    test('opens the local business when the cached decision is "authorized"',
        () async {
      final existing = await createLocalBusiness();
      final devices = _OfflineDevices(
        cached: _Cached(authorized: true, status: 'active'),
      );
      final c = container(devices: devices, user: _user());

      final opened = await start(c);
      await pumpEventQueue();

      expect(opened.id, existing.id);
    });

    test('a cached revocation blocks startup with no network at all',
        () async {
      await createLocalBusiness();
      final devices = _OfflineDevices(
        cached: _Cached(
          authorized: false,
          status: 'revoked',
          requiresFreshLogin: true,
        ),
      );
      final c = container(devices: devices, user: _user());

      await expectLater(
        start(c),
        throwsA(
          isA<DeviceAuthorizationException>()
              .having((e) => e.status, 'status', 'revoked')
              .having((e) => e.requiresFreshLogin, 'fresh login', isTrue),
        ),
      );
      await pumpEventQueue();

      expect(devices.registerCalls, 0, reason: 'must not need the cloud');
      expect(c.read(currentBusinessIdProvider), isNull);
    });

    test('a signed-out cloud session refuses to start', () async {
      await createLocalBusiness();
      final c = container(devices: _OfflineDevices(), user: null);

      await expectLater(start(c), throwsA(isA<StateError>()));
    });

    test('a brand-new device cannot start without the cloud, and creates '
        'nothing', () async {
      final devices = _OfflineDevices();
      final c = container(devices: devices, user: _user());

      await expectLater(start(c), throwsA(anything));
      await pumpEventQueue();

      expect(await db.select(db.businesses).get(), isEmpty);
      expect(devices.registerCalls, 1);
    });
  });
}