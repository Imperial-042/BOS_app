// lib/core/ledger/ledger_service.dart

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Thrown when a journal posting fails validation.
class LedgerException implements Exception {
  final String message;

  const LedgerException(this.message);

  @override
  String toString() => message;
}

class LedgerService {
  final AppDatabase db;

  LedgerService(this.db);

  /// Standard derived GL accounts every business is seeded with.
  ///
  /// Resolves the row by deterministic id and verifies that it belongs to
  /// [businessId], so a posting can never silently hit a missing or
  /// other-business account.
  Future<Account> requireAccount(String accountId, String businessId) async {
    Future<Account?> find(String id) =>
        (db.select(db.accounts)
              ..where((a) => a.id.equals(id) & a.businessId.equals(businessId)))
            .getSingleOrNull();

    var account = await find(accountId);

    // Seeded defaults use cloud-compatible UUIDs; callers may still pass the
    // legacy `acc_*` key.
    if (account == null && accountId.startsWith('acc_')) {
      account = await find(
        AppDatabase.cloudCompatibleDefaultId('accounts', accountId),
      );
    }

    if (account == null) {
      throw LedgerException(
        'Account "$accountId" does not exist in this business.',
      );
    }

    return account;
  }

  Future<Account> requirePaymentAccount(
    String accountId,
    String businessId,
  ) async {
    final account = await requireAccount(accountId, businessId);

    if (!account.isPaymentAccount) {
      throw LedgerException(
        '"${account.name}" is not a cash, bank or e-wallet account.',
      );
    }

    if (!account.isActive) {
      throw LedgerException('"${account.name}" is no longer active.');
    }

    return account;
  }

  Future<Account> receivableAccount(String businessId) =>
      requireAccount('acc_ar_$businessId', businessId);

  Future<Account> payableAccount(String businessId) =>
      requireAccount('acc_ap_$businessId', businessId);

  /// Post a balanced two-line journal entry.
  ///
  /// The journal header and BOTH ledger lines are created and tracked in
  /// the same Drift transaction.
  ///
  /// Returns the new journal entry id.
  Future<String> postSimpleEntry({
    required String businessId,
    required DateTime date,
    required int amount,
    required String debitAccountId,
    required String creditAccountId,
    required String sourceType,
    String? sourceId,
    String? description,
    String? branchId,
  }) async {
    if (amount <= 0) {
      throw const LedgerException('Amount must be greater than zero.');
    }

    if (debitAccountId == creditAccountId) {
      throw const LedgerException(
        'Debit and credit accounts must be different.',
      );
    }

    final entryId = const Uuid().v4();
    final debitLineId = const Uuid().v4();
    final creditLineId = const Uuid().v4();

    await db.transaction(() async {
      // ----------------------------------------------------------
      // Validate both accounts before writing anything.
      // ----------------------------------------------------------

      final debitAccount = await requireAccount(debitAccountId, businessId);

      final creditAccount = await requireAccount(creditAccountId, businessId);

      // ----------------------------------------------------------
      // Journal header.
      // ----------------------------------------------------------

      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: entryId,
              businessId: businessId,
              entryDate: date,
              sourceType: sourceType,
              sourceId: Value(sourceId),
              description: Value(description),
              branchId: Value(branchId),
            ),
          );

      // ----------------------------------------------------------
      // Debit line.
      // ----------------------------------------------------------

      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: debitLineId,
              journalEntryId: entryId,
              accountId: debitAccount.id,
              debit: Value(amount),
              credit: const Value(0),
            ),
          );

      // ----------------------------------------------------------
      // Credit line.
      // ----------------------------------------------------------

      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: creditLineId,
              journalEntryId: entryId,
              accountId: creditAccount.id,
              debit: const Value(0),
              credit: Value(amount),
            ),
          );

      // ----------------------------------------------------------
      // OUTBOX
      //
      // Track the complete journal structure, not just the header.
      // ----------------------------------------------------------

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'journal_entries',
        entityId: entryId,
        operation: SyncOp.create,
      );

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'ledger_lines',
        entityId: debitLineId,
        operation: SyncOp.create,
      );

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'ledger_lines',
        entityId: creditLineId,
        operation: SyncOp.create,
      );
    });

    return entryId;
  }

  /// Posts an expense/income entry using the selected category and payment
  /// account.
  ///
  /// Expense:
  ///   Dr category ledger account
  ///   Cr payment account
  ///
  /// Income:
  ///   Dr payment account
  ///   Cr category ledger account
  Future<String> postEntry({
    required String businessId,
    required String categoryId,
    required int amount,
    required String paymentAccountId,
    required String sourceType,
    DateTime? date,
    String? sourceId,
    String? description,
    String? branchId,
  }) async {
    final category =
        await (db.select(db.categories)..where(
              (c) => c.id.equals(categoryId) & c.businessId.equals(businessId),
            ))
            .getSingleOrNull();

    if (category == null) {
      throw const LedgerException(
        'The selected category does not exist in this business.',
      );
    }

    final isExpense = category.txnType == 'expense';

    final debitAccountId = isExpense
        ? category.ledgerAccountId
        : paymentAccountId;

    final creditAccountId = isExpense
        ? paymentAccountId
        : category.ledgerAccountId;

    return postSimpleEntry(
      businessId: businessId,
      date: date ?? DateTime.now(),
      amount: amount,
      debitAccountId: debitAccountId,
      creditAccountId: creditAccountId,
      sourceType: sourceType,
      sourceId: sourceId,
      description: description,
      branchId: branchId,
    );
  }
}
