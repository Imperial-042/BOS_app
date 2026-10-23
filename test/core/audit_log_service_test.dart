// // test/core/audit/audit_log_service_test.dart
// //
// // Uses an in-memory Drift database (needs a system sqlite3 library when run
// // with `flutter test` on desktop/CI). NOT executed by the author: the
// // sandbox had no Flutter toolchain. Run: flutter test test/core/audit

// import 'package:bos_application/core/audit/audit_enums.dart';
// import 'package:bos_application/core/audit/audit_log_service.dart';
// import 'package:bos_application/core/audit/audit_repository.dart';
// import 'package:bos_application/core/audit/audit_sync_codec.dart';
// import 'package:bos_application/core/auth/authorization_service.dart';
// import 'package:bos_application/core/auth/bos_access.dart';
// import 'package:bos_application/core/database/app_database.dart';
// import 'package:bos_application/core/sync/sync_change_log.dart';
// import 'package:bos_application/core/sync/sync_tracker.dart';
// import 'package:drift/drift.dart';
// import 'package:drift/native.dart';
// import 'package:flutter_test/flutter_test.dart';

// void main() {
//   late AppDatabase db;
//   late AuditLogService audit;
//   AuditContext? ctx;

//   const biz = 'biz-1';
//   const user = 'user-1';

//   AuditEvent sampleEvent({String? id, String action = 'customer.updated'}) =>
//       AuditEvent(
//         module: AuditModule.sales,
//         actionType: AuditActionType.update,
//         action: action,
//         entityType: 'customers',
//         entityId: 'c1',
//         entityLabel: 'Ann',
//         eventId: id,
//         before: {'name': 'Ann', 'phone': '1'},
//         after: {'name': 'Anne', 'phone': '1'},
//       );

//   Future<int> count(String table) async => (await db
//       .customSelect('SELECT COUNT(*) AS c FROM $table')
//       .getSingle()).read<int>('c');

//   setUp(() async {
//     db = AppDatabase.forTesting(NativeDatabase.memory());
//     SyncTracker.bind(db);
//     SyncTracker.currentUserId = user;
//     ctx = const AuditContext(
//       userId: user,
//       businessId: biz,
//       actorName: 'Owner',
//       actorRole: 'owner',
//       deviceId: 'dev-1',
//     );
//     audit = AuditLogService(db, resolveContext: () => ctx);
//     await db
//         .into(db.businesses)
//         .insert(
//           BusinessesCompanion.insert(
//             id: biz,
//             name: 'Biz',
//             ownerUserId: user,
//           ),
//         );
//   });

//   tearDown(() async {
//     SyncTracker.currentUserId = null;
//     await db.close();
//   });

//   group('event creation', () {
//     test('stores actor, business, device, record, before/after', () async {
//       final id = await audit.record(sampleEvent());
//       final row = await (db.select(
//         db.auditLogs,
//       )..where((t) => t.id.equals(id))).getSingle();

//       expect(row.businessId, biz);
//       expect(row.userId, user);
//       expect(row.actorName, 'Owner');
//       expect(row.actorRole, 'owner');
//       expect(row.deviceId, 'dev-1');
//       expect(row.module, 'sales');
//       expect(row.actionType, 'update');
//       expect(row.entityType, 'customers');
//       expect(row.entityId, 'c1');
//       // Only the changed field is kept.
//       expect(row.beforeJson, '{"name":"Ann"}');
//       expect(row.afterJson, '{"name":"Anne"}');
//     });

//     test('redacts secrets', () {
//       final out = AuditRedactor.sanitize({
//         'passwordHash': 'abc',
//         'name': 'x',
//         'nested': {'apiKey': 'k', 'ok': 1},
//       });
//       expect(out!['passwordHash'], '***');
//       expect(out['name'], 'x');
//       expect((out['nested'] as Map)['apiKey'], '***');
//       expect((out['nested'] as Map)['ok'], 1);
//     });

//     test('refund/void/adjustment require a reason', () async {
//       expect(
//         () => audit.record(
//           const AuditEvent(
//             module: AuditModule.sales,
//             actionType: AuditActionType.refund,
//             action: 'sale.refunded',
//             entityType: 'pos_sales',
//           ),
//         ),
//         throwsArgumentError,
//       );
//       await audit.record(
//         const AuditEvent(
//           module: AuditModule.sales,
//           actionType: AuditActionType.refund,
//           action: 'sale.refunded',
//           entityType: 'pos_sales',
//           reason: 'Customer returned item',
//         ),
//       );
//       expect(await count('audit_logs'), 1);
//     });

//     test('throws instead of dropping when there is no context', () async {
//       ctx = null;
//       expect(() => audit.record(sampleEvent()),
//           throwsA(isA<AuditContextException>()));
//       expect(await audit.tryRecord(sampleEvent()), isFalse);
//       expect(await count('audit_logs'), 0);
//     });
//   });

//   group('atomicity', () {
//     Future<void> insertCustomer() => db
//         .into(db.customers)
//         .insert(
//           CustomersCompanion.insert(id: 'c1', businessId: biz, name: 'Ann'),
//         );

//     test('business change and audit commit together', () async {
//       await audit.runAudited<void>(
//         change: insertCustomer,
//         event: (_) => sampleEvent(),
//       );
//       expect(await count('customers'), 1);
//       expect(await count('audit_logs'), 1);
//     });

//     test('failure after both writes rolls back both', () async {
//       await expectLater(
//         db.transaction(() async {
//           await insertCustomer();
//           await audit.record(sampleEvent());
//           throw StateError('boom');
//         }),
//         throwsStateError,
//       );
//       expect(await count('customers'), 0);
//       expect(await count('audit_logs'), 0);
//     });

