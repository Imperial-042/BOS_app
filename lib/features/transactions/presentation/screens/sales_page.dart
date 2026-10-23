// Sales & POS -> Sales
//
//   Overview   hero revenue card, insights, busiest hours, top previews
//   Cashiers   podium + ranked list (tap a cashier to see their sales)
//   Products   best sellers overall and ranked inside every category
//   History    every sale, grouped by day, with the cashier who punched it
//
// Stock-only checkouts are not sales and live in Checkout history. Voided
// sales appear in History (flagged) but never count in the numbers.

import 'dart:math' as math;

import 'package:bos_application/core/branding/branding.dart' show AppColors;
import 'package:bos_application/features/transactions/domain/receipt_text.dart';
import 'package:bos_application/features/transactions/domain/sales_analytics.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../transactions/presentation/providers/product_catalog_providers.dart'
    show productCategoriesProvider;
import 'pos_history_page.dart'
    show
        POSSaleDetailPage,
        paymentAccountNamesProvider,
        posPaymentsBySaleProvider,
        posSalesHistoryProvider,
        posTendersBySaleMapProvider;
import 'products_page.dart' show productsProvider;

// ============================================================================
// FORMATTING + PALETTE
// ============================================================================

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

String _pesoShort(int cents) {
  final v = cents / 100;
  if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 10000) return '₱${(v / 1000).toStringAsFixed(1)}K';
  return '₱${NumberFormat('#,##0').format(v)}';
}

