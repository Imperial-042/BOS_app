// Order details under the order type (table, guests, customer, address,
// platform order no.), the table picker and the table manager.

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/core/ledger/domain/order_type_service.dart';
import 'package:bos_application/features/transactions/domain/pos_session_service.dart'
    show friendlyError;
import 'package:bos_application/features/transactions/domain/pos_table_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/held_orders_sheet.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_order_state.dart';
import 'package:bos_application/features/transactions/presentation/widgets/order_type_picker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

const _kHeld = '__held__';

// ============================================================================
// PROVIDERS + VALIDATION + SAVING
// ============================================================================

/// The full order type row of the name picked in the dropdown (or null).
final selectedOrderTypeProvider = Provider<PosOrderType?>((ref) {
  final name = ref.watch(posOrderTypeProvider);
  if (name == null) return null;
  final all = ref.watch(allOrderTypesProvider).value ?? const <PosOrderType>[];
  for (final t in all) {
    if (t.isActive && t.name == name) return t;
  }
  return null;
});

/// Tables that currently have a held order, with that order.
final heldByTableProvider = Provider<Map<String, HeldOrder>>((ref) {
  final held = ref.watch(heldOrdersProvider);
  return {
    for (final h in held)
      if (h.details.tableId != null) h.details.tableId!: h,
  };
});

/// What is still missing for the chosen order type (null = all good).
String? orderDetailsProblem(WidgetRef ref) {
  final type = ref.watch(selectedOrderTypeProvider);
  final d = ref.watch(posOrderDetailsProvider);
  final tables = (ref.watch(allPosTablesProvider).value ?? const <PosTable>[])
      .where((t) => t.isActive)
      .toList();
  final held = ref.watch(heldByTableProvider);
  if (type == null) return null;

  bool blank(String? s) => (s ?? '').trim().isEmpty;

  // Only required when the business actually has tables.
  if (type.requiresTable && tables.isNotEmpty) {
    if (d.tableId == null) return 'Choose a table for ${type.name}.';
    if (held.containsKey(d.tableId)) {
      return '${d.tableLabel ?? 'This table'} already has a held order.';
    }
  }
  if (type.requiresCustomer && blank(d.contactName)) {
    return 'Enter the customer name for ${type.name}.';
  }
  if (type.requiresAddress && blank(d.address)) {
    return 'Enter the delivery address.';
  }
  if (type.requiresReference && blank(d.orderRef)) {
    return 'Enter the ${type.name} order number.';
  }
  return null;
}

/// Saves the details on the sale that was just recorded.
Future<void> attachOrderDetailsToSale(WidgetRef ref, String saleId) async {
  final type = ref.read(selectedOrderTypeProvider);
  if (type == null) return;
  final d = ref.read(posOrderDetailsProvider);

  String? clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  final db = ref.read(databaseProvider);
  final usesContact = type.requiresCustomer || type.requiresAddress;
  await (db.update(db.posSales)..where((s) => s.id.equals(saleId))).write(
    PosSalesCompanion(
      tableLabel: Value(type.requiresTable ? clean(d.tableLabel) : null),
      guests: Value(type.requiresTable ? d.guests : null),
      contactName: Value(usesContact ? clean(d.contactName) : null),
      contactPhone: Value(usesContact ? clean(d.contactPhone) : null),
      deliveryAddress: Value(type.requiresAddress ? clean(d.address) : null),
      orderRef: Value(type.requiresReference ? clean(d.orderRef) : null),
    ),
  );
}

// ============================================================================
// DETAILS CARD
// ============================================================================

class OrderDetailsCard extends ConsumerStatefulWidget {
  const OrderDetailsCard({super.key});

  @override
  ConsumerState<OrderDetailsCard> createState() => _OrderDetailsCardState();
}

