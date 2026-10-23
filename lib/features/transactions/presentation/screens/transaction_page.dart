import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart'
    show AuditLogger;
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/ledger/ledger_service.dart';
import '../../../../core/sync/sync_tracker.dart';

// ============================================================
// CONSTANTS
// ============================================================

String kCurrentBusinessId = 'biz_001';

const _incomeColor = Color(0xFF159B67);
const _expenseColor = Color(0xFFE05252);

// ============================================================
// PROVIDERS
// ============================================================

final ledgerVersionProvider = StateProvider<int>((ref) => 0);

final businessProfileProvider = StreamProvider<BusinessesData>((ref) {
  ref.watch(ledgerVersionProvider);

  final db = ref.watch(databaseProvider);

  return (db.select(
    db.businesses,
  )..where((business) => business.id.equals(kCurrentBusinessId))).watchSingle();
});

final ledgerServiceProvider = Provider<LedgerService>((ref) {
  return LedgerService(ref.watch(databaseProvider));
});

final categoriesByTypeProvider = FutureProvider.family<List<Category>, String>((
  ref,
  txnType,
) {
  ref.watch(ledgerVersionProvider);

  final db = ref.watch(databaseProvider);

  return (db.select(db.categories)..where(
        (c) =>
            c.businessId.equals(kCurrentBusinessId) &
            c.txnType.equals(txnType) &
            c.isActive.equals(true),
      ))
      .get();
});

final paymentAccountsProvider = FutureProvider<List<Account>>((ref) {
  ref.watch(ledgerVersionProvider);

  final db = ref.watch(databaseProvider);

  return (db.select(db.accounts)..where(
        (a) =>
            a.businessId.equals(kCurrentBusinessId) &
            a.isPaymentAccount.equals(true) &
            a.isActive.equals(true),
      ))
      .get();
});

// ============================================================
// TRANSACTION SERVICE
// ============================================================

class ExpensePaymentSplit {
  final String paymentAccountId;
  final int amount;

  const ExpensePaymentSplit({
    required this.paymentAccountId,
    required this.amount,
  });
}

class TransactionService {
  final AppDatabase db;
  final LedgerService ledgerService;
  final AuthorizationService auth;

  TransactionService(this.db, this.ledgerService, this.auth);

  // ----------------------------------------------------------
  // SYNC HELPERS
  // ----------------------------------------------------------

  Map<String, Object?> _expenseSnapshot(Expense e) => {
    'amount': e.amount,
    'categoryId': e.categoryId,
    'status': e.status,
    'paymentAccountId': e.paymentAccountId,
    'description': e.description,
    'reference': e.reference,
    'expenseDate': e.expenseDate,
  };
  Map<String, Object?> _incomeSnapshot(IncomeTransaction i) => {
    'amount': i.amount,
    'categoryId': i.categoryId,
    'status': i.status,
    'paymentAccountId': i.paymentAccountId,
    'customerId': i.customerId,
    'description': i.description,
    'reference': i.reference,
    'txnDate': i.txnDate,
  };

  Future<void> _queueSync({
    required String businessId,
    required String entityType,
    required String entityId,
    required String operation,
  }) async {
    await SyncTracker.record(
      db,
      businessId: businessId,
      entityType: entityType,
      entityId: entityId,
      operation: operation == 'insert' ? SyncOp.create : operation,
      ownerUserId: auth.userId,
    );

    // ignore: avoid_print
    print('[outbox] queued $operation $entityType/$entityId');
  }

  Future<List<String>> _ledgerLineIds(String journalEntryId) async {
    final rows = await (db.select(
      db.ledgerLines,
    )..where((line) => line.journalEntryId.equals(journalEntryId))).get();

    return rows.map((row) => row.id).toList();
  }

  Future<void> _trackJournalDeleted(
    String journalEntryId,
    List<String> lineIds,
  ) async {
    for (final lineId in lineIds) {
      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'ledger_lines',
        entityId: lineId,
        operation: SyncOp.delete,
      );
    }

