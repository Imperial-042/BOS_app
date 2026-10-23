// lib/features/transactions/presentation/screens/pos_shifts_page.dart
//
// Past and current shifts, with a per-shift report (sales, payment mix, cash
// reconciliation) that can be copied as text (Z-report).
//
// Use [showShiftDetailSheet] to open the detail sheet from ANY screen.

import 'dart:async';

import 'package:bos_application/core/format/money.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import 'transaction_page.dart' show kCurrentBusinessId;
import '../../domain/pos_session_service.dart';

final posShiftsProvider = StreamProvider<List<PosSession>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.posSessions)
        ..where((s) => s.businessId.equals(kCurrentBusinessId))
        ..orderBy([(s) => OrderingTerm.desc(s.openedAt)]))
      .watch();
});

// ───────────────────────── helpers ─────────────────────────

String _dt(DateTime d) => DateFormat('MMM d, yyyy · h:mm a').format(d);
String _shortDt(DateTime d) => DateFormat('MMM d · h:mm a').format(d);

String _duration(Duration d) {
  if (d.inMinutes < 1) return '<1m';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

Duration _shiftLength(PosSession s) =>
    (s.closedAt ?? DateTime.now()).difference(s.openedAt);

String _shiftCode(PosSession s) => s.id.substring(0, 6).toUpperCase();

/// Visual description of a cash variance (over / short / balanced).
class _VarianceStyle {
  final String label;
  final Color color;
  final IconData icon;
  const _VarianceStyle(this.label, this.color, this.icon);

  factory _VarianceStyle.of(int variance, ColorScheme scheme) {
    if (variance == 0) {
      return _VarianceStyle(
        'Drawer balanced',
        Colors.green.shade700,
        Icons.check_circle_rounded,
      );
    }
    if (variance > 0) {
      return _VarianceStyle(
        'Over by ${formatPeso(variance)}',
        Colors.orange.shade800,
        Icons.arrow_circle_up_rounded,
      );
    }
    return _VarianceStyle(
      'Short by ${formatPeso(-variance)}',
      scheme.error,
      Icons.arrow_circle_down_rounded,
    );
  }
}

/// Opens the shift detail sheet. Safe to call from any screen: it uses the
/// root navigator (so it sits above bottom bars / nested navigators) and the
/// sheet pins its action bar inside the bottom safe area.
Future<void> showShiftDetailSheet(BuildContext context, PosSession session) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => ShiftDetailSheet(session: session),
  );
}

// ───────────────────────── page ─────────────────────────

class POSShiftsPage extends ConsumerWidget {
  const POSShiftsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final shiftsAsync = ref.watch(posShiftsProvider);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainerLowest,
        scrolledUnderElevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shifts', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              'Open, closed, and cash variance',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      body: shiftsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Unable to load shifts: $e')),
        data: (shifts) {
          if (shifts.isEmpty) return const _EmptyShifts();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  32 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                itemCount: shifts.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => i == 0
                    ? _OverviewHeader(shifts: shifts)
                    : _ShiftCard(session: shifts[i - 1]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyShifts extends StatelessWidget {
  const _EmptyShifts();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.point_of_sale_rounded,
                size: 44,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No shifts yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Open a shift from the POS and it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── overview header ─────────────────────────

class _OverviewHeader extends StatelessWidget {
  final List<PosSession> shifts;
  const _OverviewHeader({required this.shifts});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final open = shifts.where((s) => s.status == 'open').length;
    final closed = shifts.length - open;
    var netVariance = 0;
    for (final s in shifts) {
      final c = s.countedCash;
      final e = s.expectedCash;
      if (c != null && e != null) netVariance += c - e;
    }
    final vStyle = _VarianceStyle.of(netVariance, scheme);

    Widget tile(IconData icon, String label, String value, Color color) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile(
          Icons.play_circle_rounded,
          'Open now',
          '$open',
          Colors.green.shade700,
        ),
        const SizedBox(width: 10),
        tile(Icons.lock_rounded, 'Closed', '$closed', scheme.primary),
        const SizedBox(width: 10),
        tile(
          vStyle.icon,
          'Net variance',
          netVariance == 0
              ? '₱0'
              : '${netVariance > 0 ? '+' : '-'}${formatPeso(netVariance.abs())}',
          vStyle.color,
        ),
      ],
    );
  }
}

// ───────────────────────── shift card ─────────────────────────

