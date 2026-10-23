// The "Order type" dropdown on the Current order screen, plus the manager
// sheet to add / edit / hide / delete types and add preset packs.

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/ledger/domain/order_type_service.dart';
import 'package:bos_application/features/transactions/domain/pos_session_service.dart'
    show friendlyError;
import 'package:bos_application/features/transactions/presentation/screens/pos_order_state.dart'
    show posOrderTypeProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';

IconData orderTypeIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('dine')) return Icons.restaurant_rounded;
  if (n.contains('take')) return Icons.takeout_dining_rounded;
  if (n.contains('grab') ||
      n.contains('panda') ||
      n.contains('maxim') ||
      n.contains('deliver') ||
      n.contains('lalamove')) {
    return Icons.delivery_dining_rounded;
  }
  if (n.contains('pick')) return Icons.shopping_bag_outlined;
  return Icons.label_outline_rounded;
}

IconData orderTypeIconFor(PosOrderType t) => switch (t.kind) {
  'dine_in' => Icons.restaurant_rounded,
  'takeout' => Icons.takeout_dining_rounded,
  'pickup' => Icons.shopping_bag_outlined,
  'delivery' => Icons.delivery_dining_rounded,
  'online' => Icons.public_rounded,
  _ => orderTypeIcon(t.name),
};

List<String> orderTypeChips(PosOrderType t) => [
  kOrderKindLabels[t.kind] ?? 'Other',
  if (t.requiresTable) 'Table',
  if (t.requiresCustomer) 'Customer',
  if (t.requiresAddress) 'Address',
  if (t.requiresReference) 'Order no.',
];

// ============================================================================
// DROPDOWN
// ============================================================================

class OrderTypePicker extends ConsumerWidget {
  const OrderTypePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final all =
        ref.watch(allOrderTypesProvider).value ?? const <PosOrderType>[];
    final types = all.where((t) => t.isActive).toList();
    final selected = ref.watch(posOrderTypeProvider);
    final canManage = ref.watch(canProvider(BosPermission.businessSettings));

    if (types.isEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.local_offer_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                all.isEmpty ? 'No order types yet.' : 'All order types hidden.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (canManage)
              TextButton(
                onPressed: () => showOrderTypeManager(context),
                child: const Text(
                  'Set up',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      );
    }

    final current = types.any((t) => t.name == selected) ? selected : null;
    PosOrderType? currentType;
    for (final t in types) {
      if (t.name == current) currentType = t;
    }

    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Order type',
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              contentPadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              prefixIcon: Icon(
                currentType == null
                    ? Icons.local_offer_outlined
                    : orderTypeIconFor(currentType),
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: current,
                isExpanded: true,
                isDense: true,
                borderRadius: BorderRadius.circular(14),
                hint: Text(
                  'Select order type',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(
                      'No order type',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  for (final t in types)
                    DropdownMenuItem<String>(
                      value: t.name,
                      child: Row(
                        children: [
                          Icon(orderTypeIconFor(t), size: 18),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => ref
                    .read(posOrderTypeProvider.notifier)
                    .set((v == null || v.isEmpty) ? null : v),
              ),
            ),
          ),
        ),
        if (canManage)
          IconButton(
            tooltip: 'Manage order types',
            onPressed: () => showOrderTypeManager(context),
            icon: const Icon(Icons.tune_rounded),
          ),
      ],
    );
  }
}

// ============================================================================
// SHARED MANAGE CARD (also used by the table manager)
// ============================================================================

class ManageCard extends StatelessWidget {
  const ManageCard({
    super.key,
    required this.icon,
    required this.title,
    required this.active,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.chips = const [],
  });

  final IconData icon;
  final String title;
  final List<String> chips;
  final bool active;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    decoration: active ? null : TextDecoration.lineThrough,
                    color: active ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: scheme.error,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 6, 2),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Material(
            color: active
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onToggle(!active),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        active ? 'Shown in POS' : 'Hidden from POS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Switch(value: active, onChanged: onToggle),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ============================================================================
// MANAGER SHEET
// ============================================================================

Future<void> showOrderTypeManager(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _ManageSheet(),
  );
}

class _ManageSheet extends ConsumerStatefulWidget {
  const _ManageSheet();

