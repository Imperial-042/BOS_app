import 'dart:math' as math;

import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/domain/product_variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<List<ProductOptionSelection>?> showCustomerCustomizationSheet(
  BuildContext context, {
  required String productName,
  required int basePriceCents,
  required List<ProductOptionGroup> groups,
}) {
  if (groups.isEmpty) return Future.value(const []);
  return showModalBottomSheet<List<ProductOptionSelection>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true, // protects the TOP only; the bottom is handled below
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (_) => _CustomerCustomizationSheet(
      productName: productName,
      basePriceCents: basePriceCents,
      groups: groups,
    ),
  );
}

class _CustomerCustomizationSheet extends StatefulWidget {
  const _CustomerCustomizationSheet({
    required this.productName,
    required this.basePriceCents,
    required this.groups,
  });

  final String productName;
  final int basePriceCents;
  final List<ProductOptionGroup> groups;

  @override
  State<_CustomerCustomizationSheet> createState() =>
      _CustomerCustomizationSheetState();
}

class _CustomerCustomizationSheetState
    extends State<_CustomerCustomizationSheet> {
  final Map<String, Set<String>> _selected = {};
  final Map<String, GlobalKey> _groupKeys = {};
  String? _error;
  String? _errorGroupId;

  GlobalKey _keyFor(String id) => _groupKeys.putIfAbsent(id, GlobalKey.new);

  int _minimum(ProductOptionGroup g) =>
      g.required ? (g.minSelections < 1 ? 1 : g.minSelections) : g.minSelections;

  int _count(ProductOptionGroup g) => _selected[g.id]?.length ?? 0;

  bool _satisfied(ProductOptionGroup g) => _count(g) >= _minimum(g);

  int get _extras => [
    for (final group in widget.groups)
      for (final choice in group.choices)
        if (_selected[group.id]?.contains(choice.id) == true)
          choice.priceDeltaCents,
  ].fold(0, (a, b) => a + b);

  int get _total => widget.basePriceCents + _extras;

  void _toggle(ProductOptionGroup group, ProductOptionChoice choice) {
    final selected = _selected.putIfAbsent(group.id, () => <String>{});
    if (selected.contains(choice.id)) {
      HapticFeedback.selectionClick();
      selected.remove(choice.id);
    } else {
      if (!group.multiple) selected.clear();
      if (group.maxSelections != null &&
          selected.length >= group.maxSelections!) {
        HapticFeedback.lightImpact();
        setState(() {
          _errorGroupId = group.id;
          _error =
              '${group.name} allows up to ${group.maxSelections} selection(s).';
        });
        return;
      }
      HapticFeedback.selectionClick();
      selected.add(choice.id);
    }
    setState(() {
      _error = null;
      _errorGroupId = null;
    });
  }

  void _done() {
    for (final group in widget.groups) {
      if (!_satisfied(group)) {
        HapticFeedback.mediumImpact();
        setState(() {
          _errorGroupId = group.id;
          _error =
              'Choose at least ${_minimum(group)} option(s) for ${group.name}.';
        });
        final ctx = _keyFor(group.id).currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: 0.1,
          );
        }
        return;
      }
    }
    Navigator.pop(context, [
      for (final group in widget.groups)
        for (final choice in group.choices)
          if (_selected[group.id]?.contains(choice.id) == true)
            ProductOptionSelection(
              groupId: group.id,
              choiceId: choice.id,
              groupName: group.name,
              choiceName: choice.name,
              priceDeltaCents: choice.priceDeltaCents,
              inventoryProductId: choice.inventoryProductId,
              inventorySupplyId: choice.inventorySupplyId,
              inventoryQuantity: choice.inventoryQuantity,
            ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    // Keyboard when open, nav-bar / gesture inset when closed.
    final bottomInset = math.max(
      media.viewInsets.bottom,
      media.viewPadding.bottom,
    );

    final requiredGroups = widget.groups.where((g) => g.required).toList();
    final requiredDone = requiredGroups.where(_satisfied).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: scheme.onPrimary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customize your order',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  formatPeso(widget.basePriceCents),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Required-choices progress ──
        if (requiredGroups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      requiredDone == requiredGroups.length
                          ? Icons.check_circle_rounded
                          : Icons.pending_outlined,
                      size: 16,
                      color: requiredDone == requiredGroups.length
                          ? const Color(0xFF1F9D74)
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      requiredDone == requiredGroups.length
                          ? 'All required choices made'
                          : '$requiredDone of ${requiredGroups.length} required choices made',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: requiredDone / requiredGroups.length),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Option groups (only this part scrolls) ──
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              children: [
                for (final group in widget.groups)
                  Padding(
                    key: _keyFor(group.id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GroupCard(
                      group: group,
                      selected: _selected[group.id] ?? const <String>{},
                      hasError: _errorGroupId == group.id,
                      onToggle: (choice) => _toggle(group, choice),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Pinned footer ──
        Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(14),
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
                                _error!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_extras != 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Text(
                        'Base ${formatPeso(widget.basePriceCents)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Extras ${_extras > 0 ? '+' : ''}${formatPeso(_extras)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _done,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_shopping_cart_rounded, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Add to order',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.onPrimary.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.4),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          formatPeso(_total),
                          key: ValueKey(_total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
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

// ============================================================================
// GROUP CARD
// ============================================================================

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.selected,
    required this.hasError,
    required this.onToggle,
  });

  final ProductOptionGroup group;
  final Set<String> selected;
  final bool hasError;
  final ValueChanged<ProductOptionChoice> onToggle;

  String get _hint {
    if (!group.multiple) return 'Pick one';
    final max = group.maxSelections;
    return max == null ? 'Choose any' : 'Choose up to $max';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final full =
        group.multiple &&
        group.maxSelections != null &&
        selected.length >= group.maxSelections!;
    final min = group.required
        ? (group.minSelections < 1 ? 1 : group.minSelections)
        : group.minSelections;
    final done = selected.length >= min;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasError ? scheme.error : Colors.transparent,
          width: 1.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      _hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (group.required)
                _Badge(
                  label: done ? 'Done' : 'Required',
                  icon: done ? Icons.check_rounded : null,
                  color: done ? const Color(0xFF1F9D74) : scheme.error,
                )
              else
                _Badge(label: 'Optional', color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 12),
          for (final choice in group.choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChoiceTile(
                choice: choice,
                multiple: group.multiple,
                selected: selected.contains(choice.id),
                dimmed: full && !selected.contains(choice.id),
                onTap: () => onToggle(choice),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
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

// ============================================================================
// CHOICE TILE
// ============================================================================

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.choice,
    required this.multiple,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final ProductOptionChoice choice;
  final bool multiple;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final delta = choice.priceDeltaCents;

    final IconData indicator = multiple
        ? (selected
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded)
        : (selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.55)
                  : scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    indicator,
                    key: ValueKey(selected),
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    choice.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (delta != 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.14)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      delta > 0
                          ? '+${formatPeso(delta)}'
                          : formatPeso(delta),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Text(
                    'Free',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
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