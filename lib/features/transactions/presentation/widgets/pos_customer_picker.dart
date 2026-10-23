// lib/features/transactions/presentation/widgets/pos_customer_picker.dart
//
// Pick an existing customer for a POS sale.
//
//   * Phone:  a tall bottom sheet.
//   * Tablet / wide (>= 720): a centred dialog.
//
// The list has a FIXED height and scrolls on its own, with a visible
// scrollbar, so every customer can be reached. The bottom padding clears the
// system navigation bar and the keyboard, so the last customers are never
// hidden behind them.

import 'dart:math' as math;

import 'package:bos_application/core/database/app_database.dart' show Customer;
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart'
    show customersProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<Customer?> showPosCustomerPicker(
  BuildContext context, {
  String? selectedId,
}) {
  final width = MediaQuery.sizeOf(context).width;

  if (width >= 720) {
    return showDialog<Customer>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _CustomerPicker(selectedId: selectedId, dialog: true),
        ),
      ),
    );
  }

  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _CustomerPicker(selectedId: selectedId),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  final String? selectedId;
  final bool dialog;

  const _CustomerPicker({required this.selectedId, this.dialog = false});

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final customersAsync = ref.watch(customersProvider);

    // Fixed height (so the list always has room to scroll), shrunk when the
    // keyboard is open so nothing is pushed off screen.
    final height = widget.dialog
        ? math.min(size.height * 0.8, 640.0)
        : math.max(
            280.0,
            math.min(size.height * 0.88, size.height - keyboard - 72),
          );

    return Padding(
      padding: EdgeInsets.only(bottom: widget.dialog ? 0 : keyboard),
      child: Material(
        color: scheme.surface,
        borderRadius: widget.dialog
            ? null
            : const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                if (!widget.dialog)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select customer',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              customersAsync.maybeWhen(
                                data: (all) =>
                                    '${all.length} customer'
                                    '${all.length == 1 ? '' : 's'}',
                                orElse: () => ' ',
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search name, TIN or address...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: customersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Center(child: Text('Unable to load customers: $e')),
                    data: (all) {
                      final q = _query.trim().toLowerCase();
                      final list = q.isEmpty
                          ? all
                          : all.where((c) {
                              return c.name.toLowerCase().contains(q) ||
                                  (c.tin ?? '').toLowerCase().contains(q) ||
                                  (c.address ?? '').toLowerCase().contains(q);
                            }).toList();

                      if (list.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_search_outlined,
                                  size: 44,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  all.isEmpty
                                      ? 'No customers yet.'
                                      : 'No customers match your search.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          // Extra bottom room so the last customers clear the
                          // system navigation bar.
                          padding: EdgeInsets.fromLTRB(
                            8,
                            8,
                            8,
                            20 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final c = list[i];
                            final selected = c.id == widget.selectedId;
                            final sub = [
                              if ((c.address ?? '').isNotEmpty) c.address!,
                              if ((c.tin ?? '').isNotEmpty) 'TIN ${c.tin}',
                            ].join(' · ');

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                selected: selected,
                                selectedTileColor: scheme.primaryContainer
                                    .withValues(alpha: 0.5),
                                leading: CircleAvatar(
                                  backgroundColor: scheme.primaryContainer,
                                  child: Text(
                                    c.name.isEmpty
                                        ? '?'
                                        : c.name[0].toUpperCase(),
                                    style: TextStyle(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: sub.isEmpty
                                    ? null
                                    : Text(
                                        sub,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: selected
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: scheme.primary,
                                      )
                                    : null,
                                onTap: () => Navigator.pop(context, c),
                              ),
                            );
                          },
                        ),
                      );
                    },
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
