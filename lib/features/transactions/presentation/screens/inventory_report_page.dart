// lib/features/transactions/presentation/screens/inventory_report_page.dart
//
// Inventory Report — one place to answer:
//   * What is my stock worth?                       (Overview)
//   * What is low, out, or overstocked?             (Stock)
//   * What came in, went out, or was written off?   (Movements)
//   * What should I buy next, and what will it cost? (Reorder)
//
// Everything is derived from existing tables (supplies, inventory_movements,
// product_categories); nothing new is written except when the user chooses
// "Add to cart" or "Adjust stock", which reuse the existing cart/adjust flows.
//
// RESPONSIVE BEHAVIOUR
//   * Compact  (< 600 dp)  phones            → single column, scrolling tabs
//                                              when the screen is very narrow.
//   * Medium   (600–899)   large phones/tablets → 2-column tile grids, wrapped
//                                              filter chips.
//   * Wide     (≥ 900)     tablets/desktop/web → Overview splits into two
//                                              columns, Reorder gets a sticky
//                                              summary panel beside the list.
//   * Content is capped at a comfortable max width and centred on huge screens.
//   * Text scaling is clamped (1.0–1.4) and every text that shares a row with
//     something else is flexible/ellipsised, so nothing overlaps or overflows.
//   * Filters live inside the scroll view, so landscape phones keep room for
//     the actual list.
//
// Open it from anywhere with:
//   Navigator.push(context,
//       MaterialPageRoute(builder: (_) => const InventoryReportPage()));

import 'dart:convert';
import 'dart:math' as math;

import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/supplies_price_list_page.dart'
    show
        CartPage,
        PurchaseHistoryPage,
        AllStockAdjustmentsPage,
        StockAdjustmentSheet,
        SupplyDetailPage,
        cartReadyProvider,
        cartProvider,
        suppliesProvider;
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId, ledgerVersionProvider;
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import 'package:share_plus/share_plus.dart' show Share, XFile;

// ============================================================================
// LAYOUT SYSTEM
// ============================================================================

/// Widest the content is allowed to grow before it is centred.
const double _kMaxContentWidth = 1180;

/// Widest single-column reading content (movement feed).
const double _kReadingWidth = 820;

const double _kMediumBreakpoint = 600;
const double _kWideBreakpoint = 900;

const double _kGap = 12;
const double _kSectionGap = 22;

/// Horizontal page gutter for a viewport of [width]. Grows on very wide
/// screens so content stays centred at [maxWidth].
double _gutter(double width, double maxWidth) =>
    math.max(16.0, (width - maxWidth) / 2);

/// Scroll padding that respects the gutter, notches (landscape) and the
/// home-indicator / gesture bar.
EdgeInsets _pagePadding(
  BuildContext context,
  double width, {
  double top = 12,
  double bottom = 32,
  double maxWidth = _kMaxContentWidth,
}) {
  final insets = MediaQuery.paddingOf(context);
  final side = _gutter(width, maxWidth);
  return EdgeInsets.fromLTRB(
    side + insets.left,
    top,
    side + insets.right,
    bottom + insets.bottom,
  );
}

/// Usable content width inside [_pagePadding].
double _contentWidth(
  BuildContext context,
  double width, {
  double maxWidth = _kMaxContentWidth,
}) {
  final insets = MediaQuery.paddingOf(context);
  final side = _gutter(width, maxWidth);
  return math.max(0.0, width - (side * 2) - insets.left - insets.right);
}

/// How many tiles of at least [minTile] fit in [available].
int _columnsFor(
  double available, {
  double minTile = 340,
  double gap = _kGap,
  int max = 3,
}) {
  final fit = ((available + gap) / (minTile + gap)).floor();
  return math.min(math.max(fit, 1), max);
}

List<Widget> _spaced(List<Widget> children, double gap) => [
  for (var i = 0; i < children.length; i++) ...[
    if (i > 0) SizedBox(height: gap),
    children[i],
  ],
];

// ============================================================================
// FORMATTING
// ============================================================================

final _pesoFormat = NumberFormat('#,##0.00');
final _qtyFormat = NumberFormat('#,##0.##');

String _peso(num cents) => '₱${_pesoFormat.format(cents / 100)}';
String _qty(double value) => _qtyFormat.format(value);

// ============================================================================
// STOCK STATUS
// ============================================================================

enum _Status { out, low, normal, over, unset }

extension on _Status {
  String get label => switch (this) {
    _Status.out => 'Out of stock',
    _Status.low => 'Low stock',
    _Status.normal => 'Healthy',
    _Status.over => 'Overstock',
    _Status.unset => 'No limits set',
  };

  String get shortLabel => switch (this) {
    _Status.out => 'Out',
    _Status.low => 'Low',
    _Status.normal => 'Healthy',
    _Status.over => 'Over',
    _Status.unset => 'No limits',
  };

  IconData get icon => switch (this) {
    _Status.out => Icons.remove_shopping_cart_outlined,
    _Status.low => Icons.warning_amber_rounded,
    _Status.normal => Icons.check_circle_outline_rounded,
    _Status.over => Icons.trending_up_rounded,
    _Status.unset => Icons.tune_rounded,
  };

  Color color(ColorScheme scheme) => switch (this) {
    _Status.out => scheme.error,
    _Status.low => Colors.orange.shade800,
    _Status.normal => Colors.green.shade700,
    _Status.over => Colors.blue.shade700,
    _Status.unset => scheme.onSurfaceVariant,
  };
}

// ============================================================================
// VIEW MODELS
// ============================================================================

/// One supply, with everything the report needs pre-computed.
///
/// Stock is stored in the supply's base unit (kg, ml, piece…), but owners think
/// in purchase units (packs, sacks…), so quantities are converted for display.
class _StockItem {
  _StockItem({
    required this.supply,
    required this.category,
    required this.status,
    required this.valueCents,
    required this.displayQty,
    required this.displayUnit,
    required this.unitsPerDisplay,
    required this.lowDisplay,
    required this.maxDisplay,
    required this.targetDisplay,
    required this.fill,
    required this.reorderQty,
  });

  final Supply supply;
  final String category;
  final _Status status;
  final int valueCents;
  final double displayQty;
  final String displayUnit;

  /// Base units per display unit (e.g. 25 kg per sack). 1 when shown in base units.
  final double unitsPerDisplay;
  final double? lowDisplay;
  final double? maxDisplay;

  /// Level to restock up to (max, or twice the low-stock level), in display units.
  final double? targetDisplay;

  /// Stock relative to its ceiling (0 = empty, 1 = at max). Null if no limits.
  final double? fill;

  /// Suggested purchase quantity in display units; 0 when no reorder is needed.
  final int reorderQty;
  int get reorderCostCents => reorderQty * supply.currentPrice;
  bool get needsReorder => reorderQty > 0;

  factory _StockItem.from(Supply s, Map<String, String> categories) {
    final stock = s.currentStock;
    final threshold = s.lowStockThreshold;
    final low = (threshold != null && threshold > 0)
        ? threshold
        : (s.minimumStock > 0 ? s.minimumStock : 0.0);
    final max = s.maximumStock;

    final _Status status;
    if (stock <= 0) {
      status = _Status.out;
    } else if (low > 0 && stock <= low) {
      status = _Status.low;
    } else if (max > 0 && stock > max) {
      status = _Status.over;
    } else if (low <= 0 && max <= 0) {
      status = _Status.unset;
    } else {
      status = _Status.normal;
    }

    final purchaseUnit = (s.purchaseUnit ?? '').trim();
    final usePurchase = purchaseUnit.isNotEmpty && s.unitsPerPurchase > 0;
    final per = usePurchase ? s.unitsPerPurchase : 1.0;

    final ceiling = max > 0 ? max : (low > 0 ? low * 2 : null);

    var reorderQty = 0;
    if (status == _Status.out || status == _Status.low) {
      final needBase = ceiling == null ? per : (ceiling - stock);
      reorderQty = math.max(1, (needBase / per).ceil());
    }

    final categoryId = s.categoryId;

    return _StockItem(
      supply: s,
      category:
          (categoryId != null ? categories[categoryId] : null) ??
          'Uncategorized',
      status: status,
      valueCents: stock <= 0 ? 0 : (stock * s.costPerBaseUnit).round(),
      displayQty: stock / per,
      displayUnit: usePurchase ? purchaseUnit : s.stockUnit,
      unitsPerDisplay: per,
      lowDisplay: low > 0 ? low / per : null,
      maxDisplay: max > 0 ? max / per : null,
      targetDisplay: ceiling == null ? null : ceiling / per,
      fill: (ceiling == null || ceiling <= 0)
          ? null
          : (stock / ceiling).clamp(0.0, 1.5),
      reorderQty: reorderQty,
    );
  }
}

