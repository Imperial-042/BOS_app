// lib/features/production/presentation/screens/products_page.dart
//
// Products list (with live "how many can I make" badges) + recipe
// editor (supports nested product components) + Record Production,
// which deducts real stock via ProductionService.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId;
import '../../domain/production_service.dart';
import '../../domain/costing_service.dart';
import '../../domain/unit_options.dart';

// ============================================================
// PROVIDERS
// ============================================================

final productionServiceProvider = Provider<ProductionService>((ref) {
  return ProductionService(ref.watch(databaseProvider));
});

final costingServiceProvider = Provider<CostingService>((ref) {
  return CostingService(ref.watch(databaseProvider));
});

final profitabilityProvider =
    FutureProvider.family<ProfitabilityResult, String>((ref, productId) {
      ref.watch(
        ledgerVersionProvider,
      ); // recompute whenever supply cost/recipe/price changes
      return ref.watch(costingServiceProvider).computeProfitability(productId);
    });

final productsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where(
          (p) =>
              p.businessId.equals(kCurrentBusinessId) & p.isActive.equals(true),
        )
        ..orderBy([(p) => OrderingTerm.asc(p.name)]))
      .watch();
});

final producibilityProvider =
    FutureProvider.family<ProducibilityResult, String>((ref, productId) {
      ref.watch(
        ledgerVersionProvider,
      ); // re-check whenever stock changes anywhere
      return ref
          .watch(productionServiceProvider)
          .computeMaxProducible(productId);
    });

final suppliesForPickerProvider = StreamProvider<List<Supply>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.supplies)
        ..where(
          (s) =>
              s.businessId.equals(kCurrentBusinessId) & s.isActive.equals(true),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch();
});

