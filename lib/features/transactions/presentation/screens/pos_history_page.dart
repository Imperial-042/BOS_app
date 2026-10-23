// lib/features/production/presentation/screens/pos_history_page.dart
//
// Checkout history + receipt detail. Receipts show the payment method used
// and, when a payment screenshot was scanned at checkout, its details
// (provider, reference no., amount paid, date/time) and the photo.

import 'dart:io';
import 'dart:math' as math;

import 'package:bos_application/core/auth/approval_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/domain/pos_session_service.dart';
import 'package:bos_application/features/transactions/domain/receipt_text.dart';
import 'package:bos_application/features/transactions/domain/sales_analytics.dart';
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_sync_status.dart';
import 'package:bos_application/features/transactions/presentation/screens/products_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/manager_approval_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId;

String _peso(int cents) => formatPeso(cents);
String _formatDate(DateTime d) => DateFormat('MMM d, yyyy').format(d);
String _formatTime(DateTime d) => DateFormat('h:mm a').format(d);
String _formatDateTime(DateTime d) =>
    DateFormat('MMM d, yyyy · h:mm a').format(d);

final posSalesHistoryProvider = StreamProvider<List<PosSale>>((ref) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  final branchId = ref.watch(selectedBranchIdProvider);
  final isMain = branchId == AppDatabase.mainBranchId(kCurrentBusinessId);
  return (db.select(db.posSales)
        ..where(
          (s) =>
              s.businessId.equals(kCurrentBusinessId) &
              (isMain
                  ? (s.branchId.equals(branchId) | s.branchId.isNull())
                  : s.branchId.equals(branchId)),
        )
        ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]))
      .watch();
});

final posSaleItemsProvider = StreamProvider.family<List<PosSaleItem>, String>((
  ref,
  saleId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.posSaleItems,
  )..where((i) => i.saleId.equals(saleId))).watch();
});

/// Every saved payment proof, keyed by sale id.
final posPaymentsBySaleProvider = StreamProvider<Map<String, PosSalePayment>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.posSalePayments)
      .watch()
      .map((rows) => {for (final r in rows) r.saleId: r});
});

/// Account id -> name, so a sale's paymentAccountId can be shown as
/// "GCash", "Cash on Hand", etc.
final paymentAccountNamesProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)
        ..where((a) => a.businessId.equals(kCurrentBusinessId)))
      .watch()
      .map((rows) => {for (final a in rows) a.id: a.name});
});

/// All tenders grouped by sale id (split payments, change, references).
final posTendersBySaleMapProvider =
    StreamProvider<Map<String, List<PosSaleTender>>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.select(db.posSaleTenders).watch().map((rows) {
        final map = <String, List<PosSaleTender>>{};
        for (final r in rows) {
          (map[r.saleId] ??= <PosSaleTender>[]).add(r);
        }
        return map;
      });
    });

/// Live copy of one sale, so the receipt page updates after void / restore.
final posSaleByIdProvider = StreamProvider.family<PosSale?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.posSales,
  )..where((s) => s.id.equals(id))).watchSingleOrNull();
});

class POSHistoryPage extends ConsumerStatefulWidget {
  const POSHistoryPage({super.key});

  @override
  ConsumerState<POSHistoryPage> createState() => _POSHistoryPageState();
}

enum _RangeKey { today, week, month, all, custom }

enum _TypeFilter { all, sales, stockOnly, voided }

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEEE, MMM d, yyyy').format(d);
}

/// The proof photo of a sale: legacy payment row first, then any tender.
String? _proofPathOf(
  PosSale sale,
  PosSalePayment? payment,
  List<PosSaleTender>? tenders,
) {
  if (sale.isStockOnly) return null;
  final p = payment?.photoPath;
  if (p != null && p.trim().isNotEmpty) return p;
  for (final t in tenders ?? const <PosSaleTender>[]) {
    final path = _tenderPhotoPath(t);
    if (path != null) return path;
  }
  return null;
}