class _OrderDetailsCardState extends ConsumerState<OrderDetailsCard> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _orderRef = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sync(ref.read(posOrderDetailsProvider));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _orderRef.dispose();
    super.dispose();
  }

  /// Keeps the text boxes in step when the details are cleared or restored.
  void _sync(OrderDetails d) {
    void set(TextEditingController c, String? v) {
      final t = v ?? '';
      if (c.text != t) c.text = t;
    }

    set(_name, d.contactName);
    set(_phone, d.contactPhone);
    set(_address, d.address);
    set(_orderRef, d.orderRef);
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
    TextInputType? keyboard,
    int lines = 1,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: lines,
        textCapitalization: caps,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OrderDetails>(posOrderDetailsProvider, (_, next) => _sync(next));

    final type = ref.watch(selectedOrderTypeProvider);
    if (type == null ||
        !(type.requiresTable ||
            type.requiresCustomer ||
            type.requiresAddress ||
            type.requiresReference)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = ref.watch(posOrderDetailsProvider);
    final n = ref.read(posOrderDetailsProvider.notifier);
    final tables = (ref.watch(allPosTablesProvider).value ?? const <PosTable>[])
        .where((t) => t.isActive)
        .toList();
    final canManage = ref.watch(canProvider(BosPermission.businessSettings));

    final children = <Widget>[];

    // ---------- table ----------
    if (type.requiresTable) {
      if (tables.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    canManage
                        ? 'No tables yet. Add your tables to assign orders.'
                        : 'No tables set up yet. Ask a manager to add them.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if (canManage)
                  TextButton(
                    onPressed: () => showTableManager(context),
                    child: const Text(
                      'Add tables',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showTablePicker(context),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Table',
                  isDense: true,
                  prefixIcon: const Icon(
                    Icons.table_restaurant_rounded,
                    size: 20,
                  ),
                  suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  d.tableLabel ?? 'Select a table',
                  style: TextStyle(
                    fontWeight: d.tableLabel == null
                        ? FontWeight.w500
                        : FontWeight.w800,
                    color: d.tableLabel == null
                        ? scheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
        final g = d.guests;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(
                  Icons.groups_2_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Guests',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: g == null
                      ? null
                      : () => n.setGuests(g <= 1 ? null : g - 1),
                  icon: const Icon(Icons.remove_rounded, size: 18),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    g == null ? '–' : '$g',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => n.setGuests(((g ?? 0) + 1).clamp(1, 99)),
                  icon: const Icon(Icons.add_rounded, size: 18),
                ),
              ],
            ),
          ),
        );
      }
    }

    // ---------- customer / delivery ----------
    if (type.requiresCustomer || type.requiresAddress) {
      children.add(
        _field(
          controller: _name,
          label: 'Customer name',
          icon: Icons.person_outline_rounded,
          caps: TextCapitalization.words,
          onChanged: n.setName,
        ),
      );
      children.add(
        _field(
          controller: _phone,
          label: 'Phone (optional)',
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          onChanged: n.setPhone,
        ),
      );
    }
    if (type.requiresAddress) {
      children.add(
        _field(
          controller: _address,
          label: 'Delivery address',
          icon: Icons.home_outlined,
          lines: 2,
          caps: TextCapitalization.sentences,
          onChanged: n.setAddress,
        ),
      );
    }
    if (type.requiresReference) {
      children.add(
        _field(
          controller: _orderRef,
          label: '${type.name} order no.',
          icon: Icons.tag_rounded,
          caps: TextCapitalization.characters,
          onChanged: n.setRef,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(orderTypeIconFor(type), size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${type.name} details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (type.requiresTable && canManage && tables.isNotEmpty)
                TextButton(
                  onPressed: () => showTableManager(context),
                  child: const Text(
                    'Manage tables',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

// ============================================================================
// TABLE PICKER
// ============================================================================

Future<void> showTablePicker(BuildContext context) async {
  final r = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => const _TablePickerSheet(),
  );
  if (r == _kHeld && context.mounted) showHeldOrdersSheet(context);
}

class _TablePickerSheet extends ConsumerWidget {
  const _TablePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tables = (ref.watch(allPosTablesProvider).value ?? const <PosTable>[])
        .where((t) => t.isActive)
        .toList();
    final held = ref.watch(heldByTableProvider);
    final selectedId = ref.watch(posOrderDetailsProvider).tableId;
    final canManage = ref.watch(canProvider(BosPermission.businessSettings));
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;

    final sheetWidth = MediaQuery.sizeOf(context).width.clamp(0.0, 640.0);
    final inner = sheetWidth - 40;
    final cols = (inner / 120).floor().clamp(2, 6);
    final tileW = (inner - 10 * (cols - 1)) / cols;

    final groups = <String, List<PosTable>>{};
    for (final t in tables) {
      final s = (t.section ?? '').trim();
      (groups[s] ??= <PosTable>[]).add(t);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a.isEmpty ? -1 : (b.isEmpty ? 1 : a.compareTo(b)));

    Widget tile(PosTable t) {
      final h = held[t.id];
      final isSelected = selectedId == t.id;
      final occupied = h != null && !isSelected;
      final Color bg = isSelected
          ? scheme.primary
          : occupied
          ? scheme.errorContainer
          : scheme.surfaceContainerLow;
      final Color fg = isSelected
          ? scheme.onPrimary
          : occupied
          ? scheme.onErrorContainer
          : scheme.onSurface;
      final status = isSelected
          ? 'This order'
          : occupied
          ? 'Held · ${formatPeso(h.total)}'
          : 'Free';

      return SizedBox(
        width: tileW,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (occupied) {
                Navigator.pop(context, _kHeld);
                return;
              }
              ref.read(posOrderDetailsProvider.notifier).setTable(t.id, t.name);
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? scheme.primary
                      : occupied
                      ? scheme.error.withValues(alpha: 0.4)
                      : Colors.green.withValues(alpha: 0.5),
                  width: 1.4,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.table_restaurant_rounded, size: 18, color: fg),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.people_alt_outlined, size: 13, color: fg),
                      const SizedBox(width: 4),
                      Text(
                        '${t.seats}',
                        style: TextStyle(
                          color: fg,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected || occupied
                          ? fg
                          : Colors.green.shade700,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Choose a table',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (canManage)
                TextButton(
                  onPressed: () => showTableManager(context),
                  child: const Text(
                    'Manage',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            'Tap an occupied table to open its held order.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: tables.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'No tables yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + systemBottom),
                  children: [
                    for (final k in keys) ...[
                      if (k.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
                          child: Text(
                            k,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [for (final t in groups[k]!) tile(t)],
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ============================================================================
// TABLE MANAGER
// ============================================================================

Future<void> showTableManager(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _TableManagerSheet(),
  );
}

class _TableManagerSheet extends ConsumerStatefulWidget {
  const _TableManagerSheet();

  @override
  ConsumerState<_TableManagerSheet> createState() => _TableManagerSheetState();
}

class _TableManagerSheetState extends ConsumerState<_TableManagerSheet> {
  final _name = TextEditingController();
  final _seats = TextEditingController(text: '4');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _add() async {
    final service = ref.read(posTableServiceProvider);
    final businessId = ref.read(selectedBusinessIdProvider);
    await _run(
      () => service.add(
        businessId,
        name: _name.text,
        seats: int.tryParse(_seats.text.trim()) ?? 4,
      ),
    );
    if (_error == null) _name.clear();
  }

  Future<void> _quickAdd() async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _QuickAddDialog(initialSeats: _seats.text),
    );
    if (result == null || !mounted) return;
    final service = ref.read(posTableServiceProvider);
    final businessId = ref.read(selectedBusinessIdProvider);
    await _run(
      () => service.addSeries(businessId, count: result.$1, seats: result.$2),
    );
  }

  Future<void> _edit(PosTable t) async {
    final result = await showDialog<(String, int, String)>(
      context: context,
      builder: (_) => _EditTableDialog(table: t),
    );
    if (result == null || !mounted) return;
    final service = ref.read(posTableServiceProvider);
    await _run(
      () => service.update(
        t,
        name: result.$1,
        seats: result.$2,
        section: result.$3,
      ),
    );
  }

  Future<bool> _confirmDelete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('Past receipts keep the table name.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = ref.read(posTableServiceProvider);
    final all = ref.watch(allPosTablesProvider).value ?? const <PosTable>[];
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tables',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'New table (e.g. Table 1)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 76,
                      child: TextField(
                        controller: _seats,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Seats',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _add, child: const Text('Add')),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _quickAdd,
                    icon: const Icon(Icons.library_add_outlined, size: 18),
                    label: const Text(
                      'Quick add several',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                24 + (keyboardOpen ? 0 : systemBottom),
              ),
              children: [
                for (final t in all)
                  ManageCard(
                    icon: Icons.table_restaurant_rounded,
                    title: t.name,
                    chips: [
                      '${t.seats} seats',
                      if ((t.section ?? '').isNotEmpty) t.section!,
                    ],
                    active: t.isActive,
                    onToggle: (v) => _run(() => service.setActive(t, v)),
                    onEdit: () => _edit(t),
                    onDelete: () async {
                      if (await _confirmDelete(t.name)) {
                        await _run(() => service.delete(t));
                      }
                    },
                  ),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No tables yet. Add one above, or use "Quick add '
                      'several" for Table 1, Table 2...',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
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
// DIALOGS THAT OWN THEIR CONTROLLERS (safe to dispose)
// ============================================================================

class _QuickAddDialog extends StatefulWidget {
  const _QuickAddDialog({required this.initialSeats});
  final String initialSeats;

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  late final _count = TextEditingController(text: '10');
  late final _seats = TextEditingController(text: widget.initialSeats);

  @override
  void dispose() {
    _count.dispose();
    _seats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Quick add tables'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _count,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'How many tables',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seats,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Seats each',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            int.tryParse(_count.text.trim()) ?? 0,
            int.tryParse(_seats.text.trim()) ?? 4,
          )),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _EditTableDialog extends StatefulWidget {
  const _EditTableDialog({required this.table});
  final PosTable table;

  @override
  State<_EditTableDialog> createState() => _EditTableDialogState();
}

class _EditTableDialogState extends State<_EditTableDialog> {
  late final _name = TextEditingController(text: widget.table.name);
  late final _seats = TextEditingController(text: '${widget.table.seats}');
  late final _section = TextEditingController(text: widget.table.section ?? '');

  @override
  void dispose() {
    _name.dispose();
    _seats.dispose();
    _section.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Edit table'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seats,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Seats',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _section,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Section (optional, e.g. Patio)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            _name.text,
            int.tryParse(_seats.text.trim()) ?? widget.table.seats,
            _section.text,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