class _Snapshot {
  _Snapshot(this.items);

  final List<_StockItem> items;

  late final int totalValue = items.fold(0, (sum, i) => sum + i.valueCents);

  int count(_Status status) => items.where((i) => i.status == status).length;

  /// Out-of-stock first, then the emptiest low-stock items.
  late final List<_StockItem> reorder = () {
    final list = items.where((i) => i.needsReorder).toList();
    list.sort((a, b) {
      final byStatus = a.status.index.compareTo(b.status.index);
      if (byStatus != 0) return byStatus;
      return (a.fill ?? 0).compareTo(b.fill ?? 0);
    });
    return list;
  }();

  late final int reorderCost = reorder.fold(
    0,
    (sum, i) => sum + i.reorderCostCents,
  );

  late final Map<String, int> valueByCategory = () {
    final map = <String, int>{};
    for (final item in items) {
      map[item.category] = (map[item.category] ?? 0) + item.valueCents;
    }
    return map;
  }();

  List<String> get categories =>
      (items.map((i) => i.category).toSet().toList())..sort();
}

// ============================================================================
// MOVEMENTS
// ============================================================================

enum _MoveKind { restock, used, adjustment, transfer }

extension on _MoveKind {
  String get label => switch (this) {
    _MoveKind.restock => 'Restocked',
    _MoveKind.used => 'Used / sold',
    _MoveKind.adjustment => 'Adjusted',
    _MoveKind.transfer => 'Transfers & opening',
  };
}

class _Move {
  _Move(this.movement, this.supply);

  final InventoryMovement movement;
  final Supply supply;

  double get qty => movement.quantity;

  /// Valued at the supply's current average cost (history keeps quantity only).
  int get valueCents => (qty.abs() * supply.costPerBaseUnit).round();

  _MoveKind get kind {
    // A void/restore of a sale only reverses stock; it is not a write-off.
    final ref = movement.referenceType;
    if (ref == 'pos_void' || ref == 'pos_restore') return _MoveKind.transfer;
    return switch (movement.movementType) {
      'restock' => _MoveKind.restock,
      'production_consumption' => _MoveKind.used,
      'manual_adjustment' => _MoveKind.adjustment,
      'transfer_out' ||
      'transfer_in' ||
      'transfer_cancel' ||
      'opening_balance' => _MoveKind.transfer,
      _ => qty >= 0 ? _MoveKind.restock : _MoveKind.used,
    };
  }
}

class _MoveTotals {
  _MoveTotals(List<_Move> moves) {
    for (final m in moves) {
      switch (m.kind) {
        case _MoveKind.transfer:
          break;
        case _MoveKind.restock:
          if (m.qty > 0) restocked += m.valueCents;
        case _MoveKind.used:
          used += m.valueCents;
        case _MoveKind.adjustment:
          if (m.qty < 0) writtenOff += m.valueCents;
      }
    }
  }

  int restocked = 0;
  int used = 0;
  int writtenOff = 0;
}

class _AdjustmentSummary {
  int count = 0;
  double increase = 0; // base units added
  double decrease = 0; // base units removed (positive number)
  DateTime? lastDate;
  String lastNote = '';

  double get net => increase - decrease;
}

Map<String, _AdjustmentSummary> _summariseAdjustments(List<_Move> moves) {
  final map = <String, _AdjustmentSummary>{};
  for (final m in moves) {
    if (m.kind != _MoveKind.adjustment) continue;
    final s = map.putIfAbsent(m.supply.id, _AdjustmentSummary.new);
    s.count++;
    if (m.qty >= 0) {
      s.increase += m.qty;
    } else {
      s.decrease += -m.qty;
    }
    final date = m.movement.movementDate;
    if (s.lastDate == null || date.isAfter(s.lastDate!)) {
      s.lastDate = date;
      s.lastNote = (m.movement.notes ?? '').trim();
    }
  }
  return map;
}

/// Net adjustment in display units, signed ("+2", "-1.5").
String _signed(double v) => v > 0 ? '+${_qty(v)}' : _qty(v);

enum _Preset { days7, days30, month, custom }

extension on _Preset {
  String get label => switch (this) {
    _Preset.days7 => 'Last 7 days',
    _Preset.days30 => 'Last 30 days',
    _Preset.month => 'This month',
    _Preset.custom => 'Custom',
  };
}

final _categoryNamesProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final rows = await (db.select(
    db.productCategories,
  )..where((c) => c.businessId.equals(kCurrentBusinessId))).get();

  return {for (final c in rows) c.id: c.name};
});

final _movementsProvider = FutureProvider.autoDispose
    .family<List<_Move>, DateTimeRange>((ref, range) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);
      final branchId = ref.watch(selectedBranchIdProvider);

      final query =
          db.select(db.inventoryMovements).join([
              innerJoin(
                db.supplies,
                db.supplies.id.equalsExp(db.inventoryMovements.supplyId),
              ),
            ])
            ..where(
              db.supplies.businessId.equals(kCurrentBusinessId) &
                  inventoryMovementInBranch(
                    db.inventoryMovements,
                    kCurrentBusinessId,
                    branchId,
                  ) &
                  db.inventoryMovements.movementDate.isBiggerOrEqualValue(
                    range.start,
                  ) &
                  db.inventoryMovements.movementDate.isSmallerThanValue(
                    range.end,
                  ),
            )
            ..orderBy([OrderingTerm.desc(db.inventoryMovements.movementDate)]);

      final rows = await query.get();
      return [
        for (final row in rows)
          _Move(
            row.readTable(db.inventoryMovements),
            row.readTable(db.supplies),
          ),
      ];
    });

enum _Sort { attention, name, value, quantity }

extension on _Sort {
  String get label => switch (this) {
    _Sort.attention => 'Needs attention',
    _Sort.name => 'Name (A–Z)',
    _Sort.value => 'Value (high to low)',
    _Sort.quantity => 'Quantity (low to high)',
  };
}

// ============================================================================
// EXPORT
// ============================================================================

enum _ExportAction { pdf, csv, print, copy }

/// What the export sheet hands back: what to do, and whether to limit the
/// report to the filters currently applied on the Stock tab.
typedef _ExportChoice = (_ExportAction action, bool filteredOnly);

/// The PDF's built-in fonts have no peso sign, so amounts print as "PHP".
String _pesoPdf(num cents) => 'PHP ${_pesoFormat.format(cents / 100)}';