// ============================================================
// PAGE — Products list
// ============================================================

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filter(List<Product> products) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Products & Recipes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 2),
            Text(
              'Production-aware inventory',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (products) {
          if (products.isEmpty) {
            return _EmptyState(onAdd: () => _openAddProductSheet(context));
          }
          final filtered = _filter(products);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No products match "$_query".',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                ...filtered.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProductCard(product: p),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_product',
        backgroundColor: AppColors.primary,
        onPressed: () => _openAddProductSheet(context),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _openAddProductSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProductForm(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.restaurant_menu_outlined,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No products yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              'Add a product and its recipe to start tracking production.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add product'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PRODUCT CARD — shows live producibility + limiting ingredient
// ============================================================

class _ProductCard extends ConsumerWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final producibilityAsync = ref.watch(producibilityProvider(product.id));

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(product: product),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (!product.isSellable) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Component',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    producibilityAsync.when(
                      data: (result) => Text(
                        result.limitingComponentName == null
                            ? 'No recipe set'
                            : 'Limited by ${result.limitingComponentName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      loading: () => const SizedBox(
                        height: 14,
                        child: LinearProgressIndicator(),
                      ),
                      error: (e, _) => Text(
                        'Error',
                        style: TextStyle(fontSize: 12, color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              producibilityAsync.when(
                data: (result) => _ProducibilityBadge(
                  maxUnits: result.maxUnits,
                  unit: product.unit,
                  hasRecipe: result.limitingComponentName != null,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProducibilityBadge extends StatelessWidget {
  final int maxUnits;
  final String unit;
  final bool hasRecipe;
  const _ProducibilityBadge({
    required this.maxUnits,
    required this.unit,
    required this.hasRecipe,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasRecipe) return const SizedBox.shrink();
    final color = maxUnits <= 0
        ? Colors.redAccent
        : (maxUnits <= 10 ? Colors.orange : Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$maxUnits',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          Text(unit, style: TextStyle(color: color, fontSize: 9)),
        ],
      ),
    );
  }
}

// ============================================================
// ADD PRODUCT FORM
// ============================================================

class _ProductForm extends ConsumerStatefulWidget {
  final Product? existing;
  const _ProductForm({this.existing});

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _priceController = TextEditingController(
    text: widget.existing?.sellPrice != null
        ? (widget.existing!.sellPrice! / 100).toStringAsFixed(2)
        : '',
  );
  String? _unit;
  bool _isSellable = true;
  bool _saving = false;

  static const _units = ['cup', 'serving', 'piece', 'bottle', 'box', 'pack'];

  @override
  void initState() {
    super.initState();
    _unit = widget.existing?.unit;
    _isSellable = widget.existing?.isSellable ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty || _unit == null) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final price = double.tryParse(_priceController.text);

    try {
      if (widget.existing == null) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: const Uuid().v4(),
                businessId: kCurrentBusinessId,
                name: _nameController.text.trim(),
                unit: _unit!,
                sellPrice: Value(price == null ? null : (price * 100).round()),
                isSellable: Value(_isSellable),
              ),
            );
      } else {
        await (db.update(
          db.products,
        )..where((p) => p.id.equals(widget.existing!.id))).write(
          ProductsCompanion(
            name: Value(_nameController.text.trim()),
            unit: Value(_unit!),
            sellPrice: Value(price == null ? null : (price * 100).round()),
            isSellable: Value(_isSellable),
          ),
        );
      }
      ref.invalidate(productsProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'Add Product' : 'Edit Product',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Product name',
                  hintText: 'e.g. Spanish Latte, Espresso Base',
                  prefixIcon: Icon(Icons.restaurant_menu_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Unit',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _units
                    .map(
                      (u) => ChoiceChip(
                        label: Text(u),
                        selected: _unit == u,
                        onSelected: (_) => setState(() => _unit = u),
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.16,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Sell price (optional)',
                  prefixText: '₱ ',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sold directly to customers'),
                subtitle: const Text(
                  'Turn off for an intermediate component (e.g. Espresso Base)',
                ),
                value: _isSellable,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _isSellable = v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.existing == null
                              ? 'Save Product'
                              : 'Update Product',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PRODUCT DETAIL — recipe editor + producibility + record production
// ============================================================

class ProductDetailPage extends ConsumerWidget {
  final Product product;
  const ProductDetailPage({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final producibilityAsync = ref.watch(producibilityProvider(product.id));
    final recipeAsync = ref.watch(_recipeWithComponentsProvider(product.id));

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(product.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _ProductForm(existing: product),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete product',
            onPressed: () => _confirmDeleteProduct(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          producibilityAsync.when(
            data: (result) =>
                _ProducibilityHero(product: product, result: result),
            loading: () => const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 16),
          Consumer(
            builder: (context, ref, _) {
              final profitAsync = ref.watch(profitabilityProvider(product.id));
              return profitAsync.when(
                data: (p) => _ProfitabilityCard(profitability: p),
                loading: () => const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => const SizedBox.shrink(),
              );
            },
          ),
          const SizedBox(height: 16),
          if (product.isSellable)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openRecordProductionSheet(context),
                icon: const Icon(Icons.point_of_sale_outlined),
                label: const Text('Record Sale / Production'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recipe',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openAddComponentSheet(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Ingredient'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          recipeAsync.when(
            data: (data) {
              if (data.components.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No recipe defined yet — add ingredients above.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  if (data.recipe.yieldQuantity != 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Yields ${data.recipe.yieldQuantity} ${product.unit} per batch',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ...data.components.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ComponentTile(
                        component: c,
                        recipeId: data.recipe.id,
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }

  void _openRecordProductionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordProductionSheet(product: product),
    );
  }

  void _openAddComponentSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddComponentSheet(product: product),
    );
  }

  // ------------------------------------------------------------
  // DELETE PRODUCT / RECIPE — checks whether this product is used
  // as a sub-recipe ingredient elsewhere first, since deleting it
  // out from under another recipe would silently break that
  // recipe's cost/producibility calculation.
  // ------------------------------------------------------------
  Future<void> _confirmDeleteProduct(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final db = ref.read(databaseProvider);

    // Find any OTHER recipe that uses this product as a component.
    final referencingComponents = await (db.select(
      db.recipeComponents,
    )..where((c) => c.componentProductId.equals(product.id))).get();

    final parentProductNames = <String>{};
    for (final comp in referencingComponents) {
      final recipe = await (db.select(
        db.recipes,
      )..where((r) => r.id.equals(comp.recipeId))).getSingleOrNull();
      if (recipe == null) continue;
      final parent = await (db.select(
        db.products,
      )..where((p) => p.id.equals(recipe.productId))).getSingleOrNull();
      if (parent != null) parentProductNames.add(parent.name);
    }

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${product.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This removes the product and its recipe. This can\'t be undone.',
            ),
            if (parentProductNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'It\'s also used as an ingredient in: ${parentProductNames.join(', ')}.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Those recipes will lose this ingredient — you\'ll need to replace it if you still want to make them.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await db.transaction(() async {
      // Remove this product's own recipe (and its components).
      final ownRecipe = await (db.select(
        db.recipes,
      )..where((r) => r.productId.equals(product.id))).getSingleOrNull();
      if (ownRecipe != null) {
        await (db.delete(
          db.recipeComponents,
        )..where((c) => c.recipeId.equals(ownRecipe.id))).go();
        await (db.delete(
          db.recipes,
        )..where((r) => r.id.equals(ownRecipe.id))).go();
      }

      // Remove any OTHER recipe's line that used this product as an
      // ingredient, so nothing is left pointing at a deleted product.
      await (db.delete(
        db.recipeComponents,
      )..where((c) => c.componentProductId.equals(product.id))).go();

      await (db.delete(
        db.products,
      )..where((p) => p.id.equals(product.id))).go();
    });

    ref.invalidate(productsProvider);
    ref.read(ledgerVersionProvider.notifier).state++;

    if (context.mounted) Navigator.pop(context); // back to the Products list
  }
}

class _ProducibilityHero extends StatelessWidget {
  final Product product;
  final ProducibilityResult result;
  const _ProducibilityHero({required this.product, required this.result});

  @override
  Widget build(BuildContext context) {
    final hasRecipe =
        result.limitingComponentName != null ||
        result.componentMaxUnits.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You can currently make',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasRecipe
                ? '${result.maxUnits} ${product.unit}${result.maxUnits == 1 ? '' : 's'}'
                : 'No recipe set',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (result.limitingComponentName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Limited by ${result.limitingComponentName}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
          if (result.componentMaxUnits.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...result.componentMaxUnits.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${e.value}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// PROFITABILITY CARD — cost, sell price, gross profit & margin,
// with a per-ingredient cost breakdown (spec sections 15-17).
// ============================================================

class _ProfitabilityCard extends ConsumerWidget {
  final ProfitabilityResult profitability;
  const _ProfitabilityCard({required this.profitability});

  String _peso(int cents) => '₱${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasSellPrice = profitability.sellPriceCents != null;
    final marginColor = (profitability.grossMarginPercent ?? 0) >= 40
        ? Colors.green
        : ((profitability.grossMarginPercent ?? 0) >= 20
              ? Colors.orange
              : Colors.redAccent);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calculate_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Cost & Profitability',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  label: 'Cost',
                  value: _peso(profitability.costCents),
                  color: scheme.onSurface,
                ),
              ),
              if (hasSellPrice) ...[
                Expanded(
                  child: _StatColumn(
                    label: 'Sell Price',
                    value: _peso(profitability.sellPriceCents!),
                    color: scheme.onSurface,
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    label: 'Gross Profit',
                    value: _peso(profitability.grossProfitCents!),
                    color: profitability.grossProfitCents! >= 0
                        ? Colors.green
                        : Colors.redAccent,
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    label: 'Margin',
                    value:
                        '${profitability.grossMarginPercent!.toStringAsFixed(1)}%',
                    color: marginColor,
                  ),
                ),
              ],
            ],
          ),
          if (!hasSellPrice) ...[
            const SizedBox(height: 8),
            Text(
              'Set a sell price on this product to see gross profit and margin.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ============================================================
// RECIPE DATA LOADING
// ============================================================

class _RecipeWithComponents {
  final Recipe recipe;
  final List<_ComponentDisplay> components;
  _RecipeWithComponents({required this.recipe, required this.components});
}

class _ComponentDisplay {
  final RecipeComponent raw;
  final String name;
  _ComponentDisplay({required this.raw, required this.name});
}

final _recipeWithComponentsProvider =
    FutureProvider.family<_RecipeWithComponents, String>((
      ref,
      productId,
    ) async {
      final db = ref.watch(databaseProvider);

      var recipe = await (db.select(
        db.recipes,
      )..where((r) => r.productId.equals(productId))).getSingleOrNull();
      recipe ??= await _ensureRecipeExists(db, productId);

      final rawComponents = await (db.select(
        db.recipeComponents,
      )..where((c) => c.recipeId.equals(recipe!.id))).get();

      final displayed = <_ComponentDisplay>[];
      for (final c in rawComponents) {
        if (c.componentType == 'supply') {
          final supply = await (db.select(
            db.supplies,
          )..where((s) => s.id.equals(c.supplyId!))).getSingle();
          displayed.add(_ComponentDisplay(raw: c, name: supply.name));
        } else {
          final p = await (db.select(
            db.products,
          )..where((pr) => pr.id.equals(c.componentProductId!))).getSingle();
          displayed.add(_ComponentDisplay(raw: c, name: '${p.name} (recipe)'));
        }
      }

      return _RecipeWithComponents(recipe: recipe, components: displayed);
    });

Future<Recipe> _ensureRecipeExists(AppDatabase db, String productId) async {
  final id = const Uuid().v4();
  await db
      .into(db.recipes)
      .insert(RecipesCompanion.insert(id: id, productId: productId));
  return (db.select(db.recipes)..where((r) => r.id.equals(id))).getSingle();
}

// ============================================================
// COMPONENT TILE (with remove)
// ============================================================

class _ComponentTile extends ConsumerWidget {
  final _ComponentDisplay component;
  final String recipeId;
  const _ComponentTile({required this.component, required this.recipeId});

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final c = component.raw;

    final result = await showDialog<_QuantityUnitResult>(
      context: context,
      builder: (_) => _EditComponentQuantityDialog(
        componentName: component.name,
        initialQuantity: c.quantityRequired,
        initialUnit: c.unit,
      ),
    );

    if (result == null) return;

    await (db.update(
      db.recipeComponents,
    )..where((rc) => rc.id.equals(c.id))).write(
      RecipeComponentsCompanion(
        quantityRequired: Value(result.quantity),
        unit: Value(result.unit),
      ),
    );

    ref.invalidate(_recipeWithComponentsProvider);
    ref.read(ledgerVersionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final c = component.raw;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            c.componentType == 'supply'
                ? Icons.inventory_2_outlined
                : Icons.account_tree_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              component.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _editQuantity(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${c.quantityRequired} ${c.unit}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.edit_outlined,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final db = ref.read(databaseProvider);
              await (db.delete(
                db.recipeComponents,
              )..where((rc) => rc.id.equals(c.id))).go();
              ref.invalidate(_recipeWithComponentsProvider);
              ref.read(ledgerVersionProvider.notifier).state++;
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EDIT COMPONENT QUANTITY/UNIT DIALOG — lets an already-added
// ingredient's amount be corrected without removing and re-adding
// it. Saved changes bump ledgerVersionProvider, so producibility,
// profitability, and the Supplies "Used in products" section all
// recompute against the new quantity automatically.
// ============================================================

class _QuantityUnitResult {
  final double quantity;
  final String unit;
  const _QuantityUnitResult(this.quantity, this.unit);
}

class _EditComponentQuantityDialog extends StatefulWidget {
  final String componentName;
  final double initialQuantity;
  final String initialUnit;
  const _EditComponentQuantityDialog({
    required this.componentName,
    required this.initialQuantity,
    required this.initialUnit,
  });

  @override
  State<_EditComponentQuantityDialog> createState() =>
      _EditComponentQuantityDialogState();
}

class _EditComponentQuantityDialogState
    extends State<_EditComponentQuantityDialog> {
  late final _qtyController = TextEditingController(
    text: widget.initialQuantity == widget.initialQuantity.roundToDouble()
        ? widget.initialQuantity.toInt().toString()
        : widget.initialQuantity.toString(),
  );
  late String _unit = widget.initialUnit;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a valid quantity');
      return;
    }
    Navigator.pop(context, _QuantityUnitResult(qty, _unit));
  }

  @override
  Widget build(BuildContext context) {
    final units = compatibleStockUnits(widget.initialUnit);
    return AlertDialog(
      title: Text('Edit "${widget.componentName}"'),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _qtyController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Quantity',
                errorText: _error,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: units.contains(_unit) ? _unit : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: units
                  .map(
                    (u) => DropdownMenuItem(
                      value: u,
                      child: Text(
                        kStockUnitLabels[u] ?? u,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _unit = v);
              },
            ),
          ),
        ],
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
// ADD COMPONENT SHEET — pick a Supply OR another Product (nesting)
// ============================================================

class _AddComponentSheet extends ConsumerStatefulWidget {
  final Product product;
  const _AddComponentSheet({required this.product});

  @override
  ConsumerState<_AddComponentSheet> createState() => _AddComponentSheetState();
}

class _AddComponentSheetState extends ConsumerState<_AddComponentSheet> {
  bool _isSupply = true;
  String? _selectedId;
  String? _selectedUnit;
  double? _selectedStock;
  final _qtyController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suppliesAsync = ref.watch(suppliesForPickerProvider);
    final productsAsync = ref.watch(productsProvider);
    final qty = double.tryParse(_qtyController.text);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add Ingredient',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'For every ${widget.product.unit} of ${widget.product.name}, how much of something does it use?',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),

              _StepLabel(number: 1, text: 'What kind of ingredient is this?'),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Raw Supply'),
                    icon: Icon(Icons.inventory_2_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Sub-recipe'),
                    icon: Icon(Icons.account_tree_outlined, size: 16),
                  ),
                ],
                selected: {_isSupply},
                onSelectionChanged: (s) => setState(() {
                  _isSupply = s.first;
                  _selectedId = null;
                  _selectedUnit = null;
                  _selectedStock = null;
                }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _isSupply
                      ? 'A raw material tracked in Supplies — flour, milk, cups, etc.'
                      : 'Another product with its own recipe — e.g. an Espresso Base used inside this one.',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              _StepLabel(
                number: 2,
                text: _isSupply ? 'Which supply?' : 'Which product?',
              ),
              const SizedBox(height: 8),
              if (_isSupply)
                suppliesAsync.when(
                  data: (supplies) => DropdownButtonFormField<String>(
                    initialValue: _selectedId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Supply',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    items: supplies
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              '${s.name} — ${s.currentStock} ${s.stockUnit} in stock',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      final chosen = supplies.firstWhere((s) => s.id == v);
                      setState(() {
                        _selectedId = v;
                        _selectedUnit = chosen
                            .stockUnit; // default to the supply's own unit
                        _selectedStock = chosen.currentStock;
                      });
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Unable to load supplies'),
                )
              else
                productsAsync.when(
                  data: (products) {
                    final options = products
                        .where((p) => p.id != widget.product.id)
                        .toList();
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Product / Sub-recipe',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: options
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        final chosen = options.firstWhere((p) => p.id == v);
                        setState(() {
                          _selectedId = v;
                          _selectedUnit = chosen.unit;
                          _selectedStock = null;
                        });
                      },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Unable to load products'),
                ),
              const SizedBox(height: 18),

              _StepLabel(number: 3, text: 'How much is needed?'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items:
                          (_selectedUnit == null
                                  ? kStockUnitOptions
                                  : compatibleStockUnits(_selectedUnit!))
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    kStockUnitLabels[u] ?? u,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: _selectedId == null
                          ? null
                          : (v) => setState(() => _selectedUnit = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        qty != null && _selectedUnit != null
                            ? (_selectedStock != null
                                  ? 'You have ${_selectedStock!.toStringAsFixed(_selectedStock! % 1 == 0 ? 0 : 1)} ${_selectedUnit!} available; this recipe needs $qty $_selectedUnit for each ${widget.product.unit}.'
                                  : 'This means: making 1 ${widget.product.unit} of ${widget.product.name} uses $qty $_selectedUnit of this.')
                            : 'Quantity is needed per single ${widget.product.unit} — if a batch makes more than one, set that on the recipe\'s yield, not here.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Add to Recipe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qtyController.text);
    if (_selectedId == null ||
        qty == null ||
        qty <= 0 ||
        (_selectedUnit ?? '').trim().isEmpty) {
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);

    try {
      var recipe = await (db.select(
        db.recipes,
      )..where((r) => r.productId.equals(widget.product.id))).getSingleOrNull();
      recipe ??= await _ensureRecipeExists(db, widget.product.id);

      await db
          .into(db.recipeComponents)
          .insert(
            RecipeComponentsCompanion.insert(
              id: const Uuid().v4(),
              recipeId: recipe.id,
              componentType: _isSupply ? 'supply' : 'product',
              supplyId: Value(_isSupply ? _selectedId : null),
              componentProductId: Value(_isSupply ? null : _selectedId),
              quantityRequired: qty,
              unit: _selectedUnit!.trim(),
            ),
          );

      ref.invalidate(_recipeWithComponentsProvider);
      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StepLabel extends StatelessWidget {
  final int number;
  final String text;
  const _StepLabel({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    );
  }
}

// ============================================================
// RECORD PRODUCTION SHEET
// ============================================================

final _productionPaymentAccountsProvider = FutureProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)..where(
        (a) =>
            a.businessId.equals(kCurrentBusinessId) &
            a.isPaymentAccount.equals(true) &
            a.isActive.equals(true),
      ))
      .get();
});

class _RecordProductionSheet extends ConsumerStatefulWidget {
  final Product product;
  const _RecordProductionSheet({required this.product});

  @override
  ConsumerState<_RecordProductionSheet> createState() =>
      _RecordProductionSheetState();
}

class _RecordProductionSheetState
    extends ConsumerState<_RecordProductionSheet> {
  final _qtyController = TextEditingController(text: '1');
  String? _paymentAccountId;
  bool _stockOnly = false; // when true, skip the income/ledger side entirely
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final producibilityAsync = ref.watch(
      producibilityProvider(widget.product.id),
    );
    final accountsAsync = ref.watch(_productionPaymentAccountsProvider);
    final hasSellPrice = widget.product.sellPrice != null;
    final qty = double.tryParse(_qtyController.text);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Record Sale — ${widget.product.name}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              producibilityAsync.when(
                data: (r) => Text(
                  'Currently makeable: ${r.maxUnits} ${widget.product.unit}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _qtyController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity sold',
                  suffixText: widget.product.unit,
                ),
                onChanged: (_) => setState(() {}),
              ),

              if (!hasSellPrice) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No sell price is set on this product, so only ingredient stock will be deducted — no income will be recorded. Set a price (edit the product) to record real sales here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Stock deduction only'),
                  subtitle: const Text(
                    'Skip recording income — e.g. for a free sample or staff consumption',
                  ),
                  value: _stockOnly,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _stockOnly = v),
                ),
                if (!_stockOnly) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Paid via',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  accountsAsync.when(
                    data: (accounts) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: accounts
                          .map(
                            (a) => ChoiceChip(
                              label: Text(a.name),
                              selected: _paymentAccountId == a.id,
                              onSelected: (_) =>
                                  setState(() => _paymentAccountId = a.id),
                              selectedColor: AppColors.primary.withValues(
                                alpha: 0.16,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  if (qty != null && qty > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Will record ₱${((widget.product.sellPrice! * qty) / 100).toStringAsFixed(2)} in income',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ],

              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          hasSellPrice && !_stockOnly
                              ? 'Record Sale'
                              : 'Deduct Ingredients',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a valid quantity.');
      return;
    }

    final recordIncome = widget.product.sellPrice != null && !_stockOnly;
    if (recordIncome && _paymentAccountId == null) {
      setState(
        () => _error =
            'Choose a payment account, or turn on "Stock deduction only".',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final service = ref.read(productionServiceProvider);
      if (recordIncome) {
        await service.sellProduct(
          productId: widget.product.id,
          quantity: qty,
          paymentAccountId: _paymentAccountId!,
        );
      } else {
        await service.recordProduction(
          productId: widget.product.id,
          quantity: qty,
          referenceType: 'product_sale',
        );
      }
      ref.read(ledgerVersionProvider.notifier).state++;
      ref.invalidate(producibilityProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
