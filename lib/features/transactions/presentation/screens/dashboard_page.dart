// lib/features/dashboard/presentation/screens/dashboard_page.dart
//
// The business-at-a-glance screen: period totals, category
// breakdown donuts (income & expense), an income-vs-expense trend
// line, and a peek at recent Journal Entry activity.
//
// Add to pubspec.yaml if not already present:
//   fl_chart, intl

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column, Table;
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show businessProfileProvider, ledgerVersionProvider, kCurrentBusinessId;
import '../../../transactions/presentation/screens/journal_entry_page.dart'
    show journalEntriesProvider, JournalEntryRow, JournalEntryType;
import '../../../transactions/presentation/screens/cashflow_page.dart'
    show accountBalancesProvider;
import '../providers/transaction_date_filter.dart';

String _peso(int cents, {bool compact = false}) {
  if (compact && cents.abs() >= 100000 * 100) {
    return '₱${NumberFormat.compact().format(cents / 100)}';
  }
  return '₱${NumberFormat('#,##0.00').format(cents / 100)}';
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

final periodTotalsProvider =
    FutureProvider.family<({int income, int expense}), TransactionDateFilter>((
      ref,
      filter,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final range = filter.range;

      final incomeRow = await db
          .customSelect(
            '''
    SELECT COALESCE(SUM(amount), 0) AS total FROM income_transactions
    WHERE business_id = ? AND status = 'completed' AND txn_date >= ? AND txn_date < ?
    ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
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
              Variable.withDateTime(range.start),
              Variable.withDateTime(range.end),
            ],
          )
          .getSingle();

      return (
        income: incomeRow.read<int>('total'),
        expense: expenseRow.read<int>('total'),
      );
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

// ============================================================
// TREND PROVIDER — income vs expense over time
// ============================================================

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

      // ------------------------------------------------------------
      // INCOME
      // ------------------------------------------------------------

      final incomeRows = await db
          .customSelect(
            '''
    SELECT
      txn_date,
      amount
    FROM income_transactions
    WHERE business_id = ?
      AND status = 'completed'
      AND txn_date >= ?
      AND txn_date < ?
    ORDER BY txn_date
    ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(start),
              Variable.withDateTime(endExclusive),
            ],
          )
          .get();

      // ------------------------------------------------------------
      // EXPENSE
      // ------------------------------------------------------------

      final expenseRows = await db
          .customSelect(
            '''
    SELECT
      expense_date,
      amount
    FROM expenses
    WHERE business_id = ?
      AND status = 'completed'
      AND expense_date >= ?
      AND expense_date < ?
    ORDER BY expense_date
    ''',
            variables: [
              Variable.withString(kCurrentBusinessId),
              Variable.withDateTime(start),
              Variable.withDateTime(endExclusive),
            ],
          )
          .get();

      // ------------------------------------------------------------
      // AGGREGATE IN DART
      // ------------------------------------------------------------

      final incomeByDay = <String, int>{};
      final expenseByDay = <String, int>{};

      // ------------------------------------------------------------
      // INCOME ROWS
      // ------------------------------------------------------------

      for (final row in incomeRows) {
        final date = row.readNullable<DateTime>('txn_date');
        final amount = row.readNullable<int>('amount') ?? 0;

        if (date == null) {
          debugPrint('TREND DEBUG: income row has NULL txn_date');
          continue;
        }

        final key = DateFormat(monthly ? 'yyyy-MM' : 'yyyy-MM-dd').format(date);

        incomeByDay[key] = (incomeByDay[key] ?? 0) + amount;
      }

      // ------------------------------------------------------------
      // EXPENSE ROWS
      // ------------------------------------------------------------

      for (final row in expenseRows) {
        final date = row.readNullable<DateTime>('expense_date');
        final amount = row.readNullable<int>('amount') ?? 0;

        if (date == null) {
          debugPrint('TREND DEBUG: expense row has NULL expense_date');
          continue;
        }

        final key = DateFormat(monthly ? 'yyyy-MM' : 'yyyy-MM-dd').format(date);

        expenseByDay[key] = (expenseByDay[key] ?? 0) + amount;
      }

      // ------------------------------------------------------------
      // DEBUG
      // ------------------------------------------------------------
      // ------------------------------------------------------------
      // DEBBUGER TREND CHART
      // ------------------------------------------------------------

      // debugPrint(
      //   'TREND DEBUG: incomeRows=${incomeRows.length}, '
      //   'expenseRows=${expenseRows.length}',
      // );

      // debugPrint('TREND DEBUG income: $incomeByDay');
      // debugPrint('TREND DEBUG expense: $expenseByDay');

      // ------------------------------------------------------------
      // BUILD COMPLETE DATE RANGE
      // ------------------------------------------------------------

      final pointCount = monthly
          ? (endExclusive.year - start.year) * 12 +
                endExclusive.month -
                start.month
          : endExclusive.difference(start).inDays;

      return List.generate(pointCount, (index) {
        final date = monthly
            ? DateTime(start.year, start.month + index)
            : start.add(Duration(days: index));

        final key = DateFormat(monthly ? 'yyyy-MM' : 'yyyy-MM-dd').format(date);

        return DaySummary(
          date: date,
          income: incomeByDay[key] ?? 0,
          expense: expenseByDay[key] ?? 0,
        );
      });
    });

