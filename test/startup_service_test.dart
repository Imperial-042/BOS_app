// test/startup_service_test.dart
//
// StartupService in local-only mode (Supabase not configured): which business
// opens, that a first one is created only when none exists, that other
// people's businesses are never opened, and that the open business is
// published through applyCurrentBusiness (the single write path).

import 'package:bos_application/app/startup/startup_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/business/current_business.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = 'u_owner';
const _other = 'u_other';

bool _active() => true;
void _noop() {}
const _hooks = StartupHooks(isActive: _active, restart: _noop);

Future<BusinessesData> _createBusiness(
  AppDatabase db,
  String name, {
  String userId = _owner,
  bool current = false,
}) {
  return BusinessService(
    db,
    AuthorizationService(userId: userId, businessId: null, membership: null),
  ).createBusiness(name: name, setAsCurrent: current);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SyncTracker.currentUserId = _owner;
    setCurrentBusinessIdForTest('biz_001');
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  ProviderContainer container({String? userId = _owner}) {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        supabaseAvailableProvider.overrideWithValue(false),
      ],
    );
    addTearDown(c.dispose);
    if (userId != null) {
      c.read(authenticatedUserIdProvider.notifier).state = userId;
    }
    return c;
  }

  Future<BusinessesData> start(ProviderContainer c) {
    return c
        .read(startupServiceProvider)
        .ensureBusinessExists(allowCreateFirstBusiness: false, hooks: _hooks);
  }

  group('StartupService (local-only)', () {
    test('creates the first business when none exists', () async {
      final c = container();

      final opened = await start(c);

      expect(opened.ownerUserId, _owner);
      final rows = await db.select(db.businesses).get();
      expect(rows, hasLength(1));
      expect(rows.single.isCurrent, isTrue);
      expect(c.read(currentBusinessIdProvider), opened.id);
      expect(kCurrentBusinessId, opened.id);
    });

    test('reopens the existing business instead of creating another', () async {
      final existing = await _createBusiness(db, 'Alpha', current: true);
      final c = container();

      final opened = await start(c);

      expect(opened.id, existing.id);
      expect(await db.select(db.businesses).get(), hasLength(1));
      expect(c.read(currentBusinessIdProvider), existing.id);
    });

    test('opens the business marked current when there are several', () async {
      final a = await _createBusiness(db, 'Alpha');
      final b = await _createBusiness(db, 'Beta');
      // Set the flag explicitly so the test does not depend on how
      // createBusiness orders them.
      await db.customStatement('UPDATE businesses SET is_current = 0');
      await db.customStatement(
        'UPDATE businesses SET is_current = 1 WHERE id = ?',
        [b.id],
      );
      final c = container();

      final opened = await start(c);

      expect(opened.id, b.id);
      expect(opened.id, isNot(a.id));
      final current = await (db.select(
        db.businesses,
      )..where((x) => x.isCurrent.equals(true))).get();
      expect(current.map((x) => x.id), [b.id]);
    });

    test("never opens someone else's business", () async {
      final theirs = await _createBusiness(db, 'Theirs', userId: _other);
      final c = container();

      final opened = await start(c);

      expect(opened.id, isNot(theirs.id));
      expect(opened.ownerUserId, _owner);
      expect(await db.select(db.businesses).get(), hasLength(2));
    });

    test('refuses to start when nobody is signed in', () async {
      final c = container(userId: null);

      await expectLater(start(c), throwsA(isA<StateError>()));
      expect(await db.select(db.businesses).get(), isEmpty);
    });
  });

  group('applyCurrentBusiness', () {
    test('reports a change and bumps the ledger version once', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final apply = Provider<bool Function(String)>(
        (ref) =>
            (id) => applyCurrentBusiness(ref, id),
      );

      final before = c.read(ledgerVersionProvider);

      expect(c.read(apply)('biz_x'), isTrue);
      expect(kCurrentBusinessId, 'biz_x');
      expect(c.read(currentBusinessIdProvider), 'biz_x');
      expect(c.read(ledgerVersionProvider), before + 1);

      // Same business again: nothing changes.
      expect(c.read(apply)('biz_x'), isFalse);
      expect(c.read(ledgerVersionProvider), before + 1);
    });
  });
}