/// Plain number for spreadsheets: no thousands separators, no trailing zeros.
String _plain(double value) {
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Stops spreadsheet apps from treating text such as "=SUM(A1)" as a formula.
String _safeText(String value) =>
    value.isNotEmpty && '=+-@'.contains(value[0]) ? "'$value" : value;

/// Builds a print-ready A4 (landscape) stock report.
Future<Uint8List> _buildStockPdf({
  required List<_StockItem> items,
  required String scopeLabel,
  required Map<String, _AdjustmentSummary> adjustments,
  required String periodLabel,
}) async {
  final generated = DateFormat('MMM d, yyyy, h:mm a').format(DateTime.now());
  final totalValue = items.fold<int>(0, (sum, i) => sum + i.valueCents);
  int count(_Status s) => items.where((i) => i.status == s).length;

  PdfColor statusColor(_Status s) => switch (s) {
    _Status.out => PdfColors.red700,
    _Status.low => PdfColors.orange800,
    _Status.normal => PdfColors.green700,
    _Status.over => PdfColors.blue700,
    _Status.unset => PdfColors.grey700,
  };

  pw.Widget cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );

  pw.Widget stat(String label, String value) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );

  const right = pw.TextAlign.right;

  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        cell('Item', bold: true),
        cell('SKU', bold: true),
        cell('Category', bold: true),
        cell('Status', bold: true),
        cell('In stock', bold: true, align: right),
        cell('Min', bold: true, align: right),
        cell('Max', bold: true, align: right),
        cell('Adjusted (net)', bold: true, align: right),
        cell('Value', bold: true, align: right),
      ],
    ),
    for (final i in items)
      pw.TableRow(
        children: [
          cell(i.supply.name),
          cell((i.supply.sku ?? '').trim().isEmpty ? '-' : i.supply.sku!),
          cell(i.category),
          cell(i.status.label, bold: true, color: statusColor(i.status)),
          cell('${_qty(i.displayQty)} ${i.displayUnit}', align: right),
          cell(i.lowDisplay == null ? '-' : _qty(i.lowDisplay!), align: right),
          cell(i.maxDisplay == null ? '-' : _qty(i.maxDisplay!), align: right),
          cell(() {
            final a = adjustments[i.supply.id];
            if (a == null) return '-';
            return '${_signed(a.net / i.unitsPerDisplay)} ${i.displayUnit} (${a.count}x)';
          }(), align: right),
          cell(_pesoPdf(i.valueCents), align: right),
        ],
      ),
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        cell('Total', bold: true),
        cell(''),
        cell(''),
        cell(''),
        cell(''),
        cell(''),
        cell(''),
        cell(''), // new: under "Adjusted (net)"
        cell(_pesoPdf(totalValue), bold: true, align: right),
      ],
    ),
  ];

  final doc = pw.Document(title: 'Inventory stock report', author: 'BOS');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 34),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated $generated',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
      build: (ctx) => [
        pw.Text(
          'Inventory stock report',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'As of $generated   |   $scopeLabel',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
        ),
        pw.Text(
          'Stock is valued at average cost. Amounts are in Philippine pesos (PHP).',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.Text(
          'Adjusted (net) = manual stock adjustments from $periodLabel (number of adjustments in brackets).',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            stat('Total stock value', _pesoPdf(totalValue)),
            stat('Items', '${items.length}'),
            stat('Out of stock', '${count(_Status.out)}'),
            stat('Low stock', '${count(_Status.low)}'),
            stat('Overstock', '${count(_Status.over)}'),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const pw.FlexColumnWidth(3.4),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.8),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.7),
            5: const pw.FlexColumnWidth(1.1),
            6: const pw.FlexColumnWidth(1.1),
            7: const pw.FlexColumnWidth(1.9),
          },
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: PdfColors.grey300,
              width: 0.5,
            ),
            bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.7),
          ),
          children: rows,
        ),
      ],
    ),
  );

  return doc.save();
}

