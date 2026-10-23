// lib/features/production/presentation/screens/products_page.dart
//
// Products list (with live "how many can I make" badges) + recipe
// editor (supports nested product components).
//
// Selling now happens only through the POS page — "Record Sale / Production"
// has been removed from here to avoid two different places doing the same
// stock deduction. Every product's sell price is required, so POS always has
// a real price to show and total.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart'
    show authorizationServiceProvider, canProvider, selectedBusinessIdProvider;
import 'package:bos_application/core/auth/authorization_service.dart'
    show PermissionDeniedException;
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/features/transactions/domain/product_catalog_service.dart';
import 'package:bos_application/features/transactions/presentation/providers/product_catalog_providers.dart';
import 'package:bos_application/features/transactions/presentation/widgets/product_catalog_widgets.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/production_service.dart';
import '../../domain/costing_service.dart';
import '../../domain/unit_options.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId, ledgerServiceProvider;

// ============================================================
// PERMISSION HELPERS
// ============================================================

/// UI guard. Every write handler also checks the relevant permission so a
/// hidden/disabled control is not the only protection.
bool _allowed(BuildContext context, WidgetRef ref, BosPermission permission) {
  try {
    ref
        .read(authorizationServiceProvider)
        .require(permission, businessId: kCurrentBusinessId);
    return true;
  } on PermissionDeniedException catch (e) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(e.message)),
      );
    return false;
  }
}

class _InventoryNoAccessView extends StatelessWidget {
  const _InventoryNoAccessView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 44,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 14),
              Text(
                'Products are restricted',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Your role cannot view inventory. Ask the business owner for access.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PROVIDERS
// ============================================================

final productionServiceProvider = Provider<ProductionService>((ref) {
  return ProductionService(
    ref.watch(databaseProvider),
    ref.watch(ledgerServiceProvider),
    branchId: ref.watch(selectedBranchIdProvider),
  );
});

final costingServiceProvider = Provider<CostingService>((ref) {
  return CostingService(
    ref.watch(databaseProvider),
    branchId: ref.watch(selectedBranchIdProvider),
    guard: (permission) => ref
        .read(authorizationServiceProvider)
        .require(permission, businessId: kCurrentBusinessId),
  );
});

final profitabilityProvider =
    FutureProvider.family<ProfitabilityResult, String>((ref, productId) {
      ref.watch(ledgerVersionProvider);
      return ref.watch(costingServiceProvider).computeProfitability(productId);
    });

/// Raw unfiltered stream — still used by the sub-recipe picker inside
/// _AddComponentSheet and by producibilityProvider.
final productsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  return (db.select(db.products)
        ..where(
          (p) => p.businessId.equals(businessId) & p.isActive.equals(true),
        )
        ..orderBy([(p) => OrderingTerm.asc(p.name)]))
      .watch();
});

final producibilityProvider =
    FutureProvider.family<ProducibilityResult, String>((ref, productId) {
      ref.watch(ledgerVersionProvider);
      return ref
          .watch(productionServiceProvider)
          .computeMaxProducible(productId);
    });

