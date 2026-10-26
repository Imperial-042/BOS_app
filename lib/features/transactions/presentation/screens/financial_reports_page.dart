// lib/features/transactions/presentation/screens/financial_reports_page.dart
//
// Financial Reports: Income Statement (Profit & Loss) and Balance Sheet.
//
// Both reuse balances already computed elsewhere in the app —
// accountBalancesProvider, assetBalancesProvider, liabilityBalancesProvider,
// and capitalBalanceProvider — rather than re-deriving them. The one truly
// new number computed here is "retained earnings": accumulated
// (income - expenses) ever posted to the ledger, which is what makes
// Assets = Liabilities + Equity actually balance, since this app never
// "closes the books" at year-end.
//
// IMPORTANT SEMANTIC NOTE — inventory is deliberately NOT an asset here:
// this app expenses a supply's full cost the moment it's purchased (Dr
// Supplies Expense / Cr Cash) rather than capitalizing it as inventory
// and recognizing COGS on sale. That means the cost of everything still
// sitting on the shelf has already reduced Retained Earnings. Counting
// it again as a Balance Sheet asset would double-count it and make the
// balance check permanently show a false "does not balance" difference.
// Its value is shown as a clearly-labeled memo line instead — see
// _InventoryMemoCard and BalanceSheetView.inventoryValueMemo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/capital_asset_liability_service.dart'
    show AccountBalanceEntry;
import 'transaction_page.dart' show ledgerVersionProvider, kCurrentBusinessId;
import 'cashflow_page.dart'
    show
        AccountBalance,
        accountBalancesProvider,
        assetBalancesProvider,
        liabilityBalancesProvider,
        capitalBalanceProvider,
        AccountLedgerPage;
import '../providers/transaction_date_filter.dart';

// ============================================================
// FORMATTING HELPER
// ============================================================

String _peso(int cents) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  ).format(cents / 100);
}

// ============================================================
// MODELS
// ============================================================

class TransactionLineDetail {
  final DateTime date;
  final String? description;
  final int amount;
  final String status;

  const TransactionLineDetail({
    required this.date,
    required this.description,
    required this.amount,
    required this.status,
  });
}

class CategoryTotal {
  final String categoryName;
  final int amount; // cents

  /// Itemized rows behind this total — populated for Income Statement
  /// lines so the drill-down sheet can list them. Empty for Balance
  /// Sheet lines, which drill down via [account] instead.
  final List<TransactionLineDetail> transactions;

  /// Set only for Balance Sheet lines (assets/liabilities/Owner's
  /// Capital) — lets the UI push the existing AccountLedgerPage
  /// instead of building a second detail view.
  final Account? account;

  const CategoryTotal({
    required this.categoryName,
    required this.amount,
    this.transactions = const [],
    this.account,
  });
}

class IncomeStatementData {
  final List<CategoryTotal> revenue;
  final List<CategoryTotal> expenses;
  final int pendingRevenueAmount;
  final int pendingRevenueCount;
  final int pendingExpenseAmount;
  final int pendingExpenseCount;

  const IncomeStatementData({
    required this.revenue,
    required this.expenses,
    this.pendingRevenueAmount = 0,
    this.pendingRevenueCount = 0,
    this.pendingExpenseAmount = 0,
    this.pendingExpenseCount = 0,
  });

  int get totalRevenue => revenue.fold(0, (sum, e) => sum + e.amount);
  int get totalExpenses => expenses.fold(0, (sum, e) => sum + e.amount);
  int get netIncome => totalRevenue - totalExpenses;
  double get netMarginPercent =>
      totalRevenue == 0 ? 0 : (netIncome / totalRevenue) * 100;

  int get pendingTotalAmount => pendingRevenueAmount + pendingExpenseAmount;
  int get pendingTotalCount => pendingRevenueCount + pendingExpenseCount;
}

class BalanceSheetView {
  final List<AccountBalance> cashAccounts;
  final List<AccountBalanceEntry> otherAssets;
  final List<AccountBalanceEntry> liabilities;
  final int capitalContributed;
  final int retainedEarnings;

