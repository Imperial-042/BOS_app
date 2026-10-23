// lib/features/transactions/domain/capital_asset_liability_service.dart

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/ledger/ledger_service.dart';
import '../../../core/sync/sync_tracker.dart';

class AccountBalanceEntry {
  final Account account;
  final int balance;

  const AccountBalanceEntry({required this.account, required this.balance});
}

class LedgerEntryRow {
  final DateTime date;
  final String? description;
  final String sourceType;
  final int debit;
  final int credit;

  const LedgerEntryRow({
    required this.date,
    required this.description,
    required this.sourceType,
    required this.debit,
    required this.credit,
  });
}

/// Enough detail to prefill an edit form for a capital/asset/liability entry.
class BalanceSheetEntryDetail {
  final String journalEntryId;
  final DateTime date;
  final String? description;
  final int amount;
  final String accountId;
  final String accountName;
  final String? subtype;

  /// The cash/bank/e-wallet account used for the transaction.
  ///
  /// Null means the asset was purchased on credit and the other
  /// side of the entry is Accounts Payable.
  final String? paymentAccountId;

  /// True when an asset was acquired on credit:
  ///
  /// Dr Asset
  /// Cr Accounts Payable
  final bool isOnCredit;

  const BalanceSheetEntryDetail({
    required this.journalEntryId,
    required this.date,
    required this.description,
    required this.amount,
    required this.accountId,
    required this.accountName,
    required this.subtype,
    required this.paymentAccountId,
    required this.isOnCredit,
  });
}

class CapitalAssetLiabilityService {
  final AppDatabase db;

  CapitalAssetLiabilityService(this.db);

  // ---------------------------------------------------------------------------
  // Legacy deterministic IDs
  // ---------------------------------------------------------------------------
  //
  // These are kept only for compatibility with older local data/code.
  // They are NOT assumed to be the actual current account IDs.
  //

  static String equityAccountId(String businessId) => 'acc_equity_$businessId';

  static String payableAccountId(String businessId) => 'acc_ap_$businessId';

  // ---------------------------------------------------------------------------
  // HELPER
  // ---------------------------------------------------------------------------
  Future<void> _audit({
    required String businessId,
    required String action,
    required AuditActionType type,
    required String journalEntryId,
    String? label,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    Map<String, Object?>? details,
  }) {
    return AuditWriter.write(
      db,
      businessId: businessId,
      userId: null,
      action: action,
      module: AuditModule.finance,
      actionType: type,
      entityType: 'journal_entries',
      entityId: journalEntryId,
      entityLabel: label,
      before: before,
      after: after,
      details: details,
    );
  }

  // ---------------------------------------------------------------------------
  // ACCOUNT RESOLUTION
  // ---------------------------------------------------------------------------

  /// Resolves an account safely for the current business.
  ///
  /// Current UUID/cloud-compatible IDs are preferred.
  ///
  /// The old deterministic equity/AP IDs are accepted only as legacy
  /// references and are translated to the actual account row by semantic
  /// account name/type.
  Future<Account> _resolveAccount({
    required String requestedId,
    required String businessId,
  }) async {
    // First: exact ID lookup.
    final exact =
        await (db.select(db.accounts)..where(
              (account) =>
                  account.id.equals(requestedId) &
                  account.businessId.equals(businessId),
            ))
            .getSingleOrNull();

    if (exact != null) {
      return exact;
    }

    // Legacy Owner's Equity ID -> resolve by semantic identity.
    if (requestedId == equityAccountId(businessId)) {
      final equity =
          await (db.select(db.accounts)..where(
                (account) =>
                    account.businessId.equals(businessId) &
                    account.name.equals("Owner's Equity") &
                    account.type.equals('equity') &
                    account.isActive.equals(true),
              ))
              .getSingleOrNull();

      if (equity != null) {
        return equity;
      }

      throw StateError(
        "Owner's Equity account does not exist for business "
        "'$businessId'.",
      );
    }

    // Legacy Accounts Payable ID -> resolve by semantic identity.
    if (requestedId == payableAccountId(businessId)) {
      final payable =
          await (db.select(db.accounts)..where(
                (account) =>
                    account.businessId.equals(businessId) &
                    account.name.equals('Accounts Payable') &
                    account.type.equals('liability') &
                    account.isActive.equals(true),
              ))
              .getSingleOrNull();

      if (payable != null) {
        return payable;
      }

      throw StateError(
        "Accounts Payable account does not exist for business "
        "'$businessId'.",
      );
    }

    throw StateError(
      'Account "$requestedId" does not exist in business "$businessId".',
    );
  }

