import 'dart:async';

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/features/transactions/domain/product_variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column, Table;

class ProductOptionsPage extends ConsumerStatefulWidget {
  const ProductOptionsPage({required this.product, super.key});
  final Product product;

  @override
  ConsumerState<ProductOptionsPage> createState() => _ProductOptionsPageState();
}

class _ProductOptionsPageState extends ConsumerState<ProductOptionsPage> {
  List<ProductOptionGroup> _groups = [];
  List<Supply> _inventorySupplies = [];
  bool _loading = true;
  bool _saving = false;
  Timer? _saveDebounce;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _queueSave() {
    _saveDebounce?.cancel();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    _saveDebounce = Timer(const Duration(milliseconds: 350), _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      final saved = await ref
          .read(productVariantServiceProvider)
          .saveGroups(
            productId: widget.product.id,
            businessId: widget.product.businessId,
            groups: _groups,
          );
      if (!mounted) return;
      setState(() {
        _groups = saved;
        _saving = false;
      });
      ref.read(productVariantVersionProvider.notifier).state++;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Unable to save product options: $error')),
        );
    }
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final groups = await ref
        .read(productVariantServiceProvider)
        .loadGroups(widget.product.id);
    final supplies =
        await (db.select(db.supplies)..where(
              (p) =>
                  p.businessId.equals(widget.product.businessId) &
                  p.isActive.equals(true),
            ))
            .get();
    if (mounted) {
      setState(() {
        _groups = groups;
        _inventorySupplies = supplies;
        _loading = false;
      });
    }
  }

  Future<void> _addGroup() async {
    final name = await _textDialog('New option group', 'e.g. Size or Toppings');
    if (name == null || name.trim().isEmpty) return;
    setState(
      () => _groups = [
        ..._groups,
        ProductOptionGroup(
          id: '',
          productId: widget.product.id,
          businessId: widget.product.businessId,
          name: name.trim(),
          required: false,
          multiple: false,
          minSelections: 0,
          maxSelections: 1,
          isAddOn: false,
          sortOrder: _groups.length,
          choices: const [],
        ),
      ],
    );
    _queueSave();
  }

  Future<void> _addChoice(int groupIndex) async {
    final draft = await showDialog<_ChoiceDraft>(
      context: context,
      builder: (_) => _ChoiceDialog(supplies: _inventorySupplies),
    );
    if (draft == null || draft.name.trim().isEmpty) return;
    final group = _groups[groupIndex];
    setState(() {
      _groups = [
        for (var i = 0; i < _groups.length; i++)
          if (i != groupIndex)
            _groups[i]
          else
            ProductOptionGroup(
              id: group.id,
              productId: group.productId,
              businessId: group.businessId,
              name: group.name,
              required: group.required,
              multiple: group.multiple,
              minSelections: group.minSelections,
              maxSelections: group.maxSelections,
              isAddOn: group.isAddOn,
              sortOrder: group.sortOrder,
              choices: [
                ...group.choices,
                ProductOptionChoice(
                  id: '',
                  groupId: group.id,
                  name: draft.name.trim(),
                  priceDeltaCents: draft.priceDeltaCents,
                  inventoryProductId: draft.inventoryProductId,
                  inventorySupplyId: draft.inventorySupplyId,
                  inventoryQuantity: draft.inventoryQuantity,
                  sortOrder: group.choices.length,
                ),
              ],
            ),
      ];
    });
    _queueSave();
  }

  Future<void> _editChoice(int groupIndex, int choiceIndex) async {
    final choice = _groups[groupIndex].choices[choiceIndex];
    final draft = await showDialog<_ChoiceDraft>(
      context: context,
      builder: (_) => _ChoiceDialog(
        supplies: _inventorySupplies,
        initial: _ChoiceDraft(
          name: choice.name,
          priceDeltaCents: choice.priceDeltaCents,
          inventoryProductId: choice.inventoryProductId,
          inventorySupplyId: choice.inventorySupplyId,
          inventoryQuantity: choice.inventoryQuantity,
        ),
      ),
    );
    if (draft == null || draft.name.trim().isEmpty) return;
    final group = _groups[groupIndex];
    final choices = [...group.choices];
    choices[choiceIndex] = ProductOptionChoice(
      id: choice.id,
      groupId: choice.groupId,
      name: draft.name.trim(),
      priceDeltaCents: draft.priceDeltaCents,
      inventoryProductId: draft.inventoryProductId,
      inventorySupplyId: draft.inventorySupplyId,
      inventoryQuantity: draft.inventoryQuantity,
      sortOrder: choice.sortOrder,
      isActive: choice.isActive,
    );
    setState(() {
      _groups[groupIndex] = ProductOptionGroup(
        id: group.id,
        productId: group.productId,
        businessId: group.businessId,
        name: group.name,
        required: group.required,
        multiple: group.multiple,
        minSelections: group.minSelections,
        maxSelections: group.maxSelections,
        isAddOn: group.isAddOn,
        sortOrder: group.sortOrder,
        choices: choices,
      );
    });
    _queueSave();
  }

  Future<String?> _textDialog(String title, String hint) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _OptionNameDialog(title: title, hint: hint),
    );
  }

  Future<void> _save() async {
    ref
        .read(authorizationServiceProvider)
        .require(
          BosPermission.inventoryEdit,
          businessId: widget.product.businessId,
        );
    _saveDebounce?.cancel();
    await _saveNow();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.product.name} options'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: Icon(_saving ? Icons.sync : Icons.check_circle_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addGroup,
        icon: const Icon(Icons.add),
        label: const Text('Option group'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
          ? const Center(child: Text('No variants or add-ons configured.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (var i = 0; i < _groups.length; i++)
                  Card(
                    child: ExpansionTile(
                      title: Text(_groups[i].name),
                      subtitle: Text(
                        _groups[i].required ? 'Required' : 'Optional',
                      ),
                      trailing: Switch(
                        value: _groups[i].required,
                        onChanged: (value) {
                          setState(() {
                            final group = _groups[i];
                            _groups[i] = ProductOptionGroup(
                              id: group.id,
                              productId: group.productId,
                              businessId: group.businessId,
                              name: group.name,
                              required: value,
                              multiple: group.multiple,
                              minSelections: value ? 1 : group.minSelections,
                              maxSelections: group.maxSelections,
                              isAddOn: group.isAddOn,
                              sortOrder: group.sortOrder,
                              choices: group.choices,
                              isActive: group.isActive,
                            );
                          });
                          _queueSave();
                        },
                      ),
                      children: [
                        SwitchListTile(
                          title: const Text('Option group active'),
                          subtitle: const Text(
                            'Turn off to hide this group from POS and online ordering',
                          ),
                          value: _groups[i].isActive,
                          onChanged: (value) {
                            final group = _groups[i];
                            setState(() {
                              _groups[i] = ProductOptionGroup(
                                id: group.id,
                                productId: group.productId,
                                businessId: group.businessId,
                                name: group.name,
                                required: group.required,
                                multiple: group.multiple,
                                minSelections: group.minSelections,
                                maxSelections: group.maxSelections,
                                isAddOn: group.isAddOn,
                                sortOrder: group.sortOrder,
                                choices: group.choices,
                                isActive: value,
                              );
                            });
                            _queueSave();
                          },
                        ),
                        SwitchListTile(
                          title: const Text('Dedicated add-on'),
                          subtitle: const Text(
                            'Show this group in the Products > Add-ons tab',
                          ),
                          value: _groups[i].isAddOn,
                          onChanged: (value) {
                            setState(() {
                              final group = _groups[i];
                              _groups[i] = ProductOptionGroup(
                                id: group.id,
                                productId: group.productId,
                                businessId: group.businessId,
                                name: group.name,
                                required: group.required,
                                multiple: group.multiple,
                                minSelections: group.minSelections,
                                maxSelections: group.maxSelections,
                                isAddOn: value,
                                sortOrder: group.sortOrder,
                                choices: group.choices,
                                isActive: group.isActive,
                              );
                            });
                            _queueSave();
                          },
                        ),
                        for (final choice in _groups[i].choices)
                          Builder(
                            builder: (context) {
                              final choiceIndex = _groups[i].choices.indexOf(
                                choice,
                              );
                              return ListTile(
                                title: Text(choice.name),
                                subtitle: Text(
                                  '${choice.priceDeltaCents == 0 ? 'No price change' : 'PHP ${(choice.priceDeltaCents / 100).toStringAsFixed(2)}'}'
                                  '${choice.inventoryProductId == null ? '' : ' · Ingredient linked'}',
                                ),
                                leading: Switch(
                                  value: choice.isActive,
                                  onChanged: (value) {
                                    final group = _groups[i];
                                    final choices = [...group.choices];
                                    choices[choiceIndex] = ProductOptionChoice(
                                      id: choice.id,
                                      groupId: choice.groupId,
                                      name: choice.name,
                                      priceDeltaCents: choice.priceDeltaCents,
                                      inventoryProductId:
                                          choice.inventoryProductId,
                                      inventorySupplyId:
                                          choice.inventorySupplyId,
                                      inventoryQuantity:
                                          choice.inventoryQuantity,
                                      sortOrder: choice.sortOrder,
                                      isActive: value,
                                    );
                                    setState(() {
                                      _groups[i] = ProductOptionGroup(
                                        id: group.id,
                                        productId: group.productId,
                                        businessId: group.businessId,
                                        name: group.name,
                                        required: group.required,
                                        multiple: group.multiple,
                                        minSelections: group.minSelections,
                                        maxSelections: group.maxSelections,
                                        isAddOn: group.isAddOn,
                                        sortOrder: group.sortOrder,
                                        choices: choices,
                                        isActive: group.isActive,
                                      );
                                    });
                                    _queueSave();
                                  },
                                ),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => _editChoice(i, choiceIndex),
                              );
                            },
                          ),
                        TextButton.icon(
                          onPressed: () => _addChoice(i),
                          icon: const Icon(Icons.add),
                          label: const Text('Add choice'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _saveError == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Changes could not be saved. Tap the check icon to retry.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
    );
  }
}

class _OptionNameDialog extends StatefulWidget {
  const _OptionNameDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_OptionNameDialog> createState() => _OptionNameDialogState();
}

class _OptionNameDialogState extends State<_OptionNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ChoiceDraft {
  const _ChoiceDraft({
    required this.name,
    required this.priceDeltaCents,
    required this.inventoryProductId,
    required this.inventorySupplyId,
    required this.inventoryQuantity,
  });

  final String name;
  final int priceDeltaCents;
  final String? inventoryProductId;
  final String? inventorySupplyId;
  final double inventoryQuantity;
}

class _ChoiceDialog extends StatefulWidget {
  const _ChoiceDialog({required this.supplies, this.initial});

  final List<Supply> supplies;
  final _ChoiceDraft? initial;

  @override
  State<_ChoiceDialog> createState() => _ChoiceDialogState();
}

class _ChoiceDialogState extends State<_ChoiceDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController(text: '0');
  final _quantity = TextEditingController(text: '1');
  String? _ingredientId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _name.text = initial.name;
      _price.text = (initial.priceDeltaCents / 100).toStringAsFixed(2);
      _quantity.text = initial.inventoryQuantity.toString();
      _ingredientId = initial.inventorySupplyId;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _submit() {
    final priceValue = double.tryParse(_price.text.trim());
    final quantity = double.tryParse(_quantity.text.trim());
    if (_name.text.trim().isEmpty ||
        priceValue == null ||
        quantity == null ||
        priceValue < 0 ||
        quantity < 0) {
      return;
    }
    Navigator.pop(
      context,
      _ChoiceDraft(
        name: _name.text.trim(),
        priceDeltaCents: (priceValue * 100).round(),
        inventoryProductId: null,
        inventorySupplyId: _ingredientId,
        inventoryQuantity: quantity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add variant or add-on'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Choice name'),
            ),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Additional price (PHP)',
              ),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _ingredientId,
              decoration: const InputDecoration(labelText: 'Ingredient'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No ingredient'),
                ),
                ...widget.supplies.map(
                  (supply) => DropdownMenuItem<String?>(
                    value: supply.id,
                    child: Text('${supply.name} (${supply.stockUnit})'),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _ingredientId = value),
            ),
            if (_ingredientId != null)
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Ingredient quantity per selection',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