  @override
  ConsumerState<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends ConsumerState<_ManageSheet> {
  String? _msg;
  bool _isError = false;

  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    try {
      await action();
      if (mounted) {
        setState(() {
          _msg = ok;
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = friendlyError(e);
          _isError = true;
        });
      }
    }
  }

  Future<void> _edit(PosOrderType? type) async {
    final spec = await showOrderTypeEditor(context, type: type);
    if (spec == null) return;
    final service = ref.read(orderTypeServiceProvider);
    final businessId = ref.read(selectedBusinessIdProvider);
    await _run(
      () => type == null
          ? service.add(businessId, spec)
          : service.update(type, spec),
    );
  }

  Future<void> _pickPack() async {
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add a preset'),
        children: [
          for (final e in kOrderTypePacks.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.key,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.value.map((s) => s.name).join(', '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (key == null) return;
    final service = ref.read(orderTypeServiceProvider);
    final businessId = ref.read(selectedBusinessIdProvider);
    int added = 0;
    await _run(() async {
      added = await service.addPack(businessId, kOrderTypePacks[key]!);
    });
    if (mounted && !_isError) {
      setState(() {
        _msg = added == 0
            ? 'Everything in "$key" is already there.'
            : 'Added $added type${added == 1 ? '' : 's'} from "$key".';
      });
    }
  }

  Future<bool> _confirmDelete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('Past receipts keep this label.'),
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
    final service = ref.read(orderTypeServiceProvider);
    final all =
        ref.watch(allOrderTypesProvider).value ?? const <PosOrderType>[];
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- pinned top ----
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Order types',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Each type can ask for a table, customer, address or a '
                  'platform order number at checkout.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _edit(null),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New type'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickPack,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Add preset'),
                    ),
                  ],
                ),
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _msg!,
                      style: TextStyle(
                        color: _isError ? scheme.error : scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ---- scrollable list ----
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
                    icon: orderTypeIconFor(t),
                    title: t.name,
                    chips: orderTypeChips(t),
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
                      'No order types yet. Tap "Add preset" to start with a '
                      'ready-made set for your kind of business.',
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
// EDITOR DIALOG (new + edit)
// ============================================================================

Future<OrderTypeSpec?> showOrderTypeEditor(
  BuildContext context, {
  PosOrderType? type,
}) {
  return showDialog<OrderTypeSpec>(
    context: context,
    builder: (_) => _TypeEditor(type: type),
  );
}

class _TypeEditor extends StatefulWidget {
  const _TypeEditor({this.type});
  final PosOrderType? type;

  @override
  State<_TypeEditor> createState() => _TypeEditorState();
}

class _TypeEditorState extends State<_TypeEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.type?.name ?? '',
  );
  late String _kind = widget.type?.kind ?? 'other';
  late bool _table = widget.type?.requiresTable ?? false;
  late bool _customer = widget.type?.requiresCustomer ?? false;
  late bool _address = widget.type?.requiresAddress ?? false;
  late bool _reference = widget.type?.requiresReference ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setKind(String k) => setState(() {
    _kind = k;
    _table = k == 'dine_in';
    _customer = k == 'pickup' || k == 'delivery';
    _address = k == 'delivery';
    _reference = k == 'online';
  });

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> on) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: on,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      scrollable: true,
      title: Text(widget.type == null ? 'New order type' : 'Edit order type'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.type == null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 14),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Kind',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _kind,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final e in kOrderKindLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  if (v != null) _setKind(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choosing a kind sets sensible defaults. Adjust them below.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 6),
          _switch(
            'Needs a table',
            'Cashier must pick a table',
            _table,
            (v) => setState(() => _table = v),
          ),
          _switch(
            'Needs customer name & phone',
            'For pick up and delivery',
            _customer,
            (v) => setState(() => _customer = v),
          ),
          _switch(
            'Needs delivery address',
            'For your own riders',
            _address,
            (v) => setState(() => _address = v),
          ),
          _switch(
            'Needs platform order no.',
            'GrabFood, Foodpanda, Shopee...',
            _reference,
            (v) => setState(() => _reference = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Enter a name.');
              return;
            }
            Navigator.pop(
              context,
              OrderTypeSpec(
                name,
                kind: _kind,
                table: _table,
                customer: _customer,
                address: _address,
                reference: _reference,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
