// lib/features/inventory/stock_transfers_page.dart  (NEW FILE)
// Inventory -> Stock Transfers. Tabs: Incoming / Outgoing / All.

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'stock_transfer_service.dart';

String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
String _err(Object e) => e is StateError ? e.message : e.toString();

/// Something that can be transferred, with the quantity at the source branch.
class _PickItem {
  const _PickItem(this.type, this.id, this.name, this.unit, this.onHand);
  final String type;
  final String id;
  final String name;
  final String unit;
  final double onHand;
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

class StockTransfersPage extends ConsumerWidget {
  const StockTransfersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = ref.watch(selectedBranchIdProvider);
    final branches = ref.watch(branchesProvider);
    final names = {
      for (final b in ref.watch(allBranchesProvider).value ?? const <Branch>[])
        b.id: b.name,
    };
    final canCreate = ref.watch(canProvider(BosPermission.stockTransferCreate));
    final all = ref.watch(stockTransfersProvider);

    if (branches.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock Transfers')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Add a second branch (Administration → Branches) to move stock '
              'between branches.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return all.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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

        Widget tab(List<StockTransfer> items) => items.isEmpty
            ? const Center(child: Text('No transfers yet.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  for (final t in items)
                    _TransferCard(
                      transfer: t,
                      names: names,
                      branchId: branchId,
                    ),
                ],
              );

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 20,
              title: Text(
                'Stock Transfers · ${names[branchId] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              bottom: TabBar(
                tabs: [
                  Tab(text: waiting > 0 ? 'Incoming ($waiting)' : 'Incoming'),
                  const Tab(text: 'Outgoing'),
                  const Tab(text: 'All'),
                ],
              ),
            ),
            floatingActionButton: canCreate
                ? FloatingActionButton.extended(
                    heroTag: 'new_transfer',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (_) => const _NewTransferSheet(),
                    ),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Send stock'),
                  )
                : null,
            body: TabBarView(
              children: [tab(incoming), tab(outgoing), tab(mine)],
            ),
          ),
        );
      },
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.transfer,
    required this.names,
    required this.branchId,
  });
  final StockTransfer transfer;
  final Map<String, String> names;
  final String branchId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = transfer;
    final (color, label) = switch (t.status) {
      'received' => (Colors.green.shade700, 'Received'),
      'cancelled' => (scheme.outline, 'Cancelled'),
      _ => (Colors.orange.shade800, 'In transit'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _TransferSheet(transfer: t, names: names),
        ),
        leading: Icon(
          t.toBranchId == branchId
              ? Icons.south_west_rounded
              : Icons.north_east_rounded,
          color: color,
        ),
        title: Text(
          '${names[t.fromBranchId] ?? '?'} → ${names[t.toBranchId] ?? '?'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(DateFormat('MMM d · h:mm a').format(t.createdAt)),
        trailing: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- detail sheet --

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet({required this.transfer, required this.names});
  final StockTransfer transfer;
  final Map<String, String> names;

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

  @override
  Widget build(BuildContext context) {
    final t = widget.transfer;
    final branchId = ref.watch(selectedBranchIdProvider);
    final items = ref.watch(stockTransferItemsProvider(t.id)).value ?? const [];
    final canReceive =
        t.status == 'in_transit' &&
        t.toBranchId == branchId &&
        ref.watch(canProvider(BosPermission.stockTransferReceive));
    final canCancel =
        t.status == 'in_transit' &&
        t.fromBranchId == branchId &&
        ref.watch(canProvider(BosPermission.stockTransferCreate));
    final service = ref.read(stockTransferServiceProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.names[t.fromBranchId] ?? '?'} → ${widget.names[t.toBranchId] ?? '?'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if ((t.notes ?? '').isNotEmpty) Text(t.notes!),
            const SizedBox(height: 12),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${it.itemName}\nSent ${_n(it.quantity)} ${it.unit}'
                        '${it.receivedQuantity != null ? ' · received ${_n(it.receivedQuantity!)}' : ''}',
                      ),
                    ),
                    if (canReceive)
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _qty.putIfAbsent(
                            it.id,
                            () => TextEditingController(text: _n(it.quantity)),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Received',
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 14),
            if (canReceive)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() {
                        final got = <String, double>{};
                        for (final it in items) {
                          final v = double.tryParse(
                            _qty[it.id]?.text.trim() ?? '',
                          );
                          got[it.id] = v ?? it.quantity;
                        }
                        return service.receive(t.id, got);
                      }),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Confirm received'),
              ),
            if (canCancel) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => service.cancel(t.id)),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Cancel and take stock back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- new transfer --

class _Line {
  _Line(this.item) : qty = TextEditingController();
  final _PickItem item;
  final TextEditingController qty;
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

  Future<void> _addItem() async {
    final picked = await showModalBottomSheet<_PickItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ItemPicker(
        taken: {for (final l in _lines) '${l.item.type}:${l.item.id}'},
      ),
    );
    if (picked != null) setState(() => _lines.add(_Line(picked)));
  }

  Future<void> _ship() async {
    final from = ref.read(selectedBranchIdProvider);
    if (_to == null) {
      setState(() => _error = 'Choose the destination branch.');
      return;
    }
    final lines = <TransferLine>[];
    for (final l in _lines) {
      final q = double.tryParse(l.qty.text.trim());
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
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = ref.watch(selectedBranchIdProvider);
    final branches = ref
        .watch(branchesProvider)
        .where((b) => b.id != from)
        .toList();
    final fromName = ref.watch(selectedBranchProvider)?.name ?? '';

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
              'Send stock from $fromName',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _to,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Send to'),
              items: [
                for (final b in branches)
                  DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _to = v),
            ),
            const SizedBox(height: 12),
            for (final l in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.item.name}\nHave ${_n(l.item.onHand)} ${l.item.unit}',
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: l.qty,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Qty',
                          suffixText: l.item.unit,
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _lines.remove(l)),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add item'),
            ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _ship,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemPicker extends ConsumerStatefulWidget {
  const _ItemPicker({required this.taken});
  final Set<String> taken;

  @override
  ConsumerState<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<_ItemPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(_transferableItemsProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search items',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final shown = list
                    .where((i) => i.name.toLowerCase().contains(_q))
                    .toList();
                return ListView(
                  children: [
                    for (final i in shown)
                      ListTile(
                        enabled:
                            i.onHand > 0 &&
                            !widget.taken.contains('${i.type}:${i.id}'),
                        leading: Icon(
                          i.type == 'supply'
                              ? Icons.inventory_2_outlined
                              : Icons.sell_outlined,
                        ),
                        title: Text(i.name),
                        subtitle: Text('${_n(i.onHand)} ${i.unit} here'),
                        onTap: () => Navigator.pop(context, i),
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
