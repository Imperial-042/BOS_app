// lib/features/transactions/presentation/screens/journal_entry_page.dart
//
// Modern Journal Entry / Transaction History screen.
//
// Features:
// - Income + expense combined journal
// - Grouped by day
// - Daily totals
// - Overall income / expense summary
// - Modern Material 3 UI
// - Responsive layout
// - Swipe Edit / Delete
// - Pull to refresh
// - Empty / loading / error states
// - Safe category lookup
//
// Dependencies:
//   flutter_slidable: ^3.1.0
//   intl: ^0.19.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

import 'transaction_page.dart';
import 'cashflow_page.dart'
    show
        capitalAssetLiabilityServiceProvider,
        assetBalancesProvider,
        liabilityBalancesProvider,
        capitalBalanceProvider,
        accountBalancesProvider,
        AddCapitalSheet,
        AddAssetSheet,
        AddLiabilitySheet;
import 'suppliers_page.dart' show supplierServiceProvider;
import 'customers_page.dart' show customerServiceProvider;
import '../providers/transaction_date_filter.dart';

// ============================================================
// MODEL
// ============================================================

enum JournalEntryType {
  income,
  expense,
  capital,
  asset,
  liability,
  supplierPurchase,
  payablePayment,
  receivablePayment,
}

class JournalEntryRow {
  final String id;
  final JournalEntryType type;
  final DateTime date;
  final String? description;
  final String categoryName;
  final int amount; // cents
  final String status;

  final Expense? sourceExpense;
  final IncomeTransaction? sourceIncome;

  JournalEntryRow({
    required this.id,
    required this.type,
    required this.date,
    required this.description,
    required this.categoryName,
    required this.amount,
    required this.status,
    this.sourceExpense,
    this.sourceIncome,
  });
}

// ============================================================
// PROVIDER
// ============================================================

final selectedJournalDateFilterProvider = StateProvider<TransactionDateFilter>(
  (ref) => const TransactionDateFilter.month(),
);

