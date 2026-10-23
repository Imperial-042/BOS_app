// lib/features/production/presentation/widgets/pos_discount_sheet.dart
//
// Pick an order discount: Senior/PWD preset, a custom percent, or a fixed
// peso amount. Returns null if dismissed, or a DiscountResult whose
// [discount] is null when the cashier chose "Remove discount".

import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/domain/pos_discount.dart';
import 'package:flutter/material.dart';

class DiscountResult {
  final PosDiscount? discount;
  const DiscountResult(this.discount);
}

Future<DiscountResult?> showPosDiscountSheet(
  BuildContext context, {
  required int subtotalCents,
  PosDiscount? current,
}) {
  return showModalBottomSheet<DiscountResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) =>
        _DiscountSheet(subtotalCents: subtotalCents, current: current),
  );
}

class _DiscountSheet extends StatefulWidget {
  final int subtotalCents;
  final PosDiscount? current;

  const _DiscountSheet({required this.subtotalCents, required this.current});

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  final _percent = TextEditingController();
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _percent.dispose();
    _amount.dispose();
    super.dispose();
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  void _pick(PosDiscount? d) => Navigator.pop(context, DiscountResult(d));

  void _applyPercent() {
    final v = double.tryParse(_percent.text.trim());
    if (v == null || v <= 0 || v > 100) {
      setState(() => _error = 'Enter a percent between 1 and 100.');
      return;
    }
    _pick(PosDiscount.percent('${_trim(v)}% off', v));
  }

  void _applyAmount() {
    final v = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter a peso amount above 0.');
      return;
    }
    final cents = (v * 100).round();
    if (cents > widget.subtotalCents) {
      setState(() => _error = 'The discount is more than the order total.');
      return;
    }
    _pick(PosDiscount.fixed('${formatPeso(cents)} off', cents));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final senior = PosDiscount.seniorPwd;
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Padding(
      // Lifts the whole sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- fixed top: title + both fields (always visible) ----
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Discount',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Order total before discount: '
                  '${formatPeso(widget.subtotalCents)}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _percent,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) => _applyPercent(),
                        decoration: const InputDecoration(
                          labelText: 'Custom percent',
                          suffixText: '%',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonal(
                      onPressed: _applyPercent,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) => _applyAmount(),
                        decoration: const InputDecoration(
                          labelText: 'Fixed amount',
                          prefixText: '₱ ',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonal(
                      onPressed: _applyAmount,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ---- scrollable area: presets + remove ----
          Flexible(
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                // Clears the gesture bar / nav buttons.
                24 + (keyboardOpen ? 0 : systemBottom),
              ),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.elderly_rounded,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      senior.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '− ${formatPeso(senior.amountFor(widget.subtotalCents))}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pick(senior),
                  ),
                ),
                if (widget.current != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _pick(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Remove discount'),
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
