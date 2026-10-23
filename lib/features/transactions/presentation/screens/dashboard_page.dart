// lib/features/transactions/presentation/screens/dashboard_page.dart
//
// The business-at-a-glance screen.
//
//   * Responsive: 1 column on phones, 2 on tablets, up to 3-4 on desktop.
//     Every card sizes to its content, so nothing overflows at large text.
//   * Period chips with previous-period comparison (% change badges).
//   * Hero net-profit card, KPI tiles with sparklines, smart insights.
//   * Interactive trend chart (Both / Income / Expense / Net).
//   * Tappable donut charts for income & expense categories.
//   * POS analytics: top sellers, cashier leaderboard, sales by hour.
//   * Balance-sheet strip and recent activity.
//   * Pull-to-refresh (also nudges a sync).
//
// Requires: fl_chart, intl, flutter_riverpod, drift.

import 'dart:async';
import 'dart:math' as math;

import 'package:bos_application/core/auth/auth_providers.dart'
    show currentUserProvider;
import 'package:bos_application/core/auth/authorization_providers.dart'
    show authenticatedUserIdProvider, selectedBusinessIdProvider;
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/sync/sync_coordinator.dart';
import 'package:bos_application/features/transactions/domain/capital_asset_liability_service.dart';
import 'package:bos_application/features/transactions/domain/sales_analytics.dart';
import 'package:bos_application/main.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/cashflow_page.dart'
    show
        accountBalancesProvider,
        capitalBalanceProvider,
        assetBalancesProvider,
        liabilityBalancesProvider;
import '../../../transactions/presentation/screens/journal_entry_page.dart'
    show journalEntriesProvider, JournalEntryRow, JournalEntryType;
import '../../../transactions/presentation/screens/transaction_page.dart'
    show businessProfileProvider, ledgerVersionProvider, kCurrentBusinessId;
import '../providers/transaction_date_filter.dart';

// ============================================================
// LIVE UPDATES
// ============================================================

const _dashboardTables = <String>{
  'income_transactions',
  'expenses',
  'categories',
  'accounts',
  'account_transfers',
  'receivable_payments',
  'payable_payments',
  'supplier_purchases',
  'journal_entries',
  'ledger_lines',
  'pos_sales',
  'pos_sale_items',
  'pos_sale_payments',
  'supplies',
  'inventory_movements',
  'businesses',
};

/// Watches the local database and bumps [ledgerVersionProvider] whenever a
/// dashboard-relevant table changes (local write, POS, or cloud pull).
final dashboardLiveUpdatesProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
  Timer? timer;
  var dirty = false;

  void flush() {
    timer = null;
    if (SyncCoordinator.anyActive) {
      timer = Timer(const Duration(milliseconds: 500), flush);
      return;
    }
    if (!dirty) return;
    dirty = false;
    ref.read(ledgerVersionProvider.notifier).state++;
  }

  final sub = db.tableUpdates().listen((updates) {
    if (!updates.any((u) => _dashboardTables.contains(u.table))) return;
    dirty = true;
    timer ??= Timer(const Duration(milliseconds: 800), flush);
  });

  ref.onDispose(() {
    timer?.cancel();
    sub.cancel();
  });
});

// ============================================================
// FORMATTING
// ============================================================

String _peso(int cents, {bool compact = false}) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  if (compact && abs >= 100000 * 100) {
    return '$sign₱${NumberFormat.compact().format(abs / 100)}';
  }
  return '$sign₱${NumberFormat('#,##0.00').format(abs / 100)}';
}

String _qty(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

String _hourLabel(int h) => DateFormat.j().format(DateTime(2000, 1, 1, h));

/// "Milk, Sugar and 3 more"
String _nameList(List<String> names, {int show = 2}) {
  if (names.isEmpty) return '';
  if (names.length <= show) {
    return names.length == 1
        ? names.first
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }
  final rest = names.length - show;
  return '${names.take(show).join(', ')} and $rest more';
}

// ============================================================
// PERIOD
// ============================================================

final selectedPeriodProvider = StateProvider<TransactionDateFilter>(
  (ref) => const TransactionDateFilter.month(),
);

// ============================================================
// MODELS
// ============================================================

class CategoryTotal {
  final String name;
  final int total;
  const CategoryTotal({required this.name, required this.total});
}

class DaySummary {
  final DateTime date;
  final int income;
  final int expense;
  const DaySummary({
    required this.date,
    required this.income,
    required this.expense,
  });
}

// ============================================================
// PROVIDERS
// ============================================================

Future<({int income, int expense})> _totalsFor(
  AppDatabase db,
  DateTime start,
  DateTime end,
) async {
  final incomeRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(amount), 0) AS total FROM income_transactions
    WHERE business_id = ? AND status = 'completed' AND txn_date >= ? AND txn_date < ?
    ''',
        variables: [
          Variable.withString(kCurrentBusinessId),
          Variable.withDateTime(start),
          Variable.withDateTime(end),
        ],
      )
      .getSingle();

  final expenseRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(amount), 0) AS total FROM expenses
    WHERE business_id = ? AND status = 'completed' AND expense_date >= ? AND expense_date < ?
    ''',
        variables: [
          Variable.withString(kCurrentBusinessId),
          Variable.withDateTime(start),
          Variable.withDateTime(end),
        ],
      )
      .getSingle();

  return (
    income: incomeRow.read<int>('total'),
    expense: expenseRow.read<int>('total'),
  );
}

final periodTotalsProvider =
    FutureProvider.family<({int income, int expense}), TransactionDateFilter>((
      ref,
      filter,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final range = filter.range;
      return _totalsFor(db, range.start, range.end);
    });

/// Totals for the period immediately before [filter] (same length).
final previousTotalsProvider =
    FutureProvider.family<({int income, int expense}), TransactionDateFilter>((
      ref,
      filter,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final range = filter.range;
      final length = range.end.difference(range.start);
      return _totalsFor(db, range.start.subtract(length), range.start);
    });