final journalEntriesProvider =
    FutureProvider.family<List<JournalEntryRow>, TransactionDateFilter>((
      ref,
      filter,
    ) async {
      ref.watch(ledgerVersionProvider);

      final db = ref.watch(databaseProvider);
      final range = filter.range;

      final expenseRows =
          await (db.select(db.expenses)
                ..where(
                  (e) =>
                      e.businessId.equals(kCurrentBusinessId) &
                      e.expenseDate.isBiggerOrEqualValue(range.start) &
                      e.expenseDate.isSmallerThanValue(range.end),
                )
                ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
              .get();

      final incomeRows =
          await (db.select(db.incomeTransactions)
                ..where(
                  (i) =>
                      i.businessId.equals(kCurrentBusinessId) &
                      i.txnDate.isBiggerOrEqualValue(range.start) &
                      i.txnDate.isSmallerThanValue(range.end),
                )
                ..orderBy([(i) => OrderingTerm.desc(i.txnDate)]))
              .get();

      final categories = await db.select(db.categories).get();

      final categoryMap = <String, String>{
        for (final category in categories) category.id: category.name,
      };

      String categoryName(String id) {
        return categoryMap[id] ?? 'Uncategorized';
      }

      // Capital/Asset/Liability entries live directly in journal_entries +
      // ledger_lines (no dedicated domain table like expenses/income have).
      // Pick out the non-cash side of each balanced pair to display.
      final calRows = await db
          .customSelect(
            '''
            SELECT je.id AS je_id, je.entry_date AS entry_date,
                   je.description AS je_description, je.source_type AS source_type,
                   a.name AS account_name, ll.debit AS debit, ll.credit AS credit
            FROM journal_entries je
            INNER JOIN ledger_lines ll ON ll.journal_entry_id = je.id
            INNER JOIN accounts a ON a.id = ll.account_id
            WHERE je.business_id = ?
              AND je.entry_date >= ? AND je.entry_date < ?
              AND (
                (je.source_type = 'capital' AND a.type = 'equity') OR
                (je.source_type = 'asset' AND a.type = 'asset' AND a.is_payment_account = 0) OR
                (je.source_type = 'liability' AND a.type = 'liability')
              )
            ORDER BY je.entry_date DESC
            ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .get();

      final calEntries = calRows.map((row) {
        final sourceType = row.read<String>('source_type');
        final type = switch (sourceType) {
          'capital' => JournalEntryType.capital,
          'asset' => JournalEntryType.asset,
          _ => JournalEntryType.liability,
        };

        return JournalEntryRow(
          id: row.read<String>('je_id'),
          type: type,
          date: row.read<DateTime>('entry_date'),
          description: row.readNullable<String>('je_description'),
          categoryName: row.read<String>('account_name'),
          amount: row.read<int>('debit') + row.read<int>('credit'),
          status: 'completed',
        );
      });

      // Supplier purchases and payable/receivable payments live in their
      // own domain tables (mirroring expenses/income), joined here with
      // the supplier/customer name so payables/receivables show up in
      // the journal too, not just on the Suppliers/Customers pages.
      final supplierPurchaseRows = await db
          .customSelect(
            '''
            SELECT sp.id AS id, sp.purchase_date AS date, sp.amount AS amount,
                   sp.notes AS notes, sp.status AS status, s.name AS party_name
            FROM supplier_purchases sp
            INNER JOIN suppliers s ON s.id = sp.supplier_id
            WHERE sp.business_id = ?
              AND sp.purchase_date >= ? AND sp.purchase_date < ?
            ORDER BY sp.purchase_date DESC
            ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .get();

      final payablePaymentRows = await db
          .customSelect(
            '''
            SELECT pp.id AS id, pp.payment_date AS date, pp.amount AS amount,
                   pp.notes AS notes, pp.status AS status, s.name AS party_name
            FROM payable_payments pp
            INNER JOIN suppliers s ON s.id = pp.supplier_id
            WHERE pp.business_id = ?
              AND pp.payment_date >= ? AND pp.payment_date < ?
            ORDER BY pp.payment_date DESC
            ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .get();

      final receivablePaymentRows = await db
          .customSelect(
            '''
            SELECT rp.id AS id, rp.payment_date AS date, rp.amount AS amount,
                   rp.notes AS notes, rp.status AS status, c.name AS party_name
            FROM receivable_payments rp
            INNER JOIN customers c ON c.id = rp.customer_id
            WHERE rp.business_id = ?
              AND rp.payment_date >= ? AND rp.payment_date < ?
            ORDER BY rp.payment_date DESC
            ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .get();

      JournalEntryRow payableReceivableRow(
        QueryRow row,
        JournalEntryType type,
      ) {
        return JournalEntryRow(
          id: row.read<String>('id'),
          type: type,
          date: row.read<DateTime>('date'),
          description: row.readNullable<String>('notes'),
          categoryName: row.read<String>('party_name'),
          amount: row.read<int>('amount'),
          status: row.read<String>('status'),
        );
      }

      final merged = <JournalEntryRow>[
        ...expenseRows.map(
          (e) => JournalEntryRow(
            id: e.id,
            type: JournalEntryType.expense,
            date: e.expenseDate,
            description: e.description,
            categoryName: categoryName(e.categoryId),
            amount: e.amount,
            status: e.status,
            sourceExpense: e,
          ),
        ),
        ...incomeRows.map(
          (i) => JournalEntryRow(
            id: i.id,
            type: JournalEntryType.income,
            date: i.txnDate,
            description: i.description,
            categoryName: categoryName(i.categoryId),
            amount: i.amount,
            status: i.status,
            sourceIncome: i,
          ),
        ),
        ...calEntries,
        ...supplierPurchaseRows.map(
          (row) => payableReceivableRow(row, JournalEntryType.supplierPurchase),
        ),
        ...payablePaymentRows.map(
          (row) => payableReceivableRow(row, JournalEntryType.payablePayment),
        ),
        ...receivablePaymentRows.map(
          (row) =>
              payableReceivableRow(row, JournalEntryType.receivablePayment),
        ),
      ];

      merged.sort((a, b) => b.date.compareTo(a.date));

      return merged;
    });

// ============================================================
// JOURNAL ENTRY PAGE
// ============================================================

class JournalEntryPage extends ConsumerWidget {
  const JournalEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(selectedJournalDateFilterProvider);
    final entriesAsync = ref.watch(journalEntriesProvider(filter));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(context, filter, ref),
      body: entriesAsync.when(
        loading: () => const _JournalLoadingState(),
        error: (error, stack) => _JournalErrorState(
          error: error,
          onRetry: () {
            ref.invalidate(journalEntriesProvider(filter));
          },
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return _JournalEmptyState(
              onAdd: () => _openNewTransaction(context),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(journalEntriesProvider(filter));

              await ref.read(journalEntriesProvider(filter).future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(child: _JournalSummary(entries: entries)),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final groups = _groupByDay(entries);
                      final group = groups[index];

                      return _DaySection(group: group);
                    }, childCount: _groupByDay(entries).length),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _buildFab(context),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    TransactionDateFilter filter,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: colors.surface,
      surfaceTintColor: colors.surfaceTint,
      titleSpacing: 20,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Journal Entry',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            ref
                .watch(businessProfileProvider)
                .maybeWhen(
                  data: (value) => value.name,
                  orElse: () => 'Your complete transaction history',
                ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        _JournalDateFilterButton(filter: filter, ref: ref),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFab(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FloatingActionButton(
      heroTag: 'journal-entry-add',
      elevation: 3,
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      onPressed: () => _openAddEntryMenu(context),
      child: const Icon(Icons.add_rounded),
    );
  }

  void _openNewTransaction(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionPage()),
    );
  }

  void _openAddEntryMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.south_west_rounded,
                color: Colors.green,
              ),
              title: const Text('Income'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openNewTransaction(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.north_east_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Expense'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openNewTransaction(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined, color: Colors.blue),
              title: const Text('Capital'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openSheet(context, const AddCapitalSheet());
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: Colors.purple,
              ),
              title: const Text('Asset'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openSheet(context, const AddAssetSheet());
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.request_quote_outlined,
                color: Colors.orange,
              ),
              title: const Text('Liability'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openSheet(context, const AddLiabilitySheet());
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  List<_DayGroup> _groupByDay(List<JournalEntryRow> entries) {
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<JournalEntryRow>>{};

    for (final entry in entries) {
      final date = DateTime(entry.date.year, entry.date.month, entry.date.day);

      final label = date == today
          ? 'Today'
          : date == yesterday
          ? 'Yesterday'
          : DateFormat('EEEE, MMMM d, yyyy').format(date);

      groups.putIfAbsent(label, () => []).add(entry);
    }

    return groups.entries
        .map((entry) => _DayGroup(label: entry.key, entries: entry.value))
        .toList();
  }
}

class _JournalDateFilterButton extends StatelessWidget {
  final TransactionDateFilter filter;
  final WidgetRef ref;

  const _JournalDateFilterButton({required this.filter, required this.ref});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TransactionDatePreset>(
      initialValue: filter.preset,
      tooltip: 'Filter entries by date',
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
          ref.read(selectedJournalDateFilterProvider.notifier).state =
              TransactionDateFilter.custom(selectedRange);
          return;
        }

        ref.read(selectedJournalDateFilterProvider.notifier).state =
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
    );
  }
}

// ============================================================
// SUMMARY
// ============================================================

class _JournalSummary extends StatelessWidget {
  final List<JournalEntryRow> entries;

  const _JournalSummary({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final income = entries
        .where((e) => e.type == JournalEntryType.income)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final expense = entries
        .where((e) => e.type == JournalEntryType.expense)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final capital = entries
        .where((e) => e.type == JournalEntryType.capital)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final asset = entries
        .where((e) => e.type == JournalEntryType.asset)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final liability = entries
        .where((e) => e.type == JournalEntryType.liability)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final balance = income - expense;

    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primary, colors.primaryContainer],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: colors.onPrimary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: colors.onPrimary,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Transaction overview',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Net movement',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimary.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${balance >= 0 ? '+' : '-'}${currency.format(balance.abs() / 100)}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entries.length} transaction${entries.length == 1 ? '' : 's'} recorded',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onPrimary.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 500;

              if (compact) {
                return Row(
                  children: [
                    Expanded(
                      child: _SummaryMetric(
                        icon: Icons.south_west_rounded,
                        label: 'Income',
                        amount: income,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryMetric(
                        icon: Icons.north_east_rounded,
                        label: 'Expenses',
                        amount: expense,
                        color: colors.error,
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _SummaryMetric(
                      icon: Icons.south_west_rounded,
                      label: 'Income',
                      amount: income,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryMetric(
                      icon: Icons.north_east_rounded,
                      label: 'Expenses',
                      amount: expense,
                      color: colors.error,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 500;

              final metrics = [
                _SummaryMetric(
                  icon: Icons.savings_outlined,
                  label: 'Capital',
                  amount: capital,
                  color: Colors.blue,
                ),
                _SummaryMetric(
                  icon: Icons.inventory_2_outlined,
                  label: 'Assets',
                  amount: asset,
                  color: Colors.purple,
                ),
                _SummaryMetric(
                  icon: Icons.request_quote_outlined,
                  label: 'Liabilities',
                  amount: liability,
                  color: Colors.orange.shade800,
                ),
              ];

              if (compact) {
                return Column(
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: metrics[i]),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: metrics[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final int amount;
  final Color color;

  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    currency.format(amount / 100),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DAY GROUP
// ============================================================

class _DayGroup {
  final String label;
  final List<JournalEntryRow> entries;

  _DayGroup({required this.label, required this.entries});
}

class _DaySection extends StatelessWidget {
  final _DayGroup group;

  const _DaySection({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final income = group.entries
        .where((e) => e.type == JournalEntryType.income)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final expense = group.entries
        .where((e) => e.type == JournalEntryType.expense)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final net = income - expense;

    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --------------------------------------------------
          // DAY HEADER
          // --------------------------------------------------

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          group.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                Flexible(
                  child: Text(
                    '${net >= 0 ? '+' : '-'}${currency.format(net.abs() / 100)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: net >= 0 ? Colors.green.shade700 : colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 9),

          // --------------------------------------------------
          // TRANSACTIONS CARD
          // --------------------------------------------------
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < group.entries.length; i++) ...[
                  _JournalEntryTile(entry: group.entries[i]),
                  if (i < group.entries.length - 1)
                    Divider(
                      height: 1,
                      indent: 76,
                      endIndent: 16,
                      color: colors.outlineVariant.withValues(alpha: 0.45),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TRANSACTION TILE
// ============================================================

class _JournalEntryTile extends ConsumerWidget {
  final JournalEntryRow entry;

  const _JournalEntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final isIncome = entry.type == JournalEntryType.income;
    final isBalanceSheetEntry =
        entry.type == JournalEntryType.capital ||
        entry.type == JournalEntryType.asset ||
        entry.type == JournalEntryType.liability;
    final isReadOnlyEntry =
        entry.type == JournalEntryType.supplierPurchase ||
        entry.type == JournalEntryType.payablePayment ||
        entry.type == JournalEntryType.receivablePayment;
    final isPending = entry.status.toLowerCase() == 'pending';

    final accentColor = switch (entry.type) {
      JournalEntryType.income => Colors.green.shade700,
      JournalEntryType.expense => colors.error,
      JournalEntryType.capital => Colors.blue.shade700,
      JournalEntryType.asset => Colors.purple.shade700,
      JournalEntryType.liability => Colors.orange.shade800,
      JournalEntryType.supplierPurchase => colors.error,
      JournalEntryType.payablePayment => Colors.orange.shade800,
      JournalEntryType.receivablePayment => Colors.green.shade700,
    };

    final tileIcon = switch (entry.type) {
      JournalEntryType.income => Icons.south_west_rounded,
      JournalEntryType.expense => Icons.north_east_rounded,
      JournalEntryType.capital => Icons.savings_outlined,
      JournalEntryType.asset => Icons.inventory_2_outlined,
      JournalEntryType.liability => Icons.request_quote_outlined,
      JournalEntryType.supplierPurchase => Icons.local_shipping_outlined,
      JournalEntryType.payablePayment => Icons.payments_outlined,
      JournalEntryType.receivablePayment => Icons.savings_outlined,
    };

    // Balance-sheet rows (capital/asset/liability) and payments received
    // from customers always represent an increase, so they're always
    // shown with a '+' regardless of the income/expense sign convention.
    final isPositive =
        isIncome ||
        isBalanceSheetEntry ||
        entry.type == JournalEntryType.receivablePayment;

    final title = entry.description?.trim().isNotEmpty == true
        ? entry.description!.trim()
        : entry.categoryName;

    final amount = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    ).format(entry.amount / 100);

    final time = DateFormat('h:mm a').format(entry.date);

    // Supplier/customer payable-and-receivable activity is view + delete
    // only for now; capital/asset/liability entries edit through their
    // own sheets instead of the income/expense form.
    final isNonEditable = isReadOnlyEntry;

    return Slidable(
      key: ValueKey(entry.id),

      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: isNonEditable ? 0.22 : 0.42,
        children: [
          if (!isNonEditable)
            SlidableAction(
              onPressed: (_) => _openEdit(context),
              backgroundColor: colors.secondaryContainer,
              foregroundColor: colors.onSecondaryContainer,
              icon: Icons.edit_rounded,
              label: 'Edit',
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(18),
              ),
            ),
          SlidableAction(
            onPressed: (_) => _confirmDelete(context, ref),
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.onErrorContainer,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            borderRadius: BorderRadius.horizontal(
              left: isNonEditable ? const Radius.circular(18) : Radius.zero,
              right: const Radius.circular(18),
            ),
          ),
        ],
      ),

      child: InkWell(
        onTap: isNonEditable ? null : () => _openEdit(context),

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),

          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ============================================================
              // ICON
              // ============================================================
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(tileIcon, color: accentColor, size: 22),
              ),

              const SizedBox(width: 12),

              // ============================================================
              // DESCRIPTION + META
              // ============================================================
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _MiniPill(
                          icon: Icons.category_outlined,
                          text: entry.categoryName,
                        ),
                        _MiniPill(icon: Icons.schedule_rounded, text: time),
                        _StatusPill(pending: isPending),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ============================================================
              // AMOUNT
              // ============================================================
              SizedBox(
                width: 82,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${isPositive ? '+' : '-'}$amount',
                        maxLines: 1,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    if (!isNonEditable)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.outline,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // EDIT
  // ============================================================
  void _openEdit(BuildContext context) {
    switch (entry.type) {
      case JournalEntryType.expense:
      case JournalEntryType.income:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionPage(
              existingExpense: entry.sourceExpense,
              existingIncome: entry.sourceIncome,
            ),
          ),
        );
      case JournalEntryType.capital:
        _openSheet(context, AddCapitalSheet(journalEntryId: entry.id));
      case JournalEntryType.asset:
        _openSheet(context, AddAssetSheet(journalEntryId: entry.id));
      case JournalEntryType.liability:
        _openSheet(context, AddLiabilitySheet(journalEntryId: entry.id));
      case JournalEntryType.supplierPurchase:
      case JournalEntryType.payablePayment:
      case JournalEntryType.receivablePayment:
        break; // read-only — no edit action is wired up for these rows
    }
  }

  void _openSheet(BuildContext context, Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  // ============================================================
  // DELETE CONFIRMATION
  // ============================================================
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final colors = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: colors.onErrorContainer,
            ),
          ),

          title: const Text('Delete transaction?', textAlign: TextAlign.center),

          content: const Text(
            'This transaction will be permanently removed from your records and your balances will be updated.',
            textAlign: TextAlign.center,
          ),

          actionsAlignment: MainAxisAlignment.center,

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
              },
              child: const Text('Cancel'),
            ),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),

              onPressed: () {
                Navigator.pop(ctx, true);
              },

              icon: const Icon(Icons.delete_outline_rounded),

              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      switch (entry.type) {
        case JournalEntryType.expense:
          await ref.read(transactionServiceProvider).deleteExpense(entry.id);
        case JournalEntryType.income:
          await ref.read(transactionServiceProvider).deleteIncome(entry.id);
        case JournalEntryType.capital:
        case JournalEntryType.asset:
        case JournalEntryType.liability:
          await ref
              .read(capitalAssetLiabilityServiceProvider)
              .deleteEntry(entry.id);
          ref.invalidate(assetBalancesProvider);
          ref.invalidate(liabilityBalancesProvider);
          ref.invalidate(capitalBalanceProvider);
          ref.invalidate(accountBalancesProvider);
        case JournalEntryType.supplierPurchase:
          await ref
              .read(supplierServiceProvider)
              .deleteSupplierPurchase(entry.id);
          ref.invalidate(liabilityBalancesProvider);
          ref.invalidate(accountBalancesProvider);
        case JournalEntryType.payablePayment:
          await ref
              .read(supplierServiceProvider)
              .deletePayablePayment(entry.id);
          ref.invalidate(liabilityBalancesProvider);
          ref.invalidate(accountBalancesProvider);
        case JournalEntryType.receivablePayment:
          await ref
              .read(customerServiceProvider)
              .deleteReceivablePayment(entry.id);
          ref.invalidate(assetBalancesProvider);
          ref.invalidate(accountBalancesProvider);
      }

      ref.read(ledgerVersionProvider.notifier).state++;

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Transaction deleted'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.error,
          content: Text('Could not delete transaction: $error'),
        ),
      );
    }
  }
}
// ============================================================
// MINI PILL
// ============================================================

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 115),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// STATUS PILL
// ============================================================

class _StatusPill extends StatelessWidget {
  final bool pending;

  const _StatusPill({required this.pending});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = pending ? Colors.orange.shade700 : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pending
                ? Icons.schedule_rounded
                : Icons.check_circle_outline_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            pending ? 'Pending' : 'Completed',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EMPTY STATE
// ============================================================

class _JournalEmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _JournalEmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 42,
                  color: colors.onPrimaryContainer,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'No transactions yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Start recording your business income and expenses to keep your finances organized.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 24),

              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add first transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LOADING STATE
// ============================================================

class _JournalLoadingState extends StatelessWidget {
  const _JournalLoadingState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 3, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Loading transactions…',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ERROR STATE
// ============================================================

class _JournalErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _JournalErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 36,
                color: colors.onErrorContainer,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Couldn’t load transactions',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Something went wrong while loading your journal entries.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
