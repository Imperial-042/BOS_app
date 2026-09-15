// lib/features/transactions/domain/capital_asset_liability_service.dart
//
// Balance-sheet side of the ledger: Capital (equity), Assets, and
// Liabilities. Mirrors the double-entry pattern used everywhere else
// in the app (see LedgerService, SupplierService, CustomerService) —
// every posting is a balanced Debit/Credit pair written straight to
// journal_entries + ledger_lines, tagged with a sourceType so the
// Journal Entry page can list them and the Dashboard can total them.

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

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

  /// The cash/bank/e-wallet side of the posting. Null means the other
  /// side is Accounts Payable (an asset bought on credit).
  final String? paymentAccountId;

  const BalanceSheetEntryDetail({
    required this.journalEntryId,
    required this.date,
    required this.description,
    required this.amount,
    required this.accountId,
    required this.accountName,
    required this.subtype,
    required this.paymentAccountId,
  });
}

class CapitalAssetLiabilityService {
  final AppDatabase db;
  CapitalAssetLiabilityService(this.db);

  static String equityAccountId(String businessId) => 'acc_equity_$businessId';
  static String payableAccountId(String businessId) => 'acc_ap_$businessId';

  Future<int> _balanceOf(Account account) async {
    final row = await db
        .customSelect(
          '''
          SELECT COALESCE(SUM(debit), 0) AS total_debit,
                 COALESCE(SUM(credit), 0) AS total_credit
          FROM ledger_lines ll
          INNER JOIN journal_entries je ON je.id = ll.journal_entry_id
          WHERE ll.account_id = ?
          ''',
          variables: [Variable.withString(account.id)],
        )
        .getSingle();

    return account.startingBalance +
        row.read<int>('total_debit') -
        row.read<int>('total_credit');
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

  /// Every dated posting against [accountId] — the read-only "view with
  /// dates" list for an asset/liability account in the Cashflow page.
  Future<List<LedgerEntryRow>> accountLedgerEntries(String accountId) async {
    final rows = await db
        .customSelect(
          '''
          SELECT je.entry_date AS entry_date, je.description AS description,
                 je.source_type AS source_type, ll.debit AS debit, ll.credit AS credit
          FROM ledger_lines ll
          INNER JOIN journal_entries je ON je.id = ll.journal_entry_id
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

  /// Non-cash asset accounts (e.g. Accounts Receivable, Equipment) —
  /// cash/bank/e-wallet stay in the Cashflow page's own account list.
  Future<List<AccountBalanceEntry>> assetBalances(String businessId) async {
    final accountsList =
        await (db.select(db.accounts)..where(
              (a) =>
                  a.businessId.equals(businessId) &
                  a.type.equals('asset') &
                  a.isPaymentAccount.equals(false) &
                  a.isActive.equals(true),
            ))
            .get();
    return _balancesFor(accountsList);
  }

  Future<List<AccountBalanceEntry>> liabilityBalances(String businessId) async {
    final accountsList =
        await (db.select(db.accounts)..where(
              (a) =>
                  a.businessId.equals(businessId) &
                  a.type.equals('liability') &
                  a.isActive.equals(true),
            ))
            .get();
    return _balancesFor(accountsList);
  }

  Future<int> capitalBalance(String businessId) async {
    final account =
        await (db.select(db.accounts)
              ..where((a) => a.id.equals(equityAccountId(businessId))))
            .getSingleOrNull();
    if (account == null) return 0;
    return _balanceOf(account);
  }

  Future<Account> addAssetAccount({
    required String businessId,
    required String name,
    required bool isCurrentAsset,
  }) async {
    final id = const Uuid().v4();
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: id,
            businessId: businessId,
            name: name,
            type: 'asset',
            subtype: Value(
              isCurrentAsset ? 'current_asset' : 'non_current_asset',
            ),
          ),
        );
    return (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();
  }

  /// [subtype] is one of 'trade_payable' | 'loan_payable' | 'other_payable'.
  Future<Account> addLiabilityAccount({
    required String businessId,
    required String name,
    required String subtype,
  }) async {
    final id = const Uuid().v4();
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: id,
            businessId: businessId,
            name: name,
            type: 'liability',
            subtype: Value(subtype),
          ),
        );
    return (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();
  }

  /// Owner puts money into the business: Debit the payment account
  /// (cash/bank/e-wallet increases), Credit Owner's Equity.
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

  /// Business acquires an asset: Debit the asset account. Credit
  /// either a payment account (paid in cash) or Accounts Payable
  /// (bought on credit, when [paymentAccountId] is null).
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

  /// Business incurs a liability (e.g. takes out a loan): Debit the
  /// payment account receiving the cash, Credit the liability account.
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

  /// Deletes a capital/asset/liability journal entry — cascades to its
  /// ledger lines (see LedgerLines.journalEntryId's onDelete: cascade).
  Future<void> deleteEntry(String journalEntryId) async {
    await (db.delete(
      db.journalEntries,
    )..where((j) => j.id.equals(journalEntryId))).go();
  }

  Future<BalanceSheetEntryDetail> getCapitalDetail(String journalEntryId) {
    return _getDetail(journalEntryId, specialLineIsCredit: true);
  }

  Future<BalanceSheetEntryDetail> getAssetDetail(String journalEntryId) {
    return _getDetail(journalEntryId, specialLineIsCredit: false);
  }

  Future<BalanceSheetEntryDetail> getLiabilityDetail(String journalEntryId) {
    return _getDetail(journalEntryId, specialLineIsCredit: true);
  }

  /// [specialLineIsCredit] picks which ledger line is the "special"
  /// (equity/asset/liability) account: capital & liability postings put
  /// it on the credit side, asset postings put it on the debit side.
  Future<BalanceSheetEntryDetail> _getDetail(
    String journalEntryId, {
    required bool specialLineIsCredit,
  }) async {
    final entry = await (db.select(
      db.journalEntries,
    )..where((j) => j.id.equals(journalEntryId))).getSingle();

    final lines = await (db.select(
      db.ledgerLines,
    )..where((l) => l.journalEntryId.equals(journalEntryId))).get();

    final specialLine = lines.firstWhere(
      (l) => specialLineIsCredit ? l.credit > 0 : l.debit > 0,
    );
    final otherLine = lines.firstWhere((l) => l.id != specialLine.id);

    final specialAccount = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(specialLine.accountId))).getSingle();

    return BalanceSheetEntryDetail(
      journalEntryId: journalEntryId,
      date: entry.entryDate,
      description: entry.description,
      amount: specialLine.debit + specialLine.credit,
      accountId: specialAccount.id,
      accountName: specialAccount.name,
      subtype: specialAccount.subtype,
      paymentAccountId: otherLine.accountId,
    );
  }

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
    await (db.update(
      db.accounts,
    )..where((a) => a.id.equals(assetAccountId))).write(
      AccountsCompanion(
        name: Value(assetAccountName),
        subtype: Value(isCurrentAsset ? 'current_asset' : 'non_current_asset'),
      ),
    );

    await _updateEntry(
      journalEntryId: journalEntryId,
      date: date,
      amount: amount,
      debitAccountId: assetAccountId,
      creditAccountId: paymentAccountId ?? payableAccountId(businessId),
      description: description,
    );
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
    await (db.update(
      db.accounts,
    )..where((a) => a.id.equals(liabilityAccountId))).write(
      AccountsCompanion(
        name: Value(liabilityAccountName),
        subtype: Value(subtype),
      ),
    );

    await _updateEntry(
      journalEntryId: journalEntryId,
      date: date,
      amount: amount,
      debitAccountId: paymentAccountId,
      creditAccountId: liabilityAccountId,
      description: description,
    );
  }

  Future<void> _updateEntry({
    required String journalEntryId,
    required DateTime date,
    required int amount,
    required String debitAccountId,
    required String creditAccountId,
    String? description,
  }) async {
    await db.transaction(() async {
      await (db.update(
        db.journalEntries,
      )..where((j) => j.id.equals(journalEntryId))).write(
        JournalEntriesCompanion(
          entryDate: Value(date),
          description: Value(description),
        ),
      );

      final lines = await (db.select(
        db.ledgerLines,
      )..where((l) => l.journalEntryId.equals(journalEntryId))).get();

      final debitLine = lines.firstWhere((l) => l.debit > 0);
      final creditLine = lines.firstWhere((l) => l.id != debitLine.id);

      await (db.update(
        db.ledgerLines,
      )..where((l) => l.id.equals(debitLine.id))).write(
        LedgerLinesCompanion(
          accountId: Value(debitAccountId),
          debit: Value(amount),
          credit: const Value(0),
        ),
      );

      await (db.update(
        db.ledgerLines,
      )..where((l) => l.id.equals(creditLine.id))).write(
        LedgerLinesCompanion(
          accountId: Value(creditAccountId),
          credit: Value(amount),
          debit: const Value(0),
        ),
      );
    });
  }

  Future<String> _postEntry({
    required String businessId,
    required DateTime date,
    required int amount,
    required String debitAccountId,
    required String creditAccountId,
    required String sourceType,
    String? description,
  }) async {
    final entryId = const Uuid().v4();

    await db.transaction(() async {
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: entryId,
              businessId: businessId,
              entryDate: date,
              sourceType: sourceType,
              description: Value(description),
            ),
          );

      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: entryId,
              accountId: debitAccountId,
              debit: Value(amount),
            ),
          );

      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: entryId,
              accountId: creditAccountId,
              credit: Value(amount),
            ),
          );
    });

    return entryId;
  }
}