String _qty(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
String _day(DateTime d) => DateFormat('EEE, MMM d, yyyy').format(d);
String _short(DateTime d) => DateFormat('MMM d').format(d);
String _time(DateTime d) => DateFormat('h:mm a').format(d);
String _hour(int h) => DateFormat('h a').format(DateTime(2000, 1, 1, h));

const _gold = Color(0xFFF5B301);
const _silver = Color(0xFF9AA5B1);
const _bronze = Color(0xFFCD7F32);

Color? _medal(int rank) => switch (rank) {
  1 => _gold,
  2 => _silver,
  3 => _bronze,
  _ => null,
};

const _palette = [
  Color(0xFF0F766E),
  Color(0xFF6366F1),
  Color(0xFFE11D48),
  Color(0xFFF59E0B),
  Color(0xFF0EA5E9),
  Color(0xFF9333EA),
  Color(0xFF16A34A),
  Color(0xFFEA580C),
];

Color _colorFor(String key) =>
    _palette[key.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];

// ============================================================================
// PERIOD
// ============================================================================

enum _Period { today, week, month30, thisMonth, all, custom }

extension on _Period {
  String get label => switch (this) {
    _Period.today => 'Today',
    _Period.week => 'Last 7 days',
    _Period.month30 => 'Last 30 days',
    _Period.thisMonth => 'This month',
    _Period.all => 'All time',
    _Period.custom => 'Custom',
  };
}

// ============================================================================
// PAGE
// ============================================================================

class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  _Period _period = _Period.week;
  DateTimeRange? _custom;
  RankBy _rankBy = RankBy.revenue;
  String? _cashierFilter;
  String? _catFilter;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  /// [start, end) — null means unbounded.
  (DateTime?, DateTime?) get _bounds {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (_period) {
      _Period.today => (today, tomorrow),
      _Period.week => (today.subtract(const Duration(days: 6)), tomorrow),
      _Period.month30 => (today.subtract(const Duration(days: 29)), tomorrow),
      _Period.thisMonth => (DateTime(now.year, now.month, 1), tomorrow),
      _Period.all => (null, null),
      _Period.custom =>
        _custom == null
            ? (null, null)
            : (
                _custom!.start,
                DateTime(
                  _custom!.end.year,
                  _custom!.end.month,
                  _custom!.end.day + 1,
                ),
              ),
    };
  }

  String get _periodLabel => _period == _Period.custom && _custom != null
      ? '${_short(_custom!.start)} – ${_short(_custom!.end)}'
      : _period.label;

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _custom,
    );
    if (range == null) return;
    setState(() {
      _custom = range;
      _period = _Period.custom;
      _cashierFilter = null;
    });
  }

  void _showCashierSales(String key) {
    setState(() => _cashierFilter = key);
    _tabs.animateTo(3);
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(posSalesHistoryProvider);
    final allItems = ref.watch(allPosSaleItemsProvider).value ?? const [];
    final cashierNames = ref.watch(cashierNamesProvider).value ?? const {};
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final categories = ref.watch(productCategoriesProvider).value ?? const [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Unable to load sales: $e')),
        data: (sales) {
          final (start, end) = _bounds;
          final inPeriod = sales.where((s) {
            if (s.isStockOnly) return false;
            if (start != null && s.saleDate.isBefore(start)) return false;
            if (end != null && !s.saleDate.isBefore(end)) return false;
            return true;
          }).toList();

          final report = buildSalesReport(
            sales: inPeriod,
            items: allItems,
            productCategory: {for (final p in products) p.id: p.categoryId},
            categoryNames: {for (final c in categories) c.id: c.name},
            cashierNames: cashierNames,
          );

          // Same-length window right before this one, for the growth chip.
          int? prevRevenue;
          if (start != null && end != null) {
            final prevStart = start.subtract(end.difference(start));
            prevRevenue = sales
                .where(
                  (s) =>
                      !s.isStockOnly &&
                      !saleIsVoided(s) &&
                      !s.saleDate.isBefore(prevStart) &&
                      s.saleDate.isBefore(start),
                )
                .fold<int>(0, (a, s) => a + s.totalAmount);
          }

          return Column(
            children: [
              _PeriodBar(
                selected: _period,
                custom: _custom,
                onSelected: (p) {
                  if (p == _Period.custom) {
                    _pickCustom();
                  } else {
                    setState(() {
                      _period = p;
                      _cashierFilter = null;
                    });
                  }
                },
              ),
              _TabSwitcher(controller: _tabs),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(
                      report: report,
                      prevRevenue: prevRevenue,
                      periodLabel: _periodLabel,
                      onGoTo: (i) => _tabs.animateTo(i),
                    ),
                    _CashiersTab(report: report, onOpen: _showCashierSales),
                    _ProductsTab(
                      report: report,
                      rankBy: _rankBy,
                      onRankBy: (v) => setState(() => _rankBy = v),
                      catFilter: _catFilter,
                      onCat: (k) => setState(() => _catFilter = k),
                    ),
                    _HistoryTab(
                      sales: inPeriod,
                      items: allItems,
                      cashierNames: cashierNames,
                      cashierFilter: _cashierFilter,
                      onCashier: (k) => setState(() => _cashierFilter = k),
                      searchController: _search,
                      query: _query,
                      onQuery: (v) => setState(() => _query = v),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// SHARED BUILDING BLOCKS
// ============================================================================

class _Scroll extends StatelessWidget {
  const _Scroll({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.max(16.0, (c.maxWidth - 1000) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 8, side, 40),
          children: children,
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Progress bar that grows in when it first appears.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, this.height = 6});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge(this.rank);
  final int rank;

  static const double _size = 26;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final medal = _medal(rank);
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: medal ?? scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: _size * 0.46,
          fontWeight: FontWeight.w900,
          color: medal != null ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.keyId, this.radius = 20});
  final String name;
  final String keyId;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(keyId);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.14),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PERIOD BAR + TAB SWITCHER
// ============================================================================

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.selected,
    required this.custom,
    required this.onSelected,
  });

  final _Period selected;
  final DateTimeRange? custom;
  final ValueChanged<_Period> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    String labelOf(_Period p) => p == _Period.custom && custom != null
        ? '${_short(custom!.start)} – ${_short(custom!.end)}'
        : p.label;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          for (final p in _Period.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: p == _Period.custom
                    ? Icon(
                        Icons.date_range_rounded,
                        size: 16,
                        color: selected == p
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      )
                    : null,
                label: Text(labelOf(p)),
                selected: selected == p,
                showCheckmark: false,
                selectedColor: scheme.primary,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected == p ? scheme.onPrimary : null,
                ),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected == p
                        ? Colors.transparent
                        : scheme.outlineVariant,
                  ),
                ),
                onSelected: (_) => onSelected(p),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: TabBar(
          controller: controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          splashBorderRadius: BorderRadius.circular(14),
          indicator: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          labelColor: scheme.onPrimary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
          tabs: const [
            Tab(height: 38, text: 'Overview'),
            Tab(height: 38, text: 'Cashiers'),
            Tab(height: 38, text: 'Products'),
            Tab(height: 38, text: 'History'),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// OVERVIEW TAB
// ============================================================================

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.report,
    required this.prevRevenue,
    required this.periodLabel,
    required this.onGoTo,
  });

  final SalesReport report;
  final int? prevRevenue;
  final String periodLabel;
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    if (report.salesCount == 0) {
      return _EmptyState(
        icon: Icons.insights_outlined,
        title: 'No sales in this period',
        message: report.voidedCount > 0
            ? '${report.voidedCount} voided sale'
                  '${report.voidedCount == 1 ? '' : 's'} not counted.'
            : 'Completed sales will be summarised and ranked here.',
      );
    }

    final top = report.topProducts(RankBy.revenue, limit: 3);
    final topMetric = top.isEmpty || top.first.revenueCents == 0
        ? 1.0
        : top.first.revenueCents.toDouble();

    return _Scroll(
      children: [
        _Hero(
          report: report,
          prevRevenue: prevRevenue,
          periodLabel: periodLabel,
        ),
        if (report.voidedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              '${report.voidedCount} voided sale'
              '${report.voidedCount == 1 ? '' : 's'} not counted.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const _Heading('Highlights'),
        _InsightsGrid(report: report),
        const _Heading('Busiest hours'),
        _HoursCard(hourly: report.hourly),
        _Heading(
          'Top sellers',
          trailing: TextButton(
            onPressed: () => onGoTo(2),
            child: const Text('See all'),
          ),
        ),
        _Card(
          child: Column(
            children: [
              for (var i = 0; i < top.length; i++)
                _ProductRow(
                  rank: i + 1,
                  product: top[i],
                  fraction: top[i].revenueCents / topMetric,
                  rankBy: RankBy.revenue,
                  showCategory: true,
                ),
            ],
          ),
        ),
        _Heading(
          'Top cashier',
          trailing: TextButton(
            onPressed: () => onGoTo(1),
            child: const Text('See all'),
          ),
        ),
        _CashierCard(
          cashier: report.cashiers.first,
          rank: 1,
          fraction: 1,
          share: report.revenueCents == 0
              ? 0
              : report.cashiers.first.revenueCents / report.revenueCents,
        ),
      ],
    );
  }
}