class _ShiftCard extends StatelessWidget {
  final PosSession session;
  const _ShiftCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOpen = session.status == 'open';

    final int? counted = session.countedCash;
    final int? expected = session.expectedCash;
    final int? variance = (counted != null && expected != null)
        ? counted - expected
        : null;
    final vStyle = variance == null
        ? null
        : _VarianceStyle.of(variance, scheme);

    final accent = isOpen ? Colors.green.shade700 : scheme.primary;

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isOpen
              ? Colors.green.shade700.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: isOpen ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => showShiftDetailSheet(context, session),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isOpen
                          ? Icons.point_of_sale_rounded
                          : Icons.receipt_long_rounded,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shift #${_shiftCode(session)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _shortDt(session.openedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(isOpen: isOpen),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    text: isOpen
                        ? 'Running ${_duration(_shiftLength(session))}'
                        : _duration(_shiftLength(session)),
                  ),
                  _InfoChip(
                    icon: Icons.account_balance_wallet_outlined,
                    text: 'Float ${formatPeso(session.openingCash)}',
                  ),
                  if (session.closedAt != null)
                    _InfoChip(
                      icon: Icons.lock_clock_outlined,
                      text: 'Closed ${_shortDt(session.closedAt!)}',
                    ),
                ],
              ),
              if (vStyle != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: vStyle.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(vStyle.icon, size: 18, color: vStyle.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vStyle.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: vStyle.color,
                          ),
                        ),
                      ),
                      Text(
                        'Counted ${formatPeso(counted!)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isOpen;
  const _StatusBadge({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isOpen ? Colors.green.shade700 : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOpen) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            isOpen ? 'OPEN' : 'CLOSED',
            style: TextStyle(
              color: color,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── detail sheet ─────────────────────────

class ShiftDetailSheet extends ConsumerStatefulWidget {
  final PosSession session;
  const ShiftDetailSheet({super.key, required this.session});

  @override
  ConsumerState<ShiftDetailSheet> createState() => _ShiftDetailSheetState();
}

class _ShiftDetailSheetState extends ConsumerState<ShiftDetailSheet> {
  late final Future<ShiftSummary> _summary = ref
      .read(posSessionServiceProvider)
      .summarize(widget.session);

  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  int _avgSale(ShiftSummary sum) =>
      sum.salesCount > 0 ? sum.grossCents ~/ sum.salesCount : 0;

  int _collected(ShiftSummary sum) =>
      sum.byAccountId.values.fold<int>(0, (a, b) => a + b);

  String _perHour(ShiftSummary sum) {
    final hours = _shiftLength(widget.session).inMinutes / 60;
    if (hours < 0.1 || sum.salesCount == 0) return '—';
    return (sum.salesCount / hours).toStringAsFixed(1);
  }

  Future<void> _copy(ShiftSummary sum) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: _zReport(sum)));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _zReport(ShiftSummary sum) {
    final s = widget.session;
    final collected = _collected(sum);
    final b = StringBuffer()
      ..writeln('SHIFT REPORT #${_shiftCode(s)}')
      ..writeln('Status: ${s.status == 'open' ? 'OPEN' : 'CLOSED'}')
      ..writeln('Opened: ${_dt(s.openedAt)}');
    final closed = s.closedAt;
    if (closed != null) b.writeln('Closed: ${_dt(closed)}');
    b
      ..writeln('Duration: ${_duration(_shiftLength(s))}')
      ..writeln('--------------------------------')
      ..writeln('Sales: ${sum.salesCount}')
      ..writeln('Voided: ${sum.voidedCount}')
      ..writeln('Stock-only: ${sum.stockOnlyCount}')
      ..writeln('Average sale: ${formatPeso(_avgSale(sum))}')
      ..writeln('Gross sales: ${formatPeso(sum.grossCents)}')
      ..writeln('--------------------------------')
      ..writeln('PAYMENTS');
    for (final e in sum.byAccountId.entries) {
      final pct = collected > 0 ? (e.value * 100 / collected) : 0;
      b.writeln(
        '${sum.accountNames[e.key] ?? 'Account'}: ${formatPeso(e.value)} '
        '(${pct.toStringAsFixed(0)}%)',
      );
    }
    b.writeln('Total collected: ${formatPeso(collected)}');
    if (sum.discountCents > 0) {
      b.writeln('Discounts given: ${formatPeso(sum.discountCents)}');
    }
    if (sum.creditCents > 0) {
      b.writeln('On credit: ${formatPeso(sum.creditCents)}');
    }
    if (sum.voidedCents > 0) {
      b.writeln('Voided value: ${formatPeso(sum.voidedCents)}');
    }
    if (sum.cashiers.isNotEmpty) {
      b
        ..writeln('--------------------------------')
        ..writeln('CASHIERS');
      for (final c in sum.cashiers) {
        b.writeln(
          '${c.name}: ${c.count} ${c.count == 1 ? 'sale' : 'sales'}, '
          '${formatPeso(c.cents)}',
        );
      }
    }
    b
      ..writeln('--------------------------------')
      ..writeln('CASH DRAWER')
      ..writeln('Opening cash: ${formatPeso(s.openingCash)}')
      ..writeln('Cash sales: ${formatPeso(sum.cashSalesCents)}');
    if (sum.changeGivenCents > 0) {
      b
        ..writeln('Cash handed over: ${formatPeso(sum.cashTenderedCents)}')
        ..writeln('Change given: ${formatPeso(sum.changeGivenCents)}');
    }
    b.writeln('Expected in drawer: ${formatPeso(sum.expectedCashCents)}');
    final int? counted = s.countedCash;
    if (counted != null) {
      final v = counted - sum.expectedCashCents;
      b
        ..writeln('Counted: ${formatPeso(counted)}')
        ..writeln(
          v == 0
              ? 'Balanced'
              : v > 0
              ? 'Over by ${formatPeso(v)}'
              : 'Short by ${formatPeso(-v)}',
        );
    }
    if (sum.voids.isNotEmpty) {
      b
        ..writeln('--------------------------------')
        ..writeln('VOIDED RECEIPTS');
      for (final v in sum.voids) {
        final why = v.reason.isEmpty ? 'no reason' : v.reason;
        b.writeln('${v.code} ${formatPeso(v.cents)} (${v.cashier}) - $why');
      }
    }
    final notes = s.notes;
    if (notes != null && notes.trim().isNotEmpty) {
      b
        ..writeln('--------------------------------')
        ..writeln('Note: ${notes.trim()}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ShiftSummary>(
      future: _summary,
      builder: (context, snap) {
        if (snap.hasError) {
          return SizedBox(
            height: 220,
            child: Center(child: Text('Unable to load shift: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final sum = snap.data!;

        // Column: scrollable content + PINNED footer. The footer lives outside
        // the scroll view and inside its own SafeArea, so the button is never
        // under the gesture bar / nav bar (the cause of the half-tappable bug).
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _content(context, sum),
              ),
            ),
            _footer(context, sum),
          ],
        );
      },
    );
  }

  // ── content ──

  Widget _content(BuildContext context, ShiftSummary sum) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.session;
    final isOpen = s.status == 'open';

    final expected = sum.expectedCashCents;
    final int? counted = s.countedCash;
    final int? variance = counted == null ? null : counted - expected;

    final collected = _collected(sum);
    final mix = sum.byAccountId.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // header
        Row(
          children: [
            Expanded(
              child: Text(
                'Shift #${_shiftCode(s)}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _StatusBadge(isOpen: isOpen),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          s.closedAt == null
              ? 'Opened ${_dt(s.openedAt)}'
              : '${_dt(s.openedAt)}  →  ${_dt(s.closedAt!)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // hero: gross sales
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                Color.lerp(scheme.primary, scheme.tertiary, 0.55)!,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GROSS SALES',
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.8),
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatPeso(sum.grossCents),
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 15,
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOpen
                        ? 'Running ${_duration(_shiftLength(s))}'
                        : 'Lasted ${_duration(_shiftLength(s))}',
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // stat grid
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.shopping_bag_outlined,
                label: 'Sales',
                value: '${sum.salesCount}',
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.block_rounded,
                label: 'Voided',
                value: '${sum.voidedCount}',
                color: sum.voidedCount > 0
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.inventory_2_outlined,
                label: 'Stock-only',
                value: '${sum.stockOnlyCount}',
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.trending_up_rounded,
                label: 'Avg. sale',
                value: formatPeso(_avgSale(sum)),
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // payment mix
        _Section(
          title: 'Payments',
          trailing: formatPeso(collected),
          child: mix.isEmpty
              ? Text(
                  'No payments recorded.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              : Column(
                  children: [
                    for (final e in mix)
                      _MixRow(
                        name: sum.accountNames[e.key] ?? 'Account',
                        amount: e.value,
                        share: collected > 0 ? e.value / collected : 0,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),

        // cashiers
        if (sum.cashiers.isNotEmpty) ...[
          _Section(
            title: 'Cashiers',
            trailing: '${sum.cashiers.length}',
            child: Column(
              children: [
                for (final c in sum.cashiers)
                  _MixRow(
                    name:
                        '${c.name} · ${c.count} ${c.count == 1 ? 'sale' : 'sales'}',
                    amount: c.cents,
                    share: sum.grossCents > 0 ? c.cents / sum.grossCents : 0,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // activity
        _Section(
          title: 'Activity',
          child: Column(
            children: [
              if (sum.firstSaleAt != null)
                _kv(scheme, 'First sale', _shortDt(sum.firstSaleAt!)),
              if (sum.lastSaleAt != null)
                _kv(scheme, 'Last sale', _shortDt(sum.lastSaleAt!)),
              _kv(scheme, 'Sales per hour', _perHour(sum)),
              if (sum.discountCents > 0)
                _kv(scheme, 'Discounts given', formatPeso(sum.discountCents)),
              if (sum.creditCents > 0)
                _kv(
                  scheme,
                  'On credit (receivable)',
                  formatPeso(sum.creditCents),
                ),
              if (sum.voidedCents > 0)
                _kv(scheme, 'Voided value', formatPeso(sum.voidedCents)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // cash drawer
        _Section(
          title: 'Cash drawer',
          child: Column(
            children: [
              _kv(scheme, 'Opening cash', formatPeso(s.openingCash)),
              _kv(scheme, '+ Cash sales', formatPeso(sum.cashSalesCents)),
              if (sum.changeGivenCents > 0) ...[
                _kv(
                  scheme,
                  '   Cash handed over',
                  formatPeso(sum.cashTenderedCents),
                ),
                _kv(
                  scheme,
                  '   Change given',
                  '-${formatPeso(sum.changeGivenCents)}',
                ),
              ],
              const Divider(height: 20),
              _kv(
                scheme,
                'Expected in drawer',
                formatPeso(expected),
                strong: true,
              ),
              if (counted != null)
                _kv(scheme, 'Counted', formatPeso(counted), strong: true),
              if (variance != null) ...[
                const SizedBox(height: 10),
                _VarianceBanner(style: _VarianceStyle.of(variance, scheme)),
              ] else if (isOpen) ...[
                const SizedBox(height: 10),
                Text(
                  'Drawer will be counted when the shift is closed.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),

        // voids
        if (sum.voids.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Voided receipts',
            trailing: '${sum.voids.length}',
            child: Column(
              children: [
                for (final v in sum.voids.take(5)) _VoidTile(info: v),
                if (sum.voids.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+${sum.voids.length - 5} more (see the full list in '
                      'the copied report)',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // notes
        if ((s.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Note',
            child: Text(s.notes!.trim(), style: theme.textTheme.bodyMedium),
          ),
        ],
      ],
    );
  }

  Widget _kv(ColorScheme scheme, String l, String v, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              v,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
                fontSize: strong ? 15 : 14,
              ),
            ),
          ],
        ),
      );

  // ── pinned footer ──

  Widget _footer(BuildContext context, ShiftSummary sum) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _copied ? Colors.green.shade700 : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => _copy(sum),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_all_rounded,
                  key: ValueKey(_copied),
                ),
              ),
              label: Text(
                _copied ? 'Copied to clipboard' : 'Copy shift report',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── small widgets ─────────────────────────

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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

class _Section extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget child;
  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MixRow extends StatelessWidget {
  final String name;
  final int amount;
  final double share; // 0..1
  const _MixRow({
    required this.name,
    required this.amount,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                formatPeso(amount),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(share * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _VarianceBanner extends StatelessWidget {
  final _VarianceStyle style;
  const _VarianceBanner({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(style.icon, color: style.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              style.label,
              style: TextStyle(fontWeight: FontWeight.w900, color: style.color),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoidTile extends StatelessWidget {
  final VoidedSaleInfo info;
  const _VoidTile({required this.info});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final why = info.reason.isEmpty ? 'No reason given' : info.reason;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.block_rounded, size: 16, color: scheme.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${info.code}${info.stockOnly ? ' · stock-only' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$why · ${info.cashier}'
                  '${info.voidedAt == null ? '' : ' · ${_shortDt(info.voidedAt!)}'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatPeso(info.cents),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: scheme.error,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }
}