  /// Memo-only worth of raw-material stock on hand. NEVER added to
  /// totalAssets or the balance check — see the file-level doc comment
  /// for why that would double-count already-expensed inventory cost.
  final int inventoryValueMemo;

  const BalanceSheetView({
    required this.cashAccounts,
    required this.otherAssets,
    required this.liabilities,
    required this.capitalContributed,
    required this.retainedEarnings,
    required this.inventoryValueMemo,
  });

  int get totalCash => cashAccounts.fold(0, (sum, e) => sum + e.balance);
  int get totalOtherAssets => otherAssets.fold(0, (sum, e) => sum + e.balance);
  int get totalAssets => totalCash + totalOtherAssets;
  int get totalLiabilities => liabilities.fold(0, (sum, e) => sum + e.balance);
  int get totalEquity => capitalContributed + retainedEarnings;
  int get totalLiabilitiesAndEquity => totalLiabilities + totalEquity;

  /// Should always be 0. Assets = Liabilities + Equity is a fundamental
  /// identity of double-entry bookkeeping — if this is ever non-zero,
  /// something in the ledger is unbalanced.
  int get reconciliationDifference => totalAssets - totalLiabilitiesAndEquity;

  // ------------------------------------------------------------
  // RATIOS
  //
  // Current/non-current classification comes from Account.subtype
  // ('current_asset'/'non_current_asset' for assets, 'trade_payable'/
  // 'loan_payable'/'other_payable' for liabilities). Loans are treated
  // as fully non-current here — an approximation; a loan with a
  // current portion due within a year would need that split tracked
  // separately to be exact.
  // ------------------------------------------------------------

  int get _currentOtherAssets => otherAssets
      .where((a) => a.account.subtype != 'non_current_asset')
      .fold(0, (sum, a) => sum + a.balance);

  int get _currentLiabilities => liabilities
      .where((l) => l.account.subtype != 'loan_payable')
      .fold(0, (sum, l) => sum + l.balance);

  /// Cash + near-cash current assets, EXCLUDING inventory — the strict
  /// "can I cover short-term debts without selling stock" test.
  double? get quickRatio {
    final liabilities = _currentLiabilities;
    if (liabilities == 0) return null;
    return (totalCash + _currentOtherAssets) / liabilities;
  }

  /// Same as above but includes the inventory memo value — the more
  /// commonly-quoted ratio, at the cost of assuming stock converts to
  /// cash at its recorded cost.
  double? get currentRatio {
    final liabilities = _currentLiabilities;
    if (liabilities == 0) return null;
    return (totalCash + _currentOtherAssets + inventoryValueMemo) / liabilities;
  }

  double? get debtToEquityRatio {
    if (totalEquity == 0) return null;
    return totalLiabilities / totalEquity;
  }
}

// ============================================================
// PROVIDERS
// ============================================================

final selectedReportsDateFilterProvider = StateProvider<TransactionDateFilter>(
  (ref) => const TransactionDateFilter.month(),
);

/// Whether pending (not-yet-completed) income/expenses count toward the
/// Income Statement totals. The Balance Sheet's retained earnings only
/// ever reflects completed, ledger-posted transactions — so leaving
/// this on can make the two reports disagree for the same period.
/// Defaults on to preserve prior behavior; the banner shown alongside
/// it always states what's excluded/included so the discrepancy is
/// never silent.
final includePendingInReportsProvider = StateProvider<bool>((ref) => true);

