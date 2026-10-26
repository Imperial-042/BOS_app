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

import 'package:bos_application/features/transactions/domain/capital_asset_liability_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        AddLiabilitySheet,
        AddCapitalWithdrawalSheet;
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
  capitalWithdrawal,
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

  // NEW: true when this expense was created by checking out the
  // Supplies shopping cart. These must only be edited/deleted from
  // Purchase History, since that flow also reverses stock and price
  // history — deleting here would desync the two.
  final bool isSupplyPurchase;

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
    this.isSupplyPurchase = false,
  });
}

String journalEntryTypeLabel(JournalEntryType type) {
  switch (type) {
    case JournalEntryType.income:
      return 'Income';

    case JournalEntryType.expense:
      return 'Expense';

    case JournalEntryType.capital:
      return 'Capital';

    case JournalEntryType.capitalWithdrawal:
      return 'Capital Withdrawal';

    case JournalEntryType.asset:
      return 'Asset';

    case JournalEntryType.liability:
      return 'Liability';

    case JournalEntryType.supplierPurchase:
      return 'Purchase';

    case JournalEntryType.payablePayment:
      return 'Liability Payment';

    case JournalEntryType.receivablePayment:
      return 'Receivable Payment';
  }
}

// ============================================================
// PROVIDER
// ============================================================

final selectedJournalDateFilterProvider = StateProvider<TransactionDateFilter>(
  (ref) => const TransactionDateFilter.month(),
);

enum _JournalFilter {
  all('All', Icons.apps_rounded),
  income('Income', Icons.south_west_rounded),
  expense('Expenses', Icons.north_east_rounded),
  capital('Capital', Icons.savings_outlined),
  assets('Assets', Icons.inventory_2_outlined),
  liabilities('Liabilities', Icons.request_quote_outlined),
  payments('Payables & receivables', Icons.swap_horiz_rounded);

  const _JournalFilter(this.label, this.icon);

  final String label;
  final IconData icon;

  bool matches(JournalEntryType t) => switch (this) {
    _JournalFilter.all => true,
    _JournalFilter.income => t == JournalEntryType.income,
    _JournalFilter.expense => t == JournalEntryType.expense,
    _JournalFilter.capital =>
      t == JournalEntryType.capital || t == JournalEntryType.capitalWithdrawal,
    _JournalFilter.assets => t == JournalEntryType.asset,
    _JournalFilter.liabilities => t == JournalEntryType.liability,
    _JournalFilter.payments =>
      t == JournalEntryType.supplierPurchase ||
          t == JournalEntryType.payablePayment ||
          t == JournalEntryType.receivablePayment,
  };
}

class _SettlementStatus {
  final Map<String, int> appliedByTransactionId;

  const _SettlementStatus(this.appliedByTransactionId);

  bool isCompleted(String transactionId, int amount) {
    final applied = appliedByTransactionId[transactionId] ?? 0;
    return applied >= amount;
  }
}

