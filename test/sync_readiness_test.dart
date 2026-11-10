// test/sync_readiness_test.dart
//
// Priority 3: Cloud & Synchronization preparation. Exercises the outbox
// change-tracking, deterministic business export, and ID stability through
// the real services against an in-memory Drift database. Two businesses
// with overlapping names prove isolation end-to-end.

import 'package:bos_application/core/business/current_business.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/ledger/ledger_service.dart';
import 'package:bos_application/core/sync/business_export_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart'
    show CustomerService;
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show TransactionService;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeded default rows use cloud-compatible UUIDs derived from their legacy
/// keys (e.g. cc_cash_<businessId>).
String seededAccountId(String legacyKey) =>
    AppDatabase.cloudCompatibleDefaultId('accounts', legacyKey);

String seededCategoryId(String legacyKey) =>
    AppDatabase.cloudCompatibleDefaultId('categories', legacyKey);

const _owner = 'u_owner';
final _date = DateTime(2026, 9, 30, 10, 30);

Future<AppDatabase> _newDb() async =>
    AppDatabase.forTesting(NativeDatabase.memory());

Future<AuthorizationService> _ownerAuth(
  AppDatabase db,
  String? businessId,
) async {
  BusinessMember? membership;
  if (businessId != null) {
    membership =
        await (db.select(db.businessMembers)..where(
              (m) => m.businessId.equals(businessId) & m.userId.equals(_owner),
            ))
            .getSingleOrNull();
  }
  return AuthorizationService(
    userId: _owner,
    businessId: businessId,
    membership: membership,
  );
}

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

