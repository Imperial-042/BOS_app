// lib/features/inventory/stock_transfers_page.dart
//
// Inventory -> Stock Transfers.
//
//   * hero with live counts (to receive / on the way / received lately)
//   * pill tabs Incoming / Outgoing / All + status filter chips
//   * transfer cards that draw the route (from -> to) with an animated truck
//     while in transit, grouped by day
//   * detail sheet: route header, timeline, item cards, receive with live
//     shortage feedback, cancel with confirmation
//   * guided "Send stock" flow: pick destination, add items in bulk, quick
//     quantity chips, live validation against what is on hand
//
// Logic is unchanged: it still calls StockTransferService.createAndShip /
// receive / cancel exactly as before.

import 'dart:math' as math;

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/people/hr_providers.dart'
    show hrNamesProvider;
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'stock_transfer_service.dart';

// ============================================================
// HELPERS
// ============================================================

const _amber = Color(0xFFB7791F);
const _slate = Color(0xFF64748B);
const _green = Color(0xFF159B67);
const _orange = Color(0xFFE67E22);

const _branchPalette = <Color>[
  Color(0xFF0E7490),
  Color(0xFF6366F1),
  Color(0xFFDB2777),
  Color(0xFF16A34A),
  Color(0xFFEA580C),
  Color(0xFF7C3AED),
];

Color _branchColor(Branch? b) {
  if (b == null) return _slate;
  if (b.isHeadquarters) return _amber;
  return _branchPalette[b.id.hashCode.abs() % _branchPalette.length];
}

IconData _branchIcon(Branch? b) => (b?.isHeadquarters ?? false)
    ? Icons.home_work_rounded
    : Icons.store_mall_directory_rounded;

String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
String _err(Object e) => e is StateError ? e.message : e.toString();
String _items(int n) => '$n item${n == 1 ? '' : 's'}';

String _when(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  return day == today
      ? DateFormat('h:mm a').format(d)
      : DateFormat('MMM d · h:mm a').format(d);
}

String _bucket(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return 'Earlier this week';
  return DateFormat('MMMM yyyy').format(d);
}

class _StatusStyle {
  const _StatusStyle(this.color, this.label, this.icon, this.gradient);
  final Color color;
  final String label;
  final IconData icon;
  final List<Color> gradient;
}

_StatusStyle _styleOf(String status) => switch (status) {
  'received' => const _StatusStyle(
    _green,
    'Received',
    Icons.check_circle_rounded,
    [Color(0xFF047857), Color(0xFF10B981)],
  ),
  'cancelled' => const _StatusStyle(
    _slate,
    'Cancelled',
    Icons.cancel_rounded,
    [Color(0xFF475569), Color(0xFF94A3B8)],
  ),
  _ => const _StatusStyle(
    _orange,
    'In transit',
    Icons.local_shipping_rounded,
    [Color(0xFFB45309), Color(0xFFF59E0B)],
  ),
};

/// Something that can be transferred, with the quantity at the source branch.
class _PickItem {
  const _PickItem(this.type, this.id, this.name, this.unit, this.onHand);
  final String type;
  final String id;
  final String name;
  final String unit;
  final double onHand;

  String get key => '$type:$id';
}

final _transferableItemsProvider = FutureProvider.autoDispose<List<_PickItem>>((
  ref,
) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final branchId = ref.watch(selectedBranchIdProvider);
  final stock = StockService(db, viewBranchId: branchId);

  final sMap = await stock.supplyQtyMap(businessId, branchId);
  final pMap = await stock.productQtyMap(businessId, branchId);
  final supplies =
      await (db.select(db.supplies)
            ..where(
              (s) => s.businessId.equals(businessId) & s.isActive.equals(true),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.name)]))
          .get();
  final products =
      await (db.select(db.products)
            ..where(
              (p) =>
                  p.businessId.equals(businessId) &
                  p.isActive.equals(true) &
                  p.trackingType.equals('stocked'),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .get();
  return [
    for (final s in supplies)
      _PickItem('supply', s.id, s.name, s.stockUnit, sMap[s.id] ?? 0),
    for (final p in products)
      _PickItem('product', p.id, p.name, p.unit, pMap[p.id] ?? 0),
  ];
});