    await SyncTracker.record(
      db,
      businessId: kCurrentBusinessId,
      entityType: 'journal_entries',
      entityId: journalEntryId,
      operation: SyncOp.delete,
    );
  }

  // ----------------------------------------------------------
  // EXPENSE
  // ----------------------------------------------------------

  Future<String> saveExpense({
    String? existingId,
    required DateTime date,
    required String categoryId,
    required int amount,
    String? paymentAccountId,
    String? description,
    String? notes,
    String? reference,
    required bool markAsPending,
    String? receiptPhotoPath,
  }) async {
    final id = existingId ?? const Uuid().v4();
    final status = markAsPending ? 'pending' : 'completed';

    await db.transaction(() async {
      String? previousJournalEntryId;
      Expense? previous;
      if (existingId != null) {
        final existing = await (db.select(
          db.expenses,
        )..where((e) => e.id.equals(existingId))).getSingleOrNull();
        previous = existing;
        previousJournalEntryId = existing?.journalEntryId;
      }

      // -----------------------------------------------------------------------
      // EDIT: remove the old journal posting.
      // Queue those deletes so the other devices remove the old posting too.
      // -----------------------------------------------------------------------
      if (previousJournalEntryId != null) {
        final oldLines =
            await (db.select(db.ledgerLines)..where(
                  (line) => line.journalEntryId.equals(previousJournalEntryId!),
                ))
                .get();

        await (db.delete(db.ledgerLines)..where(
              (line) => line.journalEntryId.equals(previousJournalEntryId!),
            ))
            .go();

        await (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
          const ExpensesCompanion(journalEntryId: Value(null)),
        );

        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(previousJournalEntryId!))).go();

        for (final line in oldLines) {
          await _queueSync(
            businessId: kCurrentBusinessId,
            entityType: 'ledger_lines',
            entityId: line.id,
            operation: 'delete',
          );
        }

        await _queueSync(
          businessId: kCurrentBusinessId,
          entityType: 'journal_entries',
          entityId: previousJournalEntryId,
          operation: 'delete',
        );
      }

      // -----------------------------------------------------------------------
      // CREATE NEW JOURNAL POSTING.
      // -----------------------------------------------------------------------
      String? journalEntryId;

      if (status == 'completed' && paymentAccountId != null) {
        journalEntryId = await ledgerService.postEntry(
          businessId: kCurrentBusinessId,
          categoryId: categoryId,
          amount: amount,
          paymentAccountId: paymentAccountId,
          sourceType: 'expense',
          date: date,
          sourceId: id,
          description: description,
        );
      }

      // -----------------------------------------------------------------------
      // SAVE EXPENSE.
      // -----------------------------------------------------------------------
      final companion = ExpensesCompanion(
        id: Value(id),
        businessId: Value(kCurrentBusinessId),
        expenseDate: Value(date),
        categoryId: Value(categoryId),
        amount: Value(amount),
        paymentAccountId: Value(paymentAccountId),
        description: Value(description),
        notes: Value(notes),
        reference: Value(reference),
        status: Value(status),
        journalEntryId: Value(journalEntryId),
        updatedAt: Value(DateTime.now()),
      );

      if (existingId == null) {
        await db.into(db.expenses).insert(companion);
      } else {
        await db.update(db.expenses).replace(companion);
      }

      // -----------------------------------------------------------------------
      // QUEUE THE NEW JOURNAL + LEDGER LINES.
      // -----------------------------------------------------------------------
      if (journalEntryId != null) {
        await _queueSync(
          businessId: kCurrentBusinessId,
          entityType: 'journal_entries',
          entityId: journalEntryId,
          operation: existingId == null ? 'insert' : 'update',
        );

        final lines = await (db.select(
          db.ledgerLines,
        )..where((line) => line.journalEntryId.equals(journalEntryId!))).get();

        for (final line in lines) {
          await _queueSync(
            businessId: kCurrentBusinessId,
            entityType: 'ledger_lines',
            entityId: line.id,
            operation: 'insert',
          );
        }
      }

      // -----------------------------------------------------------------------
      // QUEUE THE EXPENSE ITSELF.
      // -----------------------------------------------------------------------
      await _queueSync(
        businessId: kCurrentBusinessId,
        entityType: 'expenses',
        entityId: id,
        operation: existingId == null ? 'insert' : 'update',
      );

      await AuditLogger.record(
        db,
        businessId: kCurrentBusinessId,
        userId: auth.userId,
        action: existingId == null
            ? 'finance.expense_created'
            : 'finance.expense_updated',
        module: AuditModule.finance,
        actionType: existingId == null
            ? AuditActionType.create
            : AuditActionType.update,
        entityType: 'expense',
        entityId: id,
        entityLabel: description ?? 'Expense',
        before: previous == null ? null : _expenseSnapshot(previous),
        after: {
          'amount': amount,
          'categoryId': categoryId,
          'status': status,
          'paymentAccountId': paymentAccountId,
          'description': description,
          'reference': reference,
          'expenseDate': date,
        },
      );
    });

    return id;
  }
  // ----------------------------------------------------------
  // EXPENSE WITH PAYMENT SPLITS
  // ----------------------------------------------------------

  Future<String> saveExpenseWithPaymentSplits({
    required DateTime date,
    required String categoryId,
    required int amount,
    required List<ExpensePaymentSplit> payments,
    String? description,
    String? notes,
    String? reference,
  }) async {
    auth.requireAny([
      BosPermission.financeCreate,
      BosPermission.purchasingCreate,
    ], businessId: kCurrentBusinessId);

    if (amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Amount must be greater than zero.',
      );
    }

    if (payments.isEmpty) {
      throw ArgumentError.value(
        payments,
        'payments',
        'At least one payment account is required.',
      );
    }

    final totalPaid = payments.fold<int>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    if (totalPaid != amount) {
      throw ArgumentError(
        'Payment split total ($totalPaid) must equal '
        'expense amount ($amount).',
      );
    }

    final paymentIds = <String>{};

    for (final payment in payments) {
      if (payment.amount <= 0) {
        throw ArgumentError('Each payment amount must be greater than zero.');
      }

      if (!paymentIds.add(payment.paymentAccountId)) {
        throw ArgumentError(
          'A payment account cannot appear more than once in '
          'the split.',
        );
      }
    }

    final expenseId = const Uuid().v4();
    final journalEntryId = const Uuid().v4();

    await db.transaction(() async {
      final category =
          await (db.select(db.categories)..where(
                (c) =>
                    c.id.equals(categoryId) &
                    c.businessId.equals(kCurrentBusinessId) &
                    c.txnType.equals('expense') &
                    c.isActive.equals(true),
              ))
              .getSingleOrNull();

      if (category == null) {
        throw Exception(
          'The selected expense category is no longer available.',
        );
      }

      final activePaymentAccounts =
          await (db.select(db.accounts)..where(
                (a) =>
                    a.businessId.equals(kCurrentBusinessId) &
                    a.isPaymentAccount.equals(true) &
                    a.isActive.equals(true),
              ))
              .get();

      final activePaymentAccountIds = activePaymentAccounts
          .map((account) => account.id)
          .toSet();

      for (final payment in payments) {
        if (!activePaymentAccountIds.contains(payment.paymentAccountId)) {
          throw Exception(
            'One or more selected payment accounts are no longer '
            'available.',
          );
        }
      }

      // Create journal entry.
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: journalEntryId,
              businessId: kCurrentBusinessId,
              entryDate: date,
              description: Value(description),
              sourceType: 'expense',
              sourceId: Value(expenseId),
              status: const Value('completed'),
            ),
          );

      // Debit expense account.
      final debitLineId = const Uuid().v4();

      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: debitLineId,
              journalEntryId: journalEntryId,
              accountId: category.ledgerAccountId,
              debit: Value(amount),
              credit: const Value(0),
            ),
          );

      final creditLineIds = <String>[];

      // Credit each payment account.
      for (final payment in payments) {
        final lineId = const Uuid().v4();
        creditLineIds.add(lineId);

        await db
            .into(db.ledgerLines)
            .insert(
              LedgerLinesCompanion.insert(
                id: lineId,
                journalEntryId: journalEntryId,
                accountId: payment.paymentAccountId,
                debit: const Value(0),
                credit: Value(payment.amount),
              ),
            );
      }

      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: expenseId,
              businessId: kCurrentBusinessId,
              expenseDate: date,
              categoryId: categoryId,
              amount: amount,
              paymentAccountId: Value(
                payments.length == 1 ? payments.first.paymentAccountId : null,
              ),
              description: Value(description),
              notes: Value(notes),
              reference: Value(reference),
              status: const Value('completed'),
              journalEntryId: Value(journalEntryId),
            ),
          );

      // Sync journal first.
      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'journal_entries',
        entityId: journalEntryId,
        operation: SyncOp.create,
      );

      // Sync all ledger lines.
      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'ledger_lines',
        entityId: debitLineId,
        operation: SyncOp.create,
      );

      for (final lineId in creditLineIds) {
        await SyncTracker.record(
          db,
          businessId: kCurrentBusinessId,
          entityType: 'ledger_lines',
          entityId: lineId,
          operation: SyncOp.create,
        );
      }

      // Sync expense after its journal dependency.
      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'expenses',
        entityId: expenseId,
        operation: SyncOp.create,
      );
      await AuditLogger.record(
        db,
        businessId: kCurrentBusinessId,
        userId: auth.userId,
        action: 'finance.expense_created',
        module: AuditModule.finance,
        actionType: AuditActionType.create,
        entityType: 'expense',
        entityId: expenseId,
        entityLabel: description ?? 'Expense',
        after: {
          'amount': amount,
          'categoryId': categoryId,
          'status': 'completed',
          'expenseDate': date,
        },
        details: {
          'payments': [
            for (final p in payments)
              {'accountId': p.paymentAccountId, 'amount': p.amount},
          ],
        },
      );
    });

    return expenseId;
  }

  // ----------------------------------------------------------
  // INCOME
  // ----------------------------------------------------------

  Future<void> saveIncome({
    String? existingId,
    required DateTime date,
    required String categoryId,
    required int amount,
    String? paymentAccountId,
    String? customerId,
    String? description,
    String? notes,
    String? reference,
    required bool markAsPending,
  }) async {
    final id = existingId ?? const Uuid().v4();
    final status = markAsPending ? 'pending' : 'completed';

    await db.transaction(() async {
      String? previousJournalEntryId;
      IncomeTransaction? previous;
      if (existingId != null) {
        final existing = await (db.select(
          db.incomeTransactions,
        )..where((i) => i.id.equals(existingId))).getSingleOrNull();
        previous = existing;
        previousJournalEntryId = existing?.journalEntryId;
      }

      // -----------------------------------------------------------------------
      // EDIT: remove old journal posting.
      // -----------------------------------------------------------------------
      if (previousJournalEntryId != null) {
        final oldLines =
            await (db.select(db.ledgerLines)..where(
                  (line) => line.journalEntryId.equals(previousJournalEntryId!),
                ))
                .get();

        await (db.delete(db.ledgerLines)..where(
              (line) => line.journalEntryId.equals(previousJournalEntryId!),
            ))
            .go();

        await (db.update(
          db.incomeTransactions,
        )..where((i) => i.id.equals(id))).write(
          const IncomeTransactionsCompanion(journalEntryId: Value(null)),
        );

        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(previousJournalEntryId!))).go();

        for (final line in oldLines) {
          await _queueSync(
            businessId: kCurrentBusinessId,
            entityType: 'ledger_lines',
            entityId: line.id,
            operation: 'delete',
          );
        }

        await _queueSync(
          businessId: kCurrentBusinessId,
          entityType: 'journal_entries',
          entityId: previousJournalEntryId,
          operation: 'delete',
        );
      }

      // -----------------------------------------------------------------------
      // CREATE NEW JOURNAL POSTING.
      // -----------------------------------------------------------------------
      String? journalEntryId;

      if (status == 'completed' && paymentAccountId != null) {
        journalEntryId = await ledgerService.postEntry(
          businessId: kCurrentBusinessId,
          categoryId: categoryId,
          amount: amount,
          paymentAccountId: paymentAccountId,
          sourceType: 'income',
          date: date,
          sourceId: id,
          description: description,
        );
      }

      // -----------------------------------------------------------------------
      // SAVE INCOME.
      // -----------------------------------------------------------------------
      final companion = IncomeTransactionsCompanion(
        id: Value(id),
        businessId: Value(kCurrentBusinessId),
        txnDate: Value(date),
        categoryId: Value(categoryId),
        amount: Value(amount),
        paymentAccountId: Value(paymentAccountId),
        customerId: Value(customerId),
        description: Value(description),
        notes: Value(notes),
        reference: Value(reference),
        status: Value(status),
        journalEntryId: Value(journalEntryId),
        updatedAt: Value(DateTime.now()),
      );

      if (existingId == null) {
        await db.into(db.incomeTransactions).insert(companion);
      } else {
        await db.update(db.incomeTransactions).replace(companion);
      }

      // -----------------------------------------------------------------------
      // QUEUE NEW JOURNAL + LEDGER LINES.
      // -----------------------------------------------------------------------
      if (journalEntryId != null) {
        await _queueSync(
          businessId: kCurrentBusinessId,
          entityType: 'journal_entries',
          entityId: journalEntryId,
          operation: existingId == null ? 'insert' : 'update',
        );

        final lines = await (db.select(
          db.ledgerLines,
        )..where((line) => line.journalEntryId.equals(journalEntryId!))).get();

        for (final line in lines) {
          await _queueSync(
            businessId: kCurrentBusinessId,
            entityType: 'ledger_lines',
            entityId: line.id,
            operation: 'insert',
          );
        }
      }

      // -----------------------------------------------------------------------
      // QUEUE INCOME TRANSACTION.
      // -----------------------------------------------------------------------
      await _queueSync(
        businessId: kCurrentBusinessId,
        entityType: 'income_transactions',
        entityId: id,
        operation: existingId == null ? 'insert' : 'update',
      );

      await AuditLogger.record(
        db,
        businessId: kCurrentBusinessId,
        userId: auth.userId,
        action: existingId == null
            ? 'finance.income_created'
            : 'finance.income_updated',
        module: AuditModule.finance,
        actionType: existingId == null
            ? AuditActionType.create
            : AuditActionType.update,
        entityType: 'income_transaction',
        entityId: id,
        entityLabel: description ?? 'Income',
        before: previous == null ? null : _incomeSnapshot(previous),
        after: {
          'amount': amount,
          'categoryId': categoryId,
          'status': status,
          'paymentAccountId': paymentAccountId,
          'customerId': customerId,
          'description': description,
          'reference': reference,
          'txnDate': date,
        },
      );
    });
  }

  // ----------------------------------------------------------
  // DELETE EXPENSE
  // ----------------------------------------------------------

  Future<void> deleteExpense(String id) async {
    await db.transaction(() async {
      final expense = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(id))).getSingle();

      auth.require(BosPermission.financeVoid, businessId: expense.businessId);

      String? journalEntryId = expense.journalEntryId;
      List<String> ledgerLineIds = [];

      if (journalEntryId != null) {
        ledgerLineIds = await _ledgerLineIds(journalEntryId);

        await (db.delete(
          db.ledgerLines,
        )..where((line) => line.journalEntryId.equals(journalEntryId))).go();

        await (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
          const ExpensesCompanion(journalEntryId: Value(null)),
        );

        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(journalEntryId))).go();
      }

      await (db.update(db.shoppingCarts)
            ..where((cart) => cart.expenseId.equals(id)))
          .write(const ShoppingCartsCompanion(expenseId: Value(null)));

      await (db.delete(db.expenses)..where((e) => e.id.equals(id))).go();

      // The remote expense must be deleted first so its journal FK no
      // longer references the old journal entry.
      await SyncTracker.record(
        db,
        businessId: expense.businessId,
        entityType: 'expenses',
        entityId: id,
        operation: SyncOp.delete,
      );

      if (journalEntryId != null) {
        await _trackJournalDeleted(journalEntryId, ledgerLineIds);
      }

      await AuditLogger.record(
        db,
        businessId: expense.businessId,
        userId: auth.userId,
        action: 'finance.expense_deleted',
        module: AuditModule.finance,
        actionType: AuditActionType.delete,
        entityType: 'expense',
        entityId: id,
        entityLabel: expense.description ?? 'Expense',
        before: _expenseSnapshot(expense),
        details: {'amount': expense.amount, 'category': expense.categoryId},
      );
    });
  }

  // ----------------------------------------------------------
  // DELETE INCOME
  // ----------------------------------------------------------

  Future<void> deleteIncome(String id) async {
    await db.transaction(() async {
      final income = await (db.select(
        db.incomeTransactions,
      )..where((i) => i.id.equals(id))).getSingle();

      auth.require(BosPermission.financeVoid, businessId: income.businessId);

      String? journalEntryId = income.journalEntryId;
      List<String> ledgerLineIds = [];

      if (journalEntryId != null) {
        ledgerLineIds = await _ledgerLineIds(journalEntryId);

        await (db.delete(
          db.ledgerLines,
        )..where((line) => line.journalEntryId.equals(journalEntryId))).go();

        await (db.update(
          db.incomeTransactions,
        )..where((i) => i.id.equals(id))).write(
          const IncomeTransactionsCompanion(journalEntryId: Value(null)),
        );

        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(journalEntryId))).go();
      }

      await (db.delete(
        db.incomeTransactions,
      )..where((i) => i.id.equals(id))).go();

      await SyncTracker.record(
        db,
        businessId: income.businessId,
        entityType: 'income_transactions',
        entityId: id,
        operation: SyncOp.delete,
      );

      if (journalEntryId != null) {
        await _trackJournalDeleted(journalEntryId, ledgerLineIds);
      }

      await AuditLogger.record(
        db,
        businessId: income.businessId,
        userId: auth.userId,
        action: 'finance.income_deleted',
        module: AuditModule.finance,
        actionType: AuditActionType.delete,
        entityType: 'income_transaction',
        entityId: id,
        entityLabel: income.description ?? 'Income',
        before: _incomeSnapshot(income),
        details: {'amount': income.amount, 'category': income.categoryId},
      );
    });
  }

  // ----------------------------------------------------------
  // PAYMENT ACCOUNT
  // ----------------------------------------------------------

  Future<Account> addPaymentAccount(String name) async {
    auth.require(BosPermission.financeEdit, businessId: kCurrentBusinessId);

    final accountId = const Uuid().v4();

    final account = AccountsCompanion.insert(
      id: accountId,
      businessId: kCurrentBusinessId,
      name: name,
      type: 'asset',
      isPaymentAccount: const Value(true),
    );

    await db.transaction(() async {
      await db.into(db.accounts).insert(account);

      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'accounts',
        entityId: accountId,
        operation: SyncOp.create,
      );

      await AuditLogger.record(
        db,
        businessId: kCurrentBusinessId,
        userId: auth.userId,
        action: 'finance.account_created',
        module: AuditModule.finance,
        actionType: AuditActionType.create,
        entityType: 'account',
        entityId: accountId,
        entityLabel: name,
        after: {'name': name, 'type': 'asset'},
      );
    });

    return (db.select(
      db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingle();
  }

  // ----------------------------------------------------------
  // CATEGORY
  // ----------------------------------------------------------

  Future<Category> addCategory(String name, {required bool isIncome}) async {
    final fallbackAccountName = isIncome ? 'Other Income' : 'Other Expense';

    final fallbackAccount =
        await (db.select(db.accounts)..where(
              (account) =>
                  account.businessId.equals(kCurrentBusinessId) &
                  account.name.equals(fallbackAccountName) &
                  account.type.equals(isIncome ? 'income' : 'expense') &
                  account.isActive.equals(true),
            ))
            .getSingleOrNull();

    if (fallbackAccount == null) {
      throw StateError(
        'The default ledger account "$fallbackAccountName" '
        'does not exist for this business. '
        'Please restart the app so default accounts can be initialized.',
      );
    }

    final category = CategoriesCompanion.insert(
      id: const Uuid().v4(),
      businessId: kCurrentBusinessId,
      name: name.trim(),
      txnType: isIncome ? 'income' : 'expense',
      ledgerAccountId: fallbackAccount.id,
      isCustom: const Value(true),
    );

    await db.transaction(() async {
      await db.into(db.categories).insert(category);
      await AuditLogger.record(
        db,
        businessId: kCurrentBusinessId,
        userId: auth.userId,
        action: 'finance.category_created',
        module: AuditModule.finance,
        actionType: AuditActionType.create,
        entityType: 'category',
        entityId: category.id.value,
        entityLabel: name.trim(),
        after: {
          'name': name.trim(),
          'txnType': isIncome ? 'income' : 'expense',
        },
      );
    });

    return (db.select(db.categories)
          ..where((categoryRow) => categoryRow.id.equals(category.id.value)))
        .getSingle();
  }
}

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(
    ref.watch(databaseProvider),
    ref.watch(ledgerServiceProvider),
    ref.watch(authorizationServiceProvider),
  );
});

