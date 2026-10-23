// lib/features/transactions/presentation/widgets/supply_identity_fields.dart
//
// The SKU / barcode / category block for the Add Supply sheet.
// Drop it into _SupplyForm between the brand field and the unit
// dropdown; the parent keeps owning the controllers and the save button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../domain/supply_catalog_service.dart';
import '../providers/product_catalog_providers.dart'
    show productCategoriesProvider, productCatalogServiceProvider;
import '../screens/transaction_page.dart' show kCurrentBusinessId;

final supplyCatalogServiceProvider = Provider<SupplyCatalogService>((ref) {
  return SupplyCatalogService(
    ref.watch(databaseProvider),
    businessId: kCurrentBusinessId,
  );
});

class SupplyIdentityFields extends ConsumerWidget {
  final TextEditingController skuController;
  final TextEditingController barcodeController;
  final String? categoryId;
  final ValueChanged<String?> onCategoryChanged;
  final Future<String?> Function()? onScan;

  const SupplyIdentityFields({
    super.key,
    required this.skuController,
    required this.barcodeController,
    required this.categoryId,
    required this.onCategoryChanged,
    this.onScan,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(supplyCatalogServiceProvider);
    final categoriesAsync = ref.watch(productCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── SKU + generate button ──────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: skuController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'SKU / item code',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
                // Async uniqueness happens on save; this only catches
                // the obvious shape problems while typing.
                validator: (value) {
                  final normalized = SupplyCatalogService.normalizeSku(value);
                  if (normalized != null && normalized.length > 32) {
                    return 'Keep the SKU under 32 characters';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Suggest a code',
              onPressed: () async {
                final base = skuController.text.trim().isEmpty
                    ? 'SKU'
                    : skuController.text.trim();
                skuController.text = await service.suggestSku(base);
              },
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Barcode + scan button ──────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: barcodeController,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  hintText: 'Enter or scan barcode',
                  prefixIcon: const Icon(Icons.qr_code_2_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Scan barcode',
                    icon: const Icon(Icons.camera_alt_outlined),
                    onPressed: onScan == null
                        ? null
                        : () async {
                            final scannedBarcode = await onScan!.call();

                            if (scannedBarcode == null ||
                                scannedBarcode.trim().isEmpty) {
                              return;
                            }

                            barcodeController.text = scannedBarcode.trim();
                          },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Category dropdown + inline "new category" ──────────
        categoriesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
          data: (categories) {
            return Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      for (final category in categories)
                        DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(
                            category.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: onCategoryChanged,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'New category',
                  onPressed: () async {
                    final name = await showDialog<String>(
                      context: context,
                      builder: (_) => const _CategoryPromptDialog(),
                    );
                    if (name == null) return;
                    // Categories are shared between supplies and
                    // products, so this reuses the product catalog's
                    // create path rather than duplicating the table.
                    final created = await ref
                        .read(productCatalogServiceProvider)
                        .createCategory(name);
                    onCategoryChanged(created.id);
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Owns its controller so disposal follows the dialog route's lifecycle.
class _CategoryPromptDialog extends StatefulWidget {
  const _CategoryPromptDialog();

  @override
  State<_CategoryPromptDialog> createState() => _CategoryPromptDialogState();
}

class _CategoryPromptDialogState extends State<_CategoryPromptDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter a category name');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Category name',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
