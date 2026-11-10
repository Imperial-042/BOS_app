// lib/features/transactions/domain/transaction_service.dart
//
// Posts, edits and deletes expenses and income (ledger entries, sync queue,
// audit trail). No UI.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart'
      show AuditLogger;
import 'package:bos_application/core/business/current_business.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/ledger/ledger_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';

final ledgerServiceProvider = Provider<LedgerService>((ref) {
    return LedgerService(ref.watch(databaseProvider));
  });

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

    String _requireCurrentBusiness() {
      final businessId = auth.currentBusinessId;
      if (businessId == null || businessId != kCurrentBusinessId) {
        throw const PermissionDeniedException(
          'Select an active business before changing transactions.',
        );
      }
      return businessId;
    }

    Future<Category> _requireActiveCategory(
      String categoryId,
      String businessId,
      String txnType,
    ) async {
      final category =
          await (db.select(db.categories)..where(
                (c) =>
                    c.id.equals(categoryId) &
                    c.businessId.equals(businessId) &
                    c.txnType.equals(txnType) &
                    c.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (category == null) {
        throw StateError(
          'The selected ${txnType == 'income' ? 'income' : 'expense'} '
          'category is no longer available.',
        );
      }
      return category;
    }

    Future<void> _validateOptionalPaymentAccount(
      String? accountId,
      String businessId,
    ) async {
      if (accountId == null) return;
      await ledgerService.requirePaymentAccount(accountId, businessId);
    }

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
      'receiptPhotoPath': e.receiptPhotoPath,
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
      final businessId = _requireCurrentBusiness();
      if (existingId == null) {
        auth.requireAny([
          BosPermission.financeCreate,
          BosPermission.purchasingCreate,
        ], businessId: businessId);
      } else {
        auth.requireAny([
          BosPermission.financeEdit,
          BosPermission.purchasingEdit,
        ], businessId: businessId);
      }
      if (amount <= 0) {
        throw ArgumentError.value(
          amount,
          'amount',
          'Amount must be greater than zero.',
        );
      }
      if (!markAsPending && paymentAccountId == null) {
        throw ArgumentError('A completed expense must have a payment account.');
      }
      await _requireActiveCategory(categoryId, businessId, 'expense');
      await _validateOptionalPaymentAccount(paymentAccountId, businessId);

      final id = existingId ?? const Uuid().v4();
      final status = markAsPending ? 'pending' : 'completed';

      await db.transaction(() async {
        String? previousJournalEntryId;
        Expense? previous;
        if (existingId != null) {
          final existing = await (db.select(
            db.expenses,
          )..where((e) => e.id.equals(existingId))).getSingleOrNull();
          if (existing == null || existing.businessId != businessId) {
            throw StateError('The expense could not be found in this business.');
          }
          previous = existing;
          previousJournalEntryId = existing.journalEntryId;
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
          receiptPhotoPath: Value(receiptPhotoPath),
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
      final businessId = _requireCurrentBusiness();
      auth.requireAny([
        BosPermission.financeCreate,
        BosPermission.purchasingCreate,
      ], businessId: businessId);

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
      final businessId = _requireCurrentBusiness();
      if (existingId == null) {
        auth.require(BosPermission.financeCreate, businessId: businessId);
      } else {
        auth.require(BosPermission.financeEdit, businessId: businessId);
      }
      if (amount <= 0) {
        throw ArgumentError.value(
          amount,
          'amount',
          'Amount must be greater than zero.',
        );
      }
      if (!markAsPending && paymentAccountId == null) {
        throw ArgumentError(
          'A completed income transaction must have a payment account.',
        );
      }
      await _requireActiveCategory(categoryId, businessId, 'income');
      await _validateOptionalPaymentAccount(paymentAccountId, businessId);

      final id = existingId ?? const Uuid().v4();
      final status = markAsPending ? 'pending' : 'completed';

      await db.transaction(() async {
        String? previousJournalEntryId;
        IncomeTransaction? previous;
        if (existingId != null) {
          final existing = await (db.select(
            db.incomeTransactions,
          )..where((i) => i.id.equals(existingId))).getSingleOrNull();
          if (existing == null || existing.businessId != businessId) {
            throw StateError('The income could not be found in this business.');
          }
          previous = existing;
          previousJournalEntryId = existing.journalEntryId;
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
        final businessId = _requireCurrentBusiness();
        final expense =
            await (db.select(db.expenses)..where(
                  (e) => e.id.equals(id) & e.businessId.equals(businessId),
                ))
                .getSingleOrNull();
        if (expense == null) {
          throw StateError('The expense could not be found in this business.');
        }

        auth.requireAny([
          BosPermission.financeVoid,
          BosPermission.purchasingEdit,
        ], businessId: businessId);

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

        final linkedCarts =
            await (db.select(db.shoppingCarts)..where(
                  (cart) =>
                      cart.expenseId.equals(id) &
                      cart.businessId.equals(businessId),
                ))
                .get();
        await (db.update(db.shoppingCarts)..where(
              (cart) =>
                  cart.expenseId.equals(id) & cart.businessId.equals(businessId),
            ))
            .write(const ShoppingCartsCompanion(expenseId: Value(null)));
        for (final cart in linkedCarts) {
          await SyncTracker.record(
            db,
            businessId: businessId,
            entityType: 'shopping_carts',
            entityId: cart.id,
            operation: SyncOp.update,
            ownerUserId: auth.userId,
          );
        }

        await (db.delete(db.expenses)..where((e) => e.id.equals(id))).go();

        // The remote expense must be deleted first so its journal FK no
        // longer references the old journal entry.
        await SyncTracker.record(
          db,
          businessId: businessId,
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
        final businessId = _requireCurrentBusiness();
        final income =
            await (db.select(db.incomeTransactions)..where(
                  (i) => i.id.equals(id) & i.businessId.equals(businessId),
                ))
                .getSingleOrNull();
        if (income == null) {
          throw StateError('The income could not be found in this business.');
        }

        auth.require(BosPermission.financeVoid, businessId: businessId);

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
          businessId: businessId,
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
      final businessId = _requireCurrentBusiness();
      auth.require(BosPermission.financeEdit, businessId: businessId);
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
        await SyncTracker.record(
          db,
          businessId: businessId,
          entityType: 'categories',
          entityId: category.id.value,
          operation: SyncOp.create,
          ownerUserId: auth.userId,
        );
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
