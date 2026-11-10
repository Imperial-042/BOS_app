import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/transactions/domain/product_variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<List<ProductOptionSelection>?> showProductCustomizationSheet(
  BuildContext context,
  WidgetRef ref,
  Product product,
) async {
  final groups = await ref
      .read(productVariantServiceProvider)
      .loadGroups(product.id, activeOnly: true);
  if (!context.mounted) return null;
  if (groups.isEmpty) return const [];
  return showModalBottomSheet<List<ProductOptionSelection>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CustomizationSheet(product: product, groups: groups),
  );
}

class _CustomizationSheet extends StatefulWidget {
  const _CustomizationSheet({required this.product, required this.groups});
  final Product product;
  final List<ProductOptionGroup> groups;

  @override
  State<_CustomizationSheet> createState() => _CustomizationSheetState();
}

class _CustomizationSheetState extends State<_CustomizationSheet> {
  final Map<String, Set<String>> _selected = {};
  String? _error;

  int get _extra => [
    for (final group in widget.groups)
      for (final choice in group.choices)
        if (_selected[group.id]?.contains(choice.id) == true)
          choice.priceDeltaCents,
  ].fold(0, (a, b) => a + b);

  void _toggle(ProductOptionGroup group, ProductOptionChoice choice) {
    final selected = _selected.putIfAbsent(group.id, () => <String>{});
    if (selected.contains(choice.id)) {
      selected.remove(choice.id);
    } else {
      if (!group.multiple) selected.clear();
      if (group.maxSelections != null &&
          selected.length >= group.maxSelections!) {
        setState(
          () => _error =
              '${group.name} allows up to ${group.maxSelections} selection(s).',
        );
        return;
      }
      selected.add(choice.id);
    }
    setState(() => _error = null);
  }

  void _done() {
    for (final group in widget.groups) {
      final count = _selected[group.id]?.length ?? 0;
      final minimum = group.required
          ? (group.minSelections < 1 ? 1 : group.minSelections)
          : group.minSelections;
      if (count < minimum) {
        setState(
          () =>
              _error = 'Choose at least $minimum option(s) for ${group.name}.',
        );
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.product.name,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Customize your order',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final group in widget.groups)
                    ExpansionTile(
                      initiallyExpanded: true,
                      title: Text(
                        group.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        group.required
                            ? 'Required'
                            : group.multiple
                            ? 'Choose up to ${group.maxSelections ?? 'any'}'
                            : 'Optional',
                      ),
                      children: [
                        for (final choice in group.choices)
                          CheckboxListTile(
                            value:
                                _selected[group.id]?.contains(choice.id) ??
                                false,
                            onChanged: (_) => _toggle(group, choice),
                            title: Text(choice.name),
                            secondary: choice.priceDeltaCents == 0
                                ? null
                                : Text(
                                    choice.priceDeltaCents > 0
                                        ? '+${formatPeso(choice.priceDeltaCents)}'
                                        : formatPeso(choice.priceDeltaCents),
                                  ),
                          ),
                      ],
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _done,
            child: Text(
              'Add · ${formatPeso((widget.product.sellPrice ?? 0) + _extra)}',
            ),
          ),
        ],
      ),
    );
  }
}