/// Bottom sheet that lets the user pick the scope and format of the export.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.totalCount, required this.filteredCount});

  final int totalCount;

  /// Null when no filter is active (so there is no separate "current view").
  final int? filteredCount;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late bool _filteredOnly = widget.filteredCount != null;

  int get _count =>
      _filteredOnly ? (widget.filteredCount ?? 0) : widget.totalCount;

  void _choose(_ExportAction action) =>
      Navigator.pop<_ExportChoice>(context, (action, _filteredOnly));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = _count > 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export stock report',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose what to include, then how to save or share it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.filteredCount != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('All items (${widget.totalCount})'),
                    showCheckmark: false,
                    selected: !_filteredOnly,
                    onSelected: (_) => setState(() => _filteredOnly = false),
                  ),
                  ChoiceChip(
                    label: Text('Current view (${widget.filteredCount})'),
                    showCheckmark: false,
                    selected: _filteredOnly,
                    onSelected: (_) => setState(() => _filteredOnly = true),
                  ),
                ],
              )
            else
              Text(
                '${widget.totalCount} item${widget.totalCount == 1 ? '' : 's'} will be included.',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (!enabled) ...[
              const SizedBox(height: 8),
              Text(
                'No items match the current filters, so there is nothing to export.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            _ExportOption(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF report',
              subtitle: 'Summary and stock table. Share, save or send.',
              enabled: enabled,
              onTap: () => _choose(_ExportAction.pdf),
            ),
            _ExportOption(
              icon: Icons.table_chart_outlined,
              title: 'CSV spreadsheet',
              subtitle: 'Opens in Excel or Google Sheets.',
              enabled: enabled,
              onTap: () => _choose(_ExportAction.csv),
            ),
            _ExportOption(
              icon: Icons.print_outlined,
              title: 'Print',
              subtitle: 'Send the PDF report to a printer.',
              enabled: enabled,
              onTap: () => _choose(_ExportAction.print),
            ),
            _ExportOption(
              icon: Icons.copy_rounded,
              title: 'Copy as CSV',
              subtitle: 'Paste straight into a spreadsheet.',
              enabled: enabled,
              onTap: () => _choose(_ExportAction.copy),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        tileColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

// ============================================================================
// PAGE
// ============================================================================

class InventoryReportPage extends ConsumerStatefulWidget {
  const InventoryReportPage({super.key});

  @override
  ConsumerState<InventoryReportPage> createState() =>
      _InventoryReportPageState();
}

class _InventoryReportPageState extends ConsumerState<InventoryReportPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _searchController = TextEditingController();

  DateTime _asOf = DateTime.now();

  // Stock tab
  String _query = '';
  _Status? _statusFilter;
  String? _categoryFilter;
  _Sort _sort = _Sort.attention;

  // Movements / overview
  _Preset _preset = _Preset.days30;
  DateTimeRange? _custom;
  _MoveKind? _kindFilter;

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------- period ----------

  DateTimeRange get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return switch (_preset) {
      _Preset.days7 => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: tomorrow,
      ),
      _Preset.days30 => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: tomorrow,
      ),
      _Preset.month => DateTimeRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      ),
      // The picker returns midnight of the last day; the query end is exclusive.
      _Preset.custom => DateTimeRange(
        start: _custom!.start,
        end: _custom!.end.add(const Duration(days: 1)),
      ),
    };
  }

  String get _periodLabel {
    final r = _range;
    final f = DateFormat('MMM d, yyyy');
    return '${f.format(r.start)} – ${f.format(r.end.subtract(const Duration(days: 1)))}';
  }

  Future<void> _selectPreset(_Preset preset) async {
    if (preset == _Preset.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _custom,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _custom = picked;
        _preset = _Preset.custom;
      });
      return;
    }
    setState(() => _preset = preset);
  }

  // ---------- actions ----------

  Future<void> _refresh() async {
    ref.invalidate(suppliesProvider);
    ref.invalidate(_categoryNamesProvider);
    ref.invalidate(_movementsProvider);
    if (mounted) setState(() => _asOf = DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  void _openStock(_Status? status) {
    setState(() => _statusFilter = status);
    _tabs.animateTo(1);
  }

  void _snack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          behavior: SnackBarBehavior.floating,
          // Keeps the bar from stretching edge-to-edge on tablets/desktop.
          width: MediaQuery.sizeOf(context).width > 640 ? 560 : null,
        ),
      );
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack(message);
  }

  /// Adds the suggested reorder quantity to the shopping cart. Returns false
  /// when the supply is already in the cart (its quantity is left alone).
  Future<bool> _addToCart(_StockItem item) async {
    final id = item.supply.id;
    final notifier = ref.read(cartProvider.notifier);
    await notifier.load();
    if (ref.read(cartProvider).any((line) => line.supplyId == id)) {
      return false;
    }

    await notifier.addOrIncrement(item.supply);

    final line = ref.read(cartProvider).firstWhere((l) => l.supplyId == id);
    final qty = math.max(1, item.reorderQty);
    if (item.supply.isSoldByWeight) {
      await notifier.updateWeight(line.id, qty.toDouble());
    } else {
      await notifier.updateQuantity(line.id, qty);
    }
    return true;
  }

  Future<void> _addAllToCart(List<_StockItem> items) async {
    var added = 0;
    for (final item in items) {
      if (await _addToCart(item)) added++;
    }

    _snack(
      added == 0
          ? 'Everything on this list is already in your cart.'
          : 'Added $added item${added == 1 ? '' : 's'} to your cart.',
      action: SnackBarAction(
        label: 'View cart',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CartPage()),
        ),
      ),
    );
  }

  Future<void> _onStockAction(String action, _StockItem item) async {
    switch (action) {
      case 'details':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupplyDetailPage(supply: item.supply),
          ),
        );
      case 'adjust':
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          // Keeps the sheet readable on tablets / desktop instead of full width.
          constraints: const BoxConstraints(maxWidth: 640),
          builder: (_) => StockAdjustmentSheet(supply: item.supply),
        );
      case 'cart':
        final added = await _addToCart(item);
        _snack(
          added
              ? '${item.supply.name} added to your cart.'
              : '${item.supply.name} is already in your cart.',
        );
    }
  }

  // ---------- CSV / text exports ----------

  static String _csvCell(String value) => RegExp(r'[",\n]').hasMatch(value)
      ? '"${value.replaceAll('"', '""')}"'
      : value;

  String _stockCsv(
    List<_StockItem> items,
    Map<String, _AdjustmentSummary> adjustments,
    String period,
  ) {
    final rows = <List<String>>[
      [
        'Item', 'Brand', 'Category', 'SKU', 'Barcode', 'Status',
        'Stock', 'Unit', 'Stock (base)', 'Base unit',
        'Minimum (base)', 'Maximum (base)',
        'Cost per base unit (PHP)', 'Stock value (PHP)',
        // --- new ---
        'Adjustment period',
        'Adjustments (count)',
        'Adjusted in',
        'Adjusted out',
        'Net adjustment',
        'Net adjustment (base)',
        'Adjusted out value (PHP)',
        'Last adjusted',
        'Last adjustment note',
      ],
      for (final i in items)
        () {
          final a = adjustments[i.supply.id];
          final per = i.unitsPerDisplay;
          return <String>[
            _safeText(i.supply.name),
            _safeText(i.supply.brand ?? ''),
            _safeText(i.category),
            _safeText(i.supply.sku ?? ''),
            _safeText(i.supply.barcode ?? ''),
            i.status.label,
            _plain(i.displayQty),
            i.displayUnit,
            _plain(i.supply.currentStock),
            i.supply.stockUnit,
            _plain(i.supply.minimumStock),
            _plain(i.supply.maximumStock),
            (i.supply.costPerBaseUnit / 100).toStringAsFixed(4),
            (i.valueCents / 100).toStringAsFixed(2),
            // --- new ---
            period,
            '${a?.count ?? 0}',
            a == null ? '0' : _plain(a.increase / per),
            a == null ? '0' : _plain(a.decrease / per),
            a == null ? '0' : _plain(a.net / per),
            a == null ? '0' : _plain(a.net),
            a == null
                ? '0.00'
                : (a.decrease * i.supply.costPerBaseUnit / 10000)
                      .toStringAsFixed(2),
            a?.lastDate == null
                ? ''
                : DateFormat('yyyy-MM-dd HH:mm').format(a!.lastDate!),
            _safeText(a?.lastNote ?? ''),
          ];
        }(),
    ];
    return rows.map((r) => r.map(_csvCell).join(',')).join('\n');
  }

  String _reorderText(_Snapshot s) {
    final buffer = StringBuffer('Reorder list — ')
      ..writeln(DateFormat('MMM d, yyyy').format(DateTime.now()));
    for (final i in s.reorder) {
      buffer.writeln(
        '• ${i.supply.name}: ${i.reorderQty} ${i.displayUnit} '
        '(have ${_qty(i.displayQty)}) ~ ${_peso(i.reorderCostCents)}',
      );
    }
    buffer.write('Estimated total: ${_peso(s.reorderCost)}');
    return buffer.toString();
  }

  // ---------- export ----------

  bool get _filtersActive =>
      _query.trim().isNotEmpty ||
      _statusFilter != null ||
      _categoryFilter != null;

  String _scopeLabel(bool filteredOnly) {
    if (!filteredOnly || !_filtersActive) return 'All items';
    final parts = <String>[
      if (_statusFilter != null) _statusFilter!.label,
      if (_categoryFilter != null) _categoryFilter!,
      if (_query.trim().isNotEmpty) 'search "${_query.trim()}"',
    ];
    return 'Filtered: ${parts.join(', ')}';
  }

  /// "Current view" keeps the Stock tab's filters and sort; "All items" is
  /// grouped by category, then name, which reads best on paper.
  List<_StockItem> _exportItems(_Snapshot s, bool filteredOnly) {
    if (filteredOnly) return _filteredItems(s);
    return [...s.items]..sort((a, b) {
      final byCategory = a.category.toLowerCase().compareTo(
        b.category.toLowerCase(),
      );
      return byCategory != 0
          ? byCategory
          : a.supply.name.toLowerCase().compareTo(b.supply.name.toLowerCase());
    });
  }

  /// Anchor for the iPad / desktop share popover.
  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openExport(_Snapshot s) async {
    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _ExportSheet(
        totalCount: s.items.length,
        filteredCount: _filtersActive ? _filteredItems(s).length : null,
      ),
    );
    if (choice == null || !mounted) return;

    final (action, filteredOnly) = choice;
    await _runExport(s, action, filteredOnly);
  }

  Future<void> _runExport(
    _Snapshot s,
    _ExportAction action,
    bool filteredOnly,
  ) async {
    final items = _exportItems(s, filteredOnly);
    if (items.isEmpty) {
      _snack('There are no items to export.');
      return;
    }

    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final origin = _shareOrigin();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final moves = await ref.read(_movementsProvider(_range).future);
      final adjustments = _summariseAdjustments(moves);
      final period = _periodLabel;

      switch (action) {
        case _ExportAction.copy:
          await _copy(
            _stockCsv(items, adjustments, period),
            'Stock report copied — paste it into Excel or Google Sheets.',
          );

        case _ExportAction.csv:
          final csvName = 'inventory-stock-$stamp.csv';
          // The byte-order mark makes Excel read accents and symbols correctly.
          final csvBytes = Uint8List.fromList(
            utf8.encode('\uFEFF${_stockCsv(items, adjustments, period)}'),
          );
          await Share.shareXFiles(
            [XFile.fromData(csvBytes, mimeType: 'text/csv', name: csvName)],
            fileNameOverrides: [csvName],
            subject: 'Inventory stock report',
            sharePositionOrigin: origin,
          );

        case _ExportAction.pdf:
        case _ExportAction.print:
          _snack('Preparing your report…');
          final pdfName = 'inventory-stock-$stamp.pdf';
          final pdfBytes = await _buildStockPdf(
            items: items,
            scopeLabel: _scopeLabel(filteredOnly),
            adjustments: adjustments,
            periodLabel: period,
          );
          if (action == _ExportAction.print) {
            await Printing.layoutPdf(
              onLayout: (_) async => pdfBytes,
              name: pdfName,
            );
          } else {
            await Printing.sharePdf(
              bytes: pdfBytes,
              filename: pdfName,
              subject: 'Inventory stock report',
              bounds: origin,
            );
          }
          messenger.hideCurrentSnackBar();
      }
    } catch (_) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      _snack('Couldn\'t create the report. Please try again.');
    }
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cartRestore = ref.watch(cartReadyProvider);
    if (cartRestore.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Restoring purchase...'),
            ],
          ),
        ),
      );
    }
    if (cartRestore.hasError) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => ref.invalidate(cartReadyProvider),
            child: const Text('Could not restore purchase. Retry'),
          ),
        ),
      );
    }

    final suppliesAsync = ref.watch(suppliesProvider);
    final categories =
        ref.watch(_categoryNamesProvider).asData?.value ??
        const <String, String>{};
    final cartIds = ref
        .watch(cartProvider)
        .map((line) => line.supplyId)
        .whereType<String>()
        .toSet();

    final supplies = suppliesAsync.asData?.value;
    final snapshot = supplies == null
        ? null
        : _Snapshot([for (final s in supplies) _StockItem.from(s, categories)]);

    final reorderCount = snapshot?.reorder.length ?? 0;

    // Very narrow phones scroll the tabs; huge screens centre them; everything
    // in between shares the width equally.
    final scrollableTabs = screenWidth < 400 || screenWidth >= _kWideBreakpoint;
    final TabAlignment? tabAlignment = !theme.useMaterial3
        ? null
        : (scrollableTabs
              ? (screenWidth >= _kWideBreakpoint
                    ? TabAlignment.center
                    : TabAlignment.start)
              : TabAlignment.fill);

    // Respect the user's font size, but cap it so layouts never break.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 4,
          title: _TitleBlock(asOf: _asOf, showBadge: screenWidth >= 380),
          actions: [
            IconButton(
              tooltip: 'Export report',
              onPressed: snapshot == null ? null : () => _openExport(snapshot),
              icon: const Icon(Icons.ios_share_rounded),
            ),
            // On phones Refresh moves into the overflow menu (pull-to-refresh
            // also works), which keeps the title from being squeezed.
            if (screenWidth >= _kMediumBreakpoint)
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: snapshot != null,
              onSelected: (value) {
                if (snapshot == null) return;
                switch (value) {
                  case 'refresh':
                    _refresh();
                  case 'reorder':
                    _copy(_reorderText(snapshot), 'Reorder list copied.');
                  case 'history':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PurchaseHistoryPage(),
                      ),
                    );
                  case 'adjustments':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AllStockAdjustmentsPage(),
                      ),
                    );
                }
              },
              itemBuilder: (_) => [
                if (screenWidth < _kMediumBreakpoint)
                  const PopupMenuItem(
                    value: 'refresh',
                    child: _MenuRow(Icons.refresh_rounded, 'Refresh'),
                  ),
                PopupMenuItem(
                  value: 'reorder',
                  child: _MenuRow(Icons.checklist_rounded, 'Copy reorder list'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'history',
                  child: _MenuRow(Icons.history_rounded, 'Purchase history'),
                ),
                PopupMenuItem(
                  value: 'adjustments',
                  child: _MenuRow(
                    Icons.remove_shopping_cart_outlined,
                    'Stock adjustments',
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: scrollableTabs,
            tabAlignment: tabAlignment,
            tabs: [
              const Tab(text: 'Overview'),
              const Tab(text: 'Stock'),
              const Tab(text: 'Movements'),
              Tab(
                text: reorderCount > 0 ? 'Reorder · $reorderCount' : 'Reorder',
              ),
            ],
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            if (snapshot == null) {
              return suppliesAsync.hasError
                  ? _MessageState(
                      icon: Icons.error_outline_rounded,
                      title: 'Unable to load the report',
                      message: 'Check your connection to the local database.',
                      actionLabel: 'Try again',
                      onAction: () => ref.invalidate(suppliesProvider),
                    )
                  : const Center(child: CircularProgressIndicator());
            }

            if (snapshot.items.isEmpty) {
              return _MessageState(
                icon: Icons.inventory_2_outlined,
                title: 'No supplies to report on yet',
                message:
                    'Add supplies and record purchases — stock levels, value and reorder suggestions will appear here.',
                actionLabel: 'Back to supplies',
                onAction: () => Navigator.maybePop(context),
              );
            }

            return TabBarView(
              controller: _tabs,
              children: [
                _buildOverview(snapshot, width),
                _buildStock(snapshot, width),
                _buildMovements(width),
                _buildReorder(snapshot, cartIds, width),
              ],
            );
          },
        ),
      ),
    );
  }

  // ==========================================================================
  // OVERVIEW
  // ==========================================================================

  Widget _buildOverview(_Snapshot s, double width) {
    final scheme = Theme.of(context).colorScheme;
    final wide = width >= _kWideBreakpoint;

    final attention = s.reorder.take(5).toList();
    final topByValue =
        (s.items.where((i) => i.valueCents > 0).toList()
              ..sort((a, b) => b.valueCents.compareTo(a.valueCents)))
            .take(5)
            .toList();

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(snapshot: s, onFilter: _openStock),
        const SizedBox(height: _kGap),
        _KpiGrid(
          tiles: [
            _KpiData(
              icon: Icons.remove_shopping_cart_outlined,
              label: 'Out of stock',
              value: '${s.count(_Status.out)}',
              color: _Status.out.color(scheme),
              onTap: () => _openStock(_Status.out),
            ),
            _KpiData(
              icon: Icons.warning_amber_rounded,
              label: 'Low stock',
              value: '${s.count(_Status.low)}',
              color: _Status.low.color(scheme),
              onTap: () => _openStock(_Status.low),
            ),
            _KpiData(
              icon: Icons.trending_up_rounded,
              label: 'Overstocked',
              value: '${s.count(_Status.over)}',
              color: _Status.over.color(scheme),
              onTap: () => _openStock(_Status.over),
            ),
            _KpiData(
              icon: Icons.shopping_cart_checkout_rounded,
              label: 'To reorder (est.)',
              value: _peso(s.reorderCost),
              color: scheme.primary,
              onTap: () => _tabs.animateTo(3),
            ),
          ],
        ),
      ],
    );

    final attentionSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Needs attention',
          subtitle: attention.isEmpty ? null : 'Out of stock and running low',
          trailing: s.reorder.length > attention.length
              ? TextButton(
                  onPressed: () => _tabs.animateTo(3),
                  child: Text('See all ${s.reorder.length}'),
                )
              : null,
        ),
        if (attention.isEmpty)
          const _Panel(
            child: _InlineNote(
              icon: Icons.check_circle_outline_rounded,
              text: 'All stock levels are healthy. Nothing needs reordering.',
            ),
          )
        else
          _Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < attention.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  _AttentionRow(
                    item: attention[i],
                    onTap: () => _onStockAction('details', attention[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );

    final categorySection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: 'Value by category'),
        _Panel(
          child: s.totalValue <= 0
              ? const _InlineNote(
                  icon: Icons.info_outline_rounded,
                  text:
                      'No stock value yet. Record purchases with prices to see how your money is spread.',
                )
              : _CategoryBars(values: s.valueByCategory, total: s.totalValue),
        ),
      ],
    );

    final topSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Top items by value',
          subtitle: topByValue.isEmpty
              ? null
              : 'Where most of your stock money sits',
        ),
        if (topByValue.isEmpty)
          const _Panel(
            child: _InlineNote(
              icon: Icons.info_outline_rounded,
              text: 'Items appear here once they have stock and a cost.',
            ),
          )
        else
          _Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < topByValue.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  _ValueRow(
                    rank: i + 1,
                    item: topByValue[i],
                    share: s.totalValue == 0
                        ? 0
                        : topByValue[i].valueCents / s.totalValue,
                    onTap: () => _onStockAction('details', topByValue[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );

    final movementSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Stock movement',
          trailing: TextButton(
            onPressed: () => _tabs.animateTo(2),
            child: const Text('View all'),
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PeriodSelector(
                preset: _preset,
                range: _range,
                onSelected: _selectPreset,
              ),
              const SizedBox(height: 14),
              Consumer(
                builder: (context, ref, _) {
                  final async = ref.watch(_movementsProvider(_range));
                  if (async.hasError && !async.hasValue) {
                    return const _InlineNote(
                      icon: Icons.error_outline_rounded,
                      text: 'Unable to load movements. Pull down to retry.',
                    );
                  }
                  final moves = async.asData?.value;
                  return _FlowTiles(
                    totals: moves == null ? null : _MoveTotals(moves),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );

    final left = [summary, attentionSection];
    final right = [categorySection, topSection, movementSection];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding(context, width),
        children: wide
            ? [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _spaced(left, _kSectionGap),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _spaced(right, _kSectionGap),
                      ),
                    ),
                  ],
                ),
              ]
            : _spaced([...left, ...right], _kSectionGap),
      ),
    );
  }

  // ==========================================================================
  // STOCK
  // ==========================================================================

  List<_StockItem> _filteredItems(_Snapshot s) {
    final q = _query.trim().toLowerCase();

    final list = s.items.where((i) {
      if (_statusFilter != null && i.status != _statusFilter) return false;
      if (_categoryFilter != null && i.category != _categoryFilter) {
        return false;
      }
      if (q.isEmpty) return true;

      final sp = i.supply;
      return sp.name.toLowerCase().contains(q) ||
          (sp.brand ?? '').toLowerCase().contains(q) ||
          (sp.sku ?? '').toLowerCase().contains(q) ||
          (sp.barcode ?? '').toLowerCase().contains(q) ||
          i.category.toLowerCase().contains(q);
    }).toList();

    final int Function(_StockItem, _StockItem) compare = switch (_sort) {
      _Sort.attention => (a, b) {
        final byStatus = a.status.index.compareTo(b.status.index);
        return byStatus != 0 ? byStatus : (a.fill ?? 9).compareTo(b.fill ?? 9);
      },
      _Sort.name => (a, b) => a.supply.name.toLowerCase().compareTo(
        b.supply.name.toLowerCase(),
      ),
      _Sort.value => (a, b) => b.valueCents.compareTo(a.valueCents),
      _Sort.quantity => (a, b) => a.supply.currentStock.compareTo(
        b.supply.currentStock,
      ),
    };
    list.sort(compare);
    return list;
  }

  /// Search + filters. Lives inside the scroll view (not pinned) so short
  /// landscape screens keep their space for the list.
  Widget _stockHeader(_Snapshot s, List<_StockItem> items, double width) {
    final scheme = Theme.of(context).colorScheme;
    final filteredValue = items.fold<int>(0, (sum, i) => sum + i.valueCents);

    final chips = <(String, _Status?)>[
      ('All ${s.items.length}', null),
      for (final st in _Status.values)
        if (s.count(st) > 0) ('${st.shortLabel} ${s.count(st)}', st),
    ];

    final chipWidgets = <Widget>[
      for (final (label, status) in chips)
        ChoiceChip(
          label: Text(label),
          showCheckmark: false,
          avatar: status == null
              ? null
              : Icon(status.icon, size: 16, color: status.color(scheme)),
          selected: _statusFilter == status,
          onSelected: (_) => setState(() => _statusFilter = status),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'Search name, brand, SKU or barcode',
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
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: _kGap),
        // Phones scroll the chips sideways; larger screens wrap them.
        if (width >= _kMediumBreakpoint)
          Wrap(spacing: 8, runSpacing: 8, children: chipWidgets)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < chipWidgets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chipWidgets[i],
                ],
              ],
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<String?>(
              tooltip: 'Filter by category',
              onSelected: (value) =>
                  setState(() => _categoryFilter = value == '' ? null : value),
              itemBuilder: (_) => [
                const PopupMenuItem<String?>(
                  value: '',
                  child: Text('All categories'),
                ),
                for (final c in s.categories)
                  PopupMenuItem<String?>(value: c, child: Text(c)),
              ],
              child: _MenuChip(
                icon: Icons.category_outlined,
                label: _categoryFilter ?? 'All categories',
                highlighted: _categoryFilter != null,
              ),
            ),
            PopupMenuButton<_Sort>(
              tooltip: 'Sort',
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (_) => [
                for (final option in _Sort.values)
                  CheckedPopupMenuItem<_Sort>(
                    value: option,
                    checked: option == _sort,
                    child: Text(option.label),
                  ),
              ],
              child: _MenuChip(
                icon: Icons.sort_rounded,
                label: _sort.label,
                highlighted: false,
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.ios_share_rounded, size: 16),
              label: const Text('Export'),
              onPressed: () => _openExport(s),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${items.length} item${items.length == 1 ? '' : 's'} · ${_peso(filteredValue)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStock(_Snapshot s, double width) {
    final items = _filteredItems(s);
    final columns = _columnsFor(_contentWidth(context, width));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _TileList<_StockItem>(
        items: items,
        columns: columns,
        padding: _pagePadding(context, width),
        header: _stockHeader(s, items, width),
        empty: _MessageState(
          icon: Icons.search_off_rounded,
          title: 'No items match',
          message: 'Try a different search or clear the filters.',
          actionLabel: 'Clear filters',
          onAction: () => setState(() {
            _searchController.clear();
            _query = '';
            _statusFilter = null;
            _categoryFilter = null;
          }),
          expand: false,
        ),
        itemBuilder: (item) => _StockTile(
          item: item,
          onTap: () => _onStockAction('details', item),
          onAction: (action) => _onStockAction(action, item),
        ),
      ),
    );
  }

  // ==========================================================================
  // MOVEMENTS
  // ==========================================================================

  Widget _buildMovements(double width) {
    return Consumer(
      builder: (context, ref, _) {
        final async = ref.watch(_movementsProvider(_range));
        final all = async.asData?.value;
        final moves = all == null
            ? const <_Move>[]
            : (_kindFilter == null
                  ? all
                  : all.where((m) => m.kind == _kindFilter).toList());

        // Flatten into day headers + rows for a single lazy list.
        final entries = <Object>[];
        String? lastDay;
        final dayFormat = DateFormat('EEEE, MMM d');
        for (final move in moves) {
          final day = dayFormat.format(move.movement.movementDate);
          if (day != lastDay) {
            entries.add(day);
            lastDay = day;
          }
          entries.add(move);
        }

        // Loading / error / empty all render *below* the header, so the period
        // and type filters never disappear while data is (re)loading.
        Widget? statusBody;
        if (all == null) {
          statusBody = async.hasError
              ? _MessageState(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load movements',
                  message: 'Check your connection and try again.',
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(_movementsProvider),
                  expand: false,
                )
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                );
        } else if (entries.isEmpty) {
          statusBody = _MessageState(
            icon: Icons.swap_vert_rounded,
            title: 'No movements',
            message: _kindFilter == null
                ? 'Nothing was restocked, used or adjusted in this period.'
                : 'No "${_kindFilter!.label.toLowerCase()}" movements in this period.',
            expand: false,
          );
        }

        final itemCount = 1 + (statusBody != null ? 1 : entries.length);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: _pagePadding(context, width, maxWidth: _kReadingWidth),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: _kGap),
                  child: _MovementHeader(
                    preset: _preset,
                    range: _range,
                    onPreset: _selectPreset,
                    kind: _kindFilter,
                    onKind: (k) => setState(() => _kindFilter = k),
                    totals: all == null ? null : _MoveTotals(all),
                    shown: all == null ? null : moves.length,
                  ),
                );
              }
              if (statusBody != null) return statusBody;

              final entry = entries[index - 1];
              if (entry is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(
                    entry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MoveTile(move: entry as _Move),
              );
            },
          ),
        );
      },
    );
  }

  // ==========================================================================
  // REORDER
  // ==========================================================================

  Widget _buildReorder(_Snapshot s, Set<String> cartIds, double width) {
    if (s.reorder.isEmpty) {
      return const _MessageState(
        icon: Icons.verified_outlined,
        title: 'Nothing to reorder',
        message:
            'No item is out of stock or at its low-stock level. Set minimum stock on your supplies to get reorder suggestions.',
      );
    }

    final notInCart = s.reorder
        .where((i) => !cartIds.contains(i.supply.id))
        .toList();

    final summary = _ReorderSummary(
      snapshot: s,
      allInCart: notInCart.isEmpty,
      onAddAll: () => _addAllToCart(notInCart),
      onCopy: () => _copy(_reorderText(s), 'Reorder list copied.'),
    );

    Widget tile(_StockItem item) => _ReorderTile(
      item: item,
      inCart: cartIds.contains(item.supply.id),
      onAdd: () => _onStockAction('cart', item),
      onTap: () => _onStockAction('details', item),
    );

    final pad = _pagePadding(context, width);
    final content = _contentWidth(context, width);

    // Wide screens: sticky summary on the left, suggestions on the right.
    if (width >= _kWideBreakpoint) {
      const panelWidth = 340.0;
      const panelGap = 20.0;
      final listWidth = content - panelWidth - panelGap;

      return Padding(
        padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: panelWidth,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(top: 12, bottom: pad.bottom),
                child: summary,
              ),
            ),
            const SizedBox(width: panelGap),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _TileList<_StockItem>(
                  items: s.reorder,
                  columns: _columnsFor(listWidth),
                  padding: EdgeInsets.only(top: 12, bottom: pad.bottom),
                  itemBuilder: tile,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Phones / small tablets: summary scrolls with the list.
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _TileList<_StockItem>(
        items: s.reorder,
        columns: _columnsFor(content),
        padding: pad,
        header: summary,
        itemBuilder: tile,
      ),
    );
  }
}

