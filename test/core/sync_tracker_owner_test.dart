import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.businesses)
        .insert(
          BusinessesCompanion.insert(
            id: 'business',
            name: 'Test business',
            ownerUserId: 'user-a',
          ),
        );
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  test('records the authenticated account for newly queued work', () async {
    SyncTracker.currentUserId = 'user-a';

    await db.transaction(
      () => SyncTracker.record(
        db,
        businessId: 'business',
        entityType: 'customers',
        entityId: 'customer',
        operation: SyncOp.create,
      ),
    );

    final result = await db
        .customSelect(
          'SELECT owner_user_id FROM sync_outbox_owners '
          'WHERE outbox_id = (SELECT id FROM sync_outbox '
          'WHERE entity_id = ?)',
          variables: [Variable.withString('customer')],
        )
        .getSingle();

    expect(result.read<String>('owner_user_id'), 'user-a');
  });

  test('does not adopt an unattributed legacy outbox row', () async {
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: 'legacy-outbox',
            businessId: 'business',
            entityType: 'customers',
            entityId: 'legacy-customer',
            operation: SyncOp.create,
            mutationId: 'legacy-mutation',
          ),
        );
    SyncTracker.currentUserId = 'user-b';

    await db.transaction(
      () => SyncTracker.record(
        db,
        businessId: 'business',
        entityType: 'customers',
        entityId: 'legacy-customer',
        operation: SyncOp.create,
      ),
    );

    final owners = await db
        .customSelect(
          'SELECT owner_user_id FROM sync_outbox_owners '
          'WHERE outbox_id = ?',
          variables: [Variable.withString('legacy-outbox')],
        )
        .get();

    expect(owners, isEmpty);
    expect(
      await (db.select(
        db.syncOutbox,
      )..where((row) => row.id.equals('legacy-outbox'))).getSingleOrNull(),
      isNotNull,
    );
  });
}
