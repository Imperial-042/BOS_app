import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/outbox_recovery_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late OutboxRecoveryService service;

  Future<void> addBusiness(String id, {String? memberUserId}) async {
    await db
        .into(db.businesses)
        .insert(
          BusinessesCompanion.insert(
            id: id,
            name: id,
            ownerUserId: 'owner',
            isCurrent: const Value(false),
          ),
        );
    if (memberUserId != null) {
      await db.customStatement(
        'INSERT INTO business_members (id, business_id, user_id, role, status) '
        "VALUES (?, ?, ?, 'employee', 'active')",
        ['m_$id$memberUserId', id, memberUserId],
      );
    }
  }

  Future<void> addOutbox(String id, String businessId, {String? owner}) async {
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: id,
            businessId: businessId,
            entityType: 'customers',
            entityId: 'entity_$id',
            operation: 'create',
            mutationId: 'mutation_$id',
          ),
        );
    if (owner != null) {
      await db.customStatement(
        'INSERT INTO sync_outbox_owners (outbox_id, owner_user_id) VALUES (?, ?)',
        [id, owner],
      );
    }
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = OutboxRecoveryService(db);
    await addBusiness('biz_member', memberUserId: 'user_a');
    await addBusiness('biz_other');
  });

  tearDown(() => db.close());

  test('classifies held changes by why they cannot upload', () async {
    await addOutbox('legacy_mine', 'biz_member');
    await addOutbox('legacy_foreign', 'biz_other');
    await addOutbox('owned_by_b', 'biz_member', owner: 'user_b');
    await addOutbox('owned_by_a', 'biz_member', owner: 'user_a');

    final summary = await service.summarize('user_a');

    expect(summary.recoverable, 1);
    expect(summary.otherBusinesses, 1);
    expect(summary.otherAccounts, 1);
    expect(summary.total, 3);
  });

  test('adopts only unattributed rows in member businesses', () async {
    await addOutbox('legacy_mine', 'biz_member');
    await addOutbox('legacy_foreign', 'biz_other');
    await addOutbox('owned_by_b', 'biz_member', owner: 'user_b');

    final adopted = await service.adoptUnattributed('user_a');

    expect(adopted, 1);
    final owners = await db
        .customSelect('SELECT outbox_id, owner_user_id FROM sync_outbox_owners')
        .get();
    final byId = {
      for (final r in owners)
        r.read<String>('outbox_id'): r.read<String>('owner_user_id'),
    };
    expect(byId['legacy_mine'], 'user_a');
    expect(byId['owned_by_b'], 'user_b');
    expect(byId.containsKey('legacy_foreign'), isFalse);
  });

  test('adopting twice does nothing the second time', () async {
    await addOutbox('legacy_mine', 'biz_member');

    expect(await service.adoptUnattributed('user_a'), 1);
    expect(await service.adoptUnattributed('user_a'), 0);
    expect((await service.summarize('user_a')).total, 0);
  });

  test('synced rows are ignored', () async {
    await addOutbox('legacy_mine', 'biz_member');
    await db.customStatement(
      "UPDATE sync_outbox SET status = 'synced' WHERE id = 'legacy_mine'",
    );

    expect((await service.summarize('user_a')).total, 0);
    expect(await service.adoptUnattributed('user_a'), 0);
  });
}
