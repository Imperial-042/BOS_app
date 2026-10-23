// lib/features/production/presentation/screens/pos_checkout_sheet.dart
//
// The ORDER sheet: items only.
//
//   * Phone:  a bottom sheet (opened with [showPosOrderSheet]).
//   * Tablet: the always-open panel on the right of the POS ([PosOrderPanel]).
//
// This screen only edits the cart: change quantities, remove items, hold the
// order, then tap "Checkout". Everything about paying (payment methods, split
// payment, change, customer, discount, notes, stock-only) lives in
// pos_payment_sheet.dart, which "Checkout" opens.
//
// RULES
//   * Quantity can never exceed the item's available stock (+ is disabled at
//     the cap; the payment step re-checks against the database).
//   * Items that were deleted/archived are flagged and block Checkout until
//     they are removed.

import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_sell_limit.dart';
import 'package:bos_application/features/transactions/presentation/widgets/order_details_card.dart'
    show orderDetailsProblem, OrderDetailsCard;
import 'package:bos_application/features/transactions/presentation/widgets/order_type_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pos_order_state.dart';
import 'pos_payment_sheet.dart';
import 'products_page.dart' show productsProvider;

String _peso(int cents) => formatPeso(cents);

Set<String>? _liveProductIds(WidgetRef ref) {
  return ref
      .watch(productsProvider)
      .maybeWhen<Set<String>?>(
        data: (products) => {for (final p in products) p.id},
        orElse: () => null,
      );
}

Future<void> showPosOrderSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640), // ← add
    builder: (_) => const _OrderSheet(),
  );
}

/// The order panel, embedded (not a bottom sheet) for tablets.
class PosOrderPanel extends StatelessWidget {
  const PosOrderPanel({super.key});

  @override
  Widget build(BuildContext context) => const _OrderSheet(embedded: true);
}

// ============================================================================
// ORDER SHEET
// ============================================================================

class _OrderSheet extends ConsumerWidget {
  final bool embedded;
  const _OrderSheet({this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final order = ref.watch(posOrderProvider);
    final liveIds = _liveProductIds(ref);

    bool isUnavailable(POSLineItem l) =>
        liveIds != null && !liveIds.contains(l.productId);

    final unavailable = order.where(isUnavailable).toList();

    final overStock = <String>[];
    for (final l in order) {
      if (isUnavailable(l)) continue;
      final max = ref.watch(sellLimitProvider(l.productId)).value?.maxUnits;
      if (max != null && l.quantity > max) overStock.add(l.name);
    }

    final subtotal = order
        .where((l) => !isUnavailable(l))
        .fold<int>(0, (sum, l) => sum + l.lineTotal);
    final itemCount = order.fold<int>(0, (s, l) => s + l.quantity);

    final detailsProblem = orderDetailsProblem(ref);

    String? blockedReason;
    if (unavailable.isNotEmpty) {
      blockedReason = 'Remove the unavailable item(s) to continue.';
    } else if (overStock.isNotEmpty) {
      blockedReason =
          'Not enough stock for ${overStock.join(', ')}. Lower the quantity.';
    } else if (detailsProblem != null) {
      blockedReason = detailsProblem;
    }

    void hold() {
      if (order.isEmpty) return;
      ref
          .read(heldOrdersProvider.notifier)
          .hold(
            order,
            orderType: ref.read(posOrderTypeProvider),
            details: ref.read(posOrderDetailsProvider),
          );
      ref.read(posOrderProvider.notifier).clear();
      final messenger = ScaffoldMessenger.of(context);
      if (!embedded) Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Order held. Resume it from the pause icon.'),
        ),
      );
    }