// ---- Hero ------------------------------------------------------------------

List<int> _series(Map<DateTime, int> daily) {
  if (daily.isEmpty) return const [];
  final keys = daily.keys.toList()..sort();
  var first = keys.first;
  final last = keys.last;
  final cap = last.subtract(const Duration(days: 30));
  if (first.isBefore(cap)) first = cap;
  final out = <int>[];
  for (
    var d = first;
    !d.isAfter(last);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    out.add(daily[d] ?? 0);
  }
  return out;
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.report,
    required this.prevRevenue,
    required this.periodLabel,
  });

  final SalesReport report;
  final int? prevRevenue;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = _series(report.daily);

    Widget? deltaChip;
    final prev = prevRevenue;
    if (prev != null) {
      final cur = report.revenueCents;
      String text;
      IconData icon;
      Color color;
      if (prev == 0) {
        text = cur > 0 ? 'No sales in the previous period' : '';
        icon = Icons.trending_flat_rounded;
        color = Colors.white70;
      } else {
        final pct = (cur - prev) / prev * 100;
        final up = pct >= 0;
        text = '${pct.abs().toStringAsFixed(1)}% vs previous period';
        icon = up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
        color = up ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);
      }
      if (text.isNotEmpty) {
        deltaChip = Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      }
    }

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'TOTAL REVENUE',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 11.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      periodLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: report.revenueCents.toDouble()),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _peso(v.round()),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                ),
                if (deltaChip != null) ...[
                  const SizedBox(height: 8),
                  deltaChip,
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: CustomPaint(painter: _SparklinePainter(series)),
                ),
                const SizedBox(height: 14),
                Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    stat('Sales', '${report.salesCount}'),
                    stat('Average sale', _pesoShort(report.averageSaleCents)),
                    stat('Items sold', _qty(report.itemsSold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final v = values.length == 1 ? [values.first, values.first] : values;
    final maxV = v.reduce(math.max).clamp(1, 1 << 40);
    final dx = size.width / (v.length - 1);
    double y(int value) => size.height - (value / maxV) * (size.height - 8) - 4;

    final pts = [for (var i = 0; i < v.length; i++) Offset(i * dx, y(v[i]))];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final cx = (p0.dx + p1.dx) / 2;
      line.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
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
          colors: [
            Colors.white.withValues(alpha: 0.32),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pts.last, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

// ---- Insights --------------------------------------------------------------

class _InsightsGrid extends StatelessWidget {
  const _InsightsGrid({required this.report});
  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final best = report.bestDay;
    final peak = report.peakHour;
    final topProduct = report.topProducts(RankBy.revenue, limit: 1);
    final topCashier = report.cashiers.first;

    final tiles = [
      if (best != null)
        _InsightTile(
          icon: Icons.emoji_events_outlined,
          color: _gold,
          label: 'Best day',
          value: _short(best.key),
          sub: _pesoShort(best.value),
        ),
      if (peak != null)
        _InsightTile(
          icon: Icons.schedule_rounded,
          color: const Color(0xFF6366F1),
          label: 'Peak hour',
          value: _hour(peak),
          sub: _pesoShort(report.hourly[peak] ?? 0),
        ),
      if (topProduct.isNotEmpty)
        _InsightTile(
          icon: Icons.local_fire_department_outlined,
          color: const Color(0xFFEA580C),
          label: 'Top seller',
          value: topProduct.first.name,
          sub: _pesoShort(topProduct.first.revenueCents),
        ),
      _InsightTile(
        icon: Icons.workspace_premium_outlined,
        color: const Color(0xFF0F766E),
        label: 'Top cashier',
        value: topCashier.name,
        sub: _pesoShort(topCashier.revenueCents),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final cols = c.maxWidth >= 700 ? 4 : 2;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  sub,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _HoursCard extends StatelessWidget {
  const _HoursCard({required this.hourly});
  final Map<int, int> hourly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hours = hourly.keys.toList()..sort();
    final from = hours.first;
    final to = hours.last;
    final maxV = hourly.values.fold<int>(1, math.max);
    final peak = hourly.entries.reduce((a, b) => b.value > a.value ? b : a).key;

    return _Card(
      child: Column(
        children: [
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = from; h <= to; h++)
                  Expanded(
                    child: Tooltip(
                      message: '${_hour(h)} · ${_peso(hourly[h] ?? 0)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: math.max(
                              0.05,
                              (hourly[h] ?? 0) / maxV,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: h == peak
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.26),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _hour(from),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                'Peak ${_hour(peak)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                _hour(to),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CASHIERS TAB
// ============================================================================

class _CashiersTab extends StatelessWidget {
  const _CashiersTab({required this.report, required this.onOpen});

  final SalesReport report;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (report.salesCount == 0) {
      return const _EmptyState(
        icon: Icons.groups_outlined,
        title: 'No cashier activity',
        message: 'Cashiers are ranked here once sales are made.',
      );
    }

    final cashiers = report.cashiers;
    final topRevenue = cashiers.first.revenueCents == 0
        ? 1
        : cashiers.first.revenueCents;

    return _Scroll(
      children: [
        if (cashiers.length > 1) ...[
          _Card(
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 0),
            child: _Podium(top: cashiers.take(3).toList()),
          ),
          const SizedBox(height: 6),
        ],
        const _Heading('Leaderboard'),
        for (var i = 0; i < cashiers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CashierCard(
              cashier: cashiers[i],
              rank: i + 1,
              fraction: cashiers[i].revenueCents / topRevenue,
              share: report.revenueCents == 0
                  ? 0
                  : cashiers[i].revenueCents / report.revenueCents,
              onTap: () => onOpen(cashiers[i].key),
            ),
          ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top});
  final List<CashierSales> top;

  @override
  Widget build(BuildContext context) {
    final order = <int>[if (top.length > 1) 1, 0, if (top.length > 2) 2];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in order)
          Expanded(
            child: _PodiumSlot(cashier: top[i], rank: i + 1),
          ),
      ],
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({required this.cashier, required this.rank});
  final CashierSales cashier;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = _medal(rank)!;
    final height = switch (rank) {
      1 => 92.0,
      2 => 68.0,
      _ => 52.0,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1)
          const Icon(Icons.workspace_premium_rounded, color: _gold, size: 26)
        else
          const SizedBox(height: 26),
        const SizedBox(height: 2),
        _Avatar(
          name: cashier.name,
          keyId: cashier.key,
          radius: rank == 1 ? 30 : 24,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            cashier.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          _pesoShort(cashier.revenueCents),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: height),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (_, h, _) => Container(
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [medal, medal.withValues(alpha: 0.7)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CashierCard extends StatelessWidget {
  const _CashierCard({
    required this.cashier,
    required this.rank,
    required this.fraction,
    required this.share,
    this.onTap,
  });

  final CashierSales cashier;
  final int rank;
  final double fraction;
  final double share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _colorFor(cashier.key);

    return _Card(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RankBadge(rank),
          const SizedBox(width: 10),
          _Avatar(name: cashier.name, keyId: cashier.key, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cashier.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${cashier.salesCount} sale'
                  '${cashier.salesCount == 1 ? '' : 's'} · '
                  'avg ${_pesoShort(cashier.averageCents)} · '
                  '${_qty(cashier.itemsSold)} items',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _Bar(value: fraction, color: color),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _peso(cashier.revenueCents),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${(share * 100).round()}% of sales',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PRODUCTS TAB
// ============================================================================

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({
    required this.report,
    required this.rankBy,
    required this.onRankBy,
    required this.catFilter,
    required this.onCat,
  });

  final SalesReport report;
  final RankBy rankBy;
  final ValueChanged<RankBy> onRankBy;
  final String? catFilter;
  final ValueChanged<String?> onCat;

  @override
  Widget build(BuildContext context) {
    if (report.salesCount == 0) {
      return const _EmptyState(
        icon: Icons.local_fire_department_outlined,
        title: 'No products sold yet',
        message: 'Best sellers appear here once sales are made.',
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final cats = report.categories;
    final selected = catFilter == null
        ? null
        : cats.where((c) => c.key == catFilter).firstOrNull;

    double metric(ProductSales p) =>
        rankBy == RankBy.revenue ? p.revenueCents.toDouble() : p.qty;

    final topAll = report.topProducts(rankBy, limit: 10);
    final topMetric = topAll.isEmpty || metric(topAll.first) <= 0
        ? 1.0
        : metric(topAll.first);

    return _Scroll(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<RankBy>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: RankBy.revenue,
                icon: Icon(Icons.payments_outlined, size: 16),
                label: Text('By revenue'),
              ),
              ButtonSegment(
                value: RankBy.units,
                icon: Icon(Icons.shopping_bag_outlined, size: 16),
                label: Text('By units'),
              ),
            ],
            selected: {rankBy},
            onSelectionChanged: (s) => onRankBy(s.first),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All categories'),
                  selected: selected == null,
                  showCheckmark: false,
                  onSelected: (_) => onCat(null),
                ),
              ),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 5,
                      backgroundColor: _colorFor(c.key),
                    ),
                    label: Text(c.name),
                    selected: selected?.key == c.key,
                    showCheckmark: false,
                    onSelected: (_) => onCat(c.key),
                  ),
                ),
            ],
          ),
        ),
        if (selected == null) ...[
          const _Heading('Top 10 overall'),
          _Card(
            child: Column(
              children: [
                for (var i = 0; i < topAll.length; i++)
                  _ProductRow(
                    rank: i + 1,
                    product: topAll[i],
                    fraction: metric(topAll[i]) / topMetric,
                    rankBy: rankBy,
                    showCategory: true,
                  ),
              ],
            ),
          ),
          const _Heading('By category'),
          for (var i = 0; i < cats.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CategoryCard(
                category: cats[i],
                totalRevenue: report.revenueCents,
                rankBy: rankBy,
                initiallyExpanded: i == 0,
              ),
            ),
        ] else ...[
          const SizedBox(height: 12),
          _CategoryCard(
            key: ValueKey('only-${selected.key}'),
            category: selected,
            totalRevenue: report.revenueCents,
            rankBy: rankBy,
            initiallyExpanded: true,
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Ranking by units compares quantities inside each list, so mixed '
          'units (pcs vs kg) are not directly comparable.',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.rank,
    required this.product,
    required this.fraction,
    required this.rankBy,
    this.showCategory = false,
  });

  final int rank;
  final ProductSales product;
  final double fraction;
  final RankBy rankBy;
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final barColor = _medal(rank) ?? scheme.primary;

    final revenue = _peso(product.revenueCents);
    final units = '${_qty(product.qty)} ${product.unit}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RankBadge(rank),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (showCategory)
                  Text(
                    product.categoryName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 6),
                _Bar(value: fraction, color: barColor, height: 5),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rankBy == RankBy.revenue ? revenue : units,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                rankBy == RankBy.revenue ? units : revenue,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.category,
    required this.totalRevenue,
    required this.rankBy,
    required this.initiallyExpanded,
  });

  final CategorySales category;
  final int totalRevenue;
  final RankBy rankBy;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _colorFor(category.key);
    final ranked = category.ranked(rankBy);

    double metric(ProductSales p) =>
        rankBy == RankBy.revenue ? p.revenueCents.toDouble() : p.qty;
    final topMetric = metric(ranked.first) <= 0 ? 1.0 : metric(ranked.first);
    final share = totalRevenue == 0
        ? 0.0
        : category.revenueCents / totalRevenue;

    return _Card(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey('sales-cat-${category.key}'),
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.category_rounded, size: 21, color: color),
        ),
        title: Text(
          category.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${category.productCount} product'
                '${category.productCount == 1 ? '' : 's'} · '
                '${_peso(category.revenueCents)} · '
                '${(share * 100).round()}% of sales',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              _Bar(value: share, color: color, height: 4),
            ],
          ),
        ),
        children: [
          for (var i = 0; i < ranked.length; i++)
            _ProductRow(
              rank: i + 1,
              product: ranked[i],
              fraction: metric(ranked[i]) / topMetric,
              rankBy: rankBy,
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// HISTORY TAB
// ============================================================================

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({
    required this.sales,
    required this.items,
    required this.cashierNames,
    required this.cashierFilter,
    required this.onCashier,
    required this.searchController,
    required this.query,
    required this.onQuery,
  });

  final List<PosSale> sales; // period-filtered, sales only
  final List<PosSaleItem> items;
  final Map<String, String> cashierNames;
  final String? cashierFilter;
  final ValueChanged<String?> onCashier;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<String> onQuery;

  String _keyOf(PosSale s) {
    final id = saleCashierId(s);
    return (id == null || id.isEmpty) ? kUnknownCashierKey : id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accounts = ref.watch(paymentAccountNamesProvider).value ?? const {};
    final payments = ref.watch(posPaymentsBySaleProvider).value ?? const {};

    if (sales.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No sales in this period',
        message: 'Sales made at the POS will be listed here.',
      );
    }

    final itemCount = <String, int>{};
    for (final i in items) {
      itemCount[i.saleId] = (itemCount[i.saleId] ?? 0) + 1;
    }

    final tendersBySale =
        ref.watch(posTendersBySaleMapProvider).value ??
        const <String, List<PosSaleTender>>{};

    String? methodOf(PosSale s) {
      final tenders = tendersBySale[s.id];
      if (tenders != null && tenders.isNotEmpty) {
        final names = <String>{
          for (final t in tenders) accounts[t.accountId] ?? 'Account',
        };
        final providers = <String>{
          for (final t in tenders)
            if (t.provider != null) t.provider!,
        };
        final base = names.join(' + ');
        return providers.isEmpty ? base : '$base · ${providers.join(', ')}';
      }
      final account = accounts[s.paymentAccountId];
      final provider = payments[s.id]?.provider;
      if (account == null) return provider;
      return provider == null ? account : '$account · $provider';
    }

    final cashierKeys = <String, String>{};
    for (final s in sales) {
      cashierKeys[_keyOf(s)] = cashierLabel(s, cashierNames);
    }

    final q = query.trim().toLowerCase();
    final filtered = sales.where((s) {
      if (cashierFilter != null && _keyOf(s) != cashierFilter) return false;
      if (q.isEmpty) return true;
      final haystack = [
        s.id.substring(0, 6),
        cashierLabel(s, cashierNames),
        methodOf(s) ?? '',
        payments[s.id]?.referenceNo ?? '',
        s.notes ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();

    final rows = <Object>[];
    final dayTotals = <DateTime, int>{};
    DateTime? current;
    var filteredTotal = 0;
    for (final s in filtered) {
      final d = DateTime(s.saleDate.year, s.saleDate.month, s.saleDate.day);
      if (d != current) {
        current = d;
        rows.add(d);
      }
      if (!saleIsVoided(s)) {
        dayTotals[d] = (dayTotals[d] ?? 0) + s.totalAmount;
        filteredTotal += s.totalAmount;
      }
      rows.add(s);
    }

    return _Scroll(
      children: [
        TextField(
          controller: searchController,
          onChanged: onQuery,
          decoration: InputDecoration(
            hintText: 'Search cashier, method, reference or note...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      searchController.clear();
                      onQuery('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All cashiers'),
                  selected: cashierFilter == null,
                  showCheckmark: false,
                  onSelected: (_) => onCashier(null),
                ),
              ),
              for (final e in cashierKeys.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 9,
                      backgroundColor: _colorFor(e.key).withValues(alpha: 0.2),
                      child: Text(
                        e.value.isEmpty ? '?' : e.value[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: _colorFor(e.key),
                        ),
                      ),
                    ),
                    label: Text(e.value),
                    selected: cashierFilter == e.key,
                    showCheckmark: false,
                    onSelected: (_) => onCashier(e.key),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
          child: Text(
            '${filtered.length} sale${filtered.length == 1 ? '' : 's'} · '
            '${_peso(filteredTotal)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No sales match your filters.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          for (final row in rows)
            if (row is DateTime)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _day(row),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _peso(dayTotals[row] ?? 0),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SaleTile(
                  sale: row as PosSale,
                  cashierKey: _keyOf(row),
                  cashier: cashierLabel(row, cashierNames),
                  method: methodOf(row),
                  lines: itemCount[row.id] ?? 0,
                ),
              ),
      ],
    );
  }
}

class _SaleTile extends ConsumerWidget {
  const _SaleTile({
    required this.sale,
    required this.cashierKey,
    required this.cashier,
    required this.method,
    required this.lines,
  });

  final PosSale sale;
  final String cashierKey;
  final String cashier;
  final String? method;
  final int lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final voided = saleIsVoided(sale);
    final isCash = (method ?? '').toLowerCase().contains('cash');
    final syncInfo = ref.watch(posSaleSyncProvider).value?.of(sale.id);

    return _Card(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => POSSaleDetailPage(sale: sale)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(name: cashier, keyId: cashierKey, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        cashier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (voided) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'VOIDED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_time(sale.saleDate)} · ${receiptLabel(sale)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isCash
                          ? Icons.payments_outlined
                          : Icons.account_balance_wallet_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$lines item${lines == 1 ? '' : 's'}'
                        '${(sale.orderType ?? '').isEmpty ? '' : ' · ${sale.orderType}'}'
                        '${method == null ? '' : ' · $method'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (syncInfo != null) ...[
                  const SizedBox(height: 6),
                  SyncChip(info: syncInfo),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _peso(sale.totalAmount),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: voided ? scheme.onSurfaceVariant : scheme.primary,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
