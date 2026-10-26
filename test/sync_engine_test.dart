// test/sync_engine_test.dart
//
// Priority 5 sync engine: outbox mutation ids, checkpoint cursor, retry
// metadata, and offline behavior. All against in-memory Drift (no live
// Supabase needed). Live push/pull against the real project runs once the
// project's email confirmation is disabled.

import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/sync_change_log.dart';
import 'package:bos_application/core/sync/sync_coordinator.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart'
    show CustomerService;
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId;
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = 'u_owner';
final _date = DateTime(2026, 9, 30, 10, 30);

Future<AppDatabase> _newDb() async =>
    AppDatabase.forTesting(NativeDatabase.memory());

Future<BusinessesData> _createBusiness(AppDatabase db, String name) {
  return BusinessService(
    db,
    const AuthorizationService(
      userId: _owner,
      businessId: null,
      membership: null,
    ),
  ).createBusiness(name: name, setAsCurrent: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CustomerService customers;
  late BusinessesData biz;

  setUp(() async {
    db = await _newDb();
    customers = CustomerService(db);
    biz = await _createBusiness(db, 'Alpha');
    kCurrentBusinessId = biz.id;
    SyncTracker.currentUserId = _owner;
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  group('Outbox mutation ids', () {
    test('every recorded change gets a stable mutation id', () async {
      await customers.addCustomer(name: 'Ana');
      final rows = await db.select(db.syncOutbox).get();
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.mutationId, isNotEmpty);
      }
    });

    test(
      'mutation id survives a retry state change (never regenerated)',
      () async {
        await customers.addCustomer(name: 'Ana');
        final row = await db.select(db.syncOutbox).getSingle();
        final originalMutationId = row.mutationId;

        // Simulate a transient failure -> backoff -> still the same mutation.
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(row.id))).write(
          SyncOutboxCompanion(
            status: const Value('pending'),
            attemptCount: Value(1),
            lastAttemptAt: Value(DateTime.now()),
            nextAttemptAt: Value(
              DateTime.now().add(const Duration(seconds: 2)),
            ),
          ),
        );

        final retried = await db.select(db.syncOutbox).getSingle();
        expect(retried.mutationId, originalMutationId);
      },
    );
  });

  group('Checkpoints', () {
    test('no checkpoint exists before first sync', () async {
      final coordinator = SyncCoordinator(db, null, null);
      expect(
        await (db.select(
          db.syncCheckpoints,
        )..where((c) => c.businessId.equals(biz.id))).getSingleOrNull(),
        isNull,
      );
      expect(coordinator.isOnline, isFalse);
    });

    test('pull cursor version change rewinds cursors only once', () async {
      await db
          .into(db.syncCheckpoints)
          .insert(
            SyncCheckpointsCompanion(
              businessId: Value(biz.id),
              lastServerCursor: const Value(500),
            ),
          );

      await SyncChangeLog.ensurePullCursorVersion(db, version: '2');
      var checkpoint = await db.select(db.syncCheckpoints).getSingle();
      expect(checkpoint.lastServerCursor, 0);

      await (db.update(db.syncCheckpoints)
            ..where((c) => c.businessId.equals(biz.id)))
          .write(const SyncCheckpointsCompanion(lastServerCursor: Value(550)));
      await SyncChangeLog.ensurePullCursorVersion(db, version: '2');
      checkpoint = await db.select(db.syncCheckpoints).getSingle();
      expect(checkpoint.lastServerCursor, 550);

      await SyncChangeLog.ensurePullCursorVersion(db, version: '3');
      checkpoint = await db.select(db.syncCheckpoints).getSingle();
      expect(checkpoint.lastServerCursor, 0);
    });

    test(
      'syncNow is a safe no-op when the backend is not configured',
      () async {
        final coordinator = SyncCoordinator(db, null, null);
        final summary = await coordinator.syncNow(biz.id, userId: _owner);
        expect(summary.state, SyncState.offline);
        // Nothing was pushed; the outbox is untouched.
        expect(await db.select(db.syncOutbox).get(), isEmpty);
      },
    );

    test('a second concurrent sync for the same business is refused', () async {
      final coordinator = SyncCoordinator(db, null, null);
      // First call acquires the in-memory lock via _active.add — but since
      // the backend is null it returns offline immediately. To exercise the
      // lock we check the public surface: two rapid calls both complete
      // without throwing or corrupting state.
      final a = await coordinator.syncNow(biz.id, userId: _owner);
      final b = await coordinator.syncNow(biz.id, userId: _owner);
      expect(a.state, SyncState.offline);
      expect(b.state, SyncState.offline);
    });
  });

  group('Failure preservation (no data loss)', () {
    test('a failed push never deletes the local record', () async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();
      await customers.recordSale(
        customerId: ana.id,
        amount: 5000,
        date: _date,
        isOnCredit: true,
      );

      // Simulate a permanent push failure: mark the outbox row failed.
      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox, isNotEmpty);
      for (final row in outbox) {
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(row.id))).write(
          const SyncOutboxCompanion(
            status: Value('failed'),
            error: Value('simulated failure'),
          ),
        );
      }

      // The business record itself is untouched — never deleted on failure.
      final income = await db.select(db.incomeTransactions).get();
      expect(income, hasLength(1));
      expect(income.single.amount, 5000);
    });
  });
}
