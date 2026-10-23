// lib/features/production/presentation/screens/held_orders_sheet.dart
//
// Lists orders the cashier parked with "Hold" so they can be resumed.
// Held orders live in memory only: they survive navigation but not an app
// restart. (Persisting them needs a Drift table; see Phase 2.)

import 'package:bos_application/core/format/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'pos_order_state.dart';

Future<void> showHeldOrdersSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _HeldOrdersSheet(),
  );
}

class _HeldOrdersSheet extends ConsumerWidget {
  const _HeldOrdersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final held = ref.watch(heldOrdersProvider);

    if (held.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No held orders.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    void resume(HeldOrder h) {
      if (ref.read(posOrderProvider).isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Hold or finish the current order first.'),
            ),
          );
        return;
      }
      final taken = ref.read(heldOrdersProvider.notifier).take(h.id);
      if (taken == null) return;
      ref.read(posOrderProvider.notifier).replaceAll(taken.lines);
      Navigator.pop(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Held orders',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: held.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final h = held[i];
              final names = h.lines.map((l) => l.name).join(', ');
              return Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${h.count} item${h.count == 1 ? '' : 's'} · '
                            '${formatPeso(h.total)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            names,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'Held ${DateFormat('h:mm a').format(h.heldAt)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => resume(h),
                      child: const Text(
                        'Resume',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Discard',
                      onPressed: () =>
                          ref.read(heldOrdersProvider.notifier).discard(h.id),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