// ============================================================
// PAGE
// ============================================================

class StockTransfersPage extends ConsumerStatefulWidget {
  const StockTransfersPage({super.key});

  @override
  ConsumerState<StockTransfersPage> createState() => _StockTransfersPageState();
}

class _StockTransfersPageState extends ConsumerState<StockTransfersPage> {
  String? _status; // null = every status

  void _openSend() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _NewTransferSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final branchId = ref.watch(selectedBranchIdProvider);
    final branches = ref.watch(branchesProvider);
    final byId = {
      for (final b in ref.watch(allBranchesProvider).value ?? const <Branch>[])
        b.id: b,
    };
    final canCreate = ref.watch(canProvider(BosPermission.stockTransferCreate));
    final all = ref.watch(stockTransfersProvider);

    if (branches.length < 2) return const _SingleBranchState();

    return all.when(
      loading: () => const _LoadingSkeleton(),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (list) {
        final incoming = list.where((t) => t.toBranchId == branchId).toList();
        final outgoing = list.where((t) => t.fromBranchId == branchId).toList();
        final mine = list
            .where(
              (t) => t.fromBranchId == branchId || t.toBranchId == branchId,
            )
            .toList();

        final waiting = incoming.where((t) => t.status == 'in_transit').length;
        final onTheWay = outgoing
            .where((t) => t.status == 'in_transit')
            .length;
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        final receivedRecent = incoming
            .where(
              (t) =>
                  t.status == 'received' &&
                  (t.receivedAt ?? t.updatedAt).isAfter(cutoff),
            )
            .length;

        final hero = _TransferHero(
          branchName: byId[branchId]?.name ?? 'This branch',
          waiting: waiting,
          onTheWay: onTheWay,
          receivedRecent: receivedRecent,
        );

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            floatingActionButton: canCreate
                ? FloatingActionButton.extended(
                    heroTag: 'new_transfer',
                    onPressed: _openSend,
                    icon: const Icon(Icons.local_shipping_rounded),
                    label: const Text('Send stock'),
                  )
                : null,
            body: LayoutBuilder(
              builder: (context, c) {
                final side = math.max(16.0, (c.maxWidth - 900) / 2);

                Widget tab(List<StockTransfer> src, String kind) {
                  final shown = _status == null
                      ? src
                      : src.where((t) => t.status == _status).toList();

                  final children = <Widget>[];
                  String? last;
                  for (var i = 0; i < shown.length; i++) {
                    final t = shown[i];
                    final b = _bucket(t.createdAt);
                    if (b != last) {
                      children.add(_DayHeader(b));
                      last = b;
                    }
                    children.add(
                      _FadeIn(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TransferCard(
                            transfer: t,
                            byId: byId,
                            branchId: branchId,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: EdgeInsets.fromLTRB(side, 6, side, 110),
                    children: [
                      hero,
                      const SizedBox(height: 14),
                      if (shown.isEmpty)
                        _EmptyTransfers(
                          kind: kind,
                          filtered: _status != null,
                          onSend: canCreate ? _openSend : null,
                        )
                      else
                        ...children,
                    ],
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                      child: _PillTabs(waiting: waiting),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: _StatusChips(
                        selected: _status,
                        pad: side,
                        onSelect: (v) => setState(() => _status = v),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          tab(incoming, 'incoming'),
                          tab(outgoing, 'outgoing'),
                          tab(mine, 'all'),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// SMALL SHARED WIDGETS
// ============================================================

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + math.min(index, 8) * 45),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 12),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _CountUp extends StatelessWidget {
  const _CountUp(this.value, {required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Text('${v.round()}', style: style),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: scheme.onSurfaceVariant,
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
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
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

// ============================================================
// HERO + TABS + FILTERS
// ============================================================

class _TransferHero extends StatelessWidget {
  const _TransferHero({
    required this.branchName,
    required this.waiting,
    required this.onTheWay,
    required this.receivedRecent,
  });

  final String branchName;
  final int waiting;
  final int onTheWay;
  final int receivedRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -60,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -50,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stock transfers',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.place_rounded,
                                size: 14,
                                color: Color(0xD9FFFFFF),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'You are at $branchName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xD9FFFFFF),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        value: waiting,
                        label: 'To receive',
                        highlight: waiting > 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStat(value: onTheWay, label: 'On the way'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStat(
                        value: receivedRecent,
                        label: 'Received 30d',
                      ),
                    ),
                  ],
                ),
                if (waiting > 0) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => DefaultTabController.maybeOf(
                        context,
                      )?.animateTo(0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                waiting == 1
                                    ? '1 transfer is waiting for you to confirm'
                                    : '$waiting transfers are waiting for you to confirm',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: highlight ? 0.28 : 0.16),
        borderRadius: BorderRadius.circular(16),
        border: highlight
            ? Border.all(color: Colors.white.withValues(alpha: 0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _CountUp(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented pill tabs: the selected tab is a filled gradient pill.
class _PillTabs extends StatelessWidget {
  const _PillTabs({required this.waiting});

  final int waiting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(12),
        labelColor: Colors.white,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: AppColors.heroGradient),
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Incoming'),
                if (waiting > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _orange,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$waiting',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(text: 'Outgoing'),
          const Tab(text: 'All'),
        ],
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.selected,
    required this.pad,
    required this.onSelect,
  });

  final String? selected;
  final double pad;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? value, Color? dot) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        showCheckmark: false,
        selected: selected == value,
        avatar: dot == null
            ? const Icon(Icons.apps_rounded, size: 16)
            : Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
        label: Text(label),
        onSelected: (_) => onSelect(value),
      ),
    );

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        children: [
          chip('All', null, null),
          chip('In transit', 'in_transit', _orange),
          chip('Received', 'received', _green),
          chip('Cancelled', 'cancelled', _slate),
        ],
      ),
    );
  }
}

// ============================================================
// TRANSFER CARD
// ============================================================

class _TransferCard extends ConsumerWidget {
  const _TransferCard({
    required this.transfer,
    required this.byId,
    required this.branchId,
  });

  final StockTransfer transfer;
  final Map<String, Branch> byId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final t = transfer;
    final st = _styleOf(t.status);
    final items =
        ref.watch(stockTransferItemsProvider(t.id)).value ??
        const <StockTransferItem>[];
    final from = byId[t.fromBranchId];
    final to = byId[t.toBranchId];
    final incoming = t.toBranchId == branchId;
    final inTransit = t.status == 'in_transit';
    final actionNeeded = incoming && inTransit;
    final short =
        t.status == 'received' &&
        items.any(
          (i) =>
              i.receivedQuantity != null &&
              i.receivedQuantity! + 1e-9 < i.quantity,
        );
    final summary = items.isEmpty
        ? ''
        : items.take(2).map((i) => i.itemName).join(', ') +
              (items.length > 2 ? ' +${items.length - 2} more' : '');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: actionNeeded
              ? st.color.withValues(alpha: 0.6)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: actionNeeded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (actionNeeded ? st.color : Colors.black).withValues(
              alpha: actionNeeded ? 0.14 : 0.04,
            ),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            clipBehavior: Clip.antiAlias,
            constraints: const BoxConstraints(maxWidth: 640),
            builder: (_) => _TransferSheet(transfer: t, byId: byId),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: st.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _RouteEnd(
                              branch: from,
                              isYou: t.fromBranchId == branchId,
                            ),
                            Expanded(
                              child: _RouteLine(
                                color: st.color,
                                icon: st.icon,
                                moving: inTransit,
                              ),
                            ),
                            _RouteEnd(
                              branch: to,
                              isYou: t.toBranchId == branchId,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _Pill(st.label, st.color, icon: st.icon),
                            if (short) ...[
                              const SizedBox(width: 6),
                              const _Pill(
                                'Short',
                                Color(0xFFDC2626),
                                icon: Icons.warning_amber_rounded,
                              ),
                            ],
                            const Spacer(),
                            Text(
                              _when(t.createdAt),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (items.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${_items(items.length)} · $summary',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (inTransit) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: st.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  actionNeeded
                                      ? Icons.touch_app_rounded
                                      : Icons.hourglass_top_rounded,
                                  size: 16,
                                  color: st.color,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    actionNeeded
                                        ? 'Tap to confirm what arrived'
                                        : 'Waiting for ${to?.name ?? 'the receiver'} to confirm',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: st.color,
                                    ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteEnd extends StatelessWidget {
  const _RouteEnd({required this.branch, required this.isYou});

  final Branch? branch;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _branchColor(branch);

    return SizedBox(
      width: 86,
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isYou ? 0.2 : 0.12),
              shape: BoxShape.circle,
              border: isYou ? Border.all(color: color, width: 1.6) : null,
            ),
            child: Icon(_branchIcon(branch), size: 19, color: color),
          ),
          const SizedBox(height: 5),
          Text(
            branch?.name ?? '?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isYou ? FontWeight.w900 : FontWeight.w700,
              color: isYou ? color : scheme.onSurface,
            ),
          ),
          if (isYou)
            Text(
              'You',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}

/// A line between two branches with a status icon in the middle. While the
/// transfer is in transit the truck drives back and forth along the line.
class _RouteLine extends StatefulWidget {
  const _RouteLine({
    required this.color,
    required this.icon,
    required this.moving,
  });

  final Color color;
  final IconData icon;
  final bool moving;

  @override
  State<_RouteLine> createState() => _RouteLineState();
}

class _RouteLineState extends State<_RouteLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.moving) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _RouteLine old) {
    super.didUpdateWidget(old);
    if (widget.moving && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.moving && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 2.5,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final x = widget.moving
                  ? -0.7 + 1.4 * Curves.easeInOut.transform(_c.value)
                  : 0.0;
              return Align(alignment: Alignment(x, 0), child: child);
            },
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: widget.color, width: 1.6),
              ),
              child: Icon(
                widget.moving ? Icons.local_shipping_rounded : widget.icon,
                size: 15,
                color: widget.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// STATES
// ============================================================

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers({
    required this.kind,
    required this.filtered,
    required this.onSend,
  });

  final String kind;
  final bool filtered;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (icon, title, message) = filtered
        ? (
            Icons.filter_alt_off_rounded,
            'Nothing with this status',
            'Try another status filter to see more transfers.',
          )
        : switch (kind) {
            'incoming' => (
              Icons.move_to_inbox_rounded,
              'Nothing on the way to you',
              'When another branch sends you stock it shows up here, ready '
                  'to confirm.',
            ),
            'outgoing' => (
              Icons.outbox_rounded,
              'You haven\'t sent any stock',
              'Send supplies or products to another branch and track them '
                  'until they arrive.',
            ),
            _ => (
              Icons.swap_horiz_rounded,
              'No transfers yet',
              'Stock you send or receive between branches will be listed '
                  'here.',
            ),
          };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primaryContainer,
                  ),
                  child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 18),
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
              if (onSend != null && !filtered && kind != 'incoming') ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onSend,
                  icon: const Icon(Icons.local_shipping_rounded),
                  label: const Text('Send stock'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SingleBranchState extends StatelessWidget {
  const _SingleBranchState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget node(IconData icon, Color color) => Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 30, color: color),
    );

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    node(Icons.home_work_rounded, _amber),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: scheme.outline,
                        size: 30,
                      ),
                    ),
                    node(Icons.add_business_rounded, scheme.primary),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Add a second branch',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stock transfers move supplies and products between your '
                  'branches. Create another branch in Administration → '
                  'Branches to get started.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
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

class _LoadingSkeleton extends StatefulWidget {
  const _LoadingSkeleton();

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget block(double h, {double r = 22}) => Container(
      height: h,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(r),
      ),
    );