/// All-time (income - expenses) posted to the ledger for this business.
/// Only ledger-posted transactions count: saveExpense/saveIncome only
/// post a journal entry when status == 'completed', so pending
/// transactions are correctly excluded here, same as everywhere else
/// balances are computed from the ledger.
final retainedEarningsProvider = FutureProvider<int>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final row = await db
      .customSelect(
        '''
        SELECT
          COALESCE(SUM(
            CASE WHEN a.type = 'income' THEN ll.credit - ll.debit ELSE 0 END
          ), 0) AS total_income,
          COALESCE(SUM(
            CASE WHEN a.type = 'expense' THEN ll.debit - ll.credit ELSE 0 END
          ), 0) AS total_expense
        FROM ledger_lines ll
        INNER JOIN journal_entries je ON je.id = ll.journal_entry_id
        INNER JOIN accounts a ON a.id = ll.account_id
        WHERE je.business_id = ?
        ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .getSingle();

  return row.read<int>('total_income') - row.read<int>('total_expense');
});

typedef IncomeStatementArgs = ({
  TransactionDateFilter filter,
  bool includePending,
});

/// Revenue and expenses grouped by category for a date range. Sources
/// straight from incomeTransactions/expenses (not the ledger). Always
/// fetches both pending and completed rows so the pending banner can
/// report what's excluded regardless of the toggle, then applies
/// [IncomeStatementArgs.includePending] only to what's totaled.
final incomeStatementProvider =
    FutureProvider.family<IncomeStatementData, IncomeStatementArgs>((
      ref,
      args,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final range = args.filter.range;

      final incomeRows =
          await (db.select(db.incomeTransactions)..where(
                (i) =>
                    i.businessId.equals(kCurrentBusinessId) &
                    i.txnDate.isBiggerOrEqualValue(range.start) &
                    i.txnDate.isSmallerThanValue(range.end),
              ))
              .get();

      final expenseRows =
          await (db.select(db.expenses)..where(
                (e) =>
                    e.businessId.equals(kCurrentBusinessId) &
                    e.expenseDate.isBiggerOrEqualValue(range.start) &
                    e.expenseDate.isSmallerThanValue(range.end),
              ))
              .get();

      // THE FIX: scope categories to this business — the original
      // query fetched every category across every business.
      final categories = await (db.select(
        db.categories,
      )..where((c) => c.businessId.equals(kCurrentBusinessId))).get();
      final categoryName = {for (final c in categories) c.id: c.name};

      final includedIncome = args.includePending
          ? incomeRows
          : incomeRows.where((r) => r.status == 'completed').toList();
      final includedExpense = args.includePending
          ? expenseRows
          : expenseRows.where((r) => r.status == 'completed').toList();

      final revenueByCategory = <String, int>{};
      final revenueDetails = <String, List<TransactionLineDetail>>{};
      for (final row in includedIncome) {
        final name = categoryName[row.categoryId] ?? 'Uncategorized';
        revenueByCategory[name] = (revenueByCategory[name] ?? 0) + row.amount;
        (revenueDetails[name] ??= []).add(
          TransactionLineDetail(
            date: row.txnDate,
            description: row.description,
            amount: row.amount,
            status: row.status,
          ),
        );
      }

      final expensesByCategory = <String, int>{};
      final expenseDetails = <String, List<TransactionLineDetail>>{};
      for (final row in includedExpense) {
        final name = categoryName[row.categoryId] ?? 'Uncategorized';
        expensesByCategory[name] = (expensesByCategory[name] ?? 0) + row.amount;
        (expenseDetails[name] ??= []).add(
          TransactionLineDetail(
            date: row.expenseDate,
            description: row.description,
            amount: row.amount,
            status: row.status,
          ),
        );
      }

      final revenue =
          revenueByCategory.entries
              .map(
                (e) => CategoryTotal(
                  categoryName: e.key,
                  amount: e.value,
                  transactions: (revenueDetails[e.key] ?? [])
                    ..sort((a, b) => b.date.compareTo(a.date)),
                ),
              )
              .toList()
            ..sort((a, b) => b.amount.compareTo(a.amount));

      final expenses =
          expensesByCategory.entries
              .map(
                (e) => CategoryTotal(
                  categoryName: e.key,
                  amount: e.value,
                  transactions: (expenseDetails[e.key] ?? [])
                    ..sort((a, b) => b.date.compareTo(a.date)),
                ),
              )
              .toList()
            ..sort((a, b) => b.amount.compareTo(a.amount));

      final pendingIncome = incomeRows.where((r) => r.status == 'pending');
      final pendingExpense = expenseRows.where((r) => r.status == 'pending');

      return IncomeStatementData(
        revenue: revenue,
        expenses: expenses,
        pendingRevenueAmount: pendingIncome.fold(0, (s, r) => s + r.amount),
        pendingRevenueCount: pendingIncome.length,
        pendingExpenseAmount: pendingExpense.fold(0, (s, r) => s + r.amount),
        pendingExpenseCount: pendingExpense.length,
      );
    });

/// Totals for the period immediately preceding the selected range, of
/// equal length — used for the vs-last-period comparison chips. This
/// is a sliding window (same number of days back), not a "prior
/// calendar month/quarter", since it works generically for any preset
/// or custom range without needing to know the filter's internals.
final previousPeriodTotalsProvider =
    FutureProvider.family<({int revenue, int expenses}), IncomeStatementArgs>((
      ref,
      args,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final range = args.filter.range;
      final duration = range.end.difference(range.start);
      final previousStart = range.start.subtract(duration);
      final previousEnd = range.start;

      final incomeRows =
          await (db.select(db.incomeTransactions)..where(
                (i) =>
                    i.businessId.equals(kCurrentBusinessId) &
                    i.txnDate.isBiggerOrEqualValue(previousStart) &
                    i.txnDate.isSmallerThanValue(previousEnd),
              ))
              .get();

      final expenseRows =
          await (db.select(db.expenses)..where(
                (e) =>
                    e.businessId.equals(kCurrentBusinessId) &
                    e.expenseDate.isBiggerOrEqualValue(previousStart) &
                    e.expenseDate.isSmallerThanValue(previousEnd),
              ))
              .get();

      final includedIncome = args.includePending
          ? incomeRows
          : incomeRows.where((r) => r.status == 'completed');
      final includedExpense = args.includePending
          ? expenseRows
          : expenseRows.where((r) => r.status == 'completed');

      return (
        revenue: includedIncome.fold<int>(0, (s, r) => s + r.amount),
        expenses: includedExpense.fold<int>(0, (s, r) => s + r.amount),
      );
    });

/// Current worth of raw-material stock on hand — see the file-level
/// doc comment and BalanceSheetView.inventoryValueMemo for why this is
/// memo-only and never folded into totalAssets.
final inventoryValueProvider = FutureProvider<int>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final supplies =
      await (db.select(db.supplies)..where(
            (s) =>
                s.businessId.equals(kCurrentBusinessId) &
                s.isActive.equals(true),
          ))
          .get();

  return supplies
      .fold<double>(0, (sum, s) => sum + (s.currentStock * s.costPerBaseUnit))
      .round();
});

/// The owner's-equity account, resolved by the deterministic id
/// seedDefaultsForBusiness gives it, so "Owner's Capital" can drill
/// down into AccountLedgerPage like every other Balance Sheet line.
final equityAccountProvider = FutureProvider<Account?>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)..where(
        (a) =>
            a.businessId.equals(kCurrentBusinessId) &
            a.id.isIn([
              AppDatabase.cloudCompatibleDefaultId(
                'accounts',
                'acc_equity_$kCurrentBusinessId',
              ),
              'acc_equity_$kCurrentBusinessId',
            ]),
      ))
      .getSingleOrNull();
});

/// Current (as-of-now) balance sheet — matches how every other balance
/// in this app (Cashflow accounts, assets, liabilities, capital) is
/// already always shown as a live "now" figure, not a historical
/// point-in-time snapshot.
final balanceSheetProvider = FutureProvider<BalanceSheetView>((ref) async {
  final cash = await ref.watch(accountBalancesProvider.future);
  final otherAssets = await ref.watch(assetBalancesProvider.future);
  final liabilities = await ref.watch(liabilityBalancesProvider.future);
  final capital = await ref.watch(capitalBalanceProvider.future);
  final retainedEarnings = await ref.watch(retainedEarningsProvider.future);
  final inventoryValue = await ref.watch(inventoryValueProvider.future);

  return BalanceSheetView(
    cashAccounts: cash,
    otherAssets: otherAssets,
    liabilities: liabilities,
    capitalContributed: capital,
    retainedEarnings: retainedEarnings,
    inventoryValueMemo: inventoryValue,
  );
});

// ============================================================
// PAGE
// ============================================================

class FinancialReportsPage extends StatefulWidget {
  const FinancialReportsPage({super.key});

  @override
  State<FinancialReportsPage> createState() => _FinancialReportsPageState();
}

class _FinancialReportsPageState extends State<FinancialReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Financial Reports',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Income Statement'),
            Tab(text: 'Balance Sheet'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_IncomeStatementTab(), _BalanceSheetTab()],
      ),
    );
  }
}

// ============================================================
// INCOME STATEMENT TAB
// ============================================================

class _IncomeStatementTab extends ConsumerWidget {
  const _IncomeStatementTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(selectedReportsDateFilterProvider);
    final includePending = ref.watch(includePendingInReportsProvider);
    final args = (filter: filter, includePending: includePending);

    final dataAsync = ref.watch(incomeStatementProvider(args));
    final previousAsync = ref.watch(previousPeriodTotalsProvider(args));
    final colors = Theme.of(context).colorScheme;

    return dataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load the income statement.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      ),
      data: (data) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _ReportsDateFilterBar(filter: filter),
            const SizedBox(height: 10),
            _PendingToggleRow(includePending: includePending),
            if (data.pendingTotalCount > 0) ...[
              const SizedBox(height: 10),
              _PendingBanner(data: data, includePending: includePending),
            ],
            const SizedBox(height: 16),
            _NetIncomeHero(data: data, previous: previousAsync.asData?.value),
            const SizedBox(height: 16),
            _ReportSection(
              title: 'Revenue',
              icon: Icons.south_west_rounded,
              accentColor: Colors.green.shade700,
              lines: data.revenue,
              total: data.totalRevenue,
              emptyText: 'No revenue recorded for this period.',
              onTapLine: (line) => _showCategoryDetailSheet(
                context,
                line: line,
                isRevenue: true,
              ),
            ),
            const SizedBox(height: 16),
            _ReportSection(
              title: 'Expenses',
              icon: Icons.north_east_rounded,
              accentColor: colors.error,
              lines: data.expenses,
              total: data.totalExpenses,
              emptyText: 'No expenses recorded for this period.',
              onTapLine: (line) => _showCategoryDetailSheet(
                context,
                line: line,
                isRevenue: false,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PendingToggleRow extends ConsumerWidget {
  final bool includePending;
  const _PendingToggleRow({required this.includePending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Include pending transactions',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        Switch.adaptive(
          value: includePending,
          onChanged: (v) =>
              ref.read(includePendingInReportsProvider.notifier).state = v,
        ),
      ],
    );
  }
}

class _PendingBanner extends StatelessWidget {
  final IncomeStatementData data;
  final bool includePending;

  const _PendingBanner({required this.data, required this.includePending});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = data.pendingTotalCount;
    final amount = _peso(data.pendingTotalAmount);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Colors.orange.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              includePending
                  ? '$count pending transaction${count == 1 ? '' : 's'} ($amount) '
                        '${count == 1 ? 'is' : 'are'} included above, but not yet '
                        'reflected in the Balance Sheet — only completed transactions '
                        'post to the ledger.'
                  : '$count pending transaction${count == 1 ? '' : 's'} ($amount) '
                        '${count == 1 ? 'is' : 'are'} excluded above, matching the '
                        'Balance Sheet.',
              style: TextStyle(
                fontSize: 11.5,
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetIncomeHero extends StatelessWidget {
  final IncomeStatementData data;
  final ({int revenue, int expenses})? previous;

  const _NetIncomeHero({required this.data, this.previous});

  String? _deltaLabel(int current, int previousValue) {
    if (previousValue == 0) return current == 0 ? null : 'new';
    final pct = ((current - previousValue) / previousValue.abs()) * 100;
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = data.netIncome >= 0;
    final prevNetIncome = previous == null
        ? null
        : previous!.revenue - previous!.expenses;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET INCOME',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.75),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${positive ? '+' : '-'}${_peso(data.netIncome.abs())}',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          if (prevNetIncome != null) ...[
            const SizedBox(height: 4),
            Text(
              'vs ${_peso(prevNetIncome)} last period',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _HeroChip(
                label: 'Revenue',
                value: _peso(data.totalRevenue),
                delta: previous == null
                    ? null
                    : _deltaLabel(data.totalRevenue, previous!.revenue),
              ),
              const SizedBox(width: 8),
              _HeroChip(
                label: 'Expenses',
                value: _peso(data.totalExpenses),
                delta: previous == null
                    ? null
                    : _deltaLabel(data.totalExpenses, previous!.expenses),
              ),
              const SizedBox(width: 8),
              _HeroChip(
                label: 'Margin',
                value: '${data.netMarginPercent.toStringAsFixed(1)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final String value;
  final String? delta;

  const _HeroChip({required this.label, required this.value, this.delta});

  @override
  Widget build(BuildContext context) {
    final showDelta = delta != null && delta != 'new';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (showDelta) ...[
                  const SizedBox(width: 4),
                  Text(
                    delta!,
                    style: TextStyle(
                      color: delta!.startsWith('-')
                          ? Colors.redAccent.shade100
                          : Colors.greenAccent.shade100,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CATEGORY DETAIL DRILL-DOWN (Income Statement lines)
// ============================================================

void _showCategoryDetailSheet(
  BuildContext context, {
  required CategoryTotal line,
  required bool isRevenue,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryDetailSheet(line: line, isRevenue: isRevenue),
  );
}

class _CategoryDetailSheet extends StatelessWidget {
  final CategoryTotal line;
  final bool isRevenue;

  const _CategoryDetailSheet({required this.line, required this.isRevenue});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.categoryName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${line.transactions.length} transaction'
                        '${line.transactions.length == 1 ? '' : 's'} · '
                        '${_peso(line.amount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: line.transactions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No transaction details available.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: line.transactions.length,
                    separatorBuilder: (_, __) => const Divider(height: 18),
                    itemBuilder: (context, index) {
                      final t = line.transactions[index];
                      final pending = t.status == 'pending';
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.description?.trim().isNotEmpty == true
                                      ? t.description!
                                      : line.categoryName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      DateFormat('MMM d, yyyy').format(t.date),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (pending) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'Pending',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _peso(t.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: isRevenue
                                  ? Colors.green.shade700
                                  : scheme.error,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BALANCE SHEET TAB
// ============================================================

class _BalanceSheetTab extends ConsumerWidget {
  const _BalanceSheetTab();

  void _openAccountLedger(BuildContext context, CategoryTotal line) {
    if (line.account == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AccountLedgerPage(account: line.account!, balance: line.amount),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheetAsync = ref.watch(balanceSheetProvider);
    final equityAccountAsync = ref.watch(equityAccountProvider);
    final colors = Theme.of(context).colorScheme;

    return sheetAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load the balance sheet.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      ),
      data: (sheet) {
        final assetLines = [
          ...sheet.cashAccounts.map(
            (a) => CategoryTotal(
              categoryName: a.account.name,
              amount: a.balance,
              account: a.account,
            ),
          ),
          ...sheet.otherAssets.map(
            (a) => CategoryTotal(
              categoryName: a.account.name,
              amount: a.balance,
              account: a.account,
            ),
          ),
        ];

        final liabilityLines = sheet.liabilities
            .map(
              (l) => CategoryTotal(
                categoryName: l.account.name,
                amount: l.balance,
                account: l.account,
              ),
            )
            .toList();

        final equityAccount = equityAccountAsync.asData?.value;
        final equityLines = [
          CategoryTotal(
            categoryName: "Owner's Capital",
            amount: sheet.capitalContributed,
            account: equityAccount,
          ),
          const CategoryTotal(
            categoryName: 'Retained Earnings',
            amount: 0,
          ).copyWithAmount(sheet.retainedEarnings),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'As of ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message:
                      'Always shows current balances — a dated, '
                      'point-in-time balance sheet isn\'t available yet.',
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ReportSection(
              title: 'Assets',
              icon: Icons.account_balance_wallet_rounded,
              accentColor: Colors.blue.shade700,
              lines: assetLines,
              total: sheet.totalAssets,
              emptyText: 'No assets recorded yet.',
              onTapLine: (line) => _openAccountLedger(context, line),
            ),
            const SizedBox(height: 16),
            _ReportSection(
              title: 'Liabilities',
              icon: Icons.request_quote_outlined,
              accentColor: Colors.orange.shade800,
              lines: liabilityLines,
              total: sheet.totalLiabilities,
              emptyText: 'No liabilities recorded yet.',
              onTapLine: (line) => _openAccountLedger(context, line),
            ),
            const SizedBox(height: 16),
            _ReportSection(
              title: 'Equity',
              icon: Icons.savings_outlined,
              accentColor: Colors.purple.shade700,
              lines: equityLines,
              total: sheet.totalEquity,
              emptyText: 'No equity recorded yet.',
              allowNegativeLines: true,
              onTapLine: (line) => _openAccountLedger(context, line),
            ),
            const SizedBox(height: 16),
            _InventoryMemoCard(inventoryValue: sheet.inventoryValueMemo),
            const SizedBox(height: 16),
            _FinancialRatiosCard(sheet: sheet),
            const SizedBox(height: 16),
            _BalanceCheckCard(sheet: sheet),
          ],
        );
      },
    );
  }
}

extension on CategoryTotal {
  /// Small helper so the Retained Earnings line can be built as a
  /// const-friendly literal above and then given its real amount.
  CategoryTotal copyWithAmount(int amount) => CategoryTotal(
    categoryName: categoryName,
    amount: amount,
    transactions: transactions,
    account: account,
  );
}

class _InventoryMemoCard extends StatelessWidget {
  final int inventoryValue;
  const _InventoryMemoCard({required this.inventoryValue});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: Colors.teal.shade700,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Inventory on hand',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text(
                _peso(inventoryValue),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.teal.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The current worth of raw-material stock in Supplies. Shown for '
            'reference only — it\'s not counted in Total Assets or the '
            'balance check below, because this app expenses a supply\'s '
            'cost as soon as it\'s purchased rather than capitalizing it '
            'as inventory.',
            style: TextStyle(
              fontSize: 11.5,
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialRatiosCard extends StatelessWidget {
  final BalanceSheetView sheet;
  const _FinancialRatiosCard({required this.sheet});

  String _fmt(double? value) => value == null ? '—' : value.toStringAsFixed(2);

  Color _liquidityColor(double? value, double healthyAt) {
    if (value == null) return Colors.grey;
    return value >= healthyAt ? Colors.green.shade700 : Colors.orange.shade800;
  }

  Color _leverageColor(double? value) {
    if (value == null) return Colors.grey;
    return value <= 1.0 ? Colors.green.shade700 : Colors.orange.shade800;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              const Text(
                'Financial ratios',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RatioTile(
                  label: 'Current ratio',
                  value: _fmt(sheet.currentRatio),
                  color: _liquidityColor(sheet.currentRatio, 1.5),
                  hint: 'Includes inventory',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RatioTile(
                  label: 'Quick ratio',
                  value: _fmt(sheet.quickRatio),
                  color: _liquidityColor(sheet.quickRatio, 1.0),
                  hint: 'Cash & receivables only',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RatioTile(
                  label: 'Debt-to-equity',
                  value: _fmt(sheet.debtToEquityRatio),
                  color: _leverageColor(sheet.debtToEquityRatio),
                  hint: 'Lower is safer',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatioTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String hint;

  const _RatioTile({
    required this.label,
    required this.value,
    required this.color,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: TextStyle(fontSize: 9.5, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _BalanceCheckCard extends StatelessWidget {
  final BalanceSheetView sheet;

  const _BalanceCheckCard({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final balanced = sheet.reconciliationDifference == 0;
    final color = balanced ? Colors.green.shade700 : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                balanced
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                balanced ? 'Books are balanced' : 'Books do not balance',
                style: TextStyle(fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CheckRow(label: 'Total Assets', value: sheet.totalAssets),
          _CheckRow(
            label: 'Total Liabilities + Equity',
            value: sheet.totalLiabilitiesAndEquity,
          ),
          if (!balanced) ...[
            const Divider(height: 18),
            _CheckRow(
              label: 'Difference',
              value: sheet.reconciliationDifference,
              bold: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final int value;
  final bool bold;

  const _CheckRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            _peso(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SHARED: REPORT SECTION (list of lines + total)
// ============================================================

class _ReportSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<CategoryTotal> lines;
  final int total;
  final String emptyText;
  final bool allowNegativeLines;

  /// When provided, a line is tappable if it also carries an [Account]
  /// (Balance Sheet lines) or itemized [transactions] (Income
  /// Statement lines) — a line with neither (e.g. Retained Earnings)
  /// renders plainly with no chevron.
  final void Function(CategoryTotal line)? onTapLine;

  const _ReportSection({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.lines,
    required this.total,
    required this.emptyText,
    this.allowNegativeLines = false,
    this.onTapLine,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                _peso(total),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: accentColor,
                ),
              ),
            ],
          ),
          if (lines.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              emptyText,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ] else ...[
            const SizedBox(height: 12),
            for (final line in lines) _buildLineRow(context, colors, line),
          ],
        ],
      ),
    );
  }

  Widget _buildLineRow(
    BuildContext context,
    ColorScheme colors,
    CategoryTotal line,
  ) {
    final canOpen =
        onTapLine != null &&
        (line.account != null || line.transactions.isNotEmpty);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line.categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            _peso(line.amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: (!allowNegativeLines || line.amount >= 0)
                  ? colors.onSurface
                  : colors.error,
            ),
          ),
          if (canOpen) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: colors.outline),
          ],
        ],
      ),
    );

    if (!canOpen) return row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTapLine!(line),
        child: row,
      ),
    );
  }
}

// ============================================================
// DATE FILTER BAR (Income Statement only)
// ============================================================

class _ReportsDateFilterBar extends ConsumerWidget {
  final TransactionDateFilter filter;

  const _ReportsDateFilterBar({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            filter.label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        PopupMenuButton<TransactionDatePreset>(
          initialValue: filter.preset,
          tooltip: 'Change period',
          onSelected: (preset) async {
            if (preset == TransactionDatePreset.custom) {
              final selectedRange = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                currentDate: DateTime.now(),
                initialDateRange: filter.preset == TransactionDatePreset.custom
                    ? filter.range
                    : null,
              );
              if (selectedRange == null) return;
              ref.read(selectedReportsDateFilterProvider.notifier).state =
                  TransactionDateFilter.custom(selectedRange);
              return;
            }

            ref.read(selectedReportsDateFilterProvider.notifier).state =
                TransactionDateFilter(preset: preset);
          },
          itemBuilder: (context) => TransactionDatePreset.values.map((preset) {
            final selected = preset == filter.preset;
            return PopupMenuItem<TransactionDatePreset>(
              value: preset,
              child: Row(
                children: [
                  Expanded(
                    child: Text(TransactionDateFilter(preset: preset).label),
                  ),
                  if (selected) const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            );
          }).toList(),
          icon: const Icon(Icons.date_range_rounded),
        ),
      ],
    );
  }
}