// ============================================================
// TREND CHART — responsive income vs expense chart
// ============================================================

// ============================================================
// TREND CHART — fully adaptive
// ============================================================

// ============================================================
// TREND CHART — adaptive + overflow safe
// ============================================================

class _TrendChart extends StatelessWidget {
  final List<DaySummary> days;

  static double _niceMaxY(double value) {
    if (value <= 0) {
      return 100;
    }

    final padded = value * 1.20;

    if (padded <= 100) return 100;
    if (padded <= 500) return 500;
    if (padded <= 1000) return 1000;
    if (padded <= 5000) return 5000;
    if (padded <= 10000) return 10000;
    if (padded <= 50000) return 50000;
    if (padded <= 100000) return 100000;
    if (padded <= 500000) return 500000;

    return (padded / 250000).ceil() * 250000;
  }

  const _TrendChart({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      final hasData = days.any((day) => day.income > 0 || day.expense > 0);

      if (!hasData) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.show_chart_rounded, size: 30),
                SizedBox(height: 8),
                Text(
                  'No income or expenses recorded',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'Transactions will appear here once recorded.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('No data for this period yet.')),
      );
    }

    if (days.length == 1) {
      return _buildSingleDayView(context);
    }
    final hasData = days.any((day) => day.income > 0 || day.expense > 0);