final suppliesForPickerProvider = StreamProvider<List<Supply>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  return (db.select(db.supplies)
        ..where(
          (s) => s.businessId.equals(businessId) & s.isActive.equals(true),
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
    if (!ref.watch(canProvider(BosPermission.inventoryView))) {
      return const _InventoryNoAccessView();
    }
    final canCreate = ref.watch(canProvider(BosPermission.inventoryCreate));
    final scheme = Theme.of(context).colorScheme;

    // productListingsProvider respects productQueryProvider (search +
    // filters set by ProductFilterBar). productsProvider is kept for
    // the recipe picker and producibility — it is NOT watched here.
    final listingsAsync = ref.watch(productListingsProvider);
    final totalAsync = ref.watch(productTotalCountProvider);

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
      body: listingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (listings) {
          // True when zero products exist in the database at all.
          final totalCount = totalAsync.maybeWhen(
            data: (n) => n,
            orElse: () => listings.length,
          );

          if (totalCount == 0) {
            return _EmptyState(
              canAdd: canCreate,
              onAdd: () => _openAddProductSheet(context, ref),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // Search box + category chips + filter/sort button.
              ProductFilterBar(
                onScan: () => Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
                ),
              ),
              const SizedBox(height: 14),

              if (listings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No products match your filters.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                ...listings.map(
                  (listing) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProductCard(product: listing.product),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              heroTag: 'add_product',
              backgroundColor: AppColors.primary,
              onPressed: () => _openAddProductSheet(context, ref),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
    );
  }

  void _openAddProductSheet(BuildContext context, WidgetRef ref) {
    if (!_allowed(context, ref, BosPermission.inventoryCreate)) return;
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
  final bool canAdd;
  const _EmptyState({required this.onAdd, required this.canAdd});

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
            if (canAdd) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add product'),
              ),
            ],
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
// ADD / EDIT PRODUCT FORM
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
  late final _skuController = TextEditingController(
    text: widget.existing?.sku ?? '',
  );
  late final _barcodeController = TextEditingController(
    text: widget.existing?.barcode ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description ?? '',
  );

  String? _unit;
  bool _isSellable = true;
  String? _categoryId;
  ProductType _productType = ProductType.finished;
  TrackingType _trackingType = TrackingType.recipe;
  bool _saving = false;

  static const _units = ['cup', 'serving', 'piece', 'bottle', 'box', 'pack'];

  @override
  void initState() {
    super.initState();
    _unit = widget.existing?.unit;
    _isSellable = widget.existing?.isSellable ?? true;

    if (widget.existing != null) {
      final p = widget.existing!;
      _categoryId = p.categoryId;
      _productType = ProductTypeX.parse(p.productType);
      _trackingType = TrackingTypeX.parse(p.trackingType);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<String?> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || barcode == null || barcode.trim().isEmpty) return null;
    return ProductCatalogService.normalizeBarcode(barcode);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _unit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a product name and choose a unit.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // A sell price is required for anything sold directly to customers, so
    // POS always has a real price to show and total. Components (not sold
    // directly, e.g. "Espresso Base") are exempt — nobody buys them on their
    // own — and never appear on the POS menu regardless of price.
    final priceText = _priceController.text.trim();
    final price = priceText.isEmpty ? null : double.tryParse(priceText);

    if (_isSellable && (price == null || price <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a sell price greater than ₱0.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_isSellable && price != null && price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sell price must be greater than ₱0, or left blank.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final writePermission = widget.existing == null
        ? BosPermission.inventoryCreate
        : BosPermission.inventoryEdit;
    if (!_allowed(context, ref, writePermission)) return;

    setState(() => _saving = true);

    final sellPriceCents = price == null ? null : (price * 100).round();

    try {
      if (!_allowed(context, ref, writePermission)) return;
      final service = ref.read(productCatalogServiceProvider);
      final audit = ref.read(auditLogServiceProvider);

      if (widget.existing == null) {
        await service.createProduct(
          name: name,
          unit: _unit!,
          sku: _skuController.text.trim().isEmpty
              ? null
              : _skuController.text.trim(),
          barcode: _barcodeController.text.trim().isEmpty
              ? null
              : _barcodeController.text.trim(),
          categoryId: _categoryId,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: _productType,
          tracking: _trackingType,
          sellPrice: sellPriceCents,
          isSellable: _productType == ProductType.intermediate
              ? false
              : _isSellable,
        );
        await audit.tryRecord(
          AuditEvent(
            module: AuditModule.inventory,
            actionType: AuditActionType.create,
            action: 'inventory.product_created',
            entityType: 'products',
            entityLabel: name,
            after: {
              'name': name,
              'unit': _unit,
              'sellPrice': sellPriceCents,
              'isSellable': _productType == ProductType.intermediate
                  ? false
                  : _isSellable,
              'productType': _productType.name,
              'trackingType': _trackingType.name,
              'sku': _skuController.text.trim(),
              'barcode': _barcodeController.text.trim(),
            },
          ),
        );
      } else {
        final before = widget.existing!;
        await service.updateProduct(
          widget.existing!.id,
          name: name,
          unit: _unit,
          sku: _skuController.text.trim().isEmpty
              ? null
              : _skuController.text.trim(),
          barcode: _barcodeController.text.trim().isEmpty
              ? null
              : _barcodeController.text.trim(),
          categoryId: _categoryId,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: _productType,
          tracking: _trackingType,
          sellPrice: sellPriceCents,
          isSellable: _productType == ProductType.intermediate
              ? false
              : _isSellable,
        );
        await audit.tryRecord(
          AuditEvent(
            module: AuditModule.inventory,
            actionType: AuditActionType.update,
            action: 'inventory.product_updated',
            entityType: 'products',
            entityId: before.id,
            entityLabel: name,
            before: {
              'name': before.name,
              'unit': before.unit,
              'sellPrice': before.sellPrice,
              'isSellable': before.isSellable,
              'productType': ProductTypeX.parse(before.productType).name,
              'trackingType': TrackingTypeX.parse(before.trackingType).name,
              'sku': before.sku ?? '',
              'barcode': before.barcode ?? '',
            },
            after: {
              'name': name,
              'unit': _unit,
              'sellPrice': sellPriceCents,
              'isSellable': _productType == ProductType.intermediate
                  ? false
                  : _isSellable,
              'productType': _productType.name,
              'trackingType': _trackingType.name,
              'sku': _skuController.text.trim(),
              'barcode': _barcodeController.text.trim(),
            },
          ),
        );
      }

      ref.invalidate(productsProvider);
      ref.invalidate(productListingsProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } on DuplicateProductCodeException catch (e) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      final errorColor = Theme.of(context).colorScheme.error;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: errorColor,
          ),
        );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Unable to save: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        // Material (not a plain decorated Container) so ListTile-based
        // children — SwitchListTile included — paint their background and
        // ink splashes correctly instead of being hidden underneath.
        child: Material(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.existing == null
                            ? 'Add Product'
                            : 'Edit Product',
                        style: const TextStyle(
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
                const SizedBox(height: 20),

                // ── SECTION 1: Basic info ──────────────────────────
                _FormSectionLabel(
                  icon: Icons.restaurant_menu_outlined,
                  title: 'Basic info',
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Product name *',
                    hintText: 'e.g. Spanish Latte, Espresso Base',
                    prefixIcon: Icon(Icons.restaurant_menu_outlined),
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Sold / produced in *',
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
                  decoration: InputDecoration(
                    labelText: _isSellable ? 'Sell price *' : 'Sell price',
                    hintText: _isSellable
                        ? 'Required for items sold directly'
                        : 'Optional — components aren\'t sold on their own',
                    prefixText: '₱ ',
                    prefixIcon: const Icon(Icons.sell_outlined),
                  ),
                ),
                const SizedBox(height: 8),

                if (_productType != ProductType.intermediate)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sold directly to customers'),
                    subtitle: const Text(
                      'Turn off for intermediate components (e.g. Espresso Base)',
                    ),
                    value: _isSellable,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setState(() => _isSellable = v),
                  ),

                const SizedBox(height: 24),

                // ── SECTION 2: Product identity ────────────────────
                _FormSectionLabel(
                  icon: Icons.badge_outlined,
                  title: 'Product identity',
                ),
                const SizedBox(height: 12),

                // SKU, barcode, category, type, tracking, description.
                ProductIdentityFields(
                  skuController: _skuController,
                  barcodeController: _barcodeController,
                  descriptionController: _descriptionController,
                  categoryId: _categoryId,
                  productType: _productType,
                  trackingType: _trackingType,
                  editingProductId: widget.existing?.id,
                  onCategoryChanged: (id) => setState(() => _categoryId = id),
                  onScan: _saving ? null : _scanBarcode,
                  onTypeChanged: (type) => setState(() {
                    _productType = type;
                    _trackingType = type.defaultTracking;
                    if (type == ProductType.intermediate) _isSellable = false;
                  }),
                  onTrackingChanged: (tracking) =>
                      setState(() => _trackingType = tracking),
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.existing == null
                                ? 'Save Product'
                                : 'Update Product',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),

                // This keeps the button visibly away from the bottom edge.
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  const _FormSectionLabel({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.primary),
        const SizedBox(width: 7),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ],
    );
  }
}

// ============================================================
// PRODUCT DETAIL — recipe editor + producibility
// ============================================================

class ProductDetailPage extends ConsumerWidget {
  final Product product;
  const ProductDetailPage({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canProvider(BosPermission.inventoryView))) {
      return const _InventoryNoAccessView();
    }
    final canEdit = ref.watch(canProvider(BosPermission.inventoryEdit));
    final canCreate = ref.watch(canProvider(BosPermission.inventoryCreate));
    final scheme = Theme.of(context).colorScheme;
    final producibilityAsync = ref.watch(producibilityProvider(product.id));
    final recipeAsync = ref.watch(_recipeWithComponentsProvider(product.id));

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(product.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (canEdit)
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
          if (canEdit)
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
              if (canCreate)
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
              final recipe = data.recipe;
              if (recipe == null || data.components.isEmpty) {
                final message = recipe == null
                    ? (canCreate
                          ? 'No recipe defined yet — add ingredients above.'
                          : 'No recipe defined yet.')
                    : (canCreate
                          ? 'No ingredients yet — add ingredients above.'
                          : 'No ingredients have been added to this recipe.');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  if (recipe.yieldQuantity != 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Yields ${recipe.yieldQuantity} ${product.unit} per batch',
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
                        recipeId: recipe.id,
                        productName: product.name,
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

  void _openAddComponentSheet(BuildContext context, WidgetRef ref) {
    if (!_allowed(context, ref, BosPermission.inventoryCreate)) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddComponentSheet(product: product),
    );
  }

  Future<void> _confirmDeleteProduct(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (!_allowed(context, ref, BosPermission.inventoryEdit)) return;
    final db = ref.read(databaseProvider);
    final audit = ref.read(auditLogServiceProvider);

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
    if (!_allowed(context, ref, BosPermission.inventoryEdit)) return;

    await db.transaction(() async {
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

      await (db.delete(
        db.recipeComponents,
      )..where((c) => c.componentProductId.equals(product.id))).go();

      await (db.delete(
        db.products,
      )..where((p) => p.id.equals(product.id))).go();

      await audit.record(
        AuditEvent(
          module: AuditModule.inventory,
          actionType: AuditActionType.delete,
          action: 'inventory.product_deleted',
          entityType: 'products',
          entityId: product.id,
          entityLabel: product.name,
          before: {
            'name': product.name,
            'unit': product.unit,
            'sellPrice': product.sellPrice,
            'isSellable': product.isSellable,
            'sku': product.sku,
            'barcode': product.barcode,
          },
          details: {
            'hadOwnRecipe': ownRecipe != null,
            'usedAsIngredientIn': parentProductNames.toList(),
            'ingredientRowsRemovedFromOtherRecipes':
                referencingComponents.length,
          },
        ),
      );
    });

    ref.invalidate(productsProvider);
    ref.invalidate(productListingsProvider);
    ref.read(ledgerVersionProvider.notifier).state++;

    if (context.mounted) Navigator.pop(context);
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
// PROFITABILITY CARD
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
  final Recipe? recipe;
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
      // Recipe data is affected by catalog changes too. In particular, when
      // a supply is archived/deleted from the Supplies catalog, its
      // recipe-component rows are removed by the catalog deletion flow.
      // Watching ledgerVersionProvider makes any already-open Product Detail
      // page immediately reload its recipe instead of keeping stale cached
      // ingredient data on screen.
      ref.watch(ledgerVersionProvider);

      final db = ref.watch(databaseProvider);

      final recipe = await (db.select(
        db.recipes,
      )..where((r) => r.productId.equals(productId))).getSingleOrNull();
      if (recipe == null) {
        // Reading a product must not create a recipe as a side effect.
        // The recipe is created when an authorized user adds its first item.
        return _RecipeWithComponents(recipe: null, components: const []);
      }

      final rawComponents = await (db.select(
        db.recipeComponents,
      )..where((c) => c.recipeId.equals(recipe.id))).get();

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
// COMPONENT TILE
// ============================================================

class _ComponentTile extends ConsumerWidget {
  final _ComponentDisplay component;
  final String recipeId;
  final String productName;

  const _ComponentTile({
    required this.component,
    required this.recipeId,
    required this.productName,
  });

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    if (!_allowed(context, ref, BosPermission.inventoryEdit)) return;
    final audit = ref.read(auditLogServiceProvider);
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

    if (result == null || !context.mounted) return;
    if (result.quantity == c.quantityRequired && result.unit == c.unit) {
      return;
    }
    if (!_allowed(context, ref, BosPermission.inventoryEdit)) return;

    await db.transaction(() async {
      await (db.update(
        db.recipeComponents,
      )..where((rc) => rc.id.equals(c.id))).write(
        RecipeComponentsCompanion(
          quantityRequired: Value(result.quantity),
          unit: Value(result.unit),
        ),
      );
      await audit.record(
        AuditEvent(
          module: AuditModule.inventory,
          actionType: AuditActionType.update,
          action: 'inventory.recipe_ingredient_updated',
          entityType: 'recipe_components',
          entityId: c.id,
          entityLabel: '$productName → ${component.name}',
          before: {'quantity': c.quantityRequired, 'unit': c.unit},
          after: {'quantity': result.quantity, 'unit': result.unit},
          details: {'recipeId': recipeId},
        ),
      );
    });

    ref.invalidate(_recipeWithComponentsProvider);
    ref.read(ledgerVersionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final canEdit = ref.watch(canProvider(BosPermission.inventoryEdit));
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
          if (canEdit)
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
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '${c.quantityRequired} ${c.unit}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                if (!_allowed(context, ref, BosPermission.inventoryEdit)) {
                  return;
                }
                final db = ref.read(databaseProvider);
                final audit = ref.read(auditLogServiceProvider);
                await db.transaction(() async {
                  await (db.delete(
                    db.recipeComponents,
                  )..where((rc) => rc.id.equals(c.id))).go();
                  await audit.record(
                    AuditEvent(
                      module: AuditModule.inventory,
                      actionType: AuditActionType.delete,
                      action: 'inventory.recipe_ingredient_removed',
                      entityType: 'recipe_components',
                      entityId: c.id,
                      entityLabel: '$productName → ${component.name}',
                      before: {
                        'quantity': c.quantityRequired,
                        'unit': c.unit,
                        'type': c.componentType,
                      },
                      details: {'recipeId': recipeId},
                    ),
                  );
                });
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
// EDIT COMPONENT QUANTITY/UNIT DIALOG
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
// ADD COMPONENT SHEET
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        // Material (not a plain decorated Container), same reasoning as in
        // _ProductForm above — keeps ink/background effects visible.
        child: Material(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    'For every ${widget.product.unit} of ${widget.product.name}, how much of something does it use?',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _StepLabel(
                    number: 1,
                    text: 'What kind of ingredient is this?',
                  ),
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
                            _selectedUnit = chosen.stockUnit;
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
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
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
                          : const Text(
                              'Add to Recipe',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
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

    if (!_allowed(context, ref, BosPermission.inventoryCreate)) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final audit = ref.read(auditLogServiceProvider);

    try {
      if (!_allowed(context, ref, BosPermission.inventoryCreate)) return;
      final componentId = const Uuid().v4();
      await db.transaction(() async {
        var recipe =
            await (db.select(db.recipes)
                  ..where((r) => r.productId.equals(widget.product.id)))
                .getSingleOrNull();
        recipe ??= await _ensureRecipeExists(db, widget.product.id);

        final ingredientName = _isSupply
            ? (await (db.select(
                    db.supplies,
                  )..where((s) => s.id.equals(_selectedId!))).getSingleOrNull())
                  ?.name
            : (await (db.select(
                    db.products,
                  )..where((p) => p.id.equals(_selectedId!))).getSingleOrNull())
                  ?.name;

        await db
            .into(db.recipeComponents)
            .insert(
              RecipeComponentsCompanion.insert(
                id: componentId,
                recipeId: recipe.id,
                componentType: _isSupply ? 'supply' : 'product',
                supplyId: Value(_isSupply ? _selectedId : null),
                componentProductId: Value(_isSupply ? null : _selectedId),
                quantityRequired: qty,
                unit: _selectedUnit!.trim(),
              ),
            );

        await audit.record(
          AuditEvent(
            module: AuditModule.inventory,
            actionType: AuditActionType.create,
            action: 'inventory.recipe_ingredient_added',
            entityType: 'recipe_components',
            entityId: componentId,
            entityLabel:
                '${widget.product.name} → ${ingredientName ?? _selectedId}',
            after: {
              'type': _isSupply ? 'supply' : 'product',
              'quantity': qty,
              'unit': _selectedUnit!.trim(),
            },
            details: {'recipeId': recipe.id},
          ),
        );
      });

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