  Future<Account> _requireEquityAccount(String businessId) {
    return _resolveAccount(
      requestedId: equityAccountId(businessId),
      businessId: businessId,
    );
  }

  Future<Account> _requirePayableAccount(String businessId) {
    return _resolveAccount(
      requestedId: payableAccountId(businessId),
      businessId: businessId,
    );
  }

  // ---------------------------------------------------------------------------
  // BALANCES
  // ---------------------------------------------------------------------------

  Future<int> _balanceOf(Account account) async {
    final row = await db
        .customSelect(
          '''
      SELECT
        COALESCE(SUM(ll.debit), 0) AS total_debit,
        COALESCE(SUM(ll.credit), 0) AS total_credit
      FROM ledger_lines ll
      INNER JOIN journal_entries je
        ON je.id = ll.journal_entry_id
      WHERE ll.account_id = ?
        AND je.business_id = ?
      ''',
          variables: [
            Variable.withString(account.id),
            Variable.withString(account.businessId),
          ],
        )
        .getSingle();

    final debit = row.read<int>('total_debit');
    final credit = row.read<int>('total_credit');

    if (account.type == 'liability' ||
        account.type == 'equity' ||
        account.type == 'income') {
      return account.startingBalance + credit - debit;
    }

    return account.startingBalance + debit - credit;
  }

  Future<List<AccountBalanceEntry>> _balancesFor(List<Account> accounts) async {
    final out = <AccountBalanceEntry>[];

    for (final account in accounts) {
      out.add(
        AccountBalanceEntry(
          account: account,
          balance: await _balanceOf(account),
        ),
      );
    }

    return out;
  }

  /// Every dated posting against [accountId].
  Future<List<LedgerEntryRow>> accountLedgerEntries(String accountId) async {
    final rows = await db
        .customSelect(
          '''
      SELECT
        je.entry_date AS entry_date,
        je.description AS description,
        je.source_type AS source_type,
        ll.debit AS debit,
        ll.credit AS credit
      FROM ledger_lines ll
      INNER JOIN journal_entries je
        ON je.id = ll.journal_entry_id
      WHERE ll.account_id = ?
      ORDER BY je.entry_date DESC, je.created_at DESC
      ''',
          variables: [Variable.withString(accountId)],
        )
        .get();

    return rows
        .map(
          (row) => LedgerEntryRow(
            date: row.read<DateTime>('entry_date'),
            description: row.readNullable<String>('description'),
            sourceType: row.read<String>('source_type'),
            debit: row.read<int>('debit'),
            credit: row.read<int>('credit'),
          ),
        )
        .toList();
  }

  Future<List<AccountBalanceEntry>> assetBalances(String businessId) async {
    final accountsList =
        await (db.select(db.accounts)..where(
              (account) =>
                  account.businessId.equals(businessId) &
                  account.type.equals('asset') &
                  account.isPaymentAccount.equals(false) &
                  account.isActive.equals(true),
            ))
            .get();

    return _balancesFor(accountsList);
  }

  Future<List<AccountBalanceEntry>> liabilityBalances(String businessId) async {
    final accountsList =
        await (db.select(db.accounts)..where(
              (account) =>
                  account.businessId.equals(businessId) &
                  account.type.equals('liability') &
                  account.isActive.equals(true),
            ))
            .get();

    return _balancesFor(accountsList);
  }

  Future<int> capitalBalance(String businessId) async {
    final account = await _requireEquityAccount(businessId);
    return _balanceOf(account);
  }

  // ---------------------------------------------------------------------------
  // ACCOUNT CREATION
  // ---------------------------------------------------------------------------