Future<List<SyncOutboxData>> _outbox(AppDatabase db, String businessId) {
  return (db.select(
    db.syncOutbox,
  )..where((o) => o.businessId.equals(businessId))).get();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LedgerService ledger;
  late CustomerService customers;
  late BusinessesData biz;

  setUp(() async {
    db = await _newDb();
    ledger = LedgerService(db);
    customers = CustomerService(db);
    biz = await _createBusiness(db, 'Alpha');
    setCurrentBusinessIdForTest(biz.id);
    SyncTracker.currentUserId = _owner;
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  group('Change tracking (outbox)', () {
    test('a journal posting is tracked as a create', () async {
      await ledger.postSimpleEntry(
        businessId: biz.id,
        date: _date,
        amount: 1000,
        debitAccountId: seededAccountId('acc_cash_${biz.id}'),
        creditAccountId: seededAccountId('acc_sales_${biz.id}'),
        sourceType: 'income',
      );

      final rows = await _outbox(db, biz.id);
      final journals = rows.where((r) => r.entityType == 'journal_entries');
      expect(journals, hasLength(1));
      expect(journals.single.operation, 'create');
      expect(journals.single.status, 'pending');
      // The journal's two ledger lines are tracked with it.
      expect(rows.where((r) => r.entityType == 'ledger_lines'), hasLength(2));
    });

    test('customer payment create + delete both tracked', () async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();
      await customers.recordSale(
        customerId: ana.id,
        amount: 5000,
        date: _date,
        isOnCredit: true,
      );
      await customers.recordPayment(
        customerId: ana.id,
        amount: 2000,
        paymentAccountId: seededAccountId('acc_cash_${biz.id}'),
        date: _date,
      );

      var rows = await _outbox(db, biz.id);
      expect(
        rows.where(
          (r) =>
              r.entityType == 'receivable_payments' && r.operation == 'create',
        ),
        hasLength(1),
      );

      final payment = await db.select(db.receivablePayments).getSingle();

      // Simulate the create having been uploaded; only then is a delete a
      // real remote change (deleting before upload just cancels the create).
      await (db.delete(db.syncOutbox)..where(
            (o) =>
                o.entityType.equals('receivable_payments') &
                o.entityId.equals(payment.id),
          ))
          .go();
      await customers.deleteReceivablePayment(payment.id);

      rows = await _outbox(db, biz.id);
      expect(
        rows.where(
          (r) =>
              r.entityType == 'receivable_payments' && r.operation == 'delete',
        ),
        hasLength(1),
      );
    });

    test('repeated pending edits fold into one outbox row', () async {
      final txns = TransactionService(db, ledger, await _ownerAuth(db, biz.id));
      final id = await txns.saveExpense(
        date: _date,
        categoryId: seededCategoryId('Rent_${biz.id}'),
        amount: 10000,
        paymentAccountId: seededAccountId('acc_cash_${biz.id}'),
        markAsPending: false,
      );
      await txns.saveExpense(
        existingId: id,
        date: _date,
        categoryId: seededCategoryId('Rent_${biz.id}'),
        amount: 12000,
        paymentAccountId: seededAccountId('acc_cash_${biz.id}'),
        markAsPending: false,
      );

      final rows = await _outbox(db, biz.id);
      final expenseCreates = rows.where(
        (r) => r.entityType == 'expenses' && r.operation == 'create',
      );
      final expenseUpdates = rows.where(
        (r) => r.entityType == 'expenses' && r.operation == 'update',
      );
      expect(expenseCreates, hasLength(1));
      // The pending create already carries the latest state.
      expect(expenseUpdates, isEmpty);
    });

    test('outbox is business-scoped', () async {
      final bizB = await _createBusiness(db, 'Beta');
      await ledger.postSimpleEntry(
        businessId: bizB.id,
        date: _date,
        amount: 1000,
        debitAccountId: seededAccountId('acc_cash_${bizB.id}'),
        creditAccountId: seededAccountId('acc_sales_${bizB.id}'),
        sourceType: 'income',
      );

      expect(await _outbox(db, biz.id), isEmpty);
      final rowsB = await _outbox(db, bizB.id);
      expect(rowsB, isNotEmpty);
      expect(rowsB.every((r) => r.businessId == bizB.id), isTrue);
    });
  });

  group('Deterministic export', () {
    test('export preserves ids, relationships, and business scope', () async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();
      await customers.recordSale(
        customerId: ana.id,
        amount: 5000,
        date: _date,
        isOnCredit: true,
      );

      final export = await BusinessExportService(db).exportBusiness(biz.id);

      // Parent-before-child order holds.
      final keys = export.keys.toList();
      expect(
        keys.indexOf('customers'),
        lessThan(keys.indexOf('income_transactions')),
      );
      expect(
        keys.indexOf('journal_entries'),
        lessThan(keys.indexOf('ledger_lines')),
      );

      // The customer id survives intact.
      expect(export['customers']!.single['id'], ana.id);
      // The income row references it, scoped to this business.
      expect(export['income_transactions']!.single['customer_id'], ana.id);
      expect(export['income_transactions']!.single['business_id'], biz.id);
      // Ledger lines come through their parent journal entry.
      expect(export['ledger_lines']!, isNotEmpty);
    });

    test('export excludes the other business entirely', () async {
      final bizB = await _createBusiness(db, 'Beta');
      await customers.addCustomer(name: 'Ana'); // in biz (current)
      setCurrentBusinessIdForTest(bizB.id);
      await customers.addCustomer(name: 'Ana'); // same name, other business
      final anaB = await (db.select(
        db.customers,
      )..where((c) => c.businessId.equals(bizB.id))).getSingle();

      final export = await BusinessExportService(db).exportBusiness(biz.id);
      final exportedIds = export['customers']!.map((r) => r['id']).toList();
      expect(exportedIds, hasLength(1));
      expect(exportedIds, isNot(contains(anaB.id)));
    });
  });

  group('Idempotency', () {
    test('a repeated upload-ready payment has one stable id', () async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();
      await customers.recordSale(
        customerId: ana.id,
        amount: 5000,
        date: _date,
        isOnCredit: true,
      );
      await customers.recordPayment(
        customerId: ana.id,
        amount: 5000,
        paymentAccountId: seededAccountId('acc_cash_${biz.id}'),
        date: _date,
      );

      final payment = await db.select(db.receivablePayments).getSingle();
      // The stable payment id is the same id the outbox references, so a
      // remote system seeing it twice recognizes one logical record.
      final outbox = await _outbox(db, biz.id);
      final createRow = outbox.firstWhere(
        (r) => r.entityType == 'receivable_payments' && r.operation == 'create',
      );
      expect(createRow.entityId, payment.id);
    });
  });
}