    return Scaffold(
      body: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            block(46, r: 16),
            const SizedBox(height: 14),
            block(160, r: 28),
            const SizedBox(height: 16),
            for (var i = 0; i < 3; i++) ...[
              block(130),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DETAIL SHEET
// ============================================================

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet({required this.transfer, required this.byId});

  final StockTransfer transfer;
  final Map<String, Branch> byId;

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final Map<String, TextEditingController> _qty = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel(StockTransferService service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: const Icon(Icons.undo_rounded),
        title: const Text('Cancel this transfer?'),
        content: const Text(
          'The stock goes back to your branch right away and the receiving '
          'branch will no longer see it as incoming.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep sending'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel and take back'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => service.cancel(widget.transfer.id));
  }

  /// null = not a valid number.
  double? _got(StockTransferItem it) {
    final c = _qty[it.id];
    if (c == null) return it.quantity;
    return double.tryParse(c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = widget.transfer;
    final st = _styleOf(t.status);
    final from = widget.byId[t.fromBranchId];
    final to = widget.byId[t.toBranchId];
    final branchId = ref.watch(selectedBranchIdProvider);
    final names = ref.watch(hrNamesProvider);
    final items =
        ref.watch(stockTransferItemsProvider(t.id)).value ??
        const <StockTransferItem>[];
    final canReceive =
        t.status == 'in_transit' &&
        t.toBranchId == branchId &&
        ref.watch(canProvider(BosPermission.stockTransferReceive));
    final canCancel =
        t.status == 'in_transit' &&
        t.fromBranchId == branchId &&
        ref.watch(canProvider(BosPermission.stockTransferCreate));
    final service = ref.read(stockTransferServiceProvider);

    if (canReceive) {
      for (final it in items) {
        _qty.putIfAbsent(
          it.id,
          () => TextEditingController(text: _n(it.quantity)),
        );
      }
    }

    // Live shortage while receiving.
    var shortCount = 0;
    var invalid = false;
    if (canReceive) {
      for (final it in items) {
        final v = _got(it);
        if (v == null || !v.isFinite || v < 0 || v > it.quantity + 1e-9) {
          invalid = true;
        } else if (v + 1e-9 < it.quantity) {
          shortCount++;
        }
      }
    }

    final sender = names[t.createdBy ?? ''];
    final receiver = names[t.receivedBy ?? ''];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------------------------------------------- header --
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: st.gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _HeaderEnd(branch: from)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Column(
                                children: [
                                  Icon(st.icon, color: Colors.white, size: 26),
                                  const SizedBox(height: 2),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(child: _HeaderEnd(branch: to)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _GlassChip(st.label),
                            _GlassChip(_items(items.length)),
                            _GlassChip(
                              DateFormat('MMM d, h:mm a').format(t.createdAt),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ------------------------------------- timeline --
                        _Timeline(
                          steps: [
                            _Step(
                              title: 'Sent from ${from?.name ?? '?'}',
                              subtitle: [
                                _when(t.shippedAt ?? t.createdAt),
                                if (sender != null) 'by $sender',
                              ].join(' · '),
                              done: true,
                              color: _orange,
                              icon: Icons.outbox_rounded,
                            ),
                            if (t.status == 'cancelled')
                              _Step(
                                title: 'Cancelled by sender',
                                subtitle: _when(t.updatedAt),
                                done: true,
                                color: _slate,
                                icon: Icons.cancel_rounded,
                              )
                            else
                              _Step(
                                title: t.status == 'received'
                                    ? 'Received at ${to?.name ?? '?'}'
                                    : 'Waiting at ${to?.name ?? '?'}',
                                subtitle: t.status == 'received'
                                    ? [
                                        _when(t.receivedAt ?? t.updatedAt),
                                        if (receiver != null) 'by $receiver',
                                      ].join(' · ')
                                    : 'Not confirmed yet',
                                done: t.status == 'received',
                                color: _green,
                                icon: Icons.move_to_inbox_rounded,
                              ),
                          ],
                        ),
                        if ((t.notes ?? '').isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.sticky_note_2_outlined,
                                  size: 18,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(t.notes!)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ITEMS',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            if (canReceive)
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        for (final it in items) {
                                          _qty[it.id]?.text = _n(it.quantity);
                                        }
                                      }),
                                icon: const Icon(
                                  Icons.done_all_rounded,
                                  size: 18,
                                ),
                                label: const Text('All arrived'),
                              ),
                          ],
                        ),
                        for (final it in items)
                          _ItemRow(
                            item: it,
                            controller: canReceive ? _qty[it.id] : null,
                            enabled: !_busy,
                            onChanged: () => setState(() => _error = null),
                          ),
                        if (canReceive && shortCount > 0) ...[
                          const SizedBox(height: 4),
                          _Banner(
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFFDC2626),
                            text:
                                '$shortCount item${shortCount == 1 ? ' is' : 's are'} short. '
                                'Only what you confirm is added to your stock.',
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          _Banner(
                            icon: Icons.error_outline_rounded,
                            color: scheme.error,
                            text: _error!,
                          ),
                        ],
                        if (canReceive) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: (_busy || invalid)
                                ? null
                                : () => _run(() {
                                    final got = <String, double>{};
                                    for (final it in items) {
                                      final v = _got(it);
                                      if (v == null || !v.isFinite) {
                                        throw StateError(
                                          'Enter a valid received quantity '
                                          'for ${it.itemName}.',
                                        );
                                      }
                                      got[it.id] = v;
                                    }
                                    HapticFeedback.mediumImpact();
                                    return service.receive(t.id, got);
                                  }),
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.inventory_2_rounded),
                            label: Text(
                              shortCount > 0
                                  ? 'Confirm with shortage'
                                  : 'Confirm received',
                            ),
                          ),
                        ],
                        if (canCancel) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _confirmCancel(service),
                            icon: const Icon(Icons.undo_rounded),
                            label: const Text('Cancel and take stock back'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderEnd extends StatelessWidget {
  const _HeaderEnd({required this.branch});

  final Branch? branch;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(_branchIcon(branch), color: Colors.white, size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          branch?.name ?? '?',
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.color,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final bool done;
  final Color color;
  final IconData icon;
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});

  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 40,
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: steps[i].done
                              ? steps[i].color
                              : scheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: steps[i].done
                                ? steps[i].color
                                : scheme.outlineVariant,
                            width: 1.6,
                          ),
                        ),
                        child: Icon(
                          steps[i].icon,
                          size: 18,
                          color: steps[i].done ? Colors.white : scheme.outline,
                        ),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: steps[i].done
                                ? steps[i].color.withValues(alpha: 0.4)
                                : scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < steps.length - 1 ? 18 : 0,
                      top: 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: steps[i].done
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          steps[i].subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One item of a transfer. While receiving it has a quantity field; after
/// receiving it shows whether everything arrived.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final StockTransferItem item;
  final TextEditingController? controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSupply = item.itemType == 'supply';
    final received = item.receivedQuantity;
    final shortBy = received == null ? 0.0 : item.quantity - received;
    final hasShortage = shortBy > 1e-9;

    final typed = controller == null
        ? null
        : double.tryParse(controller!.text.trim());
    final liveShort = typed != null && typed + 1e-9 < item.quantity;
    final bad =
        controller != null &&
        (typed == null || typed < 0 || typed > item.quantity + 1e-9);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bad
              ? scheme.error
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSupply ? Icons.inventory_2_outlined : Icons.sell_outlined,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sent ${_n(item.quantity)} ${item.unit}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (received != null) ...[
                  const SizedBox(height: 6),
                  hasShortage
                      ? _Pill(
                          'Received ${_n(received)} · short ${_n(shortBy)}',
                          const Color(0xFFDC2626),
                          icon: Icons.warning_amber_rounded,
                        )
                      : _Pill(
                          'Received ${_n(received)}',
                          _green,
                          icon: Icons.check_rounded,
                        ),
                ],
                if (liveShort && !bad) ...[
                  const SizedBox(height: 6),
                  _Pill(
                    'Short by ${_n(item.quantity - typed)}',
                    const Color(0xFFDC2626),
                  ),
                ],
                if (bad) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Enter 0 to ${_n(item.quantity)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (controller != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => onChanged(),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
                decoration: InputDecoration(
                  labelText: 'Got',
                  suffixText: item.unit,
                  isDense: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// NEW TRANSFER
// ============================================================

class _Line {
  _Line(this.item) : qty = TextEditingController();
  final _PickItem item;
  final TextEditingController qty;

  double? get value => double.tryParse(qty.text.trim());

  /// null when fine or still empty.
  String? get problem {
    final v = value;
    if (qty.text.trim().isEmpty) return null;
    if (v == null || v <= 0) return 'Enter a quantity above 0';
    if (v > item.onHand + 1e-9) {
      return 'Only ${_n(item.onHand)} ${item.unit} available';
    }
    return null;
  }

  bool get valid {
    final v = value;
    return v != null && v > 0 && v <= item.onHand + 1e-9;
  }
}

class _NewTransferSheet extends ConsumerStatefulWidget {
  const _NewTransferSheet();

  @override
  ConsumerState<_NewTransferSheet> createState() => _NewTransferSheetState();
}

class _NewTransferSheetState extends ConsumerState<_NewTransferSheet> {
  String? _to;
  final _lines = <_Line>[];
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _addItems() async {
    final picked = await showModalBottomSheet<List<_PickItem>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ItemPicker(taken: {for (final l in _lines) l.item.key}),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        for (final p in picked) {
          _lines.add(_Line(p));
        }
        _error = null;
      });
    }
  }

  void _removeLine(_Line l) {
    setState(() => _lines.remove(l));
    // The text field is still mounted for this frame; dispose after it.
    WidgetsBinding.instance.addPostFrameCallback((_) => l.qty.dispose());
  }

  /// Sets the quantity to a share of what is on hand.
  void _fill(_Line l, double fraction) {
    final on = l.item.onHand;
    var v = on * fraction;
    if (on == on.roundToDouble()) {
      v = math.max(1.0, v.floorToDouble());
    } else {
      v = double.parse(v.toStringAsFixed(2));
    }
    v = math.min(v, on);
    setState(() {
      l.qty.text = _n(v);
      _error = null;
    });
  }

  bool get _ready =>
      _to != null && _lines.isNotEmpty && _lines.every((l) => l.valid);

  Future<void> _ship() async {
    final from = ref.read(selectedBranchIdProvider);
    if (_to == null) {
      setState(() => _error = 'Choose the destination branch.');
      return;
    }
    final lines = <TransferLine>[];
    for (final l in _lines) {
      final q = l.value;
      if (q == null || q <= 0) {
        setState(() => _error = 'Enter a quantity for ${l.item.name}.');
        return;
      }
      lines.add(
        TransferLine(
          itemType: l.item.type,
          itemId: l.item.id,
          name: l.item.name,
          unit: l.item.unit,
          quantity: q,
        ),
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(stockTransferServiceProvider)
          .createAndShip(
            businessId: ref.read(selectedBusinessIdProvider),
            fromBranchId: from,
            toBranchId: _to!,
            lines: lines,
            notes: _notes.text,
          );
      ref.read(ledgerVersionProvider.notifier).state++;
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final from = ref.watch(selectedBranchIdProvider);
    final fromBranch = ref.watch(selectedBranchProvider);
    final others = ref
        .watch(branchesProvider)
        .where((b) => b.id != from)
        .toList();
    final toBranch = others.where((b) => b.id == _to).firstOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Send stock',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 14),

            // ------------------------------------------------- route card --
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.heroGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SheetEnd(
                      label: 'From',
                      name: fromBranch?.name ?? '—',
                      icon: _branchIcon(fromBranch),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white70,
                  ),
                  Expanded(
                    child: _SheetEnd(
                      label: 'To',
                      name: toBranch?.name ?? 'Choose below',
                      icon: toBranch == null
                          ? Icons.help_outline_rounded
                          : _branchIcon(toBranch),
                      dim: toBranch == null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in others)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(
                      _branchIcon(b),
                      size: 16,
                      color: _branchColor(b),
                    ),
                    selectedColor: _branchColor(b).withValues(alpha: 0.16),
                    label: Text(b.name),
                    selected: _to == b.id,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _to = b.id;
                            _error = null;
                          }),
                  ),
              ],
            ),

            // ------------------------------------------------------ items --
            const SizedBox(height: 20),
            Text(
              'ITEMS',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            for (final l in _lines) _LineCard(
              key: ObjectKey(l),
              line: l,
              enabled: !_busy,
              onChanged: () => setState(() => _error = null),
              onRemove: () => _removeLine(l),
              onFill: (f) => _fill(l, f),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _busy ? null : _addItems,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.5),
                    width: 1.4,
                  ),
                  color: scheme.primary.withValues(alpha: 0.05),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      _lines.isEmpty ? 'Add items to send' : 'Add more items',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notes,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _Banner(
                icon: Icons.error_outline_rounded,
                color: scheme.error,
                text: _error!,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: (_busy || !_ready) ? null : _ship,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.local_shipping_rounded),
              label: Text(
                _ready
                    ? 'Send ${_items(_lines.length)} to ${toBranch?.name ?? ''}'
                    : 'Choose a branch and add items',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetEnd extends StatelessWidget {
  const _SheetEnd({
    required this.label,
    required this.name,
    required this.icon,
    this.dim = false,
  });

  final String label;
  final String name;
  final IconData icon;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: dim ? 0.12 : 0.22),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: dim ? 0.7 : 1),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    required this.onFill,
  });

  final _Line line;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final ValueChanged<double> onFill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = line.item;
    final problem = line.problem;
    final v = line.value;
    final fraction = (v == null || item.onHand <= 0)
        ? 0.0
        : (v / item.onHand).clamp(0.0, 1.0).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: problem != null
              ? scheme.error
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  item.type == 'supply'
                      ? Icons.inventory_2_outlined
                      : Icons.sell_outlined,
                  size: 19,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Have ${_n(item.onHand)} ${item.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: line.qty,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => onChanged(),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    suffixText: item.unit,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: fraction,
              backgroundColor: scheme.surfaceContainerHigh,
              color: problem != null ? scheme.error : scheme.primary,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  problem ??
                      (v != null && v > 0
                          ? 'Leaves ${_n(math.max(0, item.onHand - v))} ${item.unit} here'
                          : 'Quick amount'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: problem != null
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: problem != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (item.onHand > 0) ...[
                for (final f in const [0.25, 0.5, 1.0])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        f == 1.0 ? 'All' : (f == 0.5 ? '½' : '¼'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: enabled ? () => onFill(f) : null,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ITEM PICKER (multi-select)
// ============================================================

class _ItemPicker extends ConsumerStatefulWidget {
  const _ItemPicker({required this.taken});

  final Set<String> taken;

  @override
  ConsumerState<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<_ItemPicker> {
  String _q = '';
  String? _type; // null = all, 'supply', 'product'
  final Map<String, _PickItem> _chosen = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(_transferableItemsProvider);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add items',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v.toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search items',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, value) in const [
                      ('All', null),
                      ('Supplies', 'supply'),
                      ('Products', 'product'),
                    ])
                      ChoiceChip(
                        showCheckmark: false,
                        label: Text(label),
                        selected: _type == value,
                        onSelected: (_) => setState(() => _type = value),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final shown = list
                    .where(
                      (i) =>
                          (_type == null || i.type == _type) &&
                          i.name.toLowerCase().contains(_q),
                    )
                    .toList();
                if (shown.isEmpty) {
                  return Center(
                    child: Text(
                      'No matching items',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final i = shown[index];
                    final added = widget.taken.contains(i.key);
                    final out = i.onHand <= 0;
                    final enabled = !added && !out;
                    final picked = _chosen.containsKey(i.key);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: picked
                            ? scheme.primary.withValues(alpha: 0.08)
                            : scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: picked
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.5),
                            width: picked ? 1.4 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: enabled
                              ? () => setState(() {
                                  if (picked) {
                                    _chosen.remove(i.key);
                                  } else {
                                    _chosen[i.key] = i;
                                  }
                                })
                              : null,
                          child: Opacity(
                            opacity: enabled ? 1 : 0.5,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      i.type == 'supply'
                                          ? Icons.inventory_2_outlined
                                          : Icons.sell_outlined,
                                      size: 20,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          i.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          added
                                              ? 'Already added'
                                              : out
                                              ? 'Out of stock here'
                                              : '${_n(i.onHand)} ${i.unit} here',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: out
                                                ? scheme.error
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(
                                      milliseconds: 160,
                                    ),
                                    child: Icon(
                                      picked
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      key: ValueKey(picked),
                                      color: picked
                                          ? scheme.primary
                                          : scheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _chosen.isEmpty
                    ? null
                    : () => Navigator.pop(context, _chosen.values.toList()),
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  _chosen.isEmpty
                      ? 'Select items'
                      : 'Add ${_items(_chosen.length)}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}