    if (!hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart_rounded, size: 28),
              SizedBox(height: 8),
              Text(
                'No income or expenses recorded',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 3),
              Text(
                'Transactions will appear here once recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // ======================================================
        // RESPONSIVE DIMENSIONS
        //
        // Keep the chart deliberately compact because the
        // surrounding card also needs room for its title,
        // padding, legend, etc.
        // ======================================================

        final chartHeight = width < 360
            ? 120.0
            : width < 600
            ? 132.0
            : width < 900
            ? 155.0
            : 180.0;

        final horizontalPadding = width < 360 ? 2.0 : 4.0;

        final incomeSpots = <FlSpot>[
          for (var i = 0; i < days.length; i++)
            FlSpot(i.toDouble(), days[i].income / 100),
        ];

        final expenseSpots = <FlSpot>[
          for (var i = 0; i < days.length; i++)
            FlSpot(i.toDouble(), days[i].expense / 100),
        ];

        // ======================================================
        // MAX VALUE
        // ======================================================

        final maxValue = days.fold<double>(0, (max, day) {
          final income = day.income / 100;
          final expense = day.expense / 100;

          final largest = income > expense ? income : expense;

          return largest > max ? largest : max;
        });

        final maxY = maxValue <= 0 ? 100.0 : _niceMaxY(maxValue);
        final yInterval = _calculateYInterval(maxY);
        final xInterval = _calculateXInterval(days.length);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ==================================================
              // CHART
              // ==================================================

              SizedBox(
                height: chartHeight,
                width: double.infinity,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (days.length - 1).toDouble(),

                    minY: 0,
                    maxY: maxY,

                    // Prevent drawing outside the chart bounds.
                    clipData: const FlClipData.all(),

                    // ==================================================
                    // GRID
                    // ==================================================
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: yInterval,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.withValues(alpha: 0.12),
                          strokeWidth: 1,
                        );
                      },
                    ),

                    // ==================================================
                    // AXIS TITLES
                    // ==================================================
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),

                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),

                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),

                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,

                          reservedSize: 28,

                          interval: xInterval,

                          getTitlesWidget: (value, meta) {
                            final index = value.round();

                            if (index < 0 || index >= days.length) {
                              return const SizedBox.shrink();
                            }

                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: RotatedBox(
                                quarterTurns: days.length > 14 ? 1 : 0,
                                child: Text(
                                  _formatDateLabel(
                                    days[index].date,
                                    days.length,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    fontSize: width < 400 ? 8 : 9,
                                    height: 1.0,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // ==================================================
                    // BORDER
                    // ==================================================
                    borderData: FlBorderData(show: false),

                    // ==================================================
                    // TOUCH
                    // ==================================================
                    lineTouchData: LineTouchData(
                      enabled: true,
                      handleBuiltInTouches: true,

                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) {
                          return Theme.of(context).colorScheme.inverseSurface;
                        },

                        tooltipBorderRadius: BorderRadius.circular(10),

                        fitInsideHorizontally: true,
                        fitInsideVertically: true,

                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final index = spot.x.round();

                            if (index < 0 || index >= days.length) {
                              return null;
                            }

                            final day = days[index];

                            final isIncome = spot.barIndex == 0;

                            final amount = isIncome ? day.income : day.expense;

                            return LineTooltipItem(
                              '${isIncome ? 'Income' : 'Expense'}\n'
                              '${_peso(amount)}',
                              TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onInverseSurface,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),

                    // ==================================================
                    // LINES
                    // ==================================================
                    lineBarsData: [
                      LineChartBarData(
                        spots: incomeSpots,
                        color: Colors.green,
                        barWidth: width < 400 ? 2 : 2.5,
                        isCurved: true,
                        curveSmoothness: 0.25,
                        preventCurveOverShooting: true,

                        dotData: FlDotData(
                          show: days.length <= 7,
                          getDotPainter: (spot, percent, bar, index) {
                            return FlDotCirclePainter(
                              radius: 3,
                              color: bar.color ?? Colors.grey,
                              strokeWidth: 0,
                              strokeColor: Colors.transparent,
                            );
                          },
                        ),

                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.green.withValues(alpha: 0.05),
                        ),

                        isStrokeCapRound: true,
                      ),

                      LineChartBarData(
                        spots: expenseSpots,
                        color: Colors.redAccent,
                        barWidth: width < 400 ? 2 : 2.5,
                        isCurved: true,
                        curveSmoothness: 0.25,
                        preventCurveOverShooting: true,

                        dotData: const FlDotData(show: false),

                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.redAccent.withValues(alpha: 0.04),
                        ),

                        isStrokeCapRound: true,
                      ),
                    ],
                  ),
                ),
              ),

              // ==================================================
              // LEGEND
              //
              // Smaller vertical footprint than the old version.
              // ==================================================
              const SizedBox(height: 4),

              const _TrendLegend(),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // SINGLE DAY VIEW
  // ============================================================

  Widget _buildSingleDayView(BuildContext context) {
    final day = days.first;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('MMMM d, yyyy').format(day.date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  height: 1.0,
                  color: scheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 8),

              Wrap(
                alignment: WrapAlignment.center,
                spacing: compact ? 24 : 40,
                runSpacing: 6,
                children: [
                  _SingleDayStat(
                    label: 'Income',
                    value: day.income,
                    color: Colors.green,
                  ),
                  _SingleDayStat(
                    label: 'Expense',
                    value: day.expense,
                    color: Colors.redAccent,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // Y AXIS INTERVAL
  // ============================================================

  static double _calculateYInterval(double maxY) {
    if (maxY <= 100) return 25;
    if (maxY <= 500) return 100;
    if (maxY <= 1000) return 250;
    if (maxY <= 5000) return 1000;
    if (maxY <= 10000) return 2500;
    if (maxY <= 50000) return 10000;
    if (maxY <= 100000) return 25000;
    if (maxY <= 500000) return 100000;

    return 250000;
  }

  // ============================================================
  // X AXIS INTERVAL
  // ============================================================

  static double _calculateXInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    if (count <= 21) return 3;
    if (count <= 31) return 5;
    return 7;
  }

  // ============================================================
  // DATE LABEL
  // ============================================================

  static String _formatDateLabel(DateTime date, int totalDays) {
    if (totalDays <= 7) {
      return DateFormat('EEE').format(date);
    }

    if (totalDays == 12 && date.day == 1) {
      return DateFormat('MMM').format(date);
    }

    return DateFormat('M/d').format(date);
  }
}

// ============================================================
// TREND LEGEND
// ============================================================

class _TrendLegend extends StatelessWidget {
  const _TrendLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: const [
        _LegendDot(color: Colors.green, label: 'Income'),
        SizedBox(width: 18),
        _LegendDot(color: Colors.redAccent, label: 'Expense'),
      ],
    );
  }
}

// ============================================================
// SINGLE DAY STAT
// ============================================================

