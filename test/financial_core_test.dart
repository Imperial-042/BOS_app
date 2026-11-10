// test/financial_core_test.dart
//
// Priority 1: Core Financial Integrity.
//
// Exercises the REAL services (LedgerService, TransactionService,
// CustomerService, SupplierService, CapitalAssetLiabilityService) against
// an in-memory Drift database with the standard seeded chart of accounts,
// and asserts for every scenario:
//   * the journal entry is balanced (total debits == total credits),
//   * the debit/credit sides point at the correct GL accounts,
//   * balances computed from the ledger are correct,
//   * invalid operations (overpayment, bad account, wrong business) throw
//     and leave no partial writes behind.

import 'package:bos_application/core/business/current_business.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/ledger/ledger_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:bos_application/features/transactions/domain/capital_asset_liability_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart'
    show CustomerService;
import 'package:bos_application/features/transactions/presentation/screens/suppliers_page.dart'
    show SupplierService;
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

const _biz = 'biz_test';

Future<AppDatabase> _newDb() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db
      .into(db.businesses)
      .insert(
        BusinessesCompanion.insert(
          id: _biz,
          name: 'Test Co',
          ownerUserId: 'u_owner',
          isCurrent: const Value(true),
        ),
      );
  await db.seedDefaultsForBusiness(_biz);
  return db;
}

/// Balance straight from the ledger, same formula the app reports use.
Future<int> _balance(AppDatabase db, String accountId) async {
  final account = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(accountId))).getSingle();
  final row = await db
      .customSelect(
        '''
      SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c
      FROM ledger_lines ll
      INNER JOIN journal_entries je ON je.id = ll.journal_entry_id
      WHERE ll.account_id = ? AND je.business_id = ?
      ''',
        variables: [Variable.withString(accountId), Variable.withString(_biz)],
      )
      .getSingle();
  final d = row.read<int>('d');
  final c = row.read<int>('c');
  final creditNormal = const ['liability', 'equity', 'income'];
  return creditNormal.contains(account.type)
      ? account.startingBalance + c - d
      : account.startingBalance + d - c;
}

/// Global integrity: every journal entry's debits equal its credits.
Future<void> _expectAllEntriesBalanced(AppDatabase db) async {
  final row = await db.customSelect('''
      SELECT COUNT(*) AS bad FROM (
        SELECT journal_entry_id,
               SUM(debit) AS total_debit,
               SUM(credit) AS total_credit
        FROM ledger_lines
        GROUP BY journal_entry_id
        HAVING total_debit <> total_credit
      )
      ''').getSingle();
  expect(row.read<int>('bad'), 0, reason: 'Every journal entry must balance');
}

Future<int> _journalCount(AppDatabase db) =>
    db.select(db.journalEntries).get().then((rows) => rows.length);