class _POSHistoryPageState extends ConsumerState<POSHistoryPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _RangeKey _rangeKey = _RangeKey.today;
  _TypeFilter _type = _TypeFilter.all;
  DateTimeRange? _custom;
  String? _selectedId;
  bool _filtersOpen = false; // filter panel is hidden by default

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// [start, end) or null for "all".
  DateTimeRange? get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (_rangeKey) {
      _RangeKey.today => DateTimeRange(start: today, end: tomorrow),
      _RangeKey.week => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: tomorrow,
      ),
      _RangeKey.month => DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: tomorrow,
      ),
      _RangeKey.custom =>
        _custom == null
            ? null
            : DateTimeRange(
                start: _custom!.start,
                end: DateTime(
                  _custom!.end.year,
                  _custom!.end.month,
                  _custom!.end.day,
                ).add(const Duration(days: 1)),
              ),
      _RangeKey.all => null,
    };
  }

  String get _rangeLabel => switch (_rangeKey) {
    _RangeKey.today => 'Today',
    _RangeKey.week => 'Last 7 days',
    _RangeKey.month => 'This month',
    _RangeKey.all => 'All time',
    _RangeKey.custom =>
      _custom == null
          ? 'Custom'
          : '${DateFormat('MMM d').format(_custom!.start)} – '
                '${DateFormat('MMM d').format(_custom!.end)}',
  };

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _custom,
    );
    if (picked != null && mounted) {
      setState(() {
        _custom = picked;
        _rangeKey = _RangeKey.custom;
      });
    }
  }

  // ---------- filters (one hideable panel, hidden by default) ----------

  String _typeLabel(_TypeFilter t) => switch (t) {
    _TypeFilter.all => 'All types',
    _TypeFilter.sales => 'Sales',
    _TypeFilter.stockOnly => 'Stock-only',
    _TypeFilter.voided => 'Voided',
  };

  IconData _typeIcon(_TypeFilter t) => switch (t) {
    _TypeFilter.all => Icons.apps_rounded,
    _TypeFilter.sales => Icons.point_of_sale_rounded,
    _TypeFilter.stockOnly => Icons.inventory_2_outlined,
    _TypeFilter.voided => Icons.block_rounded,
  };

  String _rangeOptionLabel(_RangeKey k) => switch (k) {
    _RangeKey.today => 'Today',
    _RangeKey.week => 'Last 7 days',
    _RangeKey.month => 'This month',
    _RangeKey.all => 'All time',
    _RangeKey.custom => _custom == null ? 'Custom range…' : _rangeLabel,
  };

  IconData _rangeIcon(_RangeKey k) => switch (k) {
    _RangeKey.today => Icons.today_rounded,
    _RangeKey.week => Icons.view_week_rounded,
    _RangeKey.month => Icons.calendar_month_rounded,
    _RangeKey.all => Icons.all_inclusive_rounded,
    _RangeKey.custom => Icons.date_range_rounded,
  };

  /// How many filters differ from the defaults (Today + All types).
  int get _activeFilters =>
      (_rangeKey != _RangeKey.today ? 1 : 0) +
      (_type != _TypeFilter.all ? 1 : 0);

  Widget _dropdownField<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<(T, String, IconData)> items,
    required ValueChanged<T> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        prefixIcon: Icon(icon, size: 20, color: scheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.$1,
                child: Row(
                  children: [
                    Icon(i.$3, size: 18),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        i.$2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _filterPanel() {
    final scheme = Theme.of(context).colorScheme;

    final rangeField = _dropdownField<_RangeKey>(
      label: 'Date',
      icon: Icons.date_range_rounded,
      value: _rangeKey,
      items: [
        for (final k in _RangeKey.values)
          (k, _rangeOptionLabel(k), _rangeIcon(k)),
      ],
      onChanged: (k) {
        if (k == _RangeKey.custom) {
          _pickCustom();
        } else {
          setState(() => _rangeKey = k);
        }
      },
    );

    final typeField = _dropdownField<_TypeFilter>(
      label: 'Type',
      icon: Icons.category_outlined,
      value: _type,
      items: [
        for (final t in _TypeFilter.values) (t, _typeLabel(t), _typeIcon(t)),
      ],
      onChanged: (t) => setState(() => _type = t),
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth >= 480) {
                return Row(
                  children: [
                    Expanded(child: rangeField),
                    const SizedBox(width: 12),
                    Expanded(child: typeField),
                  ],
                );
              }
              return Column(
                children: [rangeField, const SizedBox(height: 12), typeField],
              );
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _activeFilters == 0
                  ? null
                  : () => setState(() {
                      _rangeKey = _RangeKey.today;
                      _type = _TypeFilter.all;
                    }),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text(
                'Reset filters',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Search box + a filter button (with a badge when filters are active).
  /// The filter panel itself is hidden until the button is tapped.
  Widget _filterBar() {
    final scheme = Theme.of(context).colorScheme;
    final active = _activeFilters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _searchField()),
            const SizedBox(width: 10),
            Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: IconButton.filledTonal(
                tooltip: _filtersOpen ? 'Hide filters' : 'Show filters',
                onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
                icon: Icon(
                  _filtersOpen
                      ? Icons.filter_list_off_rounded
                      : Icons.filter_list_rounded,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            '$_rangeLabel · ${_typeLabel(_type)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _filtersOpen
              ? _filterPanel()
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _searchField() {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Search receipt #, cashier, method, reference...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: border,
        enabledBorder: border,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final salesAsync = ref.watch(posSalesHistoryProvider);
    final payments = ref.watch(posPaymentsBySaleProvider).value ?? const {};
    final tendersBySale =
        ref.watch(posTendersBySaleMapProvider).value ??
        const <String, List<PosSaleTender>>{};
    final accountNames =
        ref.watch(paymentAccountNamesProvider).value ?? const {};
    final cashierNames = ref.watch(cashierNamesProvider).value ?? const {};

    String? methodOf(PosSale s) {
      if (s.isStockOnly) return null;
      final tenders = tendersBySale[s.id];
      if (tenders != null && tenders.isNotEmpty) {
        final names = <String>{
          for (final t in tenders) tenderLabel(accountNames[t.accountId]),
        };
        final providers = <String>{
          for (final t in tenders)
            if (t.provider != null) t.provider!,
        };
        final base = names.join(' + ');
        return providers.isEmpty ? base : '$base · ${providers.join(', ')}';
      }
      final account = accountNames[s.paymentAccountId];
      final provider = payments[s.id]?.provider;
      if (account == null) return provider;
      return provider == null ? account : '$account · $provider';
    }

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Checkout history',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              'Every POS receipt, sales and stock-only',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      body: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Unable to load history: $e')),
        data: (sales) {
          if (sales.isEmpty) {
            return const _EmptyHistoryState(
              title: 'No checkouts yet',
              message:
                  'Every completed POS order, sales and stock-only, will '
                  'show up here.',
            );
          }

          final range = _range;
          final scoped = sales.where((s) {
            if (range == null) return true;
            return !s.saleDate.isBefore(range.start) &&
                s.saleDate.isBefore(range.end);
          }).toList();

          final typed = scoped.where((s) {
            return switch (_type) {
              _TypeFilter.all => true,
              _TypeFilter.sales => !s.isStockOnly && !s.isVoided,
              _TypeFilter.stockOnly => s.isStockOnly,
              _TypeFilter.voided => s.isVoided,
            };
          }).toList();

          final query = _query.trim().toLowerCase();
          final filtered = query.isEmpty
              ? typed
              : typed.where((s) {
                  final tenderRefs =
                      (tendersBySale[s.id] ?? const <PosSaleTender>[])
                          .map((t) => t.referenceNo ?? '')
                          .join(' ');
                  final searchable = [
                    _formatDate(s.saleDate),
                    s.isStockOnly ? 'stock only' : 'sale',
                    s.isVoided ? 'void voided' : '',
                    cashierLabel(s, cashierNames),
                    methodOf(s) ?? '',
                    payments[s.id]?.referenceNo ?? '',
                    payments[s.id]?.provider ?? '',
                    tenderRefs,
                    s.id.substring(0, 8),
                    s.receiptNo ?? '',
                    s.orderType ?? '',
                    s.tableLabel ?? '',
                    s.orderRef ?? '',
                    s.contactName ?? '',
                    s.contactPhone ?? '',
                    s.notes ?? '',
                  ].join(' ').toLowerCase();
                  return searchable.contains(query);
                }).toList();

          // Group by day (sales are already newest first).
          final groups = <DateTime, List<PosSale>>{};
          for (final s in filtered) {
            final d = DateTime(
              s.saleDate.year,
              s.saleDate.month,
              s.saleDate.day,
            );
            (groups[d] ??= <PosSale>[]).add(s);
          }

          return LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final wide = w >= 1000;
              final columns = wide ? 1 : (w >= 760 ? 2 : 1);
              final pad = w >= 600 ? 24.0 : 16.0;
              final listWidth = (w * 0.42).clamp(420.0, 540.0).toDouble();

              final selected = wide
                  ? (filtered.where((s) => s.id == _selectedId).firstOrNull ??
                        filtered.firstOrNull)
                  : null;

              Widget card(PosSale s) => _SaleHistoryCard(
                sale: s,
                cashier: cashierLabel(s, cashierNames),
                methodName: methodOf(s),
                proofPath: _proofPathOf(s, payments[s.id], tendersBySale[s.id]),
                selected: wide && selected?.id == s.id,
                onTap: () {
                  if (wide) {
                    setState(() => _selectedId = s.id);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => POSSaleDetailPage(sale: s),
                      ),
                    );
                  }
                },
              );

              final content = <Widget>[
                _HistorySummaryCard(sales: scoped, periodLabel: _rangeLabel),
                const SizedBox(height: 12),
                SyncSummaryBanner(saleIds: [for (final s in scoped) s.id]),
                const SizedBox(height: 14),
                _filterBar(),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: _EmptyHistoryState(
                      title: 'No receipts found',
                      message: 'Try a different date range, type or search.',
                    ),
                  )
                else
                  for (final entry in groups.entries) ...[
                    _DayHeader(
                      label: _dayLabel(entry.key),
                      count: entry.value.length,
                      total: entry.value
                          .where((s) => !s.isVoided && !s.isStockOnly)
                          .fold<int>(0, (a, s) => a + s.totalAmount),
                    ),
                    _CardGrid(
                      columns: columns,
                      children: [for (final s in entry.value) card(s)],
                    ),
                  ],
              ];

              final list = ListView(
                padding: EdgeInsets.fromLTRB(
                  pad,
                  4,
                  pad,
                  40 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: content,
              );

              if (!wide) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: list,
                  ),
                );
              }

              // Master-detail: list on the left, live receipt on the right.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: listWidth, child: list),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 20, 20),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: selected == null
                            ? const _EmptyHistoryState(
                                title: 'Select a receipt',
                                message:
                                    'Pick a receipt on the left to see its '
                                    'items and proof of payment.',
                              )
                            : POSSaleDetailPage(
                                key: ValueKey(selected.id),
                                sale: selected,
                                embedded: true,
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// ADAPTIVE CARD GRID
// ============================================================================

class _CardGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  const _CardGrid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    return LayoutBuilder(
      builder: (context, box) {
        final w = ((box.maxWidth - gap * (columns - 1)) / columns)
            .floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

// ============================================================================
// SUMMARY HERO
// ============================================================================

class _BarsPainter extends CustomPainter {
  final List<int> values;
  final Color color;
  _BarsPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce(math.max).clamp(1, 1 << 40);
    const gap = 5.0;
    final n = values.length;
    final bw = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final h = math.max(4.0, values[i] / maxV * size.height);
      final isLast = i == n - 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (bw + gap), size.height - h, bw, h),
          const Radius.circular(5),
        ),
        Paint()..color = color.withValues(alpha: isLast ? 0.95 : 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}

class _HistorySummaryCard extends StatelessWidget {
  final List<PosSale> sales;
  final String periodLabel;
  const _HistorySummaryCard({required this.sales, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final active = sales.where((s) => !s.isVoided).toList();
    final real = active.where((s) => !s.isStockOnly).toList();
    final revenue = real.fold<int>(0, (sum, s) => sum + s.totalAmount);
    final salesCount = real.length;
    final stockOnlyCount = active.where((s) => s.isStockOnly).length;
    final voidedCount = sales.length - active.length;
    final average = salesCount == 0 ? 0 : (revenue / salesCount).round();

    final byDay = <DateTime, int>{};
    for (final s in real) {
      final d = DateTime(s.saleDate.year, s.saleDate.month, s.saleDate.day);
      byDay[d] = (byDay[d] ?? 0) + s.totalAmount;
    }
    final keys = byDay.keys.toList()..sort();
    final shown = keys.length > 14 ? keys.sublist(keys.length - 14) : keys;
    final bars = [for (final k in shown) byDay[k]!];

    final stats = <(String, String, IconData)>[
      ('Sales', '$salesCount', Icons.receipt_long_rounded),
      ('Average', _peso(average), Icons.analytics_outlined),
      ('Stock-only', '$stockOnlyCount', Icons.inventory_2_outlined),
      if (voidedCount > 0) ('Voided', '$voidedCount', Icons.block_rounded),
    ];

    Widget tile((String, String, IconData) s, double width) => SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(s.$3, size: 15, color: Colors.white.withValues(alpha: 0.85)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                s.$2,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              s.$1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.72)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -70,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'TOTAL REVENUE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      periodLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: revenue.toDouble()),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _peso(v.round()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              if (bars.length >= 2) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: CustomPaint(painter: _BarsPainter(bars, Colors.white)),
                ),
              ],
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, box) {
                  const gap = 8.0;
                  final cols = box.maxWidth >= 460 ? stats.length : 2;
                  final w = ((box.maxWidth - gap * (cols - 1)) / cols)
                      .floorToDouble();
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [for (final s in stats) tile(s, w)],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DAY HEADER
// ============================================================================

class _DayHeader extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  const _DayHeader({
    required this.label,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$count receipt${count == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _peso(total),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyHistoryState extends StatelessWidget {
  final String title;
  final String message;
  const _EmptyHistoryState({required this.title, required this.message});

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
              child: Icon(
                Icons.receipt_long_outlined,
                size: 38,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
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
// SALE CARD
// ============================================================================

class _SaleHistoryCard extends ConsumerWidget {
  final PosSale sale;
  final String cashier;
  final String? methodName;
  final String? proofPath;
  final bool selected;
  final VoidCallback onTap;

  const _SaleHistoryCard({
    required this.sale,
    required this.cashier,
    required this.methodName,
    required this.proofPath,
    required this.selected,
    required this.onTap,
  });

  Widget _miniChip(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final itemsAsync = ref.watch(posSaleItemsProvider(sale.id));
    final syncInfo = ref.watch(posSaleSyncProvider).value?.of(sale.id);

    final voided = sale.isVoided;
    final stockOnly = sale.isStockOnly;
    final accent = voided
        ? scheme.error
        : stockOnly
        ? Colors.orange.shade800
        : scheme.primary;

    final proofFile = proofPath == null ? null : File(proofPath!);
    final hasProof = proofFile != null && proofFile.existsSync();

    final Widget leading = hasProof
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  proofFile,
                  width: 52,
                  height: 62,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  cacheWidth: 160,
                  errorBuilder: (_, __, ___) => Container(
                    width: 52,
                    height: 62,
                    color: scheme.surfaceContainerHigh,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Positioned(
                right: -5,
                bottom: -5,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.verified_rounded,
                    size: 17,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          )
        : Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              voided
                  ? Icons.block_rounded
                  : stockOnly
                  ? Icons.inventory_2_outlined
                  : Icons.point_of_sale_rounded,
              color: accent,
            ),
          );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 10),
          child: child,
        ),
      ),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.6),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---- receipt number + amount on one line ----
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    receiptLabel(sale),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (voided) ...[
                                  const SizedBox(width: 6),
                                  const _VoidChip(),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            stockOnly ? 'No income' : _peso(sale.totalAmount),
                            maxLines: 1,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              decoration: voided
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: (stockOnly || voided)
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatTime(sale.saleDate)} · $cashier',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ---- badges: full width, wrap to as many lines as needed ----
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          itemsAsync.maybeWhen(
                            data: (items) => _miniChip(
                              context,
                              Icons.shopping_bag_outlined,
                              '${items.length} item'
                              '${items.length == 1 ? '' : 's'}',
                            ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                          if (stockOnly)
                            _miniChip(
                              context,
                              Icons.inventory_2_outlined,
                              'Stock deduction',
                              color: Colors.orange.shade800,
                            ),
                          if ((sale.orderType ?? '').isNotEmpty)
                            _miniChip(
                              context,
                              Icons.local_offer_outlined,
                              sale.orderType!,
                            ),
                          if ((sale.tableLabel ?? '').isNotEmpty)
                            _miniChip(
                              context,
                              Icons.table_restaurant_rounded,
                              sale.tableLabel!,
                            ),
                          if ((sale.orderRef ?? '').isNotEmpty)
                            _miniChip(
                              context,
                              Icons.tag_rounded,
                              sale.orderRef!,
                            ),
                          if (methodName != null)
                            _miniChip(
                              context,
                              Icons.account_balance_wallet_outlined,
                              methodName!,
                            ),
                          if (hasProof)
                            _miniChip(
                              context,
                              Icons.verified_outlined,
                              'Proof attached',
                              color: Colors.green.shade700,
                            ),
                        ],
                      ),
                      // ---- sync status on its own line ----
                      if (syncInfo != null) ...[
                        const SizedBox(height: 8),
                        SyncChip(info: syncInfo),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// RECEIPT DETAIL
// ============================================================================

class POSSaleDetailPage extends ConsumerWidget {
  final PosSale sale;
  final bool embedded;
  const POSSaleDetailPage({
    super.key,
    required this.sale,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Live copy so the page refreshes after void / restore.
    final sale =
        ref.watch(posSaleByIdProvider(this.sale.id)).value ?? this.sale;
    final itemsAsync = ref.watch(posSaleItemsProvider(sale.id));
    final tenders =
        ref.watch(posTendersBySaleMapProvider).value?[sale.id] ??
        const <PosSaleTender>[];
    final allAccountNames =
        ref.watch(paymentAccountNamesProvider).value ??
        const <String, String>{};
    final openSession = ref.watch(currentPosSessionProvider).value;
    String? customerName;
    String? customerAddress;
    String? customerTin;
    final customerId = sale.customerId;
    if (customerId != null) {
      for (final c
          in ref.watch(customersProvider).value ?? const <Customer>[]) {
        if (c.id == customerId) {
          customerName = c.name;
          customerAddress = c.address;
          customerTin = c.tin;
        }
      }
    }
    final canVoid = ref.watch(canProvider(BosPermission.salesVoid));
    final approvalOn = ref.watch(approvalEnabledProvider).value ?? false;
    // With approvals on, anyone can ask; a manager PIN is what authorises it.
    // With approvals off, only people with the void permission see the button.
    final canChange =
        (canVoid || approvalOn) &&
        sale.sessionId != null &&
        openSession?.id == sale.sessionId;
    final payment = sale.isStockOnly
        ? null
        : (ref.watch(posPaymentsBySaleProvider).value ?? const {})[sale.id];
    final methodName = sale.isStockOnly
        ? null
        : (ref.watch(paymentAccountNamesProvider).value ??
              const {})[sale.paymentAccountId];
    final cashierNames = ref.watch(cashierNamesProvider).value ?? const {};
    final cashier = cashierLabel(sale, cashierNames);

    final proofs = _collectProofs(
      sale: sale,
      payment: payment,
      tenders: tenders,
      accountNames: allAccountNames,
    );

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        backgroundColor: Colors.transparent,
        title: const Text(
          'Receipt',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy receipt text',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: itemsAsync.value == null
                ? null
                : () async {
                    final text = ReceiptTextBuilder.build(
                      sale: sale,
                      items: itemsAsync.value!,
                      tenders: tenders,
                      accountNames: allAccountNames,
                      cashier: cashier,
                      customerName: customerName,
                      customerAddress: customerAddress,
                      customerTin: customerTin,
                    );
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('Receipt copied.')),
                        );
                    }
                  },
          ),
        ],
      ),
      bottomNavigationBar: canChange
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: sale.isVoided
                    ? OutlinedButton.icon(
                        onPressed: () => _confirmRestore(context, ref, sale),
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Restore receipt'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _confirmVoid(context, ref, sale),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                        ),
                        icon: const Icon(Icons.block_rounded),
                        label: const Text('Void receipt'),
                      ),
              ),
            )
          : null,
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Unable to load receipt: $e')),
        data: (items) {
          final subtotal = items.fold<int>(0, (s, i) => s + i.lineTotal);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  _ReceiptHero(sale: sale, cashier: cashier),
                  if (sale.isVoided &&
                      (sale.voidReason ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Reason: ${sale.voidReason}',
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SyncDetailCard(saleId: sale.id),
                  const SizedBox(height: 14),
                  // ---------------- the ticket ----------------
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                          child: Column(
                            children: [
                              _InfoRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Cashier',
                                value: cashier,
                              ),
                              if ((sale.orderType ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.local_offer_outlined,
                                  label: 'Order type',
                                  value: sale.orderType!,
                                ),
                              ],
                              if ((sale.tableLabel ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.table_restaurant_rounded,
                                  label: 'Table',
                                  value: sale.guests == null
                                      ? sale.tableLabel!
                                      : '${sale.tableLabel} · ${sale.guests} guests',
                                ),
                              ],
                              if ((sale.orderRef ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.tag_rounded,
                                  label: 'Order no.',
                                  value: sale.orderRef!,
                                ),
                              ],
                              if ((sale.contactName ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.person_pin_outlined,
                                  label: 'Contact',
                                  value: (sale.contactPhone ?? '').isEmpty
                                      ? sale.contactName!
                                      : '${sale.contactName} · ${sale.contactPhone}',
                                ),
                              ],
                              if ((sale.deliveryAddress ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.local_shipping_outlined,
                                  label: 'Deliver to',
                                  value: sale.deliveryAddress!,
                                ),
                              ],
                              if (customerName != null) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.person_outline_rounded,
                                  label: 'Customer',
                                  value: customerName,
                                ),
                              ],
                              if ((customerTin ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.badge_outlined,
                                  label: 'TIN',
                                  value: customerTin!,
                                ),
                              ],
                              if ((customerAddress ?? '').isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.home_outlined,
                                  label: 'Address',
                                  value: customerAddress!,
                                ),
                              ],
                              if (!sale.isStockOnly &&
                                  sale.discountAmount > 0) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.account_balance_wallet_outlined,
                                  label: 'Paid via',
                                  value: tenders.isEmpty
                                      ? (methodName ?? 'Unknown account')
                                      : tenders
                                            .map(
                                              (t) =>
                                                  allAccountNames[t
                                                      .accountId] ??
                                                  'Account',
                                            )
                                            .toSet()
                                            .join(' + '),
                                ),
                              ],
                              if (sale.notes != null &&
                                  sale.notes!.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.notes_outlined,
                                  label: 'Notes',
                                  value: sale.notes!,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const _TearLine(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                          child: Row(
                            children: [
                              Text(
                                'ITEMS (${items.length})',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                sale.isStockOnly ? 'QTY' : 'AMOUNT',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...items.map(
                          (item) => _ReceiptRow(item: item, sale: sale),
                        ),
                        if (!sale.isStockOnly) ...[
                          const _TearLine(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: Column(
                              children: [
                                if (sale.discountAmount > 0) ...[
                                  _TotalLine(
                                    label: 'Subtotal',
                                    value: _peso(subtotal),
                                  ),
                                  _TotalLine(
                                    label: sale.discountLabel ?? 'Discount',
                                    value: '−${_peso(sale.discountAmount)}',
                                    color: Colors.green.shade700,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                Row(
                                  children: [
                                    Text(
                                      'TOTAL',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                          ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _peso(sale.totalAmount),
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: sale.isVoided
                                                ? scheme.onSurfaceVariant
                                                : scheme.primary,
                                            decoration: sale.isVoided
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (tenders.isNotEmpty) ...[
                            const _TearLine(),
                            _TendersSection(
                              tenders: tenders,
                              accountNames: allAccountNames,
                            ),
                          ],
                        ] else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                            child: Text(
                              'No income was recorded for this checkout.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ---------------- proof of payment ----------------
                  if (proofs.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _ProofGallery(proofs: proofs),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// PROOF OF PAYMENT
// ============================================================================

class _ProofItem {
  final String? provider;
  final String? reference;
  final String? photoPath;
  final String accountName;
  final int amountPaid;
  final int expectedCents;
  final DateTime? paidAt;

  const _ProofItem({
    required this.provider,
    required this.reference,
    required this.photoPath,
    required this.accountName,
    required this.amountPaid,
    required this.expectedCents,
    required this.paidAt,
  });
}

/// The tender table may or may not store the photo; read it defensively.
String? _tenderPhotoPath(PosSaleTender t) {
  try {
    final v = (t as dynamic).photoPath;
    return (v is String && v.trim().isNotEmpty) ? v : null;
  } catch (_) {
    return null;
  }
}

/// Gathers proofs from the tenders and the legacy payments table,
/// without showing the same payment twice.
List<_ProofItem> _collectProofs({
  required PosSale sale,
  required PosSalePayment? payment,
  required List<PosSaleTender> tenders,
  required Map<String, String> accountNames,
}) {
  if (sale.isStockOnly) return const [];
  final out = <_ProofItem>[];
  final seen = <String>{};

  String keyOf(String? ref, String? photo) =>
      (ref ?? photo ?? '').trim().toLowerCase();

  for (final t in tenders) {
    final ref = t.referenceNo;
    var photo = _tenderPhotoPath(t);
    if ((ref == null || ref.isEmpty) && photo == null) continue;

    final sameAsLegacy =
        payment != null && ref != null && payment.referenceNo == ref;
    if (photo == null && sameAsLegacy) photo = payment.photoPath;

    if (!seen.add(keyOf(ref, photo))) continue;
    out.add(
      _ProofItem(
        provider: t.provider ?? (sameAsLegacy ? payment.provider : null),
        reference: ref,
        photoPath: photo,
        accountName: accountNames[t.accountId] ?? 'Account',
        amountPaid: sameAsLegacy ? payment.amountPaid : t.amount,
        expectedCents: t.amount,
        paidAt: sameAsLegacy ? payment.paidAt : null,
      ),
    );
  }

  if (payment != null &&
      seen.add(keyOf(payment.referenceNo, payment.photoPath))) {
    out.add(
      _ProofItem(
        provider: payment.provider,
        reference: payment.referenceNo,
        photoPath: payment.photoPath,
        accountName: accountNames[sale.paymentAccountId] ?? 'Payment',
        amountPaid: payment.amountPaid,
        expectedCents: sale.totalAmount,
        paidAt: payment.paidAt,
      ),
    );
  }
  return out;
}

class _ProofGallery extends StatelessWidget {
  final List<_ProofItem> proofs;
  const _ProofGallery({required this.proofs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Proof of payment',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
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
                  '${proofs.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < proofs.length; i++) ...[
          _ProofCard(proof: proofs[i], index: i, total: proofs.length),
          if (i < proofs.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _ProofCard extends StatelessWidget {
  final _ProofItem proof;
  final int index;
  final int total;

  const _ProofCard({
    required this.proof,
    required this.index,
    required this.total,
  });

  void _openViewer(BuildContext context, File file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              proof.reference == null
                  ? 'Payment proof'
                  : 'Ref ${proof.reference}',
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Hero(tag: 'proof-${file.path}', child: Image.file(file)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final path = proof.photoPath;
    final file = path == null ? null : File(path);
    final hasPhoto = file != null && file.existsSync();
    final matches = proof.amountPaid == proof.expectedCents;
    final badgeColor = matches ? Colors.green.shade700 : Colors.orange.shade800;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- photo ----
          if (hasPhoto)
            GestureDetector(
              onTap: () => _openViewer(context, file),
              child: Stack(
                children: [
                  Hero(
                    tag: 'proof-${file.path}',
                    child: Image.file(
                      file,
                      height: 300,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => _MissingPhoto(path: path),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.35),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                          ],
                          stops: const [0, 0.3, 0.65, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _GlassChip(
                      icon: Icons.account_balance_wallet_outlined,
                      text: total > 1
                          ? '${proof.provider ?? proof.accountName} · ${index + 1}/$total'
                          : (proof.provider ?? proof.accountName),
                    ),
                  ),
                  const Positioned(
                    right: 12,
                    bottom: 12,
                    child: _GlassChip(
                      icon: Icons.zoom_out_map_rounded,
                      text: 'Tap to enlarge',
                    ),
                  ),
                ],
              ),
            )
          else
            _MissingPhoto(path: path),

          // ---- details ----
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _peso(proof.amountPaid),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            matches
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded,
                            size: 14,
                            color: badgeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            matches ? 'Matches receipt' : 'Amount differs',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!matches)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Expected ${_peso(proof.expectedCents)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                if (proof.provider != null)
                  _InfoRow(
                    icon: Icons.account_balance_outlined,
                    label: 'Provider',
                    value: proof.provider!,
                  ),
                if (proof.reference != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoRow(
                          icon: Icons.tag_rounded,
                          label: 'Reference no.',
                          value: proof.reference!,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy reference',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: proof.reference!),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text('Reference copied.'),
                                ),
                              );
                          }
                        },
                      ),
                    ],
                  ),
                ],
                if (proof.paidAt != null) ...[
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.event_available_outlined,
                    label: 'Paid on',
                    value: _formatDateTime(proof.paidAt!),
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

class _MissingPhoto extends StatelessWidget {
  final String? path;
  const _MissingPhoto({required this.path});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 120,
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 30,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            path == null
                ? 'No photo was attached'
                : 'The photo is not on this device',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _GlassChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
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

// ============================================================================
// HERO + TICKET PIECES
// ============================================================================

class _ReceiptHero extends StatelessWidget {
  final PosSale sale;
  final String cashier;
  const _ReceiptHero({required this.sale, required this.cashier});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final voided = sale.isVoided;
    final stockOnly = sale.isStockOnly;

    final colors = voided
        ? const [Color(0xFFB91C1C), Color(0xFFEF4444)]
        : stockOnly
        ? const [Color(0xFFC2410C), Color(0xFFF59E0B)]
        : [scheme.primary, scheme.primary.withValues(alpha: 0.72)];
    final label = voided ? 'VOIDED' : (stockOnly ? 'STOCK ONLY' : 'PAID');
    final icon = voided
        ? Icons.block_rounded
        : (stockOnly ? Icons.inventory_2_rounded : Icons.check_circle_rounded);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                receiptLabel(sale, idLength: 8),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              stockOnly ? 'No income' : _peso(sale.totalAmount),
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                decoration: voided ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_formatDate(sale.saleDate)} · ${_formatTime(sale.saleDate)}'
            ' · $cashier',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed "tear here" line with notches on both edges. The notch colour must
/// equal the page background (surfaceContainerLowest).
class _TearLine extends StatelessWidget {
  const _TearLine();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.surfaceContainerLowest;

    return SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final count = ((box.maxWidth - 40) / 10).floor();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    count < 0 ? 0 : count,
                    (_) => Container(
                      width: 5,
                      height: 1.5,
                      color: scheme.outlineVariant,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: -11,
            child: CircleAvatar(radius: 11, backgroundColor: bg),
          ),
          Positioned(
            right: -11,
            child: CircleAvatar(radius: 11, backgroundColor: bg),
          ),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _TotalLine({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: scheme.onSurfaceVariant),
        const SizedBox(width: 9),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final PosSaleItem item;
  final PosSale sale;

  const _ReceiptRow({required this.item, required this.sale});

  String _qty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_qty(item.quantity)} ${item.unit} × ${_peso(item.unitPrice)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            sale.isStockOnly
                ? '${_qty(item.quantity)} ${item.unit}'
                : _peso(item.lineTotal),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoidChip extends StatelessWidget {
  const _VoidChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'VOID',
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Each payment of the sale: account, amount, cash received and change.
class _TendersSection extends StatelessWidget {
  final List<PosSaleTender> tenders;
  final Map<String, String> accountNames;

  const _TendersSection({required this.tenders, required this.accountNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tenders.length > 1 ? 'PAYMENTS (SPLIT)' : 'PAYMENT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          for (final t in tenders) ...[
            _InfoRow(
              icon: Icons.payments_outlined,
              label: tenderLabel(accountNames[t.accountId]),
              value: _peso(t.amount),
            ),
            if (t.tendered != null && ((t.changeGiven as int?) ?? 0) > 0) ...[
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.money_outlined,
                label: 'Cash received',
                value: _peso(t.tendered!),
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.change_circle_outlined,
                label: 'Change',
                value: _peso((t.changeGiven as int?) ?? 0),
              ),
            ],
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

Future<void> _confirmVoid(
  BuildContext context,
  WidgetRef ref,
  PosSale sale,
) async {
  final reasonCtrl = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? err;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Void this receipt?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The supplies used by this sale are put back. This is only '
                'possible while the shift is still open.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Reason (required)',
                  border: const OutlineInputBorder(),
                  errorText: err,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final r = reasonCtrl.text.trim();
                if (r.isEmpty) {
                  setState(() => err = 'Enter a reason.');
                  return;
                }
                Navigator.pop(ctx, r);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    },
  );
  if (reason == null || !context.mounted) return;

  Approver? approver;
  final approvalOn = await ApprovalService.anyPinSet(
    ref.read(databaseProvider),
    sale.businessId,
  );
  if (approvalOn) {
    if (!context.mounted) return;
    approver = await requestManagerApproval(
      context,
      title: 'Manager approval',
      message: 'Enter an owner or manager PIN to void this receipt.',
    );
    if (approver == null || !context.mounted) return;
  }

  try {
    await ref
        .read(posSessionServiceProvider)
        .voidSale(
          sale.id,
          reason: reason,
          userId: ref.read(authenticatedUserIdProvider),
          approvedByUserId: approver?.userId,
          approvedByName: approver?.name,
        );
    ref.invalidate(producibilityProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt voided. Stock put back.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

Future<void> _confirmRestore(
  BuildContext context,
  WidgetRef ref,
  PosSale sale,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore this receipt?'),
      content: const Text(
        'The sale counts again and its supplies are deducted again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  Approver? approver;
  final approvalOn = await ApprovalService.anyPinSet(
    ref.read(databaseProvider),
    sale.businessId,
  );
  if (approvalOn) {
    if (!context.mounted) return;
    approver = await requestManagerApproval(
      context,
      title: 'Manager approval',
      message: 'Enter an owner or manager PIN to restore this receipt.',
    );
    if (approver == null || !context.mounted) return;
  }

  try {
    await ref
        .read(posSessionServiceProvider)
        .restoreSale(
          sale.id,
          userId: ref.read(authenticatedUserIdProvider),
          approvedByUserId: approver?.userId,
          approvedByName: approver?.name,
        );
    ref.invalidate(producibilityProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt restored.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}