final journalEntriesProvider =
    FutureProvider.family<List<JournalEntryRow>, TransactionDateFilter>((
      ref,
      filter,
    ) async {
      ref.watch(ledgerVersionProvider);

      final db = ref.watch(databaseProvider);
      final supplierSettlement = await _calculateSupplierSettlementStatus(db);
      final customerSettlement = await _calculateCustomerSettlementStatus(db);
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

      // Capital / Asset / Liability entries live directly in
      // journal_entries + ledger_lines.
      //
      // For assets:
      // - Paid asset  -> Dr Asset / Cr Payment Account -> Completed
      // - Credit asset -> Dr Asset / Cr Accounts Payable -> Pending
      //
      // We determine the status from the actual ledger entry instead of
      // relying on a status column that does not exist in CAL entries.

      final calRows = await db
          .customSelect(
            '''
  SELECT
    je.id AS je_id,
    je.entry_date AS entry_date,
    je.description AS je_description,
    je.source_type AS source_type,

    a.name AS account_name,

    ll.debit AS debit,
    ll.credit AS credit,

    CASE
      WHEN je.source_type = 'asset'
           AND EXISTS (
             SELECT 1
             FROM ledger_lines ap
             WHERE ap.journal_entry_id = je.id
               AND ap.account_id = ?
               AND ap.credit > 0
           )
      THEN 'pending'
      ELSE 'completed'
    END AS display_status

  FROM journal_entries je

  INNER JOIN ledger_lines ll
    ON ll.journal_entry_id = je.id

  INNER JOIN accounts a
    ON a.id = ll.account_id

  WHERE je.business_id = ?
    AND je.entry_date >= ?
    AND je.entry_date < ?

    AND (
      (
        je.source_type = 'capital'
        AND a.type = 'equity'
      )

      OR

      (
        je.source_type = 'asset'
        AND a.type = 'asset'
        AND a.is_payment_account = 0
      )

      OR

      (
        je.source_type = 'liability'
        AND a.type = 'liability'
      )
    )

  ORDER BY je.entry_date DESC
  ''',
            variables: [
              Variable.withString(
                CapitalAssetLiabilityService.payableAccountId(
                  kCurrentBusinessId,
                ),
              ),
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .get();

      final calEntries = calRows.map((row) {
        final sourceType = row.read<String>('source_type');
        final debit = row.read<int>('debit');
        final credit = row.read<int>('credit');

        // For 'capital' rows, which side the equity account sits on tells us
        // whether this was money coming in or going out:
        //   contribution -> Dr payment account / Cr equity -> credit > 0
        //   withdrawal   -> Dr equity / Cr payment account  -> debit > 0
        final type = switch (sourceType) {
          'capital' =>
            debit > 0
                ? JournalEntryType.capitalWithdrawal
                : JournalEntryType.capital,
          'asset' => JournalEntryType.asset,
          'liability' => JournalEntryType.liability,
          _ => JournalEntryType.liability,
        };

        final amount = debit > 0 ? debit : credit;

        return JournalEntryRow(
          id: row.read<String>('je_id'),
          type: type,
          date: row.read<DateTime>('entry_date'),
          description: row.readNullable<String>('je_description'),
          categoryName: row.read<String>('account_name'),
          amount: amount,
          status: row.read<String>('display_status'),
        );
      });

      // Supplier purchases and payable/receivable payments live in their
      // own domain tables (mirroring expenses/income), joined here with
      // the supplier/customer name so payables/receivables show up in
      // the journal too, not just on the Suppliers/Customers pages.
      final supplierPurchaseRows = await db
          .customSelect(
            '''
      SELECT
        sp.id AS id,
        sp.purchase_date AS date,
        sp.amount AS amount,
        sp.notes AS notes,
        sp.status AS status,
        sp.is_on_credit AS is_on_credit,
        s.name AS party_name
      FROM supplier_purchases sp
      INNER JOIN suppliers s
        ON s.id = sp.supplier_id
      WHERE sp.business_id = ?
        AND sp.purchase_date >= ?
        AND sp.purchase_date < ?
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
      SELECT
        pp.id AS id,
        pp.payment_date AS date,
        pp.amount AS amount,
        pp.notes AS notes,
        pp.status AS status,
        s.name AS party_name
      FROM payable_payments pp
      INNER JOIN suppliers s
        ON s.id = pp.supplier_id
      WHERE pp.business_id = ?
        AND pp.payment_date >= ?
        AND pp.payment_date < ?
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
      SELECT
        rp.id AS id,
        rp.payment_date AS date,
        rp.amount AS amount,
        rp.notes AS notes,
        rp.status AS status,
        c.name AS party_name
      FROM receivable_payments rp
      INNER JOIN customers c
        ON c.id = rp.customer_id
      WHERE rp.business_id = ?
        AND rp.payment_date >= ?
        AND rp.payment_date < ?
      ORDER BY rp.payment_date DESC
      ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .get();

      JournalEntryRow supplierPurchaseRow(QueryRow row) {
        final id = row.read<String>('id');
        final amount = row.read<int>('amount');
        final isOnCredit = row.read<bool>('is_on_credit');

        final status = !isOnCredit
            ? 'completed'
            : supplierSettlement.isCompleted(id, amount)
            ? 'completed'
            : 'pending';

        return JournalEntryRow(
          id: id,
          type: JournalEntryType.supplierPurchase,
          date: row.read<DateTime>('date'),
          description: row.readNullable<String>('notes'),
          categoryName: row.read<String>('party_name'),
          amount: amount,
          status: status,
        );
      }

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

          // These are actual payment transactions.
          status: row.read<String>('status'),
        );
      }

      // Expense ids that came from a Supplies checkout (ShoppingCarts.expenseId).
      // These are managed exclusively from Purchase History.
      final linkedSupplyExpenseIds =
          (await (db.select(db.shoppingCarts)..where(
                    (c) =>
                        c.businessId.equals(kCurrentBusinessId) &
                        c.expenseId.isNotNull(),
                  ))
                  .get())
              .map((c) => c.expenseId!)
              .toSet();

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
            isSupplyPurchase: linkedSupplyExpenseIds.contains(e.id),
          ),
        ),
        ...incomeRows.map((i) {
          final isCreditSale =
              i.customerId != null && i.paymentAccountId == null;

          final status = isCreditSale
              ? customerSettlement.isCompleted(i.id, i.amount)
                    ? 'completed'
                    : 'pending'
              : i.status;

          return JournalEntryRow(
            id: i.id,
            type: JournalEntryType.income,
            date: i.txnDate,
            description: i.description,
            categoryName: categoryName(i.categoryId),
            amount: i.amount,
            status: status,
            sourceIncome: i,
          );
        }),
        ...calEntries,
        ...supplierPurchaseRows.map(supplierPurchaseRow),
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
Future<_SettlementStatus> _calculateCustomerSettlementStatus(
  AppDatabase db,
) async {
  // ------------------------------------------------------------
  // Credit sales = Accounts Receivable
  // ------------------------------------------------------------
  final sales = await db
      .customSelect(
        '''
    SELECT
      it.id AS sale_id,
      it.customer_id AS customer_id,
      it.amount AS amount,
      it.txn_date AS transaction_date
    FROM income_transactions it
    WHERE it.business_id = ?
      AND it.customer_id IS NOT NULL
      AND it.payment_account_id IS NULL
    ORDER BY it.customer_id, it.txn_date, it.id
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .get();

  // ------------------------------------------------------------
  // Actual customer receipts
  // ------------------------------------------------------------
  final payments = await db
      .customSelect(
        '''
    SELECT
      rp.id AS payment_id,
      rp.customer_id AS customer_id,
      rp.amount AS amount,
      rp.payment_date AS transaction_date
    FROM receivable_payments rp
    WHERE rp.business_id = ?
      AND rp.status = 'completed'
      AND rp.is_on_credit = 0
    ORDER BY rp.customer_id, rp.payment_date, rp.id
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .get();

  final applied = <String, int>{};

  // Group credit sales by customer.
  final salesByCustomer = <String, List<QueryRow>>{};

  for (final sale in sales) {
    final customerId = sale.read<String>('customer_id');

    salesByCustomer.putIfAbsent(customerId, () => <QueryRow>[]);

    salesByCustomer[customerId]!.add(sale);
  }

  // Group payments by customer.
  final paymentsByCustomer = <String, List<QueryRow>>{};

  for (final payment in payments) {
    final customerId = payment.read<String>('customer_id');

    paymentsByCustomer.putIfAbsent(customerId, () => <QueryRow>[]);

    paymentsByCustomer[customerId]!.add(payment);
  }

  // ------------------------------------------------------------
  // FIFO settlement
  //
  // Oldest unpaid credit sale receives the payment first.
  // ------------------------------------------------------------
  for (final entry in salesByCustomer.entries) {
    final customerId = entry.key;
    final customerSales = entry.value;

    final customerPayments = paymentsByCustomer[customerId] ?? <QueryRow>[];

    var paymentPool = 0;
    var saleIndex = 0;

    for (final payment in customerPayments) {
      paymentPool += payment.read<int>('amount');

      while (paymentPool > 0 && saleIndex < customerSales.length) {
        final sale = customerSales[saleIndex];

        final saleId = sale.read<String>('sale_id');
        final saleAmount = sale.read<int>('amount');

        final alreadyApplied = applied[saleId] ?? 0;

        final remaining = saleAmount - alreadyApplied;

        if (remaining <= 0) {
          saleIndex++;
          continue;
        }

        final allocation = paymentPool < remaining ? paymentPool : remaining;

        applied[saleId] = alreadyApplied + allocation;

        paymentPool -= allocation;

        if (allocation >= remaining) {
          saleIndex++;
        }
      }
    }
  }

  return _SettlementStatus(applied);
}

Future<_SettlementStatus> _calculateSupplierSettlementStatus(
  AppDatabase db,
) async {
  final purchases = await db
      .customSelect(
        '''
    SELECT
      sp.id AS purchase_id,
      sp.supplier_id AS supplier_id,
      sp.amount AS amount,
      sp.purchase_date AS transaction_date
    FROM supplier_purchases sp
    WHERE sp.business_id = ?
      AND sp.is_on_credit = 1
    ORDER BY sp.supplier_id, sp.purchase_date, sp.id
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .get();

  final payments = await db
      .customSelect(
        '''
    SELECT
      pp.id AS payment_id,
      pp.supplier_id AS supplier_id,
      pp.amount AS amount,
      pp.payment_date AS transaction_date
    FROM payable_payments pp
    WHERE pp.business_id = ?
      AND pp.status = 'completed'
    ORDER BY pp.supplier_id, pp.payment_date, pp.id
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .get();

  final applied = <String, int>{};

  // Group purchases by supplier.
  final purchasesBySupplier = <String, List<QueryRow>>{};

  for (final purchase in purchases) {
    final supplierId = purchase.read<String>('supplier_id');

    purchasesBySupplier.putIfAbsent(supplierId, () => <QueryRow>[]);

    purchasesBySupplier[supplierId]!.add(purchase);
  }

  // Group payments by supplier.
  final paymentsBySupplier = <String, List<QueryRow>>{};

  for (final payment in payments) {
    final supplierId = payment.read<String>('supplier_id');

    paymentsBySupplier.putIfAbsent(supplierId, () => <QueryRow>[]);

    paymentsBySupplier[supplierId]!.add(payment);
  }

  for (final entry in purchasesBySupplier.entries) {
    final supplierId = entry.key;
    final supplierPurchases = entry.value;
    final supplierPayments = paymentsBySupplier[supplierId] ?? <QueryRow>[];

    var paymentPool = 0;

    var purchaseIndex = 0;

    for (final payment in supplierPayments) {
      paymentPool += payment.read<int>('amount');

      while (paymentPool > 0 && purchaseIndex < supplierPurchases.length) {
        final purchase = supplierPurchases[purchaseIndex];

        final purchaseId = purchase.read<String>('purchase_id');

        final purchaseAmount = purchase.read<int>('amount');

        final alreadyApplied = applied[purchaseId] ?? 0;

        final remaining = purchaseAmount - alreadyApplied;

        if (remaining <= 0) {
          purchaseIndex++;
          continue;
        }

        final allocation = paymentPool < remaining ? paymentPool : remaining;

        applied[purchaseId] = alreadyApplied + allocation;

        paymentPool -= allocation;

        if (allocation >= remaining) {
          purchaseIndex++;
        }
      }
    }
  }

  return _SettlementStatus(applied);
}

class JournalEntryPage extends ConsumerStatefulWidget {
  const JournalEntryPage({super.key});

  @override
  ConsumerState<JournalEntryPage> createState() => _JournalEntryPageState();
}

class _JournalEntryPageState extends ConsumerState<JournalEntryPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _JournalFilter _typeFilter = _JournalFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isFiltering =>
      _query.trim().isNotEmpty || _typeFilter != _JournalFilter.all;

  void _clearAll() {
    _searchController.clear();
    setState(() {
      _query = '';
      _typeFilter = _JournalFilter.all;
    });
  }

  List<JournalEntryRow> _apply(List<JournalEntryRow> entries) {
    final q = _query.trim().toLowerCase();
    final qNum = q.replaceAll(RegExp(r'[₱,\s]'), '');

    return entries.where((e) {
      if (!_typeFilter.matches(e.type)) return false;
      if (q.isEmpty) return true;

      final amountText = (e.amount / 100).toStringAsFixed(2);
      return (e.description ?? '').toLowerCase().contains(q) ||
          e.categoryName.toLowerCase().contains(q) ||
          journalEntryTypeLabel(e.type).toLowerCase().contains(q) ||
          e.status.toLowerCase().contains(q) ||
          (qNum.isNotEmpty && amountText.contains(qNum));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(selectedJournalDateFilterProvider);
    final entriesAsync = ref.watch(journalEntriesProvider(filter));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(context, filter),
      body: Column(
        children: [
          _buildSearchHeader(context, entriesAsync.value ?? const []),
          Expanded(
            child: entriesAsync.when(
              loading: () => const _JournalLoadingState(),
              error: (error, stack) => _JournalErrorState(
                error: error,
                onRetry: () => ref.invalidate(journalEntriesProvider(filter)),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return _JournalEmptyState(
                    onAdd: () => _showEntryTypePicker(context),
                  );
                }

                final filtered = _apply(entries);
                final groups = _groupByDay(filtered);

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
                      if (!_isFiltering)
                        SliverToBoxAdapter(
                          child: _JournalSummary(entries: entries),
                        )
                      else
                        SliverToBoxAdapter(
                          child: _ResultsBar(
                            count: filtered.length,
                            onClear: _clearAll,
                          ),
                        ),
                      if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoResultsState(onClear: _clearAll),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  _DaySection(group: groups[index]),
                              childCount: groups.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'journal-entry-add',
        onPressed: () => _showEntryTypePicker(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New entry'),
      ),
    );
  }

  // ----------------------------------------------------------
  // SEARCH + FILTER CHIPS
  // ----------------------------------------------------------

  Widget _buildSearchHeader(
    BuildContext context,
    List<JournalEntryRow> entries,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    int countFor(_JournalFilter f) =>
        entries.where((e) => f.matches(e.type)).length;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search description, category, amount…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: colors.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _JournalFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _JournalFilter.values[i];
                final selected = f == _typeFilter;
                final count = countFor(f);
                final showCount = f != _JournalFilter.all && count > 0;

                return ChoiceChip(
                  showCheckmark: false,
                  selected: selected,
                  avatar: Icon(
                    f.icon,
                    size: 16,
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  label: Text(showCount ? '${f.label} · $count' : f.label),
                  onSelected: (_) => setState(() => _typeFilter = f),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    TransactionDateFilter filter,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.surface,
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
        .map((e) => _DayGroup(label: e.key, entries: e.value))
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
// ENTRY TYPE PICKER
// ============================================================

void _pushTransaction(BuildContext context, {bool income = false}) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TransactionPage(initialIsIncome: income)),
  );
}

void _openFormSheet(BuildContext context, Widget sheet) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => sheet,
  );
}

class _EntryOption {
  const _EntryOption({
    required this.title,
    required this.hint,
    required this.icon,
    required this.color,
    required this.open,
  });

  final String title;
  final String hint;
  final IconData icon;
  final Color color;
  final void Function(BuildContext context) open;
}

void _showEntryTypePicker(BuildContext context) {
  final sections = <(String, List<_EntryOption>)>[
    (
      'Everyday',
      [
        _EntryOption(
          title: 'Income',
          hint: 'Sales or money you received',
          icon: Icons.south_west_rounded,
          color: Colors.green.shade700,
          open: (c) => _pushTransaction(c, income: true),
        ),
        _EntryOption(
          title: 'Expense',
          hint: 'Bills, supplies and spending',
          icon: Icons.north_east_rounded,
          color: Theme.of(context).colorScheme.error,
          open: (c) => _pushTransaction(c),
        ),
      ],
    ),
    (
      'Owner funds',
      [
        _EntryOption(
          title: 'Capital',
          hint: 'Money you put into the business',
          icon: Icons.savings_outlined,
          color: Colors.blue.shade700,
          open: (c) => _openFormSheet(c, const AddCapitalSheet()),
        ),
        _EntryOption(
          title: 'Capital withdrawal',
          hint: 'Money you take out as the owner',
          icon: Icons.money_off_rounded,
          color: Colors.deepOrange.shade700,
          open: (c) => _openFormSheet(c, const AddCapitalWithdrawalSheet()),
        ),
      ],
    ),
    (
      'Balance sheet',
      [
        _EntryOption(
          title: 'Asset',
          hint: 'Equipment or property you own',
          icon: Icons.inventory_2_outlined,
          color: Colors.purple.shade700,
          open: (c) => _openFormSheet(c, const AddAssetSheet()),
        ),
        _EntryOption(
          title: 'Liability',
          hint: 'Loans or amounts you owe',
          icon: Icons.request_quote_outlined,
          color: Colors.orange.shade800,
          open: (c) => _openFormSheet(c, const AddLiabilitySheet()),
        ),
      ],
    ),
  ];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What would you like to record?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick the type that best matches the money movement.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            for (final (title, options) in sections) ...[
              const SizedBox(height: 20),
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final width = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final o in options)
                        SizedBox(
                          width: width,
                          child: _EntryOptionCard(
                            option: o,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              o.open(context);
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 20,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Not sure? Money from customers is Income. Money you '
                      'put in yourself is Capital. Things you buy to keep '
                      'using, like a freezer, are Assets.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSecondaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _EntryOptionCard extends StatelessWidget {
  const _EntryOptionCard({required this.option, required this.onTap});

  final _EntryOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: option.color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: option.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(option.icon, color: option.color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                option.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                option.hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultsBar extends StatelessWidget {
  const _ResultsBar({required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count result${count == 1 ? '' : 's'}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 36,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No matching entries',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different word, amount or type. The date range at the '
              'top also limits what can be found.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SUMMARY
// ============================================================

class _JournalSummary extends ConsumerWidget {
  final List<JournalEntryRow> entries;

  const _JournalSummary({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final assetBalancesAsync = ref.watch(assetBalancesProvider);
    final liabilityBalancesAsync = ref.watch(liabilityBalancesProvider);
    final capitalBalanceAsync = ref.watch(capitalBalanceProvider);

    final income = entries
        .where((e) => e.type == JournalEntryType.income)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final expense = entries
        .where((e) => e.type == JournalEntryType.expense)
        .fold<int>(0, (sum, e) => sum + e.amount);

    final capital = capitalBalanceAsync.value ?? 0;

    final asset =
        assetBalancesAsync.value?.fold<int>(
          0,
          (sum, entry) => sum + entry.balance,
        ) ??
        0;

    final liability =
        liabilityBalancesAsync.value?.fold<int>(
          0,
          (sum, entry) => sum + entry.balance,
        ) ??
        0;

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

  void _showSupplyPurchaseNotice(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'This purchase is managed from Supplies → Purchase history, '
            'so stock and price records stay in sync.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final isIncome = entry.type == JournalEntryType.income;
    final isBalanceSheetEntry =
        entry.type == JournalEntryType.capital ||
        entry.type == JournalEntryType.capitalWithdrawal ||
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
      JournalEntryType.capitalWithdrawal => Colors.deepOrange.shade700,
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
      JournalEntryType.capitalWithdrawal => Icons.money_off_rounded,
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
        (isBalanceSheetEntry &&
            entry.type != JournalEntryType.capitalWithdrawal) ||
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

    // Supply-purchase expenses are locked entirely — no edit, no delete —
    // because Purchase History's delete flow also reverses stock and
    // price history, which deleting here would bypass.
    final isSupplyPurchase = entry.isSupplyPurchase;
    final isNonEditable = isReadOnlyEntry || isSupplyPurchase;

    return Slidable(
      key: ValueKey(entry.id),

      endActionPane: isSupplyPurchase
          ? null
          : ActionPane(
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
                    left: isNonEditable
                        ? const Radius.circular(18)
                        : Radius.zero,
                    right: const Radius.circular(18),
                  ),
                ),
              ],
            ),

      child: InkWell(
        onTap: isSupplyPurchase
            ? () => _showSupplyPurchaseNotice(context)
            : (isNonEditable ? null : () => _openEdit(context)),

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
                        if (isSupplyPurchase)
                          const _MiniPill(
                            icon: Icons.lock_outline_rounded,
                            text: 'From Purchase',
                          ),
                        _TypePill(
                          text: journalEntryTypeLabel(entry.type),
                          color: accentColor,
                        ),
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
      case JournalEntryType.capitalWithdrawal:
        _openSheet(
          context,
          AddCapitalWithdrawalSheet(journalEntryId: entry.id),
        );
      case JournalEntryType.asset:
        _openSheet(context, AddAssetSheet(journalEntryId: entry.id));
      case JournalEntryType.liability:
        _openSheet(context, AddLiabilitySheet(journalEntryId: entry.id));
      case JournalEntryType.supplierPurchase:
      case JournalEntryType.payablePayment:
      case JournalEntryType.receivablePayment:
        break;
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
        case JournalEntryType.capitalWithdrawal:
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

class _TypePill extends StatelessWidget {
  final String text;
  final Color color;

  const _TypePill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
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