AuthorizationService _ownerAuth() => AuthorizationService(
  userId: 'u_owner',
  businessId: _biz,
  membership: BusinessMember(
    id: 'mem_owner_$_biz',
    businessId: _biz,
    userId: 'u_owner',
    role: 'owner',
    status: 'active',
    invitedBy: null,
    joinedAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setCurrentBusinessIdForTest(_biz);

  late AppDatabase db;
  late LedgerService ledger;
  late TransactionService txns;
  late CustomerService customers;
  late SupplierService suppliers;
  late CapitalAssetLiabilityService balanceSheet;

  final date = DateTime(2026, 9, 30, 10, 30);

  setUp(() async {
    db = await _newDb();
    SyncTracker.currentUserId = 'u_owner';
    ledger = LedgerService(db);
    txns = TransactionService(db, ledger, _ownerAuth());
    customers = CustomerService(db);
    suppliers = SupplierService(db);
    balanceSheet = CapitalAssetLiabilityService(db);
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  group('Income', () {
    test(
      'cash income: Dr cash, Cr income, uses the transaction date',
      () async {
        await txns.saveIncome(
          date: date,
          categoryId: seededCategoryId('Sale_$_biz'),
          amount: 100000, // ₱1,000.00
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          markAsPending: false,
        );

        expect(await _balance(db, seededAccountId('acc_cash_$_biz')), 100000);
        expect(await _balance(db, seededAccountId('acc_sales_$_biz')), 100000);

        final entry = await db.select(db.journalEntries).getSingle();
        expect(entry.sourceType, 'income');
        expect(entry.entryDate, date); // not DateTime.now()
        await _expectAllEntriesBalanced(db);
      },
    );

    test('credit income: Dr AR, Cr Sales Income', () async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();

      await customers.recordSale(
        customerId: ana.id,
        amount: 50000,
        date: date,
        isOnCredit: true,
      );

      expect(await _balance(db, seededAccountId('acc_ar_$_biz')), 50000);
      expect(await _balance(db, seededAccountId('acc_sales_$_biz')), 50000);
      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), 0);
      await _expectAllEntriesBalanced(db);
    });
  });

  group('Receivable collection', () {
    Future<String> saleOnCredit(int amount) async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();
      await customers.recordSale(
        customerId: ana.id,
        amount: amount,
        date: date,
        isOnCredit: true,
      );
      return ana.id;
    }

    test('partial collection: Dr cash, Cr AR; balance remains', () async {
      final customerId = await saleOnCredit(50000);
      await customers.recordPayment(
        customerId: customerId,
        amount: 20000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
        date: date,
      );

      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), 20000);
      expect(await _balance(db, seededAccountId('acc_ar_$_biz')), 30000);
      // Income is NOT recognized a second time.
      expect(await _balance(db, seededAccountId('acc_sales_$_biz')), 50000);
      await _expectAllEntriesBalanced(db);
    });

    test('full collection: receivable goes to zero', () async {
      final customerId = await saleOnCredit(50000);
      await customers.recordPayment(
        customerId: customerId,
        amount: 50000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
        date: date,
      );

      expect(await _balance(db, seededAccountId('acc_ar_$_biz')), 0);
      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), 50000);
      await _expectAllEntriesBalanced(db);
    });

    test('overpayment attempt: throws and writes nothing', () async {
      final customerId = await saleOnCredit(50000);
      final journalsBefore = await _journalCount(db);

      expect(
        () => customers.recordPayment(
          customerId: customerId,
          amount: 60000,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          date: date,
        ),
        throwsStateError,
      );

      expect(await _journalCount(db), journalsBefore);
      expect(await db.select(db.receivablePayments).get(), isEmpty);
      expect(await _balance(db, seededAccountId('acc_ar_$_biz')), 50000);
    });
  });

  group('Expenses', () {
    test('cash expense: Dr expense account, Cr payment account', () async {
      await txns.saveExpense(
        date: date,
        categoryId: seededCategoryId('Rent_$_biz'),
        amount: 75000,
        paymentAccountId: seededAccountId('acc_bank_$_biz'),
        markAsPending: false,
      );

      expect(await _balance(db, seededAccountId('acc_rent_exp_$_biz')), 75000);
      expect(await _balance(db, seededAccountId('acc_bank_$_biz')), -75000);
      await _expectAllEntriesBalanced(db);
    });

    test('editing an expense replaces its journal entry atomically', () async {
      final id = await txns.saveExpense(
        date: date,
        categoryId: seededCategoryId('Rent_$_biz'),
        amount: 75000,
        paymentAccountId: seededAccountId('acc_bank_$_biz'),
        markAsPending: false,
      );

      await txns.saveExpense(
        existingId: id,
        date: date,
        categoryId: seededCategoryId('Rent_$_biz'),
        amount: 90000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
        markAsPending: false,
      );

      // Exactly one journal entry survives, with the NEW amounts/accounts.
      expect(await _journalCount(db), 1);
      expect(await _balance(db, seededAccountId('acc_bank_$_biz')), 0);
      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), -90000);
      expect(await _balance(db, seededAccountId('acc_rent_exp_$_biz')), 90000);
      await _expectAllEntriesBalanced(db);
    });

    test('receipt photo path is persisted with the expense', () async {
      final id = await txns.saveExpense(
        date: date,
        categoryId: seededCategoryId('Rent_$_biz'),
        amount: 75000,
        paymentAccountId: seededAccountId('acc_bank_$_biz'),
        markAsPending: false,
        receiptPhotoPath: 'receipts/rent.jpg',
      );

      final expense = await (db.select(
        db.expenses,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(expense.receiptPhotoPath, 'receipts/rent.jpg');
    });

    test('income cannot be saved to an expense category', () async {
      await expectLater(
        txns.saveIncome(
          date: date,
          categoryId: seededCategoryId('Rent_$_biz'),
          amount: 10000,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          markAsPending: false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.incomeTransactions).get(), isEmpty);
      expect(await _journalCount(db), 0);
    });

    test('completed transactions require a payment account', () async {
      await expectLater(
        txns.saveExpense(
          date: date,
          categoryId: seededCategoryId('Rent_$_biz'),
          amount: 10000,
          markAsPending: false,
        ),
        throwsArgumentError,
      );
      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await _journalCount(db), 0);
    });

    test('deleting an expense syncs linked cart unlinking first', () async {
      final expenseId = await txns.saveExpense(
        date: date,
        categoryId: seededCategoryId('Rent_$_biz'),
        amount: 75000,
        paymentAccountId: seededAccountId('acc_bank_$_biz'),
        markAsPending: false,
      );
      await db
          .into(db.shoppingCarts)
          .insert(
            ShoppingCartsCompanion.insert(
              id: 'cart-linked',
              businessId: _biz,
              cartDate: date,
              totalAmount: 75000,
              expenseId: Value(expenseId),
            ),
          );

      await txns.deleteExpense(expenseId);

      final cart = await (db.select(
        db.shoppingCarts,
      )..where((row) => row.id.equals('cart-linked'))).getSingle();
      expect(cart.expenseId, isNull);
      final queuedCartUpdate = await (db.select(db.syncOutbox)..where(
            (row) =>
                row.entityType.equals('shopping_carts') &
                row.entityId.equals('cart-linked') &
                row.operation.equals('update'),
          ))
          .get();
      expect(queuedCartUpdate, hasLength(1));
    });
  });

  test('new categories are queued for synchronization', () async {
    final category = await txns.addCategory('Travel costs', isIncome: false);

    final queued =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.entityType.equals('categories') &
                  row.entityId.equals(category.id),
            ))
            .get();
    expect(queued, hasLength(1));
    expect(queued.single.operation, 'create');
  });

  group('Supplier payables', () {
    Future<String> purchaseOnCredit(int amount) async {
      await suppliers.addSupplier(name: 'Acme');
      final acme = await db.select(db.suppliers).getSingle();
      await suppliers.recordPurchase(
        supplierId: acme.id,
        amount: amount,
        date: date,
        isOnCredit: true,
      );
      return acme.id;
    }

    test('credit purchase: Dr inventory expense, Cr AP', () async {
      await purchaseOnCredit(120000);

      expect(await _balance(db, seededAccountId('acc_inv_exp_$_biz')), 120000);
      expect(await _balance(db, seededAccountId('acc_ap_$_biz')), 120000);
      await _expectAllEntriesBalanced(db);
    });

    test('partial supplier payment reduces the payable', () async {
      final supplierId = await purchaseOnCredit(120000);
      await suppliers.recordPayment(
        supplierId: supplierId,
        amount: 40000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
        date: date,
      );

      expect(await _balance(db, seededAccountId('acc_ap_$_biz')), 80000);
      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), -40000);
      await _expectAllEntriesBalanced(db);
    });

    test('full supplier payment settles the payable', () async {
      final supplierId = await purchaseOnCredit(120000);
      await suppliers.recordPayment(
        supplierId: supplierId,
        amount: 120000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
        date: date,
      );

      expect(await _balance(db, seededAccountId('acc_ap_$_biz')), 0);
      await _expectAllEntriesBalanced(db);
    });

    test('overpayment attempt: throws and writes nothing', () async {
      final supplierId = await purchaseOnCredit(120000);
      final journalsBefore = await _journalCount(db);

      expect(
        () => suppliers.recordPayment(
          supplierId: supplierId,
          amount: 120001,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          date: date,
        ),
        throwsStateError,
      );

      expect(await _journalCount(db), journalsBefore);
      expect(await db.select(db.payablePayments).get(), isEmpty);
    });

    test('duplicate full payment is rejected on the second attempt', () async {
      final supplierId = await purchaseOnCredit(120000);
      await suppliers.recordPayment(
        supplierId: supplierId,
        amount: 120000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
        date: date,
      );

      expect(
        () => suppliers.recordPayment(
          supplierId: supplierId,
          amount: 120000,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          date: date,
        ),
        throwsStateError,
      );

      expect(await db.select(db.payablePayments).get(), hasLength(1));
      expect(await _balance(db, seededAccountId('acc_ap_$_biz')), 0);
      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), -120000);
    });
  });

  group('Payment validation', () {
    test('non-payment account is rejected', () async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();
      await customers.recordSale(
        customerId: ana.id,
        amount: 10000,
        date: date,
        isOnCredit: true,
      );

      // AR is a real account but NOT a payment account.
      expect(
        () => customers.recordPayment(
          customerId: ana.id,
          amount: 5000,
          paymentAccountId: seededAccountId('acc_ar_$_biz'),
          date: date,
        ),
        throwsA(isA<LedgerException>()),
      );
    });

    test('missing account is rejected without writing anything', () async {
      final journalsBefore = await _journalCount(db);
      expect(
        () => ledger.postSimpleEntry(
          businessId: _biz,
          date: date,
          amount: 1000,
          debitAccountId: 'acc_missing_$_biz',
          creditAccountId: seededAccountId('acc_cash_$_biz'),
          sourceType: 'test',
        ),
        throwsA(isA<LedgerException>()),
      );
      expect(await _journalCount(db), journalsBefore);
      expect(await db.select(db.ledgerLines).get(), isEmpty);
    });

    test("another business's customer cannot be paid here", () async {
      // Set up a second business with its own customer.
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: 'biz_other',
              name: 'Other Co',
              ownerUserId: 'u_other',
            ),
          );
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'cust_other',
              businessId: 'biz_other',
              name: 'Outsider',
            ),
          );

      expect(
        () => customers.recordPayment(
          customerId: 'cust_other',
          amount: 1000,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          date: date,
        ),
        throwsStateError,
      );
      expect(await db.select(db.receivablePayments).get(), isEmpty);
    });

    test("another business's supplier cannot be paid here", () async {
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: 'biz_other',
              name: 'Other Co',
              ownerUserId: 'u_other',
            ),
          );
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              id: 'sup_other',
              businessId: 'biz_other',
              name: 'Outsider',
            ),
          );

      expect(
        () => suppliers.recordPayment(
          supplierId: 'sup_other',
          amount: 1000,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          date: date,
        ),
        throwsStateError,
      );
      expect(await db.select(db.payablePayments).get(), isEmpty);
    });

    test('zero-amount payment is rejected', () async {
      await customers.addCustomer(name: 'Ana');
      final ana = await db.select(db.customers).getSingle();

      expect(
        () => customers.recordPayment(
          customerId: ana.id,
          amount: 0,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          date: date,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Assets', () {
    Future<String> equipmentAccount() async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'acc_equipment_$_biz',
              businessId: _biz,
              name: 'Equipment',
              type: 'asset',
              subtype: const Value('non_current_asset'),
            ),
          );
      return 'acc_equipment_$_biz';
    }

    test('asset purchased with cash: Dr asset, Cr payment account', () async {
      final assetAccountId = await equipmentAccount();
      await balanceSheet.recordAsset(
        businessId: _biz,
        date: date,
        amount: 250000,
        assetAccountId: assetAccountId,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
      );

      expect(await _balance(db, assetAccountId), 250000);
      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), -250000);
      expect(await _balance(db, seededAccountId('acc_ap_$_biz')), 0);
      await _expectAllEntriesBalanced(db);
    });

    test(
      'asset purchased on credit: Dr asset, Cr AP (not an expense)',
      () async {
        final assetAccountId = await equipmentAccount();
        await balanceSheet.recordAsset(
          businessId: _biz,
          date: date,
          amount: 250000,
          assetAccountId: assetAccountId,
        );

        expect(await _balance(db, assetAccountId), 250000);
        expect(await _balance(db, seededAccountId('acc_ap_$_biz')), 250000);
        await _expectAllEntriesBalanced(db);
      },
    );
  });

  group('Liabilities', () {
    Future<String> loanAccount() async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'acc_loan_$_biz',
              businessId: _biz,
              name: 'Bank Loan',
              type: 'liability',
              subtype: const Value('loan_payable'),
            ),
          );
      return 'acc_loan_$_biz';
    }

    test(
      'liability incurred: Dr cash, Cr loan; paid: Dr loan, Cr cash',
      () async {
        final liabilityId = await loanAccount();
        await balanceSheet.recordLiability(
          businessId: _biz,
          date: date,
          amount: 500000,
          liabilityAccountId: liabilityId,
          paymentAccountId: seededAccountId('acc_bank_$_biz'),
        );

        expect(await _balance(db, seededAccountId('acc_bank_$_biz')), 500000);
        expect(await _balance(db, liabilityId), 500000);

        await balanceSheet.payLiability(
          businessId: _biz,
          date: date,
          amount: 150000,
          liabilityAccountId: liabilityId,
          paymentAccountId: seededAccountId('acc_bank_$_biz'),
        );

        expect(await _balance(db, liabilityId), 350000);
        expect(await _balance(db, seededAccountId('acc_bank_$_biz')), 350000);
        await _expectAllEntriesBalanced(db);

        // The payment is not an expense: no expense account was touched.
        final expenseDebit = await db.customSelect('''
          SELECT COALESCE(SUM(ll.debit), 0) AS d
          FROM ledger_lines ll
          INNER JOIN accounts a ON a.id = ll.account_id
          WHERE a.type = 'expense'
          ''').getSingle();
        expect(expenseDebit.read<int>('d'), 0);
      },
    );
  });

  group('Capital', () {
    test('owner contribution: Dr cash, Cr equity', () async {
      await balanceSheet.recordCapital(
        businessId: _biz,
        date: date,
        amount: 1000000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
      );

      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), 1000000);
      expect(await _balance(db, seededAccountId('acc_equity_$_biz')), 1000000);
      await _expectAllEntriesBalanced(db);
    });

    test('owner withdrawal: Dr equity, Cr cash — not an expense', () async {
      await balanceSheet.recordCapital(
        businessId: _biz,
        date: date,
        amount: 1000000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
      );
      await balanceSheet.recordCapitalWithdrawal(
        businessId: _biz,
        date: date,
        amount: 100000,
        paymentAccountId: seededAccountId('acc_cash_$_biz'),
      );

      expect(await _balance(db, seededAccountId('acc_cash_$_biz')), 900000);
      expect(await _balance(db, seededAccountId('acc_equity_$_biz')), 900000);
      await _expectAllEntriesBalanced(db);
    });
  });

  group('Atomicity', () {
    test('service rejects users without finance-create permission', () async {
      final cashierAuth = AuthorizationService(
        userId: 'u_cashier',
        businessId: _biz,
        membership: BusinessMember(
          id: 'mem_cashier_$_biz',
          businessId: _biz,
          userId: 'u_cashier',
          role: 'cashier',
          status: 'active',
          invitedBy: null,
          joinedAt: date,
          updatedAt: date,
        ),
      );
      final cashierTransactions = TransactionService(
        db,
        ledger,
        cashierAuth,
      );

      await expectLater(
        cashierTransactions.saveIncome(
          date: date,
          categoryId: seededCategoryId('Sale_$_biz'),
          amount: 10000,
          paymentAccountId: seededAccountId('acc_cash_$_biz'),
          markAsPending: false,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(await db.select(db.incomeTransactions).get(), isEmpty);
    });

    test('a failed posting leaves no journal entry or ledger lines', () async {
      final journalsBefore = await _journalCount(db);

      expect(
        () => txns.saveIncome(
          date: date,
          categoryId: seededCategoryId('Sale_$_biz'),
          amount: 100000,
          // Valid id format, but the row does not exist.
          paymentAccountId: 'acc_ghost_$_biz',
          markAsPending: false,
        ),
        throwsA(isA<LedgerException>()),
      );

      expect(await _journalCount(db), journalsBefore);
      expect(await db.select(db.ledgerLines).get(), isEmpty);
      expect(await db.select(db.incomeTransactions).get(), isEmpty);
    });
  });
}
