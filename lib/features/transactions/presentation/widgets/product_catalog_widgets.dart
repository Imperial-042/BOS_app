// lib/features/transactions/presentation/widgets/product_catalog_widgets.dart
//
// Drop-in UI for the product master: the catalog search/filter bar, a
// filter sheet, the category manager, and the identity fields block
// used by the add/edit product form.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/product_catalog_service.dart';
import '../providers/product_catalog_providers.dart';

// ============================================================
// SEARCH + FILTER BAR
// ============================================================

/// Sits directly above the catalog list. Search box, a horizontal row
/// of category chips, and a filter button that opens the fuller sheet.
class ProductFilterBar extends ConsumerStatefulWidget {
  /// Optional hook for a barcode scanner button — wire this to your
  /// scanner package and pass the decoded string back.
  final Future<String?> Function()? onScan;

  const ProductFilterBar({super.key, this.onScan});

  @override
  ConsumerState<ProductFilterBar> createState() => _ProductFilterBarState();
}

class _ProductFilterBarState extends ConsumerState<ProductFilterBar> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(productQueryProvider).search;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setSearch(String value) {
    ref
        .read(productQueryProvider.notifier)
        .update((q) => q.copyWith(search: value));
  }

  Future<void> _scan() async {
    final code = await widget.onScan?.call();
    if (code == null || !mounted) return;

    // A scan is an exact-match intent: resolve it straight to a product
    // when we can, and only fall back to filtering the list if not.
    final product = await ref
        .read(productCatalogServiceProvider)
        .lookupForPos(code);

    if (!mounted) return;

    if (product == null) {
      _controller.text = code;
      _setSearch(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No product matches "$code" — showing search results.'),
        ),
      );
      return;
    }

    _controller.text = product.name;
    _setSearch(product.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = ref.watch(productQueryProvider);
    final categoriesAsync = ref.watch(productCategoriesProvider);
    final counts = ref.watch(productCategoryCountsProvider).value ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: _setSearch,
                decoration: InputDecoration(
                  hintText: 'Search name, SKU, barcode, category...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _controller.clear();
                            _setSearch('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            if (widget.onScan != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Scan barcode',
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ],
            const SizedBox(width: 8),
            _FilterButton(
              activeCount: query.activeFilterCount,
              onPressed: () => showProductFilterSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: categoriesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (categories) {
              return ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CategoryChip(
                    label: 'All',
                    selected: query.categoryId == null,
                    onSelected: () => ref
                        .read(productQueryProvider.notifier)
                        .update((q) => q.copyWith(categoryId: null)),
                  ),
                  for (final category in categories)
                    _CategoryChip(
                      label: category.name,
                      count: counts[category.id],
                      selected: query.categoryId == category.id,
                      onSelected: () => ref
                          .read(productQueryProvider.notifier)
                          .update(
                            (q) => q.copyWith(
                              categoryId: q.categoryId == category.id
                                  ? null
                                  : category.id,
                            ),
                          ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ActionChip(
                      avatar: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('Manage'),
                      onPressed: () => showProductCategoryManager(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (query.hasActiveFilters) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref
                  .read(productQueryProvider.notifier)
                  .update((q) => q.cleared()),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
              label: Text(
                'Clear ${query.activeFilterCount} filter'
                '${query.activeFilterCount == 1 ? '' : 's'}',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const _FilterButton({required this.activeCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filledTonal(
          tooltip: 'Filters',
          onPressed: onPressed,
          icon: const Icon(Icons.filter_list_rounded),
        ),
        if (activeCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Text(
                '$activeCount',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onSelected;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(count == null ? label : '$label · $count'),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

// ============================================================
// FILTER SHEET
// ============================================================

Future<void> showProductFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProductFilterSheet(),
  );
}

class _ProductFilterSheet extends ConsumerWidget {
  const _ProductFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final query = ref.watch(productQueryProvider);
    final notifier = ref.read(productQueryProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filter products',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _FilterSectionLabel('Product type'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ProductType.values.map((type) {
                final selected = query.types.contains(type);
                return FilterChip(
                  label: Text(type.label),
                  selected: selected,
                  onSelected: (on) {
                    final next = {...query.types};
                    if (on) {
                      next.add(type);
                    } else {
                      next.remove(type);
                    }
                    notifier.update((q) => q.copyWith(types: next));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            _FilterSectionLabel('Tracking'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TrackingType.values.map((tracking) {
                final selected = query.tracking.contains(tracking);
                return FilterChip(
                  label: Text(tracking.label),
                  selected: selected,
                  onSelected: (on) {
                    final next = {...query.tracking};
                    if (on) {
                      next.add(tracking);
                    } else {
                      next.remove(tracking);
                    }
                    notifier.update((q) => q.copyWith(tracking: next));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            _FilterSectionLabel('Availability'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Sellable only'),
                  selected: query.sellableOnly == true,
                  onSelected: (on) => notifier.update(
                    (q) => q.copyWith(sellableOnly: on ? true : null),
                  ),
                ),
                FilterChip(
                  label: const Text('Components only'),
                  selected: query.sellableOnly == false,
                  onSelected: (on) => notifier.update(
                    (q) => q.copyWith(sellableOnly: on ? false : null),
                  ),
                ),
                FilterChip(
                  label: const Text('Low stock'),
                  selected: query.lowStockOnly,
                  onSelected: (on) =>
                      notifier.update((q) => q.copyWith(lowStockOnly: on)),
                ),
                FilterChip(
                  label: const Text('Include archived'),
                  selected: query.includeArchived,
                  onSelected: (on) =>
                      notifier.update((q) => q.copyWith(includeArchived: on)),
                ),
              ],
            ),
            const SizedBox(height: 18),

            _FilterSectionLabel('Sort by'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ProductSort.values.map((sort) {
                return ChoiceChip(
                  label: Text(sort.label),
                  selected: query.sort == sort,
                  onSelected: (_) =>
                      notifier.update((q) => q.copyWith(sort: sort)),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => notifier.update((q) => q.cleared()),
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Show results'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  final String text;
  const _FilterSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ============================================================
// CATEGORY MANAGER
// ============================================================

Future<void> showProductCategoryManager(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ProductCategoryManagerSheet(),
  );
}

class ProductCategoryManagerSheet extends ConsumerWidget {
  const ProductCategoryManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categoriesAsync = ref.watch(productCategoriesProvider);
    final counts = ref.watch(productCategoryCountsProvider).value ?? {};
    final service = ref.read(productCatalogServiceProvider);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Product categories',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            'Group products so the catalog and POS stay browsable.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: categoriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Unable to load categories: $e'),
              data: (categories) {
                if (categories.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No categories yet.'),
                  );
                }
                return ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  onReorder: (oldIndex, newIndex) {
                    final ids = categories.map((c) => c.id).toList();
                    if (newIndex > oldIndex) newIndex -= 1;
                    ids.insert(newIndex, ids.removeAt(oldIndex));
                    service.reorderCategories(ids);
                  },
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final count = counts[category.id] ?? 0;

                    return ListTile(
                      key: ValueKey(category.id),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.drag_handle_rounded),
                      title: Text(
                        category.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '$count product${count == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'rename') {
                            final name = await _promptName(
                              context,
                              initial: category.name,
                              title: 'Rename category',
                            );
                            if (name != null) {
                              await service.renameCategory(category.id, name);
                            }
                          } else if (value == 'archive') {
                            await service.archiveCategory(category.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(
                            value: 'archive',
                            child: Text('Archive'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () async {
                final name = await _promptName(context, title: 'New category');
                if (name != null) await service.createCategory(name);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add category'),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptName(
    BuildContext context, {
    String initial = '',
    required String title,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _NamePromptDialog(title: title, initial: initial),
    );
  }
}

/// Owns its controller so disposal follows the dialog route's lifecycle
/// (same reason as _TextEntryDialog in the supplies page).
class _NamePromptDialog extends StatefulWidget {
  final String title;
  final String initial;

  const _NamePromptDialog({required this.title, required this.initial});

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);
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
      title: Text(widget.title),
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

// ============================================================
// PRODUCT IDENTITY FIELDS — for the add/edit product form
// ============================================================

/// The SKU / barcode / category / type block. Drop this into the
/// existing product form between the name and price fields; the
/// parent keeps owning the controllers and the save button.
class ProductIdentityFields extends ConsumerWidget {
  final TextEditingController skuController;
  final TextEditingController barcodeController;
  final TextEditingController descriptionController;
  final String? categoryId;
  final ProductType productType;
  final TrackingType trackingType;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<ProductType> onTypeChanged;
  final ValueChanged<TrackingType> onTrackingChanged;
  final Future<String?> Function()? onScan;

  /// The product being edited, if any — so uniqueness checks can
  /// exclude it from their own collision test.
  final String? editingProductId;

  const ProductIdentityFields({
    super.key,
    required this.skuController,
    required this.barcodeController,
    required this.descriptionController,
    required this.categoryId,
    required this.productType,
    required this.trackingType,
    required this.onCategoryChanged,
    required this.onTypeChanged,
    required this.onTrackingChanged,
    this.onScan,
    this.editingProductId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final service = ref.read(productCatalogServiceProvider);
    final categoriesAsync = ref.watch(productCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: skuController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'SKU / product code',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
                // Async uniqueness lives in the save path; this catches
                // the obvious shape problems while typing.
                validator: (value) {
                  final normalized = ProductCatalogService.normalizeSku(value);
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

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: barcodeController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Barcode',
                  hintText: 'Scan or type',
                  prefixIcon: Icon(Icons.qr_code_rounded),
                ),
              ),
            ),
            if (onScan != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Scan barcode',
                onPressed: () async {
                  final code = await onScan!();
                  if (code != null) barcodeController.text = code;
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

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
                      builder: (_) => const _NamePromptDialog(
                        title: 'New category',
                        initial: '',
                      ),
                    );
                    if (name == null) return;
                    final created = await service.createCategory(name);
                    onCategoryChanged(created.id);
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        DropdownButtonFormField<ProductType>(
          initialValue: productType,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Product type',
            helperText: productType.hint,
            prefixIcon: const Icon(Icons.widgets_outlined),
          ),
          items: ProductType.values
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            onTypeChanged(value);
            // Keep tracking sensible when the type changes — the user
            // can still override it in the next dropdown.
            onTrackingChanged(value.defaultTracking);
          },
        ),
        const SizedBox(height: 12),

        DropdownButtonFormField<TrackingType>(
          initialValue: trackingType,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Stock tracking',
            helperText: trackingType.hint,
            prefixIcon: const Icon(Icons.inventory_outlined),
          ),
          items: TrackingType.values
              .map(
                (tracking) => DropdownMenuItem(
                  value: tracking,
                  child: Text(tracking.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onTrackingChanged(value);
          },
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: descriptionController,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description / notes',
            hintText: 'Optional — prep notes, variants, anything useful',
            alignLabelWithHint: true,
          ),
        ),

        if (productType == ProductType.intermediate) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recipe components stay out of the sellable catalog — '
                    'they only appear inside other recipes.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// PRODUCT TYPE BADGE — for list tiles
// ============================================================

class ProductTypeBadge extends StatelessWidget {
  final ProductListing listing;

  const ProductTypeBadge({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = listing.category?.name ?? listing.type.label;
    final color = listing.isLowStock ? Colors.orange : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            listing.isLowStock
                ? Icons.warning_amber_rounded
                : Icons.local_offer_outlined,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            listing.isLowStock ? 'Low stock · $label' : label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