class _SingleDayStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SingleDayStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),

            const SizedBox(width: 5),

            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                height: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 2),

        Text(
          _peso(value, compact: true),
          style: const TextStyle(
            fontSize: 14,
            height: 1.0,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
// ============================================================
// COLOR PALETTE (shared with category legends)
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

String _dashboardGreeting() {
  final hour = DateTime.now().hour;

  if (hour < 12) {
    return 'Good morning';
  }

  if (hour < 18) {
    return 'Good afternoon';
  }

  return 'Good evening';
}

// ============================================================
// PAGE
// ============================================================

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedPeriodProvider);
    final totalsAsync = ref.watch(periodTotalsProvider(period));
    final balancesAsync = ref.watch(accountBalancesProvider);
    final entriesAsync = ref.watch(journalEntriesProvider(period));
    final profileAsync = ref.watch(businessProfileProvider);
    final profile = profileAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final businessName = profile?.name ?? 'My Business';
    final ownerName = profile?.ownerName?.trim();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 190,
            collapsedHeight: kToolbarHeight,
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: scheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final topPadding = MediaQuery.paddingOf(context).top;
                final currentHeight = constraints.maxHeight;

                final expanded =
                    currentHeight > kToolbarHeight + topPadding + 45;

                return FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  titlePadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  title: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: expanded ? 0 : 1,
                    child: const Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  background: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // =====================================================
                            // TOP ROW
                            // =====================================================
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: scheme.primary,
                                    size: 22,
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'BOS',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                          color: scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        businessName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Period selector
                                _PeriodSelector(period: period),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // =====================================================
                            // GREETING
                            // =====================================================
                            Text(
                              ownerName == null || ownerName.isEmpty
                                  ? _dashboardGreeting()
                                  : '${_dashboardGreeting()}, $ownerName',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),

                            const SizedBox(height: 2),

                            Text(
                              'Dashboard',
                              style: TextStyle(
                                fontSize: 30,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                color: scheme.onSurface,
                              ),
                            ),

                            const SizedBox(height: 5),

                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 13,
                                  color: scheme.outline,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  DateFormat(
                                    'EEEE, MMMM d, yyyy',
                                  ).format(DateTime.now()),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                totalsAsync.when(
                  data: (totals) => balancesAsync.when(
                    data: (balances) => entriesAsync.when(
                      data: (entries) {
                        int sumOf(JournalEntryType type) => entries
                            .where((e) => e.type == type)
                            .fold<int>(0, (s, e) => s + e.amount);

                        return _SummaryHero(
                          income: totals.income,
                          expense: totals.expense,
                          capital: sumOf(JournalEntryType.capital),
                          asset: sumOf(JournalEntryType.asset),
                          liability: sumOf(JournalEntryType.liability),
                          cashPosition: balances.fold<int>(
                            0,
                            (s, b) => s + b.balance,
                          ),
                          period: period,
                        );
                      },
                      loading: () => const _HeroSkeleton(),
                      error: (_, __) => const _HeroSkeleton(),
                    ),
                    loading: () => const _HeroSkeleton(),
                    error: (_, __) => const _HeroSkeleton(),
                  ),
                  loading: () => const _HeroSkeleton(),
                  error: (e, _) => Text('Error: $e'),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: _ChartCard(
                        title: 'Expenses by Category',
                        color: Colors.redAccent,
                        child: _DonutSection(
                          asyncTotals: ref.watch(
                            categoryBreakdownProvider(('expense', period)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ChartCard(
                        title: 'Income by Category',
                        color: Colors.green,
                        child: _DonutSection(
                          asyncTotals: ref.watch(
                            categoryBreakdownProvider(('income', period)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _ChartCard(
                  title: 'Income vs Expense Trend',
                  color: scheme.primary,
                  child: ref
                      .watch(trendProvider(period))
                      .when(
                        data: (days) => _TrendChart(days: days),
                        loading: () => const SizedBox(
                          height: 150,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Unable to load trend data.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                ),
                const SizedBox(height: 16),

                _RecentActivityCard(entriesAsync: entriesAsync),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PERIOD SELECTOR
// ============================================================

class _PeriodSelector extends ConsumerWidget {
  final TransactionDateFilter period;

  const _PeriodSelector({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<TransactionDatePreset>(
      initialValue: period.preset,
      tooltip: 'Select period',
      onSelected: (selected) async {
        if (selected == TransactionDatePreset.custom) {
          final selectedRange = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            currentDate: DateTime.now(),
            initialDateRange: period.preset == TransactionDatePreset.custom
                ? period.range
                : null,
          );
          if (selectedRange == null) return;
          ref.read(selectedPeriodProvider.notifier).state =
              TransactionDateFilter.custom(selectedRange);
          return;
        }

        ref.read(selectedPeriodProvider.notifier).state = TransactionDateFilter(
          preset: selected,
        );
      },
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      itemBuilder: (context) {
        return TransactionDatePreset.values.map((preset) {
          final selected = preset == period.preset;

          return PopupMenuItem<TransactionDatePreset>(
            value: preset,
            child: Row(
              children: [
                Icon(
                  switch (preset) {
                    TransactionDatePreset.today => Icons.today_rounded,
                    TransactionDatePreset.week => Icons.view_week_rounded,
                    TransactionDatePreset.month => Icons.calendar_month_rounded,
                    TransactionDatePreset.year => Icons.date_range_rounded,
                    TransactionDatePreset.lastYear => Icons.history_rounded,
                    TransactionDatePreset.custom => Icons.event_rounded,
                  },
                  size: 19,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    TransactionDateFilter(preset: preset).label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range_rounded, size: 17, color: scheme.primary),
            const SizedBox(width: 7),
            Text(
              period.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SUMMARY HERO — gradient card with Income / Expense / Net / Cash
// ============================================================

class _SummaryHero extends StatelessWidget {
  final int income;
  final int expense;
  final int capital;
  final int asset;
  final int liability;
  final int cashPosition;
  final TransactionDateFilter period;
  const _SummaryHero({
    required this.income,
    required this.expense,
    required this.capital,
    required this.asset,
    required this.liability,
    required this.cashPosition,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final net = cashPosition;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${period.label} Net',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
              Icon(
                net >= 0 ? Icons.trending_up : Icons.trending_down,
                color: Colors.white.withValues(alpha: 0.9),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${net >= 0 ? '' : '-'}${_peso(net.abs())}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'Income',
                  value: income,
                  icon: Icons.arrow_downward,
                  positive: true,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _HeroStat(
                  label: 'Expenses',
                  value: expense,
                  icon: Icons.arrow_upward,
                  positive: false,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _HeroStat(
                  label: 'Cash',
                  value: cashPosition,
                  icon: Icons.account_balance_wallet,
                  positive: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'Capital',
                  value: capital,
                  icon: Icons.savings_outlined,
                  positive: true,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _HeroStat(
                  label: 'Assets',
                  value: asset,
                  icon: Icons.inventory_2_outlined,
                  positive: true,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _HeroStat(
                  label: 'Liabilities',
                  value: liability,
                  icon: Icons.request_quote_outlined,
                  positive: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final bool? positive;
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.white70),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _peso(value, compact: true),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ============================================================
// CHART CARD SHELL
// ============================================================

class _ChartCard extends StatelessWidget {
  final String title;
  final Color color;
  final Widget child;
  const _ChartCard({
    required this.title,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// DONUT CHART SECTION (category breakdown)
// ============================================================

class _DonutSection extends ConsumerWidget {
  final AsyncValue<List<CategoryTotal>> asyncTotals;
  const _DonutSection({required this.asyncTotals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncTotals.when(
      data: (totals) {
        if (totals.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No data for this period yet.')),
          );
        }
        final total = totals.fold<int>(0, (s, t) => s + t.total);

        return Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: [
                        for (var i = 0; i < totals.length; i++)
                          PieChartSectionData(
                            value: totals[i].total.toDouble(),
                            color: _palette[i % _palette.length],
                            radius: 20,
                            showTitle: false,
                          ),
                      ],
                      centerSpaceRadius: 34,
                      sectionsSpace: 2,
                    ),
                  ),
                  Text(
                    _peso(total, compact: true),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < totals.length && i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _palette[i % _palette.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              totals[i].name,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(totals[i].total / total * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 110,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Error: $e'),
    );
  }
}

// ============================================================
// TREND CHART (income vs expense over time)
// ============================================================

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
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
// RECENT ACTIVITY PEEK
// ============================================================

class _RecentActivityCard extends StatelessWidget {
  final AsyncValue<List<JournalEntryRow>> entriesAsync;
  const _RecentActivityCard({required this.entriesAsync});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Activity',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 12),
          entriesAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No transactions recorded yet.'),
                );
              }
              final recent = entries.take(5).toList();
              return Column(
                children: recent
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              e.status == 'pending'
                                  ? Icons.radio_button_unchecked
                                  : Icons.check_circle,
                              size: 16,
                              color: e.status == 'pending'
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                e.description?.isNotEmpty == true
                                    ? e.description!
                                    : e.categoryName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${e.type == JournalEntryType.income ? '+' : '-'}${_peso(e.amount, compact: true)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: e.type == JournalEntryType.income
                                    ? Colors.green.shade700
                                    : scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