  Future<Account> addAssetAccount({
    required String businessId,
    required String name,
    required bool isCurrentAsset,
  }) async {
    final id = const Uuid().v4();
    final cleanName = name.trim();
    final subtype = isCurrentAsset ? 'current_asset' : 'non_current_asset';

    await db.transaction(() async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              businessId: businessId,
              name: cleanName,
              type: 'asset',
              subtype: Value(subtype),
            ),
          );

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'accounts',
        entityId: id,
        operation: SyncOp.create,
      );

      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: null,
        action: 'finance.account_created',
        module: AuditModule.finance,
        actionType: AuditActionType.create,
        entityType: 'account',
        entityId: id,
        entityLabel: cleanName,
        after: {'name': cleanName, 'type': 'asset', 'subtype': subtype},
      );
    });

    return (db.select(
      db.accounts,
    )..where((account) => account.id.equals(id))).getSingle();
  }

  /// [subtype] is one of:
  /// 'trade_payable' | 'loan_payable' | 'other_payable'.
  Future<Account> addLiabilityAccount({
    required String businessId,
    required String name,
    required String subtype,
  }) async {
    final id = const Uuid().v4();
    final cleanName = name.trim();

    await db.transaction(() async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              businessId: businessId,
              name: cleanName,
              type: 'liability',
              subtype: Value(subtype),
            ),
          );

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'accounts',
        entityId: id,
        operation: SyncOp.create,
      );

      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: null,
        action: 'finance.account_created',
        module: AuditModule.finance,
        actionType: AuditActionType.create,
        entityType: 'account',
        entityId: id,
        entityLabel: cleanName,
        after: {'name': cleanName, 'type': 'liability', 'subtype': subtype},
      );
    });

    return (db.select(
      db.accounts,
    )..where((account) => account.id.equals(id))).getSingle();
  }
  // ---------------------------------------------------------------------------
  // CAPITAL
  // ---------------------------------------------------------------------------

  /// Owner puts money into the business:
  ///
  /// Dr Cash/Bank/E-Wallet
  /// Cr Owner's Equity
  Future<String> recordCapital({
    required String businessId,
    required DateTime date,
    required int amount,
    required String paymentAccountId,
    String? description,
  }) {
    return _postEntry(
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: paymentAccountId,
      creditAccountId: equityAccountId(businessId),
      sourceType: 'capital',
      description: description,
    );
  }

  /// Owner takes money out of the business:
  ///
  /// Dr Owner's Equity
  /// Cr Cash/Bank/E-Wallet
  Future<String> recordCapitalWithdrawal({
    required String businessId,
    required DateTime date,
    required int amount,
    required String paymentAccountId,
    String? description,
  }) {
    return _postEntry(
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: equityAccountId(businessId),
      creditAccountId: paymentAccountId,
      sourceType: 'capital',
      description: description,
    );
  }

  Future<void> updateCapitalWithdrawal({
    required String journalEntryId,
    required String businessId,
    required DateTime date,
    required int amount,
    required String paymentAccountId,
    String? description,
  }) {
    return _updateEntry(
      journalEntryId: journalEntryId,
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: equityAccountId(businessId),
      creditAccountId: paymentAccountId,
      description: description,
    );
  }

  // ---------------------------------------------------------------------------
  // ASSETS
  // ---------------------------------------------------------------------------

  /// Business acquires an asset:
  ///
  /// Dr Asset
  /// Cr Payment Account
  ///
  /// or, when bought on credit:
  ///
  /// Dr Asset
  /// Cr Accounts Payable
  Future<String> recordAsset({
    required String businessId,
    required DateTime date,
    required int amount,
    required String assetAccountId,
    String? paymentAccountId,
    String? description,
  }) {
    return _postEntry(
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: assetAccountId,
      creditAccountId: paymentAccountId ?? payableAccountId(businessId),
      sourceType: 'asset',
      description: description,
    );
  }

  // ---------------------------------------------------------------------------
  // LIABILITIES
  // ---------------------------------------------------------------------------

  Future<String> recordLiability({
    required String businessId,
    required DateTime date,
    required int amount,
    required String liabilityAccountId,
    required String paymentAccountId,
    String? description,
  }) {
    return _postEntry(
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: paymentAccountId,
      creditAccountId: liabilityAccountId,
      sourceType: 'liability',
      description: description,
    );
  }

  Future<String> payLiability({
    required String businessId,
    required DateTime date,
    required int amount,
    required String liabilityAccountId,
    required String paymentAccountId,
    String? description,
  }) {
    return _postEntry(
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: liabilityAccountId,
      creditAccountId: paymentAccountId,
      sourceType: 'liability_payment',
      description: description,
    );
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------

  Future<void> deleteEntry(String journalEntryId) async {
    await db.transaction(() async {
      final entry =
          await (db.select(db.journalEntries)
                ..where((journal) => journal.id.equals(journalEntryId)))
              .getSingleOrNull();

      if (entry == null) {
        return;
      }

      final lines = await (db.select(
        db.ledgerLines,
      )..where((line) => line.journalEntryId.equals(journalEntryId))).get();

      await (db.delete(
        db.journalEntries,
      )..where((journal) => journal.id.equals(journalEntryId))).go();

      await SyncTracker.record(
        db,
        businessId: entry.businessId,
        entityType: 'journal_entries',
        entityId: journalEntryId,
        operation: SyncOp.delete,
      );

      for (final line in lines) {
        await SyncTracker.record(
          db,
          businessId: entry.businessId,
          entityType: 'ledger_lines',
          entityId: line.id,
          operation: SyncOp.delete,
        );
      }
      await _audit(
        businessId: entry.businessId,
        action: 'finance.${entry.sourceType}_deleted',
        type: AuditActionType.delete,
        journalEntryId: journalEntryId,
        label: entry.description ?? entry.sourceType,
        before: {
          'date': entry.entryDate,
          'description': entry.description,
          'sourceType': entry.sourceType,
          'lines': [
            for (final l in lines)
              {'accountId': l.accountId, 'debit': l.debit, 'credit': l.credit},
          ],
        },
      );
    });
  }

  // ---------------------------------------------------------------------------
  // DETAILS
  // ---------------------------------------------------------------------------

  Future<BalanceSheetEntryDetail> getCapitalDetail(String journalEntryId) {
    return _getDetail(journalEntryId, specialLineIsCredit: true);
  }

  Future<BalanceSheetEntryDetail> getAssetDetail(String journalEntryId) {
    return _getDetail(journalEntryId, specialLineIsCredit: false);
  }

  Future<BalanceSheetEntryDetail> getLiabilityDetail(String journalEntryId) {
    return _getDetail(journalEntryId, specialLineIsCredit: true);
  }

  Future<BalanceSheetEntryDetail> getCapitalWithdrawalDetail(
    String journalEntryId,
  ) {
    return _getDetail(journalEntryId, specialLineIsCredit: false);
  }

  Future<BalanceSheetEntryDetail> _getDetail(
    String journalEntryId, {
    required bool specialLineIsCredit,
  }) async {
    final entry = await (db.select(
      db.journalEntries,
    )..where((journal) => journal.id.equals(journalEntryId))).getSingle();

    final lines = await (db.select(
      db.ledgerLines,
    )..where((line) => line.journalEntryId.equals(journalEntryId))).get();

    if (lines.length < 2) {
      throw StateError(
        'Journal entry "$journalEntryId" does not contain two ledger lines.',
      );
    }

    final specialLine = lines.firstWhere(
      (line) => specialLineIsCredit ? line.credit > 0 : line.debit > 0,
    );

    final otherLine = lines.firstWhere((line) => line.id != specialLine.id);

    final specialAccount =
        await (db.select(db.accounts)
              ..where((account) => account.id.equals(specialLine.accountId)))
            .getSingle();

    final payableAccount = await _requirePayableAccount(entry.businessId);

    final isAssetOnCredit =
        entry.sourceType == 'asset' && otherLine.accountId == payableAccount.id;

    return BalanceSheetEntryDetail(
      journalEntryId: journalEntryId,
      date: entry.entryDate,
      description: entry.description,
      amount: specialLine.debit + specialLine.credit,
      accountId: specialAccount.id,
      accountName: specialAccount.name,
      subtype: specialAccount.subtype,
      paymentAccountId: isAssetOnCredit ? null : otherLine.accountId,
      isOnCredit: isAssetOnCredit,
    );
  }

  // ---------------------------------------------------------------------------
  // UPDATE CAPITAL / ASSET / LIABILITY
  // ---------------------------------------------------------------------------

  Future<void> updateCapital({
    required String journalEntryId,
    required String businessId,
    required DateTime date,
    required int amount,
    required String paymentAccountId,
    String? description,
  }) {
    return _updateEntry(
      journalEntryId: journalEntryId,
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: paymentAccountId,
      creditAccountId: equityAccountId(businessId),
      description: description,
    );
  }

  Future<void> updateAsset({
    required String journalEntryId,
    required String businessId,
    required DateTime date,
    required int amount,
    required String assetAccountId,
    required String assetAccountName,
    required bool isCurrentAsset,
    String? paymentAccountId,
    String? description,
  }) async {
    final assetAccount = await _resolveAccount(
      requestedId: assetAccountId,
      businessId: businessId,
    );

    await db.transaction(() async {
      await (db.update(db.accounts)..where(
            (account) =>
                account.id.equals(assetAccount.id) &
                account.businessId.equals(businessId),
          ))
          .write(
            AccountsCompanion(
              name: Value(assetAccountName.trim()),
              subtype: Value(
                isCurrentAsset ? 'current_asset' : 'non_current_asset',
              ),
            ),
          );

      await _updateEntry(
        journalEntryId: journalEntryId,
        businessId: businessId,
        date: date,
        amount: amount,
        debitAccountId: assetAccount.id,
        creditAccountId: paymentAccountId ?? payableAccountId(businessId),
        description: description,
      );
    });
  }

  Future<void> updateLiability({
    required String journalEntryId,
    required String businessId,
    required DateTime date,
    required int amount,
    required String liabilityAccountId,
    required String liabilityAccountName,
    required String subtype,
    required String paymentAccountId,
    String? description,
  }) async {
    final liabilityAccount = await _resolveAccount(
      requestedId: liabilityAccountId,
      businessId: businessId,
    );

    await (db.update(db.accounts)..where(
          (account) =>
              account.id.equals(liabilityAccount.id) &
              account.businessId.equals(businessId),
        ))
        .write(
          AccountsCompanion(
            name: Value(liabilityAccountName.trim()),
            subtype: Value(subtype),
          ),
        );

    await _updateEntry(
      journalEntryId: journalEntryId,
      businessId: businessId,
      date: date,
      amount: amount,
      debitAccountId: paymentAccountId,
      creditAccountId: liabilityAccount.id,
      description: description,
    );
  }

  // ---------------------------------------------------------------------------
  // INTERNAL POSTING
  // ---------------------------------------------------------------------------

  /// Resolves legacy IDs to the actual current account IDs, validates both
  /// accounts, then delegates the balanced posting to LedgerService.
  ///
  /// This prevents ledger_lines.account_id from ever receiving a stale
  /// deterministic ID that is no longer present in Accounts.
  Future<String> _postEntry({
    required String businessId,
    required DateTime date,
    required int amount,
    required String debitAccountId,
    required String creditAccountId,
    required String sourceType,
    String? description,
  }) async {
    if (amount <= 0) {
      throw StateError('Amount must be greater than zero.');
    }

    final debitAccount = await _resolveAccount(
      requestedId: debitAccountId,
      businessId: businessId,
    );

    final creditAccount = await _resolveAccount(
      requestedId: creditAccountId,
      businessId: businessId,
    );

    if (debitAccount.id == creditAccount.id) {
      throw StateError('Debit and credit accounts must be different.');
    }

    if (sourceType == 'capital' ||
        sourceType == 'liability' ||
        sourceType == 'liability_payment' ||
        sourceType == 'asset') {
      if (debitAccount.id == creditAccount.id) {
        throw StateError(
          'The posting would use the same account on both sides.',
        );
      }
    }

    return db.transaction(() async {
      final id = await LedgerService(db).postSimpleEntry(
        businessId: businessId,
        date: date,
        amount: amount,
        debitAccountId: debitAccount.id,
        creditAccountId: creditAccount.id,
        sourceType: sourceType,
        description: description,
      );
      await _audit(
        businessId: businessId,
        action: 'finance.${sourceType}_recorded',
        type: AuditActionType.create,
        journalEntryId: id,
        label: description ?? sourceType,
        after: {
          'amount': amount,
          'date': date,
          'debitAccount': debitAccount.name,
          'creditAccount': creditAccount.name,
        },
        details: {'sourceType': sourceType},
      );
      return id;
    });
  }

  // ---------------------------------------------------------------------------
  // INTERNAL UPDATE
  // ---------------------------------------------------------------------------

  Future<void> _updateEntry({
    required String journalEntryId,
    required String businessId,
    required DateTime date,
    required int amount,
    required String debitAccountId,
    required String creditAccountId,
    String? description,
  }) async {
    if (amount <= 0) {
      throw StateError('Amount must be greater than zero.');
    }

    final debitAccount = await _resolveAccount(
      requestedId: debitAccountId,
      businessId: businessId,
    );

    final creditAccount = await _resolveAccount(
      requestedId: creditAccountId,
      businessId: businessId,
    );

    if (debitAccount.id == creditAccount.id) {
      throw StateError('Debit and credit accounts must be different.');
    }

    await db.transaction(() async {
      final entry =
          await (db.select(db.journalEntries)..where(
                (journal) =>
                    journal.id.equals(journalEntryId) &
                    journal.businessId.equals(businessId),
              ))
              .getSingleOrNull();

      if (entry == null) {
        throw StateError(
          'Journal entry "$journalEntryId" does not exist in this business.',
        );
      }

      final lines = await (db.select(
        db.ledgerLines,
      )..where((line) => line.journalEntryId.equals(journalEntryId))).get();

      if (lines.length != 2) {
        throw StateError(
          'Journal entry "$journalEntryId" must contain exactly '
          'two ledger lines.',
        );
      }

      final debitLine = lines.firstWhere((line) => line.debit > 0);

      final creditLine = lines.firstWhere((line) => line.id != debitLine.id);

      await (db.update(
        db.journalEntries,
      )..where((journal) => journal.id.equals(journalEntryId))).write(
        JournalEntriesCompanion(
          entryDate: Value(date),
          description: Value(description),
        ),
      );

      await (db.update(
        db.ledgerLines,
      )..where((line) => line.id.equals(debitLine.id))).write(
        LedgerLinesCompanion(
          accountId: Value(debitAccount.id),
          debit: Value(amount),
          credit: const Value(0),
        ),
      );

      await (db.update(
        db.ledgerLines,
      )..where((line) => line.id.equals(creditLine.id))).write(
        LedgerLinesCompanion(
          accountId: Value(creditAccount.id),
          debit: const Value(0),
          credit: Value(amount),
        ),
      );

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'journal_entries',
        entityId: journalEntryId,
        operation: SyncOp.update,
      );

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'ledger_lines',
        entityId: debitLine.id,
        operation: SyncOp.update,
      );

      await SyncTracker.record(
        db,
        businessId: businessId,
        entityType: 'ledger_lines',
        entityId: creditLine.id,
        operation: SyncOp.update,
      );

      await _audit(
        businessId: businessId,
        action: 'finance.${entry.sourceType}_updated',
        type: AuditActionType.update,
        journalEntryId: journalEntryId,
        label: description ?? entry.sourceType,
        before: {
          'date': entry.entryDate,
          'description': entry.description,
          'amount': debitLine.debit,
          'debitAccountId': debitLine.accountId,
          'creditAccountId': creditLine.accountId,
        },
        after: {
          'date': date,
          'description': description,
          'amount': amount,
          'debitAccountId': debitAccount.id,
          'creditAccountId': creditAccount.id,
        },
      );
    });
  }
}