// ============================================================================
// SHARED BUILDING BLOCKS
// ============================================================================

/// A scrolling list that lays [items] out in [columns] equal-width columns,
/// keeping rows the same height. Rows are built lazily, so long lists stay fast.
class _TileList<T> extends StatelessWidget {
  const _TileList({
    required this.items,
    required this.itemBuilder,
    required this.padding,
    required this.columns,
    this.header,
    this.empty,
    this.spacing = _kGap,
  });

  final List<T> items;
  final Widget Function(T item) itemBuilder;
  final EdgeInsets padding;
  final int columns;
  final Widget? header;

  /// Shown under the header when [items] is empty.
  final Widget? empty;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rowCount = items.isEmpty
        ? (empty == null ? 0 : 1)
        : (items.length / columns).ceil();
    final offset = header == null ? 0 : 1;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: padding,
      itemCount: rowCount + offset,
      itemBuilder: (context, index) {
        if (header != null && index == 0) {
          return Padding(
            padding: EdgeInsets.only(bottom: spacing),
            child: header,
          );
        }
        if (items.isEmpty) return empty!;

        final rowIndex = index - offset;
        final start = rowIndex * columns;
        final end = math.min(start + columns, items.length);
        final row = items.sublist(start, end);
        final isLast = rowIndex == rowCount - 1;

        final Widget content = columns == 1
            ? itemBuilder(row.first)
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) SizedBox(width: spacing),
                      Expanded(
                        child: i < row.length
                            ? itemBuilder(row[i])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              );

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : spacing),
          child: content,
        );
      },
    );
  }
}