final categoryBreakdownProvider =
    FutureProvider.family<
      List<CategoryTotal>,
      (String txnType, TransactionDateFilter filter)
    >((ref, args) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final (txnType, filter) = args;
      final range = filter.range;
      final table = txnType == 'income' ? 'income_transactions' : 'expenses';
      final dateCol = txnType == 'income' ? 'txn_date' : 'expense_date';

      final rows = await db
          .customSelect(
            '''
    SELECT c.name AS category_name, SUM(t.amount) AS total
    FROM $table t
    JOIN categories c ON c.id = t.category_id
    WHERE t.business_id = ? AND t.status = 'completed' AND t.$dateCol >= ? AND t.$dateCol < ?
    GROUP BY c.name
    ORDER BY total DESC
    ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .get();

      return rows
          .map(
            (r) => CategoryTotal(
              name: r.read<String>('category_name'),
              total: r.read<int>('total'),
            ),
          )
          .toList();
    });

final trendProvider =
    FutureProvider.family<List<DaySummary>, TransactionDateFilter>((
      ref,
      filter,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);

      final range = filter.range;
      final start = range.start;
      final endExclusive = range.end;
      final monthly =
          filter.preset == TransactionDatePreset.year ||
          filter.preset == TransactionDatePreset.lastYear;

      Future<List<QueryRow>> load(String table, String dateCol) {
        return db
            .customSelect(
              '''
    SELECT $dateCol AS d, amount FROM $table
    WHERE business_id = ? AND status = 'completed'
      AND $dateCol >= ? AND $dateCol < ?
    ORDER BY $dateCol
    ''',
              variables: [
                Variable.withString(kCurrentBusinessId),
                Variable.withDateTime(start),
                Variable.withDateTime(endExclusive),
              ],
            )
            .get();
      }

      final incomeRows = await load('income_transactions', 'txn_date');
      final expenseRows = await load('expenses', 'expense_date');

      final fmt = DateFormat(monthly ? 'yyyy-MM' : 'yyyy-MM-dd');
      final incomeByDay = <String, int>{};
      final expenseByDay = <String, int>{};

      for (final row in incomeRows) {
        final date = row.readNullable<DateTime>('d');
        if (date == null) continue;
        final key = fmt.format(date);
        incomeByDay[key] =
            (incomeByDay[key] ?? 0) + (row.readNullable<int>('amount') ?? 0);
      }
      for (final row in expenseRows) {
        final date = row.readNullable<DateTime>('d');
        if (date == null) continue;
        final key = fmt.format(date);
        expenseByDay[key] =
            (expenseByDay[key] ?? 0) + (row.readNullable<int>('amount') ?? 0);
      }

      final pointCount = monthly
          ? (endExclusive.year - start.year) * 12 +
                endExclusive.month -
                start.month
          : endExclusive.difference(start).inDays;

      return List.generate(math.max(pointCount, 0), (index) {
        final date = monthly
            ? DateTime(start.year, start.month + index)
            : start.add(Duration(days: index));
        final key = fmt.format(date);
        return DaySummary(
          date: date,
          income: incomeByDay[key] ?? 0,
          expense: expenseByDay[key] ?? 0,
        );
      });
    });

/// POS analytics for the period (top sellers, cashiers, hourly sales).
final dashboardSalesReportProvider =
    FutureProvider.family<SalesReport, TransactionDateFilter>((
      ref,
      filter,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final names = await ref.watch(cashierNamesProvider.future);
      final branchId = ref.watch(selectedBranchIdProvider);
      final isMain = branchId == AppDatabase.mainBranchId(kCurrentBusinessId);
      final range = filter.range;

      final sales =
          await (db.select(db.posSales)..where(
                (s) =>
                    s.businessId.equals(kCurrentBusinessId) &
                    (isMain
                        ? (s.branchId.equals(branchId) | s.branchId.isNull())
                        : s.branchId.equals(branchId)) &
                    s.saleDate.isBiggerOrEqualValue(range.start) &
                    s.saleDate.isSmallerThanValue(range.end),
              ))
              .get();

      final ids = sales.map((s) => s.id).toList();
      final items = ids.isEmpty
          ? <PosSaleItem>[]
          : await (db.select(
              db.posSaleItems,
            )..where((i) => i.saleId.isIn(ids))).get();

      return buildSalesReport(
        sales: sales,
        items: items,
        productCategory: const <String, String?>{},
        categoryNames: const <String, String>{},
        cashierNames: names,
      );
    });

/// Stock health snapshot for the dashboard insights.
class InventoryHealth {
  const InventoryHealth({
    required this.total,
    required this.out,
    required this.low,
    required this.over,
    required this.valueCents,
    required this.reorderCents,
    required this.outNames,
    required this.lowNames,
  });

  final int total;
  final int out;
  final int low;
  final int over;
  final int valueCents;
  final int reorderCents;
  final List<String> outNames;
  final List<String> lowNames;

  int get reorderCount => out + low;
}

/// Uses the same rules as the Inventory Report so the numbers always match.
final inventoryHealthProvider = FutureProvider<InventoryHealth>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final supplies = await (db.select(
    db.supplies,
  )..where((s) => s.businessId.equals(kCurrentBusinessId))).get();

  var out = 0, low = 0, over = 0, value = 0, reorder = 0;
  final outNames = <String>[];
  final lowNames = <String>[];

  for (final s in supplies) {
    final stock = s.currentStock;
    final threshold = s.lowStockThreshold;
    final lowLevel = (threshold != null && threshold > 0)
        ? threshold
        : (s.minimumStock > 0 ? s.minimumStock : 0.0);
    final max = s.maximumStock;

    if (stock > 0) value += (stock * s.costPerBaseUnit).round();

    final isOut = stock <= 0;
    final isLow = !isOut && lowLevel > 0 && stock <= lowLevel;
    final isOver = !isOut && !isLow && max > 0 && stock > max;

    if (isOut) {
      out++;
      outNames.add(s.name);
    } else if (isLow) {
      low++;
      lowNames.add(s.name);
    } else if (isOver) {
      over++;
    }

    if (isOut || isLow) {
      final purchaseUnit = (s.purchaseUnit ?? '').trim();
      final per = (purchaseUnit.isNotEmpty && s.unitsPerPurchase > 0)
          ? s.unitsPerPurchase
          : 1.0;
      final ceiling = max > 0 ? max : (lowLevel > 0 ? lowLevel * 2 : null);
      final needBase = ceiling == null ? per : (ceiling - stock);
      final qty = math.max(1, (needBase / per).ceil());
      reorder += qty * s.currentPrice;
    }
  }

  return InventoryHealth(
    total: supplies.length,
    out: out,
    low: low,
    over: over,
    valueCents: value,
    reorderCents: reorder,
    outNames: outNames,
    lowNames: lowNames,
  );
});

// ============================================================
// PALETTE
// ============================================================

const _palette = <Color>[
  Color(0xFF667EEA),
  Color(0xFF38EF7D),
  Color(0xFFF2994A),
  Color(0xFFEB5757),
  Color(0xFF2F80ED),
  Color(0xFF9B51E0),
  Color(0xFFF2C94C),
  Color(0xFF56CCF2),
];

const _incomeColor = Color(0xFF1E9E5A);
const _expenseColor = Color(0xFFE5484D);

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

// ============================================================
// PAGE
// ============================================================

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _tab = 0;

  Future<void> _refresh() async {
    ref.read(ledgerVersionProvider.notifier).state++;
    final uid = ref.read(authenticatedUserIdProvider);
    if (uid != null) {
      try {
        await ref
            .read(syncCoordinatorProvider)
            .syncNow(ref.read(selectedBusinessIdProvider), userId: uid)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Offline or slow: the local data is still refreshed.
      }
    }
  }

  Widget _content(TransactionDateFilter period) {
    switch (_tab) {
      case 1:
        return _FinanceTab(key: const ValueKey('finance'), period: period);
      case 2:
        return _SalesTab(key: const ValueKey('sales'), period: period);
      default:
        return _OverviewTab(key: const ValueKey('overview'), period: period);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dashboardLiveUpdatesProvider);
    final period = ref.watch(selectedPeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(16.0, (constraints.maxWidth - 1200) / 2);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(side, 16, side, 32),
              children: [
                _Header(onRefresh: _refresh),
                const SizedBox(height: 14),
                _PeriodBar(period: period),
                const SizedBox(height: 16),
                _DashTabBar(
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.passthrough,
                    alignment: Alignment.topCenter,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.015),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _content(period),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// TABS
// ============================================================

const double _gap = 16;

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({super.key, required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroSection(period: period),
        const SizedBox(height: _gap),
        _KpiSection(period: period),
        const SizedBox(height: _gap),
        _InsightsCard(period: period),
        _RecentActivityCard(
          entriesAsync: ref.watch(journalEntriesProvider(period)),
        ),
      ],
    );
  }
}

class _FinanceTab extends ConsumerWidget {
  const _FinanceTab({super.key, required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Cash flow', 'Income and expenses over time'),
        _TrendCard(period: period),
        const SizedBox(height: 22),
        const _SectionHeader(
          'Profit & position',
          'How the period went and where you stand',
        ),
        _AdaptiveGrid(
          minWidth: 340,
          maxColumns: 2,
          children: [
            _ProfitLossCard(period: period),
            const _BalanceStrip(),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionHeader('Categories', 'Tap a slice or a row to focus it'),
        _AdaptiveGrid(
          minWidth: 380,
          maxColumns: 2,
          children: [
            _DonutCard(
              title: 'Expenses by category',
              color: _expenseColor,
              asyncTotals: ref.watch(
                categoryBreakdownProvider(('expense', period)),
              ),
            ),
            _DonutCard(
              title: 'Income by category',
              color: _incomeColor,
              asyncTotals: ref.watch(
                categoryBreakdownProvider(('income', period)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({super.key, required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          'POS performance',
          'What sold, who sold it and when',
        ),
        _PosSection(period: period),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashTabBar extends StatelessWidget {
  const _DashTabBar({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  static const _tabs = <(IconData, String)>[
    (Icons.space_dashboard_rounded, 'Overview'),
    (Icons.account_balance_rounded, 'Finance'),
    (Icons.point_of_sale_rounded, 'Sales'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: selected == i ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: selected == i
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _tabs[i].$1,
                        size: 18,
                        color: selected == i
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _tabs[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected == i
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: selected == i
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Money text that counts up to its value and re-animates when it changes.
class _CountUpText extends StatelessWidget {
  const _CountUpText(this.cents, {required this.style});
  final int cents;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: cents.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(_peso(v.round()), style: style),
    );
  }
}

// ============================================================
// LAYOUT HELPERS
// ============================================================

/// Responsive card grid: columns derive from the available width.
class _AdaptiveGrid extends StatelessWidget {
  const _AdaptiveGrid({
    required this.children,
    this.minWidth = 320,
    this.maxColumns = 3,
    this.gap = 14,
  });

  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = math.min(
          maxColumns,
          math.max(1, ((available + gap) / (minWidth + gap)).floor()),
        );
        final cardWidth = (available - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in children) SizedBox(width: cardWidth, child: c),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.color,
    required this.child,
    this.trailing,
    this.icon,
  });

  final String title;
  final Color color;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon ?? Icons.circle,
                  size: icon == null ? 8 : 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: scheme.outline),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HEADER + PERIOD BAR
// ============================================================

class _Header extends ConsumerWidget {
  const _Header({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ref
        .watch(businessProfileProvider)
        .maybeWhen(data: (v) => v, orElse: () => null);
    final user = ref.watch(currentUserProvider).value;

    final uid = ref.watch(authenticatedUserIdProvider);
    final isOwner = profile != null && profile.ownerUserId == uid;
    final ownerName = (profile?.ownerName ?? '').trim();
    final accountName = (user?.displayName ?? '').trim();

    // The owner sees the name from the profile form. Everyone else sees
    // their own account name, never the owner's.
    final fullName = isOwner && ownerName.isNotEmpty ? ownerName : accountName;
    final first = fullName.isEmpty ? '' : fullName.split(' ').first;
    final business = profile?.name ?? 'My Business';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                first.isEmpty ? _greeting() : '${_greeting()}, $first',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$business · ${DateFormat('EEEE, MMM d').format(DateTime.now())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Refresh and sync',
          onPressed: onRefresh,
          icon: const Icon(Icons.sync_rounded),
        ),
      ],
    );
  }
}

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({required this.period});
  final TransactionDateFilter period;

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    TransactionDatePreset preset,
  ) async {
    if (preset == TransactionDatePreset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        currentDate: DateTime.now(),
        initialDateRange: period.preset == TransactionDatePreset.custom
            ? period.range
            : null,
      );
      if (picked == null) return;
      ref.read(selectedPeriodProvider.notifier).state =
          TransactionDateFilter.custom(picked);
      return;
    }
    ref.read(selectedPeriodProvider.notifier).state = TransactionDateFilter(
      preset: preset,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final range = period.range;
    var last = range.end.subtract(const Duration(days: 1));
    if (last.isBefore(range.start)) last = range.start;
    final fmt = DateFormat('MMM d, yyyy');
    final rangeText = DateUtils.isSameDay(range.start, last)
        ? fmt.format(range.start)
        : '${fmt.format(range.start)} – ${fmt.format(last)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final preset in TransactionDatePreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    selected: preset == period.preset,
                    avatar: preset == TransactionDatePreset.custom
                        ? const Icon(Icons.event_rounded, size: 16)
                        : null,
                    label: Text(
                      preset == TransactionDatePreset.custom
                          ? (period.preset == TransactionDatePreset.custom
                                ? period.label
                                : 'Custom')
                          : TransactionDateFilter(preset: preset).label,
                    ),
                    onSelected: (_) => _pick(context, ref, preset),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 13, color: scheme.outline),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                rangeText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// DELTA CHIP + SPARKLINE
// ============================================================

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({
    required this.current,
    required this.previous,
    this.upIsGood = true,
    this.onDark = false,
  });

  final int current;
  final int? previous;
  final bool upIsGood;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final prev = previous;
    if (prev == null || (prev == 0 && current == 0)) {
      return const SizedBox.shrink();
    }

    String text;
    Color color;
    IconData icon;

    if (prev == 0) {
      text = 'New';
      color = onDark ? Colors.white : Theme.of(context).colorScheme.primary;
      icon = Icons.fiber_new_rounded;
    } else {
      final pct = (current - prev) / prev.abs() * 100;
      final up = pct >= 0;
      final good = up == upIsGood;
      text = '${pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0)}%';
      icon = up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
      color = onDark ? Colors.white : (good ? _incomeColor : _expenseColor);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: onDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final range = hi - lo;

    Offset point(int i) {
      final x = size.width * i / (values.length - 1);
      final y = range == 0
          ? size.height / 2
          : size.height - ((values[i] - lo) / range) * (size.height - 4) - 2;
      return Offset(x, y);
    }

    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(point(i).dx, point(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}

// ============================================================
// HERO — net profit
// ============================================================

class _HeroSection extends ConsumerWidget {
  const _HeroSection({required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(periodTotalsProvider(period));
    final prev = ref.watch(previousTotalsProvider(period)).value;

    return totals.when(
      skipLoadingOnReload: true,
      loading: () => const _Skeleton(height: 190),
      error: (e, _) => const _Card(
        child: _EmptyNote(Icons.error_outline, 'Unable to load totals.'),
      ),
      data: (t) {
        final net = t.income - t.expense;
        final prevNet = prev == null ? null : prev.income - prev.expense;
        final margin = t.income > 0 ? net / t.income * 100 : null;
        final total = t.income + t.expense;
        final scheme = Theme.of(context).colorScheme;

        int flex(int v) =>
            total == 0 ? 1 : math.max(1, (v * 1000 / total).round());

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.72)],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Net profit · ${period.label}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _DeltaChip(current: net, previous: prevNet, onDark: true),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _CountUpText(
                  net,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
              if (margin != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${margin.toStringAsFixed(0)}% profit margin',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 10,
                  child: total == 0
                      ? Container(color: Colors.white24)
                      : Row(
                          children: [
                            Expanded(
                              flex: flex(t.income),
                              child: Container(color: const Color(0xFF7CF2B0)),
                            ),
                            Expanded(
                              flex: flex(t.expense),
                              child: Container(color: const Color(0xFFFF9AA0)),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _HeroStat(
                      label: 'Income',
                      value: t.income,
                      dot: const Color(0xFF7CF2B0),
                    ),
                  ),
                  Expanded(
                    child: _HeroStat(
                      label: 'Expenses',
                      value: t.expense,
                      dot: const Color(0xFFFF9AA0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.dot,
  });
  final String label;
  final int value;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _peso(value, compact: true),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// KPI TILES
// ============================================================

class _KpiSection extends ConsumerWidget {
  const _KpiSection({required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(periodTotalsProvider(period)).value;
    final prev = ref.watch(previousTotalsProvider(period)).value;
    final trend = ref.watch(trendProvider(period)).value ?? const [];
    final balances = ref.watch(accountBalancesProvider).value;
    final report = ref.watch(dashboardSalesReportProvider(period)).value;

    final cash = balances?.fold<int>(0, (s, b) => s + b.balance) ?? 0;

    List<double>? dailySales;
    if (report != null && report.daily.length > 1) {
      final keys = report.daily.keys.toList()..sort();
      dailySales = [for (final k in keys) report.daily[k]!.toDouble()];
    }

    return _SummaryCard(
      cells: [
        _SummaryCell(
          label: 'Income',
          value: _peso(totals?.income ?? 0),
          cents: totals?.income ?? 0,
          icon: Icons.south_west_rounded,
          color: _incomeColor,
          delta: _DeltaChip(
            current: totals?.income ?? 0,
            previous: prev?.income,
          ),
          spark: trend.length > 1
              ? [for (final d in trend) d.income.toDouble()]
              : null,
        ),
        _SummaryCell(
          label: 'Expenses',
          value: _peso(totals?.expense ?? 0),
          cents: totals?.expense ?? 0,
          icon: Icons.north_east_rounded,
          color: _expenseColor,
          delta: _DeltaChip(
            current: totals?.expense ?? 0,
            previous: prev?.expense,
            upIsGood: false,
          ),
          spark: trend.length > 1
              ? [for (final d in trend) d.expense.toDouble()]
              : null,
        ),
        _SummaryCell(
          label: 'Cash on hand',
          value: _peso(cash),
          cents: cash,
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF2F80ED),
          caption: 'All accounts',
        ),
        _SummaryCell(
          label: 'POS sales',
          value: '${report?.salesCount ?? 0}',
          icon: Icons.point_of_sale_rounded,
          color: const Color(0xFF9B51E0),
          caption: report == null || report.salesCount == 0
              ? 'No sales yet'
              : 'Avg ${_peso(report.averageSaleCents, compact: true)}',
          spark: dailySales,
        ),
      ],
    );
  }
}

/// One clean box holding several headline numbers, separated by hairlines.
/// 4 across on wide screens, 2x2 on phones.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.cells});
  final List<_SummaryCell> cells;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = BorderSide(
      color: scheme.outlineVariant.withValues(alpha: 0.4),
    );

    return _Card(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 640 ? 4 : 2;
            final rows = (cells.length / cols).ceil();
            return Column(
              children: [
                for (var r = 0; r < rows; r++)
                  Row(
                    children: [
                      for (var col = 0; col < cols; col++)
                        Expanded(
                          child: r * cols + col < cells.length
                              ? Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: col < cols - 1
                                          ? line
                                          : BorderSide.none,
                                      bottom: r < rows - 1
                                          ? line
                                          : BorderSide.none,
                                    ),
                                  ),
                                  child: cells[r * cols + col],
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.cents,
    this.delta,
    this.caption,
    this.spark,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final int? cents;
  final Widget? delta;
  final String? caption;
  final List<double>? spark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const valueStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    );

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: cents != null
                ? _CountUpText(cents!, style: valueStyle)
                : Text(value, style: valueStyle),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 22),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (delta != null) delta!,
                if (caption != null)
                  Text(
                    caption!,
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: spark == null
                ? null
                : _Sparkline(values: spark!, color: color),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
    this.cents,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;
  final int? cents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: cents != null
                ? _CountUpText(
                    cents!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (caption != null)
                Text(
                  caption!,
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INSIGHTS
// ============================================================

enum _InsightGroup { finance, inventory, sales }

enum _Tone { alert, warning, good, info }

Color _toneColor(_Tone tone) => switch (tone) {
  _Tone.alert => _expenseColor,
  _Tone.warning => const Color(0xFFF2994A),
  _Tone.good => _incomeColor,
  _Tone.info => const Color(0xFF2F80ED),
};

class _Insight {
  const _Insight(this.group, this.tone, this.icon, this.title, this.message);

  final _InsightGroup group;
  final _Tone tone;
  final IconData icon;
  final String title;
  final String message;
}

/// Phones get the compact list; tablets and up get the tile layout.
/// Uses the same 600 breakpoint as the navigation shell.
class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).width >= Breakpoints.compact;
    return isTablet
        ? _InsightsCardWide(period: period)
        : _InsightsCardCompact(period: period);
  }
}

/// The original simple list, used on phones.
class _InsightsCardCompact extends ConsumerWidget {
  const _InsightsCardCompact({required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(periodTotalsProvider(period)).value;
    final p = ref.watch(previousTotalsProvider(period)).value;
    final report = ref.watch(dashboardSalesReportProvider(period)).value;
    final inventory = ref.watch(inventoryHealthProvider).value;
    if (t == null) return const SizedBox.shrink();

    final tips = <(IconData, Color, String)>[];

    String pct(int cur, int prev) =>
        '${((cur - prev) / prev.abs() * 100).abs().toStringAsFixed(0)}%';

    if (p != null && p.income > 0 && t.income != p.income) {
      final up = t.income > p.income;
      tips.add((
        up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        up ? _incomeColor : _expenseColor,
        'Income is ${up ? 'up' : 'down'} ${pct(t.income, p.income)} vs the previous period.',
      ));
    }
    if (p != null && p.expense > 0 && t.expense != p.expense) {
      final up = t.expense > p.expense;
      tips.add((
        up ? Icons.warning_amber_rounded : Icons.savings_outlined,
        up ? _expenseColor : _incomeColor,
        'Spending is ${up ? 'up' : 'down'} ${pct(t.expense, p.expense)} vs the previous period.',
      ));
    }
    if (t.expense > t.income && t.expense > 0) {
      tips.add((
        Icons.error_outline_rounded,
        _expenseColor,
        'Expenses exceed income by ${_peso(t.expense - t.income)} this period.',
      ));
    } else if (t.income > 0) {
      final m = (t.income - t.expense) / t.income * 100;
      tips.add((
        Icons.pie_chart_outline_rounded,
        const Color(0xFF2F80ED),
        'You kept ${m.toStringAsFixed(0)}% of income as profit.',
      ));
    }

    // ---- Inventory ----
    if (inventory != null && inventory.total > 0) {
      if (inventory.out > 0) {
        tips.add((
          Icons.remove_shopping_cart_outlined,
          _expenseColor,
          '${inventory.out} item${inventory.out == 1 ? ' is' : 's are'} out of stock: ${_nameList(inventory.outNames)}.',
        ));
      }
      if (inventory.low > 0) {
        tips.add((
          Icons.warning_amber_rounded,
          const Color(0xFFF2994A),
          '${inventory.low} item${inventory.low == 1 ? ' is' : 's are'} running low: ${_nameList(inventory.lowNames)}.',
        ));
      }
      if (inventory.reorderCount > 0 && inventory.reorderCents > 0) {
        tips.add((
          Icons.shopping_cart_checkout_rounded,
          const Color(0xFF2F80ED),
          'Restocking ${inventory.reorderCount} item${inventory.reorderCount == 1 ? '' : 's'} would cost about ${_peso(inventory.reorderCents, compact: true)}.',
        ));
      }
      if (inventory.over > 0) {
        tips.add((
          Icons.trending_up_rounded,
          const Color(0xFF9B51E0),
          '${inventory.over} item${inventory.over == 1 ? ' is' : 's are'} overstocked. Hold off on buying more.',
        ));
      }
      if (inventory.out == 0 && inventory.low == 0) {
        tips.add((
          Icons.check_circle_outline_rounded,
          _incomeColor,
          'All ${inventory.total} supplies are at healthy stock levels.',
        ));
      }
      if (inventory.valueCents > 0) {
        tips.add((
          Icons.inventory_2_outlined,
          const Color(0xFF2F80ED),
          'Your stock is worth ${_peso(inventory.valueCents, compact: true)} at average cost.',
        ));
      }
    }

    // ---- Sales ----
    if (report != null) {
      final best = report.bestDay;
      if (best != null && report.daily.length > 1) {
        tips.add((
          Icons.emoji_events_outlined,
          const Color(0xFFF2994A),
          'Best sales day: ${DateFormat('EEE, MMM d').format(best.key)} (${_peso(best.value, compact: true)}).',
        ));
      }
      final peak = report.peakHour;
      if (peak != null) {
        tips.add((
          Icons.schedule_rounded,
          const Color(0xFF9B51E0),
          'Busiest hour is ${_hourLabel(peak)}.',
        ));
      }
      if (report.voidedCount > 0) {
        tips.add((
          Icons.block_rounded,
          _expenseColor,
          '${report.voidedCount} voided sale${report.voidedCount == 1 ? '' : 's'} this period.',
        ));
      }
    }

    if (tips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _SectionCard(
        title: 'Insights',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFFF2C94C),
        child: Column(
          children: [
            for (final tip in tips.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(tip.$1, size: 18, color: tip.$2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tip.$3,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InsightsCardWide extends ConsumerWidget {
  const _InsightsCardWide({required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(periodTotalsProvider(period)).value;
    final p = ref.watch(previousTotalsProvider(period)).value;
    final report = ref.watch(dashboardSalesReportProvider(period)).value;
    final inventory = ref.watch(inventoryHealthProvider).value;
    if (t == null) return const SizedBox.shrink();

    final items = <_Insight>[];

    String pct(int cur, int prev) =>
        '${((cur - prev) / prev.abs() * 100).abs().toStringAsFixed(0)}%';

    // ---- Finance ----
    if (p != null && p.income > 0 && t.income != p.income) {
      final up = t.income > p.income;
      items.add(
        _Insight(
          _InsightGroup.finance,
          up ? _Tone.good : _Tone.alert,
          up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          'Income ${up ? 'up' : 'down'} ${pct(t.income, p.income)}',
          'Compared with the previous period.',
        ),
      );
    }
    if (p != null && p.expense > 0 && t.expense != p.expense) {
      final up = t.expense > p.expense;
      items.add(
        _Insight(
          _InsightGroup.finance,
          up ? _Tone.warning : _Tone.good,
          up ? Icons.warning_amber_rounded : Icons.savings_outlined,
          'Spending ${up ? 'up' : 'down'} ${pct(t.expense, p.expense)}',
          'Compared with the previous period.',
        ),
      );
    }
    if (t.expense > t.income && t.expense > 0) {
      items.add(
        _Insight(
          _InsightGroup.finance,
          _Tone.alert,
          Icons.error_outline_rounded,
          'Spending exceeds income',
          'Expenses are ${_peso(t.expense - t.income)} higher than income this period.',
        ),
      );
    } else if (t.income > 0) {
      final m = (t.income - t.expense) / t.income * 100;
      items.add(
        _Insight(
          _InsightGroup.finance,
          _Tone.info,
          Icons.pie_chart_outline_rounded,
          '${m.toStringAsFixed(0)}% profit margin',
          'You kept ${m.toStringAsFixed(0)}% of your income as profit.',
        ),
      );
    }

    // ---- Inventory ----
    if (inventory != null && inventory.total > 0) {
      if (inventory.out > 0) {
        items.add(
          _Insight(
            _InsightGroup.inventory,
            _Tone.alert,
            Icons.remove_shopping_cart_outlined,
            '${inventory.out} out of stock',
            '${_nameList(inventory.outNames)}.',
          ),
        );
      }
      if (inventory.low > 0) {
        items.add(
          _Insight(
            _InsightGroup.inventory,
            _Tone.warning,
            Icons.warning_amber_rounded,
            '${inventory.low} running low',
            '${_nameList(inventory.lowNames)}.',
          ),
        );
      }
      if (inventory.reorderCount > 0 && inventory.reorderCents > 0) {
        items.add(
          _Insight(
            _InsightGroup.inventory,
            _Tone.info,
            Icons.shopping_cart_checkout_rounded,
            'Restock ≈ ${_peso(inventory.reorderCents, compact: true)}',
            'Estimated cost to restock ${inventory.reorderCount} item${inventory.reorderCount == 1 ? '' : 's'}.',
          ),
        );
      }
      if (inventory.over > 0) {
        items.add(
          _Insight(
            _InsightGroup.inventory,
            _Tone.info,
            Icons.trending_up_rounded,
            '${inventory.over} overstocked',
            'Hold off on buying more of ${inventory.over == 1 ? 'this item' : 'these'}.',
          ),
        );
      }
      if (inventory.out == 0 && inventory.low == 0) {
        items.add(
          _Insight(
            _InsightGroup.inventory,
            _Tone.good,
            Icons.check_circle_outline_rounded,
            'Stock looks healthy',
            'All ${inventory.total} supplies are at healthy levels.',
          ),
        );
      }
      if (inventory.valueCents > 0) {
        items.add(
          _Insight(
            _InsightGroup.inventory,
            _Tone.info,
            Icons.inventory_2_outlined,
            'Stock worth ${_peso(inventory.valueCents, compact: true)}',
            'Valued at average cost.',
          ),
        );
      }
    }

    // ---- Sales ----
    if (report != null) {
      final best = report.bestDay;
      if (best != null && report.daily.length > 1) {
        items.add(
          _Insight(
            _InsightGroup.sales,
            _Tone.good,
            Icons.emoji_events_outlined,
            'Best sales day',
            '${DateFormat('EEE, MMM d').format(best.key)} · ${_peso(best.value, compact: true)}',
          ),
        );
      }
      final peak = report.peakHour;
      if (peak != null) {
        items.add(
          _Insight(
            _InsightGroup.sales,
            _Tone.info,
            Icons.schedule_rounded,
            'Busiest hour',
            'Most sales happen around ${_hourLabel(peak)}.',
          ),
        );
      }
      if (report.voidedCount > 0) {
        items.add(
          _Insight(
            _InsightGroup.sales,
            _Tone.warning,
            Icons.block_rounded,
            '${report.voidedCount} voided sale${report.voidedCount == 1 ? '' : 's'}',
            'Voided during this period.',
          ),
        );
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _InsightsPanel(insights: items),
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel({required this.insights});
  final List<_Insight> insights;

  static const _groupMeta = <_InsightGroup, (String, IconData, Color)>{
    _InsightGroup.finance: (
      'Finance',
      Icons.account_balance_wallet_rounded,
      Color(0xFF2F80ED),
    ),
    _InsightGroup.inventory: (
      'Inventory',
      Icons.inventory_2_rounded,
      Color(0xFFF2994A),
    ),
    _InsightGroup.sales: (
      'Sales',
      Icons.point_of_sale_rounded,
      Color(0xFF9B51E0),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final attention = insights
        .where((i) => i.tone == _Tone.alert || i.tone == _Tone.warning)
        .length;
    final positive = insights.where((i) => i.tone == _Tone.good).length;

    final pills = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (attention > 0)
          _InsightPill(
            text: '$attention need${attention == 1 ? 's' : ''} attention',
            color: _expenseColor,
          ),
        if (positive > 0)
          _InsightPill(text: '$positive positive', color: _incomeColor),
      ],
    );

    final title = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF2C94C), Color(0xFFF2994A)],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF2994A).withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 21,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Insights',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Smart highlights for your business',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return _Card(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 560;
          final columns = math.min(
            3,
            math.max(1, ((c.maxWidth + 12) / (280 + 12)).floor()),
          );

          var tileIndex = 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    pills,
                  ],
                )
              else ...[
                title,
                const SizedBox(height: 10),
                pills,
              ],
              for (final group in _InsightGroup.values)
                if (insights.any((i) => i.group == group)) ...[
                  const SizedBox(height: 18),
                  _InsightGroupLabel(
                    label: _groupMeta[group]!.$1,
                    icon: _groupMeta[group]!.$2,
                    color: _groupMeta[group]!.$3,
                    count: insights.where((i) => i.group == group).length,
                  ),
                  const SizedBox(height: 10),
                  ..._rows(
                    insights.where((i) => i.group == group).toList(),
                    columns,
                    () => tileIndex++,
                  ),
                ],
            ],
          );
        },
      ),
    );
  }

  /// Lays tiles out in equal-height rows of [columns].
  List<Widget> _rows(
    List<_Insight> list,
    int columns,
    int Function() nextIndex,
  ) {
    const gap = 10.0;
    final rows = <Widget>[];

    for (var start = 0; start < list.length; start += columns) {
      final end = math.min(start + columns, list.length);
      final chunk = list.sublist(start, end);

      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  child: i < chunk.length
                      ? _InsightTile(insight: chunk[i], index: nextIndex())
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return rows;
  }
}

class _InsightGroupLabel extends StatelessWidget {
  const _InsightGroupLabel({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.outline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _InsightPill extends StatelessWidget {
  const _InsightPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight, required this.index});
  final _Insight insight;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _toneColor(insight.tone);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + math.min(index, 8) * 60),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 10),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(insight.icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    insight.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TREND CHART
// ============================================================

enum _TrendMode { both, income, expense, net }

class _TrendCard extends ConsumerStatefulWidget {
  const _TrendCard({required this.period});
  final TransactionDateFilter period;

  @override
  ConsumerState<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends ConsumerState<_TrendCard> {
  _TrendMode _mode = _TrendMode.both;

  static double _niceCeil(double v) {
    if (v <= 0) return 100;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / exp;
    final nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
    return nf * exp;
  }

  static double _xInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    if (count <= 21) return 3;
    if (count <= 31) return 5;
    return 7;
  }

  static String _dateLabel(DateTime date, int total) {
    if (total <= 7) return DateFormat('EEE').format(date);
    if (total == 12 && date.day == 1) return DateFormat('MMM').format(date);
    return DateFormat('M/d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final async = ref.watch(trendProvider(period));
    final scheme = Theme.of(context).colorScheme;

    return _SectionCard(
      title: 'Income vs expense trend',
      icon: Icons.show_chart_rounded,
      color: scheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in _TrendMode.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                      selected: _mode == m,
                      label: Text(switch (m) {
                        _TrendMode.both => 'Both',
                        _TrendMode.income => 'Income',
                        _TrendMode.expense => 'Expense',
                        _TrendMode.net => 'Net',
                      }),
                      onSelected: (_) => setState(() => _mode = m),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          async.when(
            skipLoadingOnReload: true,
            loading: () => const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) =>
                const _EmptyNote(Icons.error_outline, 'Unable to load trend.'),
            data: (days) => _buildChart(context, days),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<DaySummary> days) {
    final scheme = Theme.of(context).colorScheme;
    final hasData = days.any((d) => d.income > 0 || d.expense > 0);

    if (days.isEmpty || !hasData) {
      return const _EmptyNote(
        Icons.show_chart_rounded,
        'No income or expenses recorded for this period.',
      );
    }

    final monthly =
        widget.period.preset == TransactionDatePreset.year ||
        widget.period.preset == TransactionDatePreset.lastYear;

    if (days.length == 1) {
      final d = days.first;
      return Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 28,
        runSpacing: 10,
        children: [
          _SingleStat('Income', d.income, _incomeColor),
          _SingleStat('Expense', d.expense, _expenseColor),
          _SingleStat('Net', d.income - d.expense, scheme.primary),
        ],
      );
    }

    final bars = <({String label, Color color, List<double> values})>[
      if (_mode == _TrendMode.both || _mode == _TrendMode.income)
        (
          label: 'Income',
          color: _incomeColor,
          values: [for (final d in days) d.income / 100],
        ),
      if (_mode == _TrendMode.both || _mode == _TrendMode.expense)
        (
          label: 'Expense',
          color: _expenseColor,
          values: [for (final d in days) d.expense / 100],
        ),
      if (_mode == _TrendMode.net)
        (
          label: 'Net',
          color: scheme.primary,
          values: [for (final d in days) (d.income - d.expense) / 100],
        ),
    ];

    final all = [for (final b in bars) ...b.values];
    final hi = all.reduce(math.max);
    final lo = all.reduce(math.min);
    final maxY = hi <= 0 ? 100.0 : _niceCeil(hi * 1.1);
    final minY = lo >= 0 ? 0.0 : -_niceCeil(lo.abs() * 1.1);
    final yInterval = (maxY - minY) / 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width < 360
            ? 170.0
            : width < 600
            ? 190.0
            : width < 900
            ? 220.0
            : 250.0;

        return Column(
          children: [
            SizedBox(
              height: height,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (days.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          space: 4,
                          child: Text(
                            NumberFormat.compact().format(value),
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: _xInterval(days.length),
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            space: 4,
                            child: RotatedBox(
                              quarterTurns: days.length > 14 ? 1 : 0,
                              child: Text(
                                _dateLabel(days[i].date, days.length),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: scheme.outline,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => scheme.inverseSurface,
                      tooltipBorderRadius: BorderRadius.circular(10),
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItems: (spots) {
                        final items = <LineTooltipItem?>[];
                        for (var n = 0; n < spots.length; n++) {
                          final s = spots[n];
                          final i = s.x.round();
                          if (i < 0 || i >= days.length) {
                            items.add(null);
                            continue;
                          }
                          final bar = bars[s.barIndex];
                          final date = DateFormat(
                            monthly ? 'MMMM yyyy' : 'EEE, MMM d',
                          ).format(days[i].date);
                          items.add(
                            LineTooltipItem(
                              '${n == 0 ? '$date\n' : ''}${bar.label}: ${_peso((s.y * 100).round())}',
                              TextStyle(
                                color: scheme.onInverseSurface,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        return items;
                      },
                    ),
                  ),
                  lineBarsData: [
                    for (final b in bars)
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < b.values.length; i++)
                            FlSpot(i.toDouble(), b.values[i]),
                        ],
                        color: b.color,
                        barWidth: 2.5,
                        isCurved: true,
                        curveSmoothness: 0.22,
                        preventCurveOverShooting: true,
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: days.length <= 7),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              b.color.withValues(alpha: 0.18),
                              b.color.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                for (final b in bars)
                  _LegendDot(color: b.color, label: b.label),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SingleStat extends StatelessWidget {
  const _SingleStat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          _peso(value, compact: true),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ============================================================
// DONUT (tap a slice or legend row to highlight it)
// ============================================================

class _DonutCard extends StatefulWidget {
  const _DonutCard({
    required this.title,
    required this.color,
    required this.asyncTotals,
  });

  final String title;
  final Color color;
  final AsyncValue<List<CategoryTotal>> asyncTotals;

  @override
  State<_DonutCard> createState() => _DonutCardState();
}

class _DonutCardState extends State<_DonutCard> {
  int? _touched;

  List<CategoryTotal> _group(List<CategoryTotal> all) {
    if (all.length <= 6) return all;
    final top = all.take(5).toList();
    final rest = all.skip(5).fold<int>(0, (s, t) => s + t.total);
    return [...top, CategoryTotal(name: 'Others', total: rest)];
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: widget.title,
      color: widget.color,
      child: widget.asyncTotals.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox(
          height: 130,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) =>
            const _EmptyNote(Icons.error_outline, 'Unable to load.'),
        data: (raw) {
          if (raw.isEmpty) {
            return const _EmptyNote(
              Icons.donut_large_rounded,
              'No data for this period yet.',
            );
          }
          final totals = _group(raw);
          final total = totals.fold<int>(0, (s, t) => s + t.total);
          final scheme = Theme.of(context).colorScheme;
          final touched = (_touched != null && _touched! < totals.length)
              ? _touched
              : null;

          final donut = SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 44,
                    sectionsSpace: 2,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        final i = response?.touchedSection?.touchedSectionIndex;
                        setState(() {
                          _touched =
                              (event.isInterestedForInteractions &&
                                  i != null &&
                                  i >= 0)
                              ? i
                              : null;
                        });
                      },
                    ),
                    sections: [
                      for (var i = 0; i < totals.length; i++)
                        PieChartSectionData(
                          value: totals[i].total.toDouble(),
                          color: _palette[i % _palette.length],
                          radius: touched == i ? 26 : 20,
                          showTitle: false,
                        ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 150),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        touched == null ? 'Total' : totals[touched].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: scheme.outline),
                      ),
                      FittedBox(
                        child: Text(
                          _peso(
                            touched == null ? total : totals[touched].total,
                            compact: true,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final legend = Column(
            children: [
              for (var i = 0; i < totals.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      setState(() => _touched = touched == i ? null : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 5,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: _palette[i % _palette.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            totals[i].name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: touched == i
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${(totals[i].total / total * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );

          return LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 300) {
                return Column(
                  children: [donut, const SizedBox(height: 10), legend],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  donut,
                  const SizedBox(width: 14),
                  Expanded(child: legend),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// POS ANALYTICS
// ============================================================

class _PosSection extends ConsumerWidget {
  const _PosSection({required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardSalesReportProvider(period));

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const _Skeleton(height: 160),
      // POS tables unavailable or empty: simply hide the section.
      error: (e, st) {
        debugPrint('POS dashboard error: $e\n$st');
        return _SectionCard(
          title: 'POS sales',
          icon: Icons.error_outline,
          color: _expenseColor,
          child: _EmptyNote(
            Icons.error_outline,
            'Unable to load POS analytics:\n$e',
          ),
        );
      },
      data: (report) {
        if (report.salesCount == 0) {
          return const _SectionCard(
            title: 'POS sales',
            icon: Icons.point_of_sale_rounded,
            color: Color(0xFF9B51E0),
            child: _EmptyNote(
              Icons.receipt_long_outlined,
              'No POS sales in this period.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdaptiveGrid(
              minWidth: 150,
              maxColumns: 4,
              gap: 12,
              children: [
                _KpiTile(
                  label: 'Revenue',
                  value: _peso(report.revenueCents),
                  cents: report.revenueCents,
                  icon: Icons.payments_rounded,
                  color: _incomeColor,
                ),
                _KpiTile(
                  label: 'Sales',
                  value: '${report.salesCount}',
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF9B51E0),
                ),
                _KpiTile(
                  label: 'Average sale',
                  value: _peso(report.averageSaleCents),
                  cents: report.averageSaleCents,
                  icon: Icons.analytics_rounded,
                  color: const Color(0xFF2F80ED),
                ),
                _KpiTile(
                  label: 'Items sold',
                  value: _qty(report.itemsSold),
                  icon: Icons.shopping_bag_rounded,
                  color: const Color(0xFFF2994A),
                  caption: report.voidedCount > 0
                      ? '${report.voidedCount} voided'
                      : null,
                ),
              ],
            ),
            const SizedBox(height: _gap),
            _AdaptiveGrid(
              minWidth: 340,
              maxColumns: 3,
              children: [
                _TopSellersCard(report: report),
                _CashiersCard(report: report),
                _HourlyCard(report: report),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TopSellersCard extends StatefulWidget {
  const _TopSellersCard({required this.report});
  final SalesReport report;

  @override
  State<_TopSellersCard> createState() => _TopSellersCardState();
}

class _TopSellersCardState extends State<_TopSellersCard> {
  RankBy _by = RankBy.revenue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = widget.report.topProducts(_by, limit: 5);
    final top = items.isEmpty
        ? 1.0
        : (_by == RankBy.revenue
              ? items.first.revenueCents.toDouble()
              : items.first.qty);

    return _SectionCard(
      title: 'Top sellers',
      icon: Icons.local_fire_department_rounded,
      color: const Color(0xFFF2994A),
      trailing: SegmentedButton<RankBy>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(value: RankBy.revenue, label: Text('₱')),
          ButtonSegment(value: RankBy.units, label: Text('Qty')),
        ],
        selected: {_by},
        onSelectionChanged: (s) => setState(() => _by = s.first),
      ),
      child: items.isEmpty
          ? const _EmptyNote(Icons.inventory_2_outlined, 'No items sold.')
          : Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: scheme.outline,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                items[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _by == RankBy.revenue
                                  ? _peso(items[i].revenueCents, compact: true)
                                  : '${_qty(items[i].qty)} ${items[i].unit}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: top <= 0
                                ? 0
                                : ((_by == RankBy.revenue
                                              ? items[i].revenueCents.toDouble()
                                              : items[i].qty) /
                                          top)
                                      .clamp(0.0, 1.0),
                            backgroundColor: scheme.surfaceContainerHigh,
                            color: _palette[i % _palette.length],
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

class _CashiersCard extends StatelessWidget {
  const _CashiersCard({required this.report});
  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cashiers = report.cashiers.take(5).toList();
    final top = cashiers.isEmpty ? 1 : math.max(1, cashiers.first.revenueCents);

    return _SectionCard(
      title: 'Cashier leaderboard',
      icon: Icons.groups_rounded,
      color: const Color(0xFF2F80ED),
      child: Column(
        children: [
          for (var i = 0; i < cashiers.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: _palette[i % _palette.length].withValues(
                      alpha: 0.18,
                    ),
                    child: Text(
                      cashiers[i].name.isEmpty
                          ? '?'
                          : cashiers[i].name[0].toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _palette[i % _palette.length],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cashiers[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _peso(cashiers[i].revenueCents, compact: true),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${cashiers[i].salesCount} sale${cashiers[i].salesCount == 1 ? '' : 's'} · avg ${_peso(cashiers[i].averageCents, compact: true)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: scheme.outline),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: (cashiers[i].revenueCents / top).clamp(
                              0.0,
                              1.0,
                            ),
                            backgroundColor: scheme.surfaceContainerHigh,
                            color: _palette[i % _palette.length],
                          ),
                        ),
                      ],
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

class _HourlyCard extends StatelessWidget {
  const _HourlyCard({required this.report});
  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = report.peakHour;
    final maxValue = report.hourly.values.isEmpty
        ? 1
        : math.max(1, report.hourly.values.reduce(math.max));

    return _SectionCard(
      title: 'Sales by hour',
      icon: Icons.schedule_rounded,
      color: const Color(0xFF9B51E0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (peak != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Peak: ${_hourLabel(peak)} · ${_peso(report.hourly[peak] ?? 0, compact: true)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = 0; h < 24; h++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${_hourLabel(h)}: ${_peso(report.hourly[h] ?? 0)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: FractionallySizedBox(
                          heightFactor: math.max(
                            0.03,
                            (report.hourly[h] ?? 0) / maxValue,
                          ),
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: h == peak
                                  ? const Color(0xFF9B51E0)
                                  : const Color(
                                      0xFF9B51E0,
                                    ).withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in const [0, 6, 12, 18, 23])
                Text(
                  _hourLabel(h),
                  style: TextStyle(fontSize: 10, color: scheme.outline),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BALANCE STRIP
// ============================================================

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.cents,
    required this.color,
    required this.icon,
    this.delta,
    this.bold = false,
  });

  final String label;
  final int cents;
  final Color color;
  final IconData icon;
  final Widget? delta;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (delta != null) ...[delta!, const SizedBox(width: 8)],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _peso(cents),
                style: TextStyle(
                  fontSize: bold ? 16 : 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
  );
}

class _ProfitLossCard extends ConsumerWidget {
  const _ProfitLossCard({required this.period});
  final TransactionDateFilter period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final t = ref.watch(periodTotalsProvider(period)).value;
    final p = ref.watch(previousTotalsProvider(period)).value;
    final income = t?.income ?? 0;
    final expense = t?.expense ?? 0;
    final net = income - expense;

    return _SectionCard(
      title: 'Profit & loss',
      icon: Icons.receipt_long_rounded,
      color: scheme.primary,
      child: Column(
        children: [
          _StatRow(
            label: 'Income',
            cents: income,
            color: _incomeColor,
            icon: Icons.south_west_rounded,
            delta: _DeltaChip(current: income, previous: p?.income),
          ),
          const _RowDivider(),
          _StatRow(
            label: 'Expenses',
            cents: expense,
            color: _expenseColor,
            icon: Icons.north_east_rounded,
            delta: _DeltaChip(
              current: expense,
              previous: p?.expense,
              upIsGood: false,
            ),
          ),
          const _RowDivider(),
          _StatRow(
            label: 'Net profit',
            cents: net,
            color: net >= 0 ? _incomeColor : _expenseColor,
            icon: Icons.balance_rounded,
            bold: true,
            delta: _DeltaChip(
              current: net,
              previous: p == null ? null : p.income - p.expense,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceStrip extends ConsumerWidget {
  const _BalanceStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cash =
        ref
            .watch(accountBalancesProvider)
            .value
            ?.fold<int>(0, (s, b) => s + b.balance) ??
        0;
    final capital = ref.watch(capitalBalanceProvider).value ?? 0;
    final assets =
        (ref.watch(assetBalancesProvider).value ??
                const <AccountBalanceEntry>[])
            .fold<int>(0, (s, e) => s + e.balance);
    final liabilities =
        (ref.watch(liabilityBalancesProvider).value ??
                const <AccountBalanceEntry>[])
            .fold<int>(0, (s, e) => s + e.balance);

    final a = math.max(assets, 0);
    final l = math.max(liabilities, 0);

    return _SectionCard(
      title: 'Financial position',
      icon: Icons.account_balance_rounded,
      color: const Color(0xFF2F80ED),
      child: Column(
        children: [
          _StatRow(
            label: 'Cash on hand',
            cents: cash,
            color: const Color(0xFF2F80ED),
            icon: Icons.account_balance_wallet_rounded,
          ),
          const _RowDivider(),
          _StatRow(
            label: 'Capital',
            cents: capital,
            color: const Color(0xFF9B51E0),
            icon: Icons.savings_outlined,
          ),
          const _RowDivider(),
          _StatRow(
            label: 'Assets',
            cents: assets,
            color: _incomeColor,
            icon: Icons.inventory_2_outlined,
          ),
          const _RowDivider(),
          _StatRow(
            label: 'Liabilities',
            cents: liabilities,
            color: _expenseColor,
            icon: Icons.request_quote_outlined,
          ),
          if (a + l > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    if (a > 0)
                      Expanded(
                        flex: a,
                        child: Container(color: _incomeColor),
                      ),
                    if (l > 0)
                      Expanded(
                        flex: l,
                        child: Container(color: _expenseColor),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Assets',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
                Text(
                  'Liabilities',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// RECENT ACTIVITY
// ============================================================

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.entriesAsync});
  final AsyncValue<List<JournalEntryRow>> entriesAsync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _SectionCard(
      title: 'Recent activity',
      icon: Icons.history_rounded,
      color: scheme.primary,
      child: entriesAsync.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) =>
            const _EmptyNote(Icons.error_outline, 'Unable to load activity.'),
        data: (entries) {
          if (entries.isEmpty) {
            return const _EmptyNote(
              Icons.receipt_long_outlined,
              'No transactions recorded yet.',
            );
          }
          final recent = entries.take(6).toList();
          return Column(
            children: [
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                _ActivityRow(entry: recent[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});
  final JournalEntryRow entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = entry.type == JournalEntryType.income;
    final pending = entry.status == 'pending';
    final title = entry.description?.isNotEmpty == true
        ? entry.description!
        : entry.categoryName;
    final color = isIncome ? _incomeColor : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isIncome ? _incomeColor : _expenseColor).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 17,
              color: isIncome ? _incomeColor : _expenseColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      pending ? Icons.schedule_rounded : Icons.check_circle,
                      size: 12,
                      color: pending ? Colors.orange : _incomeColor,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        pending ? 'Pending' : 'Completed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIncome ? '+' : '-'}${_peso(entry.amount, compact: true)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