// ============================================================
// TRANSACTION PAGE
// ============================================================

class TransactionPage extends ConsumerStatefulWidget {
  final Expense? existingExpense;
  final IncomeTransaction? existingIncome;

  /// Which type a NEW transaction starts as. Ignored when editing.
  final bool initialIsIncome;

  const TransactionPage({
    super.key,
    this.existingExpense,
    this.existingIncome,
    this.initialIsIncome = false,
  });

  bool get isEditMode => existingExpense != null || existingIncome != null;

  @override
  ConsumerState<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends ConsumerState<TransactionPage> {
  static const _visibleCategoryCount = 6;
  static const _quickAmounts = [100, 500, 1000, 5000];

  late bool _isIncome;
  late DateTime _date;

  String? _paymentAccountId;
  String? _categoryId;

  bool _markAsPending = false;
  bool _showAdvanced = false;
  bool _isSaving = false;

  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _referenceController = TextEditingController();

  String? _receiptPhotoPath;

  @override
  void initState() {
    super.initState();

    if (widget.existingExpense != null) {
      final e = widget.existingExpense!;

      _isIncome = false;
      _date = e.expenseDate;
      _paymentAccountId = e.paymentAccountId;
      _categoryId = e.categoryId;
      _markAsPending = e.status == 'pending';

      _descriptionController.text = e.description ?? '';
      _amountController.text = (e.amount / 100).toStringAsFixed(2);
      _notesController.text = e.notes ?? '';
      _referenceController.text = e.reference ?? '';
      _receiptPhotoPath = e.receiptPhotoPath;
      _showAdvanced =
          (e.notes ?? '').isNotEmpty ||
          (e.reference ?? '').isNotEmpty ||
          e.receiptPhotoPath != null;
    } else if (widget.existingIncome != null) {
      final i = widget.existingIncome!;

      _isIncome = true;
      _date = i.txnDate;
      _paymentAccountId = i.paymentAccountId;
      _categoryId = i.categoryId;
      _markAsPending = i.status == 'pending';

      _descriptionController.text = i.description ?? '';
      _amountController.text = (i.amount / 100).toStringAsFixed(2);
      _notesController.text = i.notes ?? '';
      _referenceController.text = i.reference ?? '';
      _showAdvanced =
          (i.notes ?? '').isNotEmpty || (i.reference ?? '').isNotEmpty;
    } else {
      _isIncome = widget.initialIsIncome;
      _date = DateTime.now();
    }

    // Keeps the summary in the save bar live.
    _amountController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Color get _accentColor => _isIncome ? _incomeColor : _expenseColor;

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final categoriesAsync = ref.watch(
      categoriesByTypeProvider(_isIncome ? 'income' : 'expense'),
    );
    final accountsAsync = ref.watch(paymentAccountsProvider);

    final categoryName = _categoryId == null
        ? null
        : categoriesAsync.value
              ?.where((c) => c.id == _categoryId)
              .firstOrNull
              ?.name;
    final accountName = _paymentAccountId == null
        ? null
        : accountsAsync.value
              ?.where((a) => a.id == _paymentAccountId)
              .firstOrNull
              ?.name;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 20,
        title: Text(
          widget.isEditMode ? 'Edit transaction' : 'New transaction',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          if (widget.isEditMode &&
              ref.watch(canProvider(BosPermission.financeVoid)))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Delete',
                onPressed: _isSaving ? null : _confirmDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildSaveBar(categoryName, accountName),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _buildTypeSelector(),
                const SizedBox(height: 16),
                _buildAmountSection(),
                const SizedBox(height: 16),
                _buildDetailsCard(),
                const SizedBox(height: 22),
                _buildPickerCard(categoriesAsync, accountsAsync),
                const SizedBox(height: 22),
                _buildPendingCard(),
                const SizedBox(height: 12),
                _buildAdvancedSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // SAVE BAR (sticks above the keyboard)
  // ==========================================================

  Widget _buildSaveBar(String? categoryName, String? accountName) {
    final theme = Theme.of(context);
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;

    final parts = <String>[
      if (categoryName != null) categoryName,
      if (accountName != null) accountName,
      if (_markAsPending) 'Pending',
    ];

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_isIncome ? '+' : '-'}₱${_money(amount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: _accentColor,
                          ),
                        ),
                        Text(
                          parts.isEmpty
                              ? (_isIncome ? 'Income' : 'Expense')
                              : parts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _isSaving
                            ? const SizedBox(
                                key: ValueKey('loading'),
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.isEditMode ? 'Update' : 'Save',
                                key: const ValueKey('text'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // TYPE SELECTOR
  // ==========================================================

  Widget _buildTypeSelector() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _typeButton(
              label: 'Expense',
              icon: Icons.north_east_rounded,
              selected: !_isIncome,
              color: _expenseColor,
              enabled: !widget.isEditMode,
              onTap: () => setState(() {
                _isIncome = false;
                _categoryId = null;
              }),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _typeButton(
              label: 'Income',
              icon: Icons.south_west_rounded,
              selected: _isIncome,
              color: _incomeColor,
              enabled: !widget.isEditMode,
              onTap: () => setState(() {
                _isIncome = true;
                _categoryId = null;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final fg = selected
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled && !selected ? onTap : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // AMOUNT
  // ==========================================================

  Widget _buildAmountSection() {
    final theme = Theme.of(context);
    final hasAmount = _amountController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accentColor.withValues(alpha: .13),
            theme.colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _accentColor.withValues(alpha: .25)),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: .10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Amount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (hasAmount)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _amountController.clear(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Text(
                '₱',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _accentColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          Container(
            height: 3,
            width: 56,
            decoration: BoxDecoration(
              color: _accentColor,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pesos in _quickAmounts)
                ActionChip(
                  onPressed: () => _addAmount(pesos),
                  label: Text('+₱${_money(pesos.toDouble(), decimals: 0)}'),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _accentColor,
                  ),
                  backgroundColor: _accentColor.withValues(alpha: .08),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _addAmount(int pesos) {
    final current = double.tryParse(_amountController.text.trim()) ?? 0;
    final next = current + pesos;
    _amountController.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    _amountController.selection = TextSelection.collapsed(
      offset: _amountController.text.length,
    );
  }

  // ==========================================================
  // DATE + DESCRIPTION
  // ==========================================================

  Widget _buildDetailsCard() {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final yesterdayOnly = todayOnly.subtract(const Duration(days: 1));
    final dateOnly = DateTime(_date.year, _date.month, _date.day);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconContainer(Icons.calendar_today_rounded, _accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _formatDate(_date),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: _pickDate, child: const Text('Pick date')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Today'),
                selected: dateOnly == todayOnly,
                showCheckmark: false,
                onSelected: (_) => setState(() => _date = DateTime.now()),
              ),
              ChoiceChip(
                label: const Text('Yesterday'),
                selected: dateOnly == yesterdayOnly,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  final y = DateTime.now().subtract(const Duration(days: 1));
                  _date = y;
                }),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDivider(),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.notes_rounded, size: 21),
              hintText: _isIncome
                  ? 'What was this income for? (e.g. Walk-in sales)'
                  : 'What was this for? (e.g. Ice and packaging)',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ACCOUNTS (cards)
  // ==========================================================

  IconData _accountIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('cash')) return Icons.payments_outlined;
    if (n.contains('bank') ||
        n.contains('bpi') ||
        n.contains('bdo') ||
        n.contains('metro') ||
        n.contains('union')) {
      return Icons.account_balance_outlined;
    }
    return Icons.account_balance_wallet_outlined;
  }

  Widget _buildAccounts(AsyncValue<List<Account>> accountsAsync) {
    return accountsAsync.when(
      loading: _loadingBox,
      error: (_, _) => _errorBox('Could not load payment accounts.'),
      data: (accounts) {
        if (accounts.isEmpty) {
          return _emptySelection(
            text: 'No payment accounts yet',
            actionText: 'Add account',
            onPressed: _addNewAccount,
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final width = (constraints.maxWidth - gap) / 2;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final account in accounts)
                  SizedBox(width: width, child: _accountCard(account)),
                SizedBox(
                  width: width,
                  child: _addCard(label: 'Add account', onTap: _addNewAccount),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _accountCard(Account account) {
    final theme = Theme.of(context);
    final selected = _paymentAccountId == account.id;

    return Material(
      color: selected
          ? _accentColor.withValues(alpha: .09)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() {
          _paymentAccountId = selected ? null : account.id;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? _accentColor.withValues(alpha: .6)
                  : theme.colorScheme.outlineVariant.withValues(alpha: .7),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              _iconContainer(
                selected ? Icons.check_rounded : _accountIcon(account.name),
                selected ? _accentColor : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  account.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? _accentColor : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addCard({required String label, required VoidCallback onTap}) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(minHeight: 66),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // CATEGORIES (top chips + searchable "All")
  // ==========================================================

  Widget _buildCategories(AsyncValue<List<Category>> categoriesAsync) {
    return categoriesAsync.when(
      loading: _loadingBox,
      error: (_, _) => _errorBox('Could not load categories.'),
      data: (categories) {
        final matching = categories
            .where((c) => c.txnType == (_isIncome ? 'income' : 'expense'))
            .toList();

        if (_categoryId != null && !matching.any((c) => c.id == _categoryId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _categoryId != null) {
              setState(() => _categoryId = null);
            }
          });
        }

        if (matching.isEmpty) {
          return _emptySelection(
            text: _isIncome
                ? 'No income categories yet'
                : 'No expense categories yet',
            actionText: 'Add category',
            onPressed: _addNewCategory,
          );
        }

        final shown = matching.take(_visibleCategoryCount).toList();
        final selected = matching.where((c) => c.id == _categoryId).firstOrNull;
        if (selected != null && !shown.any((c) => c.id == selected.id)) {
          shown.insert(0, selected);
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in shown)
              _selectionChip(
                label: category.name,
                selected: _categoryId == category.id,
                icon: Icons.label_outline_rounded,
                onTap: () => setState(() {
                  _categoryId = _categoryId == category.id ? null : category.id;
                }),
              ),
            if (matching.length > _visibleCategoryCount)
              _addChip(
                label: 'All (${matching.length})',
                icon: Icons.search_rounded,
                onTap: () => _openCategorySearch(matching),
              ),
            _addChip(label: 'Add category', onTap: _addNewCategory),
          ],
        );
      },
    );
  }

  Future<void> _openCategorySearch(List<Category> all) async {
    final picked = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        var query = '';

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = all
                .where(
                  (c) => c.name.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setSheetState(() => query = v),
                        decoration: InputDecoration(
                          hintText: 'Search categories',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching category'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final c = filtered[i];
                                final isSelected = c.id == _categoryId;
                                return ListTile(
                                  leading: Icon(
                                    Icons.label_outline_rounded,
                                    color: isSelected ? _accentColor : null,
                                  ),
                                  title: Text(c.name),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_circle_rounded,
                                          color: _accentColor,
                                        )
                                      : null,
                                  onTap: () => Navigator.pop(sheetContext, c),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _categoryId = picked.id);
    }
  }

  // ==========================================================
  // PICKER CARD (dropdown menus)
  // ==========================================================

  static const _addSentinel = '__add__';
  static const _noneSentinel = '__none__';

  Widget _buildPickerCard(
    AsyncValue<List<Category>> categoriesAsync,
    AsyncValue<List<Account>> accountsAsync,
  ) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Category',
            subtitle: _isIncome
                ? 'What type of income is this?'
                : 'What type of expense is this?',
          ),
          const SizedBox(height: 10),
          _buildCategoryDropdown(categoriesAsync),
          const SizedBox(height: 18),
          _buildSectionTitle(
            'Payment account',
            subtitle: _markAsPending
                ? 'Optional while pending'
                : (_isIncome
                      ? 'Where the money went in'
                      : 'Where the money came from'),
          ),
          const SizedBox(height: 10),
          _buildAccountDropdown(accountsAsync),
        ],
      ),
    );
  }

  Widget _dropdownShell({
    required IconData icon,
    required bool filled,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: filled
            ? _accentColor.withValues(alpha: .07)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: filled
              ? _accentColor.withValues(alpha: .5)
              : theme.colorScheme.outlineVariant,
          width: filled ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          _iconContainer(
            icon,
            filled ? _accentColor : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonHideUnderline(child: child)),
        ],
      ),
    );
  }

  Widget _menuRow(
    IconData icon,
    String text, {
    Color? color,
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(AsyncValue<List<Category>> categoriesAsync) {
    final theme = Theme.of(context);

    return categoriesAsync.when(
      loading: _loadingBox,
      error: (_, _) => _errorBox('Could not load categories.'),
      data: (categories) {
        final matching = categories
            .where((c) => c.txnType == (_isIncome ? 'income' : 'expense'))
            .toList();

        if (_categoryId != null && !matching.any((c) => c.id == _categoryId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _categoryId != null) {
              setState(() => _categoryId = null);
            }
          });
        }

        if (matching.isEmpty) {
          return _emptySelection(
            text: _isIncome
                ? 'No income categories yet'
                : 'No expense categories yet',
            actionText: 'Add category',
            onPressed: _addNewCategory,
          );
        }

        final value = matching.any((c) => c.id == _categoryId)
            ? _categoryId
            : null;

        return _dropdownShell(
          icon: Icons.label_outline_rounded,
          filled: value != null,
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            menuMaxHeight: 360,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: theme.colorScheme.surface,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            hint: Text(
              'Select a category',
              style: TextStyle(
                fontSize: 14.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            items: [
              for (final c in matching)
                DropdownMenuItem<String>(
                  value: c.id,
                  child: _menuRow(
                    Icons.label_outline_rounded,
                    c.name,
                    color: c.id == value ? _accentColor : null,
                    bold: c.id == value,
                  ),
                ),
              DropdownMenuItem<String>(
                value: _addSentinel,
                child: _menuRow(
                  Icons.add_rounded,
                  'Add category',
                  color: theme.colorScheme.primary,
                  bold: true,
                ),
              ),
            ],
            onChanged: (v) {
              if (v == _addSentinel) {
                _addNewCategory();
                return;
              }
              setState(() => _categoryId = v);
            },
          ),
        );
      },
    );
  }

  Widget _buildAccountDropdown(AsyncValue<List<Account>> accountsAsync) {
    final theme = Theme.of(context);

    return accountsAsync.when(
      loading: _loadingBox,
      error: (_, _) => _errorBox('Could not load payment accounts.'),
      data: (accounts) {
        if (accounts.isEmpty) {
          return _emptySelection(
            text: 'No payment accounts yet',
            actionText: 'Add account',
            onPressed: _addNewAccount,
          );
        }

        final value = accounts.any((a) => a.id == _paymentAccountId)
            ? _paymentAccountId
            : null;

        return _dropdownShell(
          icon: Icons.account_balance_wallet_outlined,
          filled: value != null,
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            menuMaxHeight: 360,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: theme.colorScheme.surface,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            hint: Text(
              _markAsPending ? 'No account (optional)' : 'Select an account',
              style: TextStyle(
                fontSize: 14.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            items: [
              if (_markAsPending)
                DropdownMenuItem<String>(
                  value: _noneSentinel,
                  child: _menuRow(
                    Icons.block_rounded,
                    'No account yet',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final a in accounts)
                DropdownMenuItem<String>(
                  value: a.id,
                  child: _menuRow(
                    _accountIcon(a.name),
                    a.name,
                    color: a.id == value ? _accentColor : null,
                    bold: a.id == value,
                  ),
                ),
              DropdownMenuItem<String>(
                value: _addSentinel,
                child: _menuRow(
                  Icons.add_rounded,
                  'Add account',
                  color: theme.colorScheme.primary,
                  bold: true,
                ),
              ),
            ],
            onChanged: (v) {
              if (v == _addSentinel) {
                _addNewAccount();
                return;
              }
              setState(() => _paymentAccountId = v == _noneSentinel ? null : v);
            },
          ),
        );
      },
    );
  }

  // ==========================================================
  // PENDING
  // ==========================================================

  Widget _buildPendingCard() {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _markAsPending
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: .7)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _markAsPending
              ? theme.colorScheme.tertiary.withValues(alpha: .25)
              : theme.colorScheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          _iconContainer(
            Icons.schedule_rounded,
            _markAsPending
                ? theme.colorScheme.tertiary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pending transaction',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _markAsPending
                      ? 'This will not affect your balance yet.'
                      : 'Transaction will be recorded immediately.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _markAsPending,
            onChanged: (value) => setState(() => _markAsPending = value),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ADVANCED
  // ==========================================================

  Widget _buildAdvancedSection() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Additional details',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'Notes, reference${_isIncome ? '' : ', receipt'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _showAdvanced ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _showAdvanced
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _buildDivider(),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Notes',
                      hintText: 'Optional additional information',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _referenceController,
                    decoration: InputDecoration(
                      labelText: 'Reference number',
                      hintText: 'Optional',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (!_isIncome) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickReceipt,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _receiptPhotoPath == null
                                  ? Icons.receipt_long_outlined
                                  : Icons.check_circle_outline_rounded,
                              color: _receiptPhotoPath == null
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _receiptPhotoPath == null
                                    ? 'Attach receipt photo (optional)'
                                    : 'Receipt attached — tap to replace',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            if (_receiptPhotoPath != null)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () =>
                                    setState(() => _receiptPhotoPath = null),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPONENTS
  // ==========================================================

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _selectionChip({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _accentColor.withValues(alpha: .11)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? _accentColor.withValues(alpha: .55)
                  : theme.colorScheme.outlineVariant.withValues(alpha: .7),
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : icon,
                size: 17,
                color: selected
                    ? _accentColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? _accentColor : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addChip({
    required String label,
    required VoidCallback onTap,
    IconData icon = Icons.add_rounded,
  }) {
    final theme = Theme.of(context);

    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 17, color: theme.colorScheme.primary),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      backgroundColor: theme.colorScheme.surface,
    );
  }

  Widget _iconContainer(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: .45),
    );
  }

  Widget _loadingBox() {
    return Container(
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySelection({
    required String text,
    required String actionText,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(actionText)),
        ],
      ),
    );
  }

  // ==========================================================
  // FORMATTING + DATE
  // ==========================================================

  String _money(double value, {int decimals = 2}) {
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  String _formatDate(DateTime date) {
    final today = DateTime.now();

    final sameDay =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (sameDay) return 'Today';

    final yesterday = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));

    final isYesterday =
        date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;

    if (isYesterday) return 'Yesterday';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final file = await picker.pickImage(source: source, imageQuality: 70);

    if (file != null && mounted) {
      setState(() => _receiptPhotoPath = file.path);
    }
  }

  // ==========================================================
  // ADD ACCOUNT / CATEGORY
  // ==========================================================

  Future<void> _addNewAccount() async {
    final name = await _promptForName(
      title: 'Add payment account',
      hint: 'e.g. GCash, GoTyme, BPI',
    );

    if (name == null || name.trim().isEmpty) return;

    final account = await ref
        .read(transactionServiceProvider)
        .addPaymentAccount(name.trim());

    ref.invalidate(paymentAccountsProvider);

    if (mounted) setState(() => _paymentAccountId = account.id);
  }

  Future<void> _addNewCategory() async {
    final name = await _promptForName(
      title: 'Add category',
      hint: _isIncome ? 'e.g. Rental Income' : 'e.g. Delivery Fuel',
    );

    if (name == null || name.trim().isEmpty) return;

    final category = await ref
        .read(transactionServiceProvider)
        .addCategory(name.trim(), isIncome: _isIncome);

    ref.invalidate(categoriesByTypeProvider(_isIncome ? 'income' : 'expense'));

    if (mounted) setState(() => _categoryId = category.id);
  }

  Future<String?> _promptForName({
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (value) => Navigator.pop(ctx, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // SAVE (logic unchanged)
  // ==========================================================

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_categoryId == null) {
      _showError('Choose a category first.');
      return;
    }

    final amountValue = double.tryParse(_amountController.text.trim());

    if (amountValue == null || amountValue <= 0) {
      _showError('Enter a valid amount.');
      return;
    }

    if (!_markAsPending && _paymentAccountId == null) {
      _showError(
        'Choose a payment account, or '
        'mark the transaction as pending.',
      );
      return;
    }

    setState(() => _isSaving = true);

    final amountCents = (amountValue * 100).round();

    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    final reference = _referenceController.text.trim().isEmpty
        ? null
        : _referenceController.text.trim();

    final service = ref.read(transactionServiceProvider);

    try {
      if (_isIncome) {
        await service.saveIncome(
          existingId: widget.existingIncome?.id,
          date: _date,
          categoryId: _categoryId!,
          amount: amountCents,
          paymentAccountId: _paymentAccountId,
          description: description,
          notes: notes,
          reference: reference,
          markAsPending: _markAsPending,
        );
      } else {
        await service.saveExpense(
          existingId: widget.existingExpense?.id,
          date: _date,
          categoryId: _categoryId!,
          amount: amountCents,
          paymentAccountId: _paymentAccountId,
          description: description,
          notes: notes,
          reference: reference,
          receiptPhotoPath: _receiptPhotoPath,
          markAsPending: _markAsPending,
        );
      }

      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Could not save transaction: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==========================================================
  // DELETE (logic unchanged)
  // ==========================================================

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          icon: Icon(
            Icons.delete_outline_rounded,
            size: 32,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Delete transaction?'),
          content: const Text(
            'This will remove the transaction '
            'and reverse its ledger entry.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    final service = ref.read(transactionServiceProvider);

    try {
      if (widget.existingExpense != null) {
        await service.deleteExpense(widget.existingExpense!.id);
      } else if (widget.existingIncome != null) {
        await service.deleteIncome(widget.existingIncome!.id);
      }

      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Could not delete transaction: $e');

      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(message),
        ),
      );
  }
}