    Future<void> checkout() async {
      final done = await showPosPaymentSheet(context);
      if (done == true && !embedded && context.mounted) {
        Navigator.pop(context);
      }
    }

    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: embedded ? 0 : MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: order.isEmpty
              ? (embedded
                    ? const _EmptyOrderPanel()
                    : SizedBox(
                        height: 220,
                        child: Center(
                          child: Text(
                            'Order is empty.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ))
              : Column(
                  mainAxisSize: embedded ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    _OrderHeader(
                      itemCount: itemCount,
                      embedded: embedded,
                      onHold: hold,
                      onClose: () => Navigator.pop(context),
                    ),
                    _OrderInfoRow(problem: detailsProblem),
                    Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    Flexible(
                      fit: embedded ? FlexFit.tight : FlexFit.loose,
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        children: [
                          if (unavailable.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _UnavailableBanner(
                              count: unavailable.length,
                              onRemoveAll: () => ref
                                  .read(posOrderProvider.notifier)
                                  .removeItems(
                                    unavailable.map((l) => l.productId),
                                  ),
                            ),
                          ],
                          for (var i = 0; i < order.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            _OrderLineRow(
                              line: order[i],
                              unavailable: isUnavailable(order[i]),
                            ),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Swipe an item left to remove it',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _OrderFooter(
                      itemCount: itemCount,
                      subtotal: subtotal,
                      blockedReason: blockedReason,
                      onCheckout: checkout,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
// ============================================================================
// HEADER
// ============================================================================

class _OrderHeader extends StatelessWidget {
  final int itemCount;
  final bool embedded;
  final VoidCallback onHold;
  final VoidCallback onClose;

  const _OrderHeader({
    required this.itemCount,
    required this.embedded,
    required this.onHold,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current order',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '$itemCount item${itemCount == 1 ? '' : 's'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onHold,
            icon: const Icon(Icons.pause_circle_outline_rounded, size: 20),
            label: const Text(
              'Hold',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (!embedded)
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// ORDER INFO — one quiet row; details open in a small sheet
// ============================================================================

Future<void> _showOrderInfoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _OrderInfoSheet(),
  );
}

class _OrderInfoRow extends ConsumerWidget {
  final String? problem;
  const _OrderInfoRow({required this.problem});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final type = ref.watch(posOrderTypeProvider);
    final d = ref.watch(posOrderDetailsProvider);

    bool has(String? s) => (s ?? '').trim().isNotEmpty;
    final parts = <String>[
      if (type != null) type,
      if (has(d.tableLabel)) d.tableLabel!,
      if (d.guests != null) '${d.guests} guests',
      if (has(d.contactName)) d.contactName!,
      if (has(d.orderRef)) '#${d.orderRef}',
    ];

    final bad = problem != null;
    final color = bad ? scheme.error : scheme.onSurfaceVariant;

    return InkWell(
      onTap: () => _showOrderInfoSheet(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
        child: Row(
          children: [
            Icon(
              bad ? Icons.error_outline_rounded : Icons.tune_rounded,
              size: 20,
              color: bad ? scheme.error : scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parts.isEmpty
                        ? 'Order type, table or customer'
                        : parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: parts.isEmpty
                          ? FontWeight.w500
                          : FontWeight.w800,
                      color: parts.isEmpty ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (bad)
                    Text(
                      problem!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _OrderInfoSheet extends StatelessWidget {
  const _OrderInfoSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Order details',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            const OrderTypePicker(),
            const SizedBox(height: 12),
            const OrderDetailsCard(),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FOOTER — total + Checkout
// ============================================================================

class _OrderFooter extends StatelessWidget {
  final int itemCount;
  final int subtotal;
  final String? blockedReason;
  final VoidCallback onCheckout;

  const _OrderFooter({
    required this.itemCount,
    required this.subtotal,
    required this.blockedReason,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = blockedReason != null;
    final fg = blocked ? scheme.onSurfaceVariant : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: blocked
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            blockedReason!,
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: blocked ? null : onCheckout,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  gradient: blocked
                      ? null
                      : LinearGradient(
                          colors: [
                            scheme.primary,
                            Color.lerp(scheme.primary, Colors.black, 0.25)!,
                          ],
                        ),
                  color: blocked ? scheme.surfaceContainerHighest : null,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: blocked
                      ? null
                      : [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$itemCount item${itemCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CHARGE',
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.75),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(end: subtotal.toDouble()),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => Text(
                              _peso(v.round()),
                              style: TextStyle(
                                color: fg,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: fg, size: 26),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// UNAVAILABLE BANNER
// ============================================================================

class _UnavailableBanner extends StatelessWidget {
  final int count;
  final VoidCallback onRemoveAll;

  const _UnavailableBanner({required this.count, required this.onRemoveAll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 item in this order is no longer available. Remove '
                            'it to continue with payment.'
                      : '$count items in this order are no longer available. '
                            'Remove them to continue with payment.',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRemoveAll,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(
                count == 1 ? 'Remove item' : 'Remove $count items',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ORDER LINE — a plain row; swipe left to remove
// ============================================================================

class _OrderLineRow extends ConsumerWidget {
  final POSLineItem line;
  final bool unavailable;

  const _OrderLineRow({required this.line, required this.unavailable});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    int? maxUnits;
    var limitKnown = false;
    if (!unavailable) {
      final limit = ref.watch(sellLimitProvider(line.productId)).value;
      limitKnown = limit != null;
      maxUnits = limit?.maxUnits;
    }
    final over = maxUnits != null && line.quantity > maxUnits;
    final atMax = maxUnits != null && line.quantity >= maxUnits;

    final sub = line.unitPriceCents == 0
        ? 'No price set'
        : '${_peso(line.unitPriceCents)} / ${line.unit}';

    String? note;
    Color noteColor = scheme.onSurfaceVariant;
    if (unavailable) {
      note = 'No longer available';
      noteColor = scheme.error;
    } else if (over) {
      note = 'Only $maxUnits available';
      noteColor = scheme.error;
    } else if (atMax) {
      note = 'Max available';
      noteColor = Colors.orange.shade800;
    }

    void remove() =>
        ref.read(posOrderProvider.notifier).removeItem(line.productId);

    void increase() {
      final ok = ref
          .read(posOrderProvider.notifier)
          .updateQuantity(
            line.productId,
            line.quantity + 1,
            maxUnits: maxUnits,
          );
      if (!ok) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Only ${maxUnits ?? 0} ${line.unit} of ${line.name} '
                'available.',
              ),
            ),
          );
      }
    }

    Future<void> editQty() async {
      HapticFeedback.selectionClick();
      final value = await showDialog<int>(
        context: context,
        builder: (_) => _QtyDialog(
          name: line.name,
          unit: line.unit,
          initial: line.quantity,
          maxUnits: maxUnits,
        ),
      );
      if (value == null || !context.mounted) return;

      final target = maxUnits != null && value > maxUnits ? maxUnits : value;
      ref
          .read(posOrderProvider.notifier)
          .updateQuantity(line.productId, target, maxUnits: maxUnits);

      if (target != value) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Only $maxUnits ${line.unit} of ${line.name} available. '
                'Set to $maxUnits.',
              ),
            ),
          );
      }
    }

    return Dismissible(
      key: ValueKey('line-${line.productId}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => remove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline_rounded, color: scheme.error),
      ),
      child: Container(
        color: scheme.surface,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      decoration: unavailable
                          ? TextDecoration.lineThrough
                          : null,
                      color: unavailable ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note ?? sub,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: note == null
                          ? FontWeight.w500
                          : FontWeight.w800,
                      color: note == null ? scheme.onSurfaceVariant : noteColor,
                    ),
                  ),
                ],
              ),
            ),
            if (unavailable)
              IconButton(
                tooltip: 'Remove',
                onPressed: remove,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              )
            else ...[
              _QtyStepper(
                quantity: line.quantity,
                canIncrease:
                    limitKnown &&
                    (maxUnits == null || line.quantity < maxUnits),
                onDecrease: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(posOrderProvider.notifier)
                      .updateQuantity(line.productId, line.quantity - 1);
                },
                onIncrease: () {
                  HapticFeedback.selectionClick();
                  increase();
                },
                onEdit: editQty,
              ),
              SizedBox(
                width: 78,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _peso(line.lineTotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Minimal stepper: − 2 +  (tap the number to type any quantity).
class _QtyStepper extends StatelessWidget {
  final int quantity;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onEdit;

  const _QtyStepper({
    required this.quantity,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const box = BoxConstraints.tightFor(width: 34, height: 34);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          constraints: box,
          padding: EdgeInsets.zero,
          tooltip: 'Less',
          onPressed: onDecrease,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            height: 34,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border(
                bottom: BorderSide(
                  color: scheme.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
            ),
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
        IconButton.filled(
          constraints: box,
          padding: EdgeInsets.zero,
          tooltip: 'More',
          style: IconButton.styleFrom(
            disabledBackgroundColor: scheme.surfaceContainerHighest,
          ),
          onPressed: canIncrease ? onIncrease : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}
// ============================================================================
// EMPTY STATE (tablet panel)
// ============================================================================

class _EmptyOrderPanel extends StatelessWidget {
  const _EmptyOrderPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox.expand(
      child: Center(
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
                  Icons.shopping_bag_outlined,
                  size: 38,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Current order',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap a product on the left to start an order.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ============================================================================
// QUANTITY DIALOG
// ============================================================================

class _QtyDialog extends StatefulWidget {
  final String name;
  final String unit;
  final int initial;
  final int? maxUnits;

  const _QtyDialog({
    required this.name,
    required this.unit,
    required this.initial,
    required this.maxUnits,
  });

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _ctrl = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select everything so typing replaces the old number.
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _ctrl.text.length,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v < 0) {
      setState(() => _error = 'Enter a whole number.');
      return;
    }
    // 0 removes the item (updateQuantity handles it).
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = widget.maxUnits;

    return AlertDialog(
      title: Text(
        widget.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
            decoration: InputDecoration(
              suffixText: widget.unit,
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            max == null
                ? 'Type any quantity. Enter 0 to remove the item.'
                : 'Up to $max available. Enter 0 to remove the item.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set quantity')),
      ],
    );
  }
}
