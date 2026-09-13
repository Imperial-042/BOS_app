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

class ProductsPage extends ConsumerWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ProductCard(product: products[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
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
          Text(
            '${c.quantityRequired} ${c.unit}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Raw Supply')),
                  ButtonSegment(value: false, label: Text('Sub-recipe')),
                ],
                selected: {_isSupply},
                onSelectionChanged: (s) => setState(() {
                  _isSupply = s.first;
                  _selectedId = null;
                }),
              ),
              const SizedBox(height: 16),
              if (_isSupply)
                suppliesAsync.when(
                  data: (supplies) => DropdownButtonFormField<String>(
                    initialValue: _selectedId,
                    decoration: const InputDecoration(
                      labelText: 'Supply',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    items: supplies
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              '${s.name} (stock: ${s.currentStock} ${s.stockUnit})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedId = v;
                      _selectedUnit = supplies
                          .firstWhere((s) => s.id == v)
                          .stockUnit;
                    }),
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
                      decoration: const InputDecoration(
                        labelText: 'Product / Sub-recipe',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: options
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedId = v;
                        _selectedUnit = options
                            .firstWhere((p) => p.id == v)
                            .unit;
                      }),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Unable to load products'),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Quantity required',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Unit',
                        hintText: _selectedUnit ?? 'g, ml, piece...',
                      ),
                      onChanged: (v) => _selectedUnit = v,
                      controller: TextEditingController(text: _selectedUnit)
                        ..selection = TextSelection.collapsed(
                          offset: (_selectedUnit ?? '').length,
                        ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: quantity is per batch — if this recipe yields more than 1 unit, that\'s set on the recipe, not here.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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

// ============================================================
// RECORD PRODUCTION SHEET
// ============================================================

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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            producibilityAsync.when(
              data: (r) => Text(
                'Currently makeable: ${r.maxUnits} ${widget.product.unit}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
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
            ),
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
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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
                    : const Text('Deduct Ingredients'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(productionServiceProvider)
          .recordProduction(
            productId: widget.product.id,
            quantity: qty,
            referenceType: 'product_sale',
          );
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