//     test('audit failure rolls back the business change', () async {
//       ctx = null;
//       await expectLater(
//         audit.runAudited<void>(
//           change: insertCustomer,
//           event: (_) => sampleEvent(),
//         ),
//         throwsA(isA<AuditContextException>()),
//       );
//       expect(await count('customers'), 0);
//     });
//   });

//   group('offline queue + duplicates', () {
//     Future<List<SyncOutboxData>> auditOutbox() async =>
//         (await db.select(db.syncOutbox).get())
//             .where((o) => o.entityType == 'audit_logs')
//             .toList();

//     test('event is queued as a pending create (no network involved)', () async {
//       final id = await audit.record(sampleEvent());
//       await SyncChangeLog.drain(db, fallbackOwner: user);

//       final rows = await auditOutbox();
//       expect(rows, hasLength(1));
//       expect(rows.single.entityId, id);
//       expect(rows.single.operation, 'create');
//       expect(rows.single.status, 'pending');
//     });

//     test('same event id is stored and queued once', () async {
//       await audit.record(sampleEvent(id: 'evt-1'));
//       await audit.record(sampleEvent(id: 'evt-1'));
//       await SyncChangeLog.drain(db, fallbackOwner: user);
//       await SyncChangeLog.drain(db, fallbackOwner: user);

//       expect(await count('audit_logs'), 1);
//       expect(await auditOutbox(), hasLength(1));
//     });

//     test('mutation id is stable when the change is re-recorded', () async {
//       await audit.record(sampleEvent(id: 'evt-2'));
//       await SyncChangeLog.drain(db, fallbackOwner: user);
//       final first = (await auditOutbox()).single.mutationId;

//       await SyncTracker.record(
//         db,
//         businessId: biz,
//         entityType: 'audit_logs',
//         entityId: 'evt-2',
//         operation: SyncOp.create,
//         ownerUserId: user,
//       );
//       final after = await auditOutbox();
//       expect(after, hasLength(1));
//       expect(after.single.mutationId, first);
//     });
//   });

//   group('history protection (local)', () {
//     setUp(() async => audit.record(sampleEvent(id: 'evt-3')));

//     test('app code cannot update or delete audit rows', () async {
//       await expectLater(
//         db.customStatement("UPDATE audit_logs SET reason = 'x'"),
//         throwsA(anything),
//       );
//       await expectLater(
//         db.customStatement('DELETE FROM audit_logs'),
//         throwsA(anything),
//       );
//       expect(await count('audit_logs'), 1);
//     });

//     test('sync pull (suppressed) may still apply a cloud copy', () async {
//       await SyncChangeLog.suppressed(
//         db,
//         () => db.customStatement("UPDATE audit_logs SET reason = 'cloud'"),
//       );
//       final row = await db.select(db.auditLogs).getSingle();
//       expect(row.reason, 'cloud');
//     });
//   });

//   group('viewing permission + filters', () {
//     AuthorizationService authWith(Set<BosPermission> perms) =>
//         AuthorizationService(
//           userId: user,
//           businessId: biz,
//           membership: BusinessMember(
//             id: 'm1',
//             businessId: biz,
//             userId: user,
//             role: 'owner',
//             status: 'active',
//             joinedAt: DateTime(2026),
//             updatedAt: DateTime(2026),
//           ),
//           effectivePermissions: perms,
//         );

//     test('denied without the permission', () {
//       final repo = AuditRepository(db, authWith({}));
//       expect(
//         () => repo.watch(const AuditFilter()),
//         throwsA(isA<PermissionDeniedException>()),
//       );
//       expect(
//         () => AuditRepository(db, AuthorizationService.denied)
//             .watch(const AuditFilter()),
//         throwsA(isA<PermissionDeniedException>()),
//       );
//     });

//     test('filters by module, action type, record and date', () async {
//       await audit.record(sampleEvent(id: 'a'));
//       await audit.record(
//         AuditEvent(
//           module: AuditModule.inventory,
//           actionType: AuditActionType.adjustment,
//           action: 'stock.adjusted',
//           entityType: 'supplies',
//           entityId: 's9',
//           entityLabel: 'Flour',
//           reason: 'Spoilage',
//           eventId: 'b',
//         ),
//       );
//       final repo = AuditRepository(
//         db,
//         authWith({AuditRepository.viewPermission}),
//       );

//       Future<List<String>> ids(AuditFilter f) async =>
//           (await repo.watch(f).first).map((r) => r.id).toList();

//       expect(await ids(const AuditFilter()), hasLength(2));
//       expect(
//         await ids(const AuditFilter(module: AuditModule.inventory)),
//         ['b'],
//       );
//       expect(
//         await ids(const AuditFilter(actionType: AuditActionType.update)),
//         ['a'],
//       );
//       expect(await ids(const AuditFilter(query: 'Flour')), ['b']);
//       expect(await ids(const AuditFilter(userId: 'someone-else')), isEmpty);
//       expect(
//         await ids(AuditFilter(from: DateTime.now().add(const Duration(days: 1)))),
//         isEmpty,
//       );
//     });
//   });

//   group('sync codec', () {
//     test('decodes JSON text columns for jsonb', () {
//       final out = AuditSyncCodec.toCloud({
//         'id': 'x',
//         'before_json': '{"a":1}',
//         'after_json': null,
//         'details': 'not json',
//         'reason': '{"left":"alone"}',
//       });
//       expect(out['before_json'], {'a': 1});
//       expect(out['after_json'], isNull);
//       expect(out['details'], 'not json');
//       expect(out['reason'], '{"left":"alone"}');
//     });
//   });
// }
