import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/sync_change_log.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SyncTracker.currentUserId = null;
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  test('shared writer requires reasons for adjustments', () async {
    await expectLater(
      AuditWriter.write(
        db,
        businessId: 'business-1',
        userId: 'user-1',
        action: 'inventory.adjusted',
        entityType: 'supplies',
        actionType: AuditActionType.adjustment,
      ),
      throwsArgumentError,
    );
  });

  test('shared writer refuses events without a real actor', () async {
    await expectLater(
      AuditWriter.write(
        db,
        businessId: 'business-1',
        userId: null,
        action: 'inventory.updated',
        entityType: 'supplies',
      ),
      throwsStateError,
    );
  });

  test(
    'audit service rejects a business outside its resolved context',
    () async {
      final service = AuditLogService(
        db,
        resolveContext: () =>
            const AuditContext(userId: 'user-1', businessId: 'business-1'),
      );

      await expectLater(
        service.record(
          const AuditEvent(
            module: AuditModule.inventory,
            actionType: AuditActionType.update,
            action: 'inventory.updated',
            entityType: 'supplies',
            businessId: 'business-2',
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('client reports are labelled and queued as unverified events', () async {
    await SyncChangeLog.install(db);
    await db
        .into(db.businesses)
        .insert(
          BusinessesCompanion.insert(
            id: 'business-1',
            name: 'Business',
            ownerUserId: 'user-1',
          ),
        );
    SyncTracker.currentUserId = 'user-1';

    final id = await AuditWriter.write(
      db,
      businessId: 'business-1',
      userId: 'user-1',
      action: 'inventory.updated',
      entityType: 'supplies',
    );
    await SyncChangeLog.drain(db);

    final row = await (db.select(
      db.auditLogs,
    )..where((entry) => entry.id.equals(id))).getSingle();
    expect(row.source, 'client_reported');
    final outbox = await (db.select(
      db.syncOutbox,
    )..where((entry) => entry.entityType.equals('audit_logs'))).get();
    expect(outbox, hasLength(1));
    expect(outbox.single.operation, 'create');
  });
}