/// App-bar title: a small icon badge, the page name and when the data was
/// last refreshed. The badge is dropped on narrow screens to protect the title.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.asOf, required this.showBadge});

  final DateTime asOf;
  final bool showBadge;

  String get _stamp {
    final now = DateTime.now();
    final sameDay =
        now.year == asOf.year && now.month == asOf.month && now.day == asOf.day;
    final time = DateFormat('h:mm a').format(asOf);
    return sameDay
        ? 'today, $time'
        : '${DateFormat('MMM d').format(asOf)}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        if (showBadge) ...[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inventory report',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Updated $_stamp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
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
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// A money/quantity figure that shrinks instead of overflowing, capped to
/// [maxWidth] so it can never squeeze the text beside it.
class _Amount extends StatelessWidget {
  const _Amount(this.text, {this.style, this.maxWidth = 116})
    : alignment = Alignment.centerRight;

  final String text;
  final TextStyle? style;
  final double maxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(text, maxLines: 1, style: style),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.highlighted,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlighted
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(maxWidth: 200, minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.expand = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );

    return expand
        ? Center(child: SingleChildScrollView(child: content))
        : Center(child: content);
  }
}

// ============================================================================
// OVERVIEW WIDGETS
// ============================================================================

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.snapshot, required this.onFilter});

  final _Snapshot snapshot;
  final ValueChanged<_Status?> onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = snapshot;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total stock value',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _peso(s.totalValue),
              maxLines: 1,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${s.items.length} item${s.items.length == 1 ? '' : 's'} across ${s.valueByCategory.length} categor${s.valueByCategory.length == 1 ? 'y' : 'ies'}, valued at average cost',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          _HealthBar(snapshot: s),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in _Status.values)
                if (s.count(status) > 0)
                  Material(
                    color: scheme.surface.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onFilter(status),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: status.color(scheme),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${status.shortLabel} ${s.count(status)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.snapshot});

  final _Snapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final status in _Status.values)
              if (snapshot.count(status) > 0)
                Expanded(
                  flex: snapshot.count(status),
                  child: Container(
                    margin: const EdgeInsets.only(right: 1.5),
                    color: status.color(scheme),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
}

/// 2 columns on phones, 4 across when the parent is wide enough.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.tiles});

  final List<_KpiData> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        const gap = 10.0;
        final rows = (tiles.length / columns).ceil();

        return Column(
          children: [
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      Expanded(
                        child: r * columns + c < tiles.length
                            ? _KpiTile(data: tiles[r * columns + c])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Panel(
      onTap: data.onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(data.icon, size: 20, color: data.color),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, required this.onTap});

  final _StockItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = item.status.color(scheme);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(item.status.icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.supply.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.status == _Status.out
                        ? 'Out of stock · order ${item.reorderQty} ${item.displayUnit}'
                        : '${_qty(item.displayQty)} ${item.displayUnit} left · order ${item.reorderQty}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Amount(
              _peso(item.reorderCostCents),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.rank,
    required this.item,
    required this.share,
    required this.onTap,
  });

  final int rank;
  final _StockItem item;
  final double share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.supply.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${_qty(item.displayQty)} ${item.displayUnit} · ${(share * 100).toStringAsFixed(1)}% of total',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Amount(
              _peso(item.valueCents),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.values, required this.total});

  final Map<String, int> values;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final sorted = values.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final rows = <MapEntry<String, int>>[
      ...sorted.take(6),
      if (sorted.length > 6)
        MapEntry(
          'Other categories',
          sorted.skip(6).fold<int>(0, (sum, e) => sum + e.value),
        ),
    ];
    final largest = rows.isEmpty ? 1 : rows.first.value;

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  rows[i].key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Amount(
                '${_peso(rows[i].value)} · ${(rows[i].value / total * 100).toStringAsFixed(0)}%',
                maxWidth: 170,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rows[i].value / largest,
              minHeight: 8,
              backgroundColor: scheme.primary.withValues(alpha: 0.10),
              color: scheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.preset,
    required this.range,
    required this.onSelected,
  });

  final _Preset preset;
  final DateTimeRange range;
  final ValueChanged<_Preset> onSelected;

  String get _customLabel {
    final format = DateFormat('MMM d');
    final last = range.end.subtract(const Duration(days: 1));
    return '${format.format(range.start)} – ${format.format(last)}';
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in _Preset.values)
          ChoiceChip(
            showCheckmark: false,
            avatar: p == _Preset.custom
                ? const Icon(Icons.date_range_rounded, size: 16)
                : null,
            label: Text(
              p == _Preset.custom && preset == _Preset.custom
                  ? _customLabel
                  : p.label,
            ),
            selected: preset == p,
            onSelected: (_) => onSelected(p),
          ),
      ],
    );
  }
}

/// Restocked / used / written-off totals. Side by side when there is room,
/// stacked as full-width rows on narrow panels so figures stay readable.
/// A null [totals] means "still loading" and shows a dash.
class _FlowTiles extends StatelessWidget {
  const _FlowTiles({required this.totals});

  final _MoveTotals? totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final tiles = <_FlowData>[
      _FlowData(
        icon: Icons.move_to_inbox_rounded,
        label: 'Restocked',
        cents: totals?.restocked,
        color: Colors.green.shade700,
      ),
      _FlowData(
        icon: Icons.outbox_rounded,
        label: 'Used / sold',
        cents: totals?.used,
        color: Colors.blue.shade700,
      ),
      _FlowData(
        icon: Icons.delete_sweep_outlined,
        label: 'Written off',
        cents: totals?.writtenOff,
        color: scheme.error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 440;

        if (horizontal) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _FlowTile(data: tiles[i])),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _FlowTile(data: tiles[i], inline: true),
            ],
          ],
        );
      },
    );
  }
}

class _FlowData {
  const _FlowData({
    required this.icon,
    required this.label,
    required this.cents,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int? cents;
  final Color color;
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({required this.data, this.inline = false});

  final _FlowData data;

  /// Icon + label on the left, amount on the right (narrow layout).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = data.color;
    final value = data.cents == null ? '—' : _peso(data.cents!);

    final labelText = Text(
      data.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: inline
          ? Row(
              children: [
                Icon(data.icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(child: labelText),
                const SizedBox(width: 10),
                _Amount(
                  value,
                  maxWidth: 160,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(data.icon, size: 18, color: color),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
                labelText,
              ],
            ),
    );
  }
}

// ============================================================================
// STOCK TAB WIDGETS
// ============================================================================

class _StockTile extends StatelessWidget {
  const _StockTile({
    required this.item,
    required this.onTap,
    required this.onAction,
  });

  final _StockItem item;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = item.status.color(scheme);
    final supply = item.supply;
    final brand = (supply.brand ?? '').trim();

    final limits = [
      if (item.lowDisplay != null) 'Min ${_qty(item.lowDisplay!)}',
      if (item.maxDisplay != null) 'Max ${_qty(item.maxDisplay!)}',
    ].join(' · ');

    // Stacked in three bands (identity, status, numbers) so a long name or a
    // large quantity can never collide with its neighbour.
    return _Panel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(item.status.icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supply.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (brand.isNotEmpty)
                        Text(
                          brand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: onAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'details',
                    child: _MenuRow(Icons.open_in_new_rounded, 'View details'),
                  ),
                  PopupMenuItem(
                    value: 'adjust',
                    child: _MenuRow(
                      Icons.remove_shopping_cart_outlined,
                      'Adjust stock',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'cart',
                    child: _MenuRow(
                      Icons.add_shopping_cart_rounded,
                      'Add to cart',
                    ),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(text: item.status.label, color: color),
                    _Pill(text: item.category, color: scheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${_qty(item.displayQty)} ${item.displayUnit}',
                            maxLines: 1,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _peso(item.valueCents),
                            maxLines: 1,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.fill != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: item.fill!.clamp(0.0, 1.0),
                      minHeight: 6,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                    ),
                  ),
                  if (limits.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$limits ${item.displayUnit}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MOVEMENTS TAB WIDGETS
// ============================================================================

class _MovementHeader extends StatelessWidget {
  const _MovementHeader({
    required this.preset,
    required this.range,
    required this.onPreset,
    required this.kind,
    required this.onKind,
    required this.totals,
    required this.shown,
  });

  final _Preset preset;
  final DateTimeRange range;
  final ValueChanged<_Preset> onPreset;
  final _MoveKind? kind;
  final ValueChanged<_MoveKind?> onKind;

  /// Null while loading.
  final _MoveTotals? totals;
  final int? shown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = shown;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PeriodSelector(preset: preset, range: range, onSelected: onPreset),
          const SizedBox(height: 14),
          _FlowTiles(totals: totals),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All types'),
                showCheckmark: false,
                selected: kind == null,
                onSelected: (_) => onKind(null),
              ),
              for (final k in _MoveKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  showCheckmark: false,
                  selected: kind == k,
                  onSelected: (_) => onKind(k),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            count == null
                ? 'Loading movements…'
                : '$count movement${count == 1 ? '' : 's'} · valued at current average cost',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveTile extends StatelessWidget {
  const _MoveTile({required this.move});

  final _Move move;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final positive = move.qty >= 0;
    final color = positive ? Colors.green.shade700 : scheme.error;
    final icon = switch (move.kind) {
      _MoveKind.restock => Icons.move_to_inbox_rounded,
      _MoveKind.used => Icons.outbox_rounded,
      _MoveKind.adjustment => Icons.tune_rounded,
      _MoveKind.transfer => Icons.swap_horiz_rounded,
    };

    final note = (move.movement.notes ?? '').trim();
    final unit = move.supply.stockUnit;

    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  move.supply.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  [
                    move.kind.label,
                    if (note.isNotEmpty) note,
                    DateFormat('h:mm a').format(move.movement.movementDate),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Amount(
                  '${positive ? '+' : '−'}${_qty(move.qty.abs())} $unit',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                _Amount(
                  _peso(move.valueCents),
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

// ============================================================================
// REORDER TAB WIDGETS
// ============================================================================

class _ReorderSummary extends StatelessWidget {
  const _ReorderSummary({
    required this.snapshot,
    required this.allInCart,
    required this.onAddAll,
    required this.onCopy,
  });

  final _Snapshot snapshot;
  final bool allInCart;
  final VoidCallback onAddAll;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = snapshot;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested purchase',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _peso(s.reorderCost),
              maxLines: 1,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${s.reorder.length} item${s.reorder.length == 1 ? '' : 's'} · restocks each to its maximum, or twice its low-stock level, at the latest price.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          // Wraps under the primary action instead of squeezing on narrow cards.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: allInCart ? null : onAddAll,
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: Text(allInCart ? 'All in cart' : 'Add all to cart'),
              ),
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy list'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    required this.item,
    required this.inCart,
    required this.onAdd,
    required this.onTap,
  });

  final _StockItem item;
  final bool inCart;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = item.status.color(scheme);
    final unit = item.displayUnit;

    return _Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.supply.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Pill(text: item.status.label, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Have ${_qty(item.displayQty)} $unit'
            '${item.targetDisplay == null ? '' : ' · restock to ${_qty(item.targetDisplay!)} $unit'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ${item.reorderQty} $unit',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '≈ ${_peso(item.reorderCostCents)} at ${_peso(item.supply.currentPrice)} each',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              inCart
                  ? FilledButton.tonalIcon(
                      onPressed: null,
                      icon: Icon(Icons.check_rounded, size: 18),
                      label: Text('In cart'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: onAdd,
                      icon: const Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 18,
                      ),
                      label: const Text('Add'),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
