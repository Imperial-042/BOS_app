// lib/features/production/presentation/screens/pos_page.dart
//
// Point of Sale.
//
// MENU RULES
//   * Only sellable products with a sell price appear on the menu.
//   * Components (products NOT marked "Sold directly to customers", e.g. an
//     intermediate "Espresso Base") are exempt from needing a price and never
//     appear here — they exist only to be used inside other recipes.
//   * A tile is tappable only when it has a recipe AND enough stock.
//
// ORDER RULES
//   * If a product in the order is deleted/archived, its line is flagged
//     "no longer available" and checkout is blocked until it is removed.
//     The same check runs again inside Complete Sale against the database,
//     so a stale screen can never push a deleted product through.
//
// PAYMENT PROOF
//   * Optional: scan a GCash/GoTyme/etc. screenshot to record the reference
//     no., amount and date. Duplicate references are rejected.

import 'dart:async';
import 'dart:io';

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/core/navigation/nav_visibility.dart';
import 'package:bos_application/features/customer/presentation/customer_storefront_management_screen.dart'
    show CustomerOrdersInboxScreen;
import 'package:bos_application/features/transactions/presentation/screens/held_orders_sheet.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_sell_limit.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_shifts_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/manager_approval_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../transactions/presentation/providers/product_catalog_providers.dart'
    show productCategoriesProvider;
import '../../domain/pos_session_service.dart' show currentPosSessionProvider;
import '../widgets/pos_category_bar.dart';
import '../widgets/pos_session_widgets.dart';
import '../widgets/product_customization_sheet.dart';
import 'pos_checkout_sheet.dart';
import 'pos_history_page.dart';
import 'orders_page.dart';
import 'pos_order_state.dart';
import 'returns_page.dart';
// ignore: unused_shown_name
import 'products_page.dart' show productsProvider, producibilityProvider;

String _peso(int cents) => formatPeso(cents);

// ============================================================================
// MENU + AVAILABILITY PROVIDERS
// ============================================================================

/// Everything the cashier can pick from: sellable products that have a sell
/// price. Components (not sold directly, e.g. "Espresso Base") are exempt
/// from needing a price — since nobody buys them on their own — so they
/// never appear here; they only exist to be used inside other recipes.
final _posMenuProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  return products.where((p) => p.isSellable && p.sellPrice != null).toList();
});

// ============================================================================
// WIDE HEADER — tablet and bigger
// ============================================================================

/// A header action: icon + label pill (label drops on narrower screens).
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showLabel = true,
    this.badge = 0,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showLabel;
  final int badge;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : scheme.onSurface;
    final bg = danger
        ? scheme.errorContainer.withValues(alpha: 0.55)
        : scheme.primary.withValues(alpha: 0.08);

    return Tooltip(
      message: label,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 14 : 11,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: Icon(icon, size: 20, color: fg),
                ),
                if (showLabel) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The POS header for tablet+: brand badge, title, centred search and
/// action pills, on a soft tinted gradient.
class _PosWideHeader extends StatelessWidget implements PreferredSizeWidget {
  const _PosWideHeader({required this.search, required this.actions});

  final Widget search;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      child: Container(
        height: 84,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.5),
              scheme.surface,
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary,
                    scheme.primary.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.point_of_sale_rounded,
                color: scheme.onPrimary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Point of Sale',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 900)
                  Text(
                    'Tap a product to add it to the order',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: search,
                ),
              ),
            ),
            const SizedBox(width: 16),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              actions[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// IDs of every active product, or null while that is still loading.
/// A product that was deleted or archived is simply absent from this set.
Set<String>? _liveProductIds(WidgetRef ref) {
  return ref
      .watch(productsProvider)
      .maybeWhen<Set<String>?>(
        data: (products) => {for (final p in products) p.id},
        orElse: () => null,
      );
}

// ============================================================================
// PRODUCT AVATAR — real photo when available, otherwise a stable
// gradient + icon derived from the product itself. Never a blank box.
// ============================================================================

class _ProductAvatar extends StatelessWidget {
  final Product product;
  final double radius;

  const _ProductAvatar({required this.product, this.radius = 18});

  static const List<List<Color>> _gradients = [
    [Color(0xFFFF9A8B), Color(0xFFFF6A88)],
    [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
    [Color(0xFF6DD5FA), Color(0xFF2980B9)],
    [Color(0xFFFDCBF1), Color(0xFFACB6E5)],
    [Color(0xFFFFB347), Color(0xFFFF6961)],
    [Color(0xFF89F7FE), Color(0xFF66A6FF)],
    [Color(0xFFF6D365), Color(0xFFFDA085)],
    [Color(0xFFA1C4FD), Color(0xFF7367F0)],
    [Color(0xFF43E97B), Color(0xFF38F9D7)],
    [Color(0xFFFA8BFF), Color(0xFF2BD2FF)],
  ];

  static const List<IconData> _icons = [
    Icons.local_cafe_rounded,
    Icons.bakery_dining_rounded,
    Icons.icecream_rounded,
    Icons.lunch_dining_rounded,
    Icons.local_pizza_rounded,
    Icons.emoji_food_beverage_rounded,
    Icons.cake_rounded,
    Icons.restaurant_rounded,
    Icons.fastfood_rounded,
    Icons.set_meal_rounded,
    Icons.liquor_rounded,
    Icons.cookie_rounded,
  ];

  int get _seed => product.id.codeUnits.fold<int>(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.vertical(top: Radius.circular(radius));
    final imagePath = product.imagePath?.trim();

    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _placeholder(borderRadius),
        ),
      );
    }

    return _placeholder(borderRadius);
  }

  Widget _placeholder(BorderRadius borderRadius) {
    final gradient = _gradients[_seed % _gradients.length];
    final icon = _icons[_seed % _icons.length];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 44, color: Colors.white.withValues(alpha: 0.95)),
    );
  }
}

// ============================================================================
// MAIN PAGE
// ============================================================================

class POSPage extends ConsumerStatefulWidget {
  const POSPage({super.key});

  @override
  ConsumerState<POSPage> createState() => _POSPageState();
}

class _POSPageState extends ConsumerState<POSPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _categoryId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// [menu] is already limited to items that may be sold (see
  /// _posMenuProvider).
  List<Product> _filterProducts(List<Product> menu) {
    final query = _query.trim().toLowerCase();

    return menu.where((p) {
      if (_categoryId != null && p.categoryId != _categoryId) return false;
      if (query.isEmpty) return true;

      return p.name.toLowerCase().contains(query) ||
          (p.sku ?? '').toLowerCase().contains(query) ||
          (p.barcode ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || !mounted) return;
    _searchController.text = code;
    setState(() => _query = code);
  }

  void _openOrderSheet() => showPosOrderSheet(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final menuAsync = ref.watch(_posMenuProvider);
    final categoriesAsync = ref.watch(productCategoriesProvider);
    final order = ref.watch(posOrderProvider);
    final heldCount = ref.watch(heldOrdersProvider).length;
    final wide = MediaQuery.sizeOf(context).width >= kPosSplitBreakpoint;

    final sessionAsync = ref.watch(currentPosSessionProvider);
    final session = sessionAsync.value;

    final liveIds = _liveProductIds(ref);
    final unavailableCount = liveIds == null
        ? 0
        : order.where((l) => !liveIds.contains(l.productId)).length;

    final orderTotal = order
        .where((l) => liveIds == null || liveIds.contains(l.productId))
        .fold<int>(0, (sum, l) => sum + l.lineTotal);

    final orderCount = order.fold<int>(0, (sum, l) => sum + l.quantity);

    final labels = MediaQuery.sizeOf(context).width >= 1100;
    final canViewSales = ref.watch(canProvider(BosPermission.salesView));
    final canVoid = ref.watch(canProvider(BosPermission.salesVoid));

    Future<void> setPin() async {
      final saved = await showSetApprovalPinDialog(context);
      if (saved && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Approval PIN saved.')));
      }
    }

    final wideHeader = _PosWideHeader(
      search: _SearchField(
        controller: _searchController,
        onScan: _scan,
        onChanged: (value) => setState(() => _query = value),
        onClear: () {
          _searchController.clear();
          setState(() => _query = '');
        },
      ),
      actions: [
        if (canViewSales)
          _HeaderAction(
            icon: Icons.shopping_bag_outlined,
            label: 'Customer orders',
            showLabel: labels,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CustomerOrdersInboxScreen(
                  businessId: ref.read(selectedBusinessIdProvider),
                  branchId: ref.read(selectedBranchIdProvider),
                ),
              ),
            ),
          ),
        _HeaderAction(
          icon: Icons.history_rounded,
          label: 'History',
          showLabel: labels,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const POSHistoryPage()),
          ),
        ),
        _HeaderAction(
          icon: Icons.list_alt_rounded,
          label: 'Orders',
          showLabel: labels,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrdersPage()),
          ),
        ),
        if (canVoid)
          _HeaderAction(
            icon: Icons.assignment_return_outlined,
            label: 'Returns',
            showLabel: labels,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReturnsPage()),
            ),
          ),
        if (heldCount > 0)
          _HeaderAction(
            icon: Icons.pause_circle_outline_rounded,
            label: 'Held orders',
            showLabel: labels,
            badge: heldCount,
            onTap: () => showHeldOrdersSheet(context),
          ),
        _HeaderAction(
          icon: Icons.event_note_rounded,
          label: 'Shifts',
          showLabel: labels,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const POSShiftsPage()),
          ),
        ),
        if (canVoid)
          _HeaderAction(
            icon: Icons.pin_outlined,
            label: 'Approval PIN',
            showLabel: labels,
            onTap: setPin,
          ),
        if (session != null)
          _HeaderAction(
            icon: Icons.lock_clock_rounded,
            label: 'Close shift',
            showLabel: labels,
            danger: true,
            onTap: () => showCloseShiftSheet(context, ref, session),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: wide
          ? wideHeader
          : AppBar(
              automaticallyImplyLeading: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 20,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Point of Sale',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap a product to add it to the order',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Checkout history',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const POSHistoryPage()),
                  ),
                  icon: const Icon(Icons.history_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Orders and returns',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (value) => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => switch (value) {
                        'orders' => const OrdersPage(),
                        'customer-orders' => CustomerOrdersInboxScreen(
                          businessId: ref.read(selectedBusinessIdProvider),
                          branchId: ref.read(selectedBranchIdProvider),
                        ),
                        _ => const ReturnsPage(),
                      },
                    ),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'orders',
                      child: ListTile(
                        leading: Icon(Icons.list_alt_rounded),
                        title: Text('Orders'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (canViewSales)
                      const PopupMenuItem(
                        value: 'customer-orders',
                        child: ListTile(
                          leading: Icon(Icons.shopping_bag_outlined),
                          title: Text('Customer orders'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (ref.watch(canProvider(BosPermission.salesVoid)))
                      const PopupMenuItem(
                        value: 'returns',
                        child: ListTile(
                          leading: Icon(Icons.assignment_return_outlined),
                          title: Text('Returns'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
                if (ref.watch(canProvider(BosPermission.salesVoid)))
                  IconButton(
                    tooltip: 'Approval PIN',
                    icon: const Icon(Icons.pin_outlined),
                    onPressed: () async {
                      final saved = await showSetApprovalPinDialog(context);
                      if (saved && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Approval PIN saved.')),
                        );
                      }
                    },
                  ),
                if (heldCount > 0)
                  IconButton(
                    tooltip: 'Held orders',
                    onPressed: () => showHeldOrdersSheet(context),
                    icon: Badge.count(
                      count: heldCount,
                      child: const Icon(Icons.pause_circle_outline_rounded),
                    ),
                  ),
                IconButton(
                  tooltip: 'Shifts',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const POSShiftsPage()),
                  ),
                  icon: const Icon(Icons.event_note_rounded),
                ),
                if (session != null)
                  IconButton(
                    tooltip: 'Close shift',
                    onPressed: () => showCloseShiftSheet(context, ref, session),
                    icon: const Icon(Icons.lock_clock_rounded),
                  ),
                if (!wide)
                  _OrderHeaderButton(
                    itemCount: orderCount,
                    hasProblem: unavailableCount > 0,
                    onPressed: order.isEmpty ? null : _openOrderSheet,
                  ),
                const SizedBox(width: 8),
              ],
            ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Unable to load shift: $e')),
        data: (s) {
          if (s == null) return const PosShiftClosedView();

          final menuColumn = Column(
            children: [
              PosShiftBar(
                session: s,
                onClose: () => showCloseShiftSheet(context, ref, s),
              ),
              if (!wide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: _SearchField(
                    controller: _searchController,
                    onScan: _scan,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
                ),
              if (wide) const SizedBox(height: 10),
              categoriesAsync.when(
                data: (categories) => PosCategoryBar(
                  categories: categories,
                  selectedId: _categoryId,
                  onSelected: (id) => setState(() => _categoryId = id),
                ),
                loading: () => const SizedBox(height: 48),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: menuAsync.when(
                  // Keep the grid on screen while stock recalculates after a sale.
                  skipLoadingOnReload: true,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text('Unable to load products: $e')),
                  data: (menu) {
                    if (menu.isEmpty) return const _EmptyPOSState();

                    final filtered = _filterProducts(menu);
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          'No products match your search.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      );
                    }

                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        order.isEmpty || wide ? 24 : 100,
                      ),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: wide ? 200 : 150,
                        mainAxisSpacing: wide ? 14 : 10,
                        crossAxisSpacing: wide ? 14 : 10,
                        childAspectRatio: 1,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _POSProductTile(product: filtered[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          );

          if (!wide) return menuColumn;

          // Tablet: menu on the left, current order + checkout on the right.
          // Tablet+: catalog on the left, order + checkout always open on
          // the right.
          final panelWidth = (MediaQuery.sizeOf(context).width * 0.32)
              .clamp(340.0, 440.0)
              .toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: menuColumn),
              const VerticalDivider(width: 1),
              SizedBox(width: panelWidth, child: const PosOrderPanel()),
            ],
          );
        },
      ),
      bottomNavigationBar: (session == null || order.isEmpty || wide)
          ? null
          : _ChargeBar(
              count: orderCount,
              total: orderTotal,
              problems: unavailableCount,
              onTap: () {
                HapticFeedback.mediumImpact();
                _openOrderSheet();
              },
            ),
    );
  }
}

// ============================================================================
// SEARCH FIELD
// ============================================================================

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback? onScan;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search or scan items...',
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            if (onScan != null)
              IconButton(
                tooltip: 'Scan barcode',
                onPressed: onScan,
                icon: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ============================================================================
// PRODUCT TILE
// ============================================================================

enum _Availability { available, checking, outOfStock, noRecipe, unavailable }

extension on _Availability {
  bool get canSell => this == _Availability.available;

  /// Text laid over the product photo when the tile can't be sold.
  String? get overlayLabel => switch (this) {
    _Availability.outOfStock => 'OUT OF STOCK',
    _Availability.noRecipe => 'NO RECIPE',
    _Availability.unavailable => 'UNAVAILABLE',
    _ => null,
  };

  /// Explains why a tap did nothing. Null while we're still checking.
  String? blockedMessage(String name, {String? limiting}) => switch (this) {
    _Availability.noRecipe =>
      '$name has no ingredients yet. Add a recipe in Products & Recipes '
          'before selling it.',
    _Availability.outOfStock =>
      limiting == null
          ? '$name can\'t be made right now — its ingredients are out of '
                'stock.'
          : '$name can\'t be made right now — out of $limiting.',
    _Availability.unavailable =>
      'Couldn\'t check stock for $name. Please try again.',
    _ => null,
  };
}

class _POSProductTile extends ConsumerWidget {
  final Product product;

  const _POSProductTile({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limitAsync = ref.watch(sellLimitProvider(product.id));
    final inOrder = ref.watch(
      posOrderProvider.select((o) {
        for (final l in o) {
          if (l.productId == product.id) return l.quantity;
        }
        return 0;
      }),
    );

    return limitAsync.when(
      skipLoadingOnReload: true,
      data: (limit) {
        if (limit.noRecipe) {
          return _POSTileCard(
            product: product,
            inOrder: inOrder,
            availability: _Availability.noRecipe,
            stockBadge: const _NoRecipeBadge(),
          );
        }

        final max = limit.maxUnits;
        if (max == null) {
          // Service / untracked item: always sellable, no stock badge.
          return _POSTileCard(
            product: product,
            inOrder: inOrder,
            availability: _Availability.available,
            stockBadge: null,
          );
        }

        final left = max - inOrder;
        return _POSTileCard(
          product: product,
          inOrder: inOrder,
          maxUnits: max,
          limiting: limit.limiting,
          availability: max <= 0
              ? _Availability.outOfStock
              : _Availability.available,
          stockBadge: _StockBadgeText(
            maxUnits: left < 0 ? 0 : left,
            unit: product.unit,
            allInOrder: inOrder > 0 && left <= 0,
          ),
        );
      },
      loading: () => _POSTileCard(
        product: product,
        inOrder: inOrder,
        availability: _Availability.checking,
        stockBadge: null,
      ),
      error: (_, __) => _POSTileCard(
        product: product,
        inOrder: inOrder,
        availability: _Availability.unavailable,
        stockBadge: null,
      ),
    );
  }
}

class _NoRecipeBadge extends StatelessWidget {
  const _NoRecipeBadge();

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Add ingredients',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StockBadgeText extends StatelessWidget {
  final int maxUnits;
  final String unit;
  final bool allInOrder;

  const _StockBadgeText({
    required this.maxUnits,
    required this.unit,
    this.allInOrder = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = allInOrder
        ? Colors.orange.shade800
        : maxUnits <= 0
        ? Colors.redAccent
        : (maxUnits <= 10 ? Colors.orange.shade800 : Colors.green.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        allInOrder
            ? 'All in order'
            : maxUnits <= 0
            ? 'Out of stock'
            : '$maxUnits $unit left',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _POSTileCard extends ConsumerStatefulWidget {
  final Product product;
  final _Availability availability;
  final Widget? stockBadge;
  final int? maxUnits;
  final String? limiting;
  final int inOrder;

  const _POSTileCard({
    required this.product,
    required this.availability,
    required this.stockBadge,
    this.maxUnits,
    this.limiting,
    this.inOrder = 0,
  });

  @override
  ConsumerState<_POSTileCard> createState() => _POSTileCardState();
}

class _POSTileCardState extends ConsumerState<_POSTileCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    lowerBound: 0.0,
    upperBound: 0.05,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _controller.forward();

  void _onTapCancel() => _controller.reverse();

  Future<void> _onTapUp(TapUpDetails _) async {
    _controller.reverse();

    // Last line of defence: never add anything that isn't sellable, even if
    // a stale tap arrives right as the tile's state changes.
    if (!widget.availability.canSell) return;

    final options = await showProductCustomizationSheet(
      context,
      ref,
      widget.product,
    );
    if (!mounted || options == null) return;
    final added = options.isEmpty
        ? ref
              .read(posOrderProvider.notifier)
              .addOrIncrement(widget.product, maxUnits: widget.maxUnits)
        : ref
              .read(posOrderProvider.notifier)
              .addConfigured(
                widget.product,
                options,
                maxUnits: widget.maxUnits,
              );

    if (!added) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Text(
              'Only ${widget.maxUnits} ${widget.product.unit} of '
              '${widget.product.name} available — all are in the order.',
            ),
          ),
        );
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 850),
          content: Text('${widget.product.name} added'),
        ),
      );
  }

  /// Tapping a blocked tile tells the cashier why, instead of doing nothing.
  void _showBlockedMessage() {
    final message = widget.availability.blockedMessage(
      widget.product.name,
      limiting: widget.limiting,
    );
    if (message == null) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final product = widget.product;
    final availability = widget.availability;
    final canSell = availability.canSell;
    final overlayLabel = availability.overlayLabel;
    final hasPrice = product.sellPrice != null;
    final inOrder = widget.inOrder;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Transform.scale(scale: 1 - _controller.value, child: child),
      child: Opacity(
        opacity: canSell
            ? 1
            : (availability == _Availability.checking ? 0.7 : 0.55),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: inOrder > 0
                ? Border.all(color: scheme.primary, width: 2.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: (inOrder > 0 ? scheme.primary : Colors.black).withValues(
                  alpha: inOrder > 0 ? 0.28 : 0.10,
                ),
                blurRadius: inOrder > 0 ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(inOrder > 0 ? 17 : 20),
            child: Material(
              color: scheme.surfaceContainerLow,
              child: InkWell(
                onTapDown: canSell ? _onTapDown : null,
                onTapCancel: canSell ? _onTapCancel : null,
                onTapUp: canSell
                    ? (d) {
                        HapticFeedback.selectionClick();
                        unawaited(_onTapUp(d));
                      }
                    : null,
                onTap: canSell || availability == _Availability.checking
                    ? null
                    : _showBlockedMessage,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ProductAvatar(product: product, radius: 0),
                    // dark fade so the name is always readable
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Color(0xCC000000),
                          ],
                          stops: [0, 0.38, 1],
                        ),
                      ),
                    ),
                    if (overlayLabel != null)
                      Container(
                        color: Colors.black38,
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            overlayLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 10.5,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    if (widget.stockBadge != null && overlayLabel == null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: widget.stockBadge!,
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (c, a) =>
                            ScaleTransition(scale: a, child: c),
                        child: inOrder > 0
                            ? Container(
                                key: ValueKey(inOrder),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: scheme.primary.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '$inOrder',
                                  style: TextStyle(
                                    color: scheme.onPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey(0)),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 9,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              height: 1.15,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black54),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasPrice ? _peso(product.sellPrice!) : 'No price',
                            style: TextStyle(
                              color: hasPrice
                                  ? Colors.white
                                  : Colors.orange.shade200,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              shadows: const [
                                Shadow(blurRadius: 6, color: Colors.black54),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyPOSState extends StatelessWidget {
  const _EmptyPOSState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.point_of_sale_outlined,
                size: 34,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Nothing to sell yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Mark a product as sellable and give it a sell price in '
              'Products & Recipes to see it here. Components appear once '
              'they have ingredients.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ORDER HEADER BUTTON
// ============================================================================

class _OrderHeaderButton extends StatelessWidget {
  final int itemCount;

  /// True when the order contains something that must be removed.
  final bool hasProblem;
  final VoidCallback? onPressed;

  const _OrderHeaderButton({
    required this.itemCount,
    required this.hasProblem,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: hasProblem
              ? 'Current order — needs attention'
              : 'Current order',
          onPressed: onPressed,
          icon: Icon(
            Icons.receipt_long_rounded,
            color: hasProblem ? scheme.error : null,
          ),
        ),
        if (itemCount > 0)
          Positioned(
            top: 4,
            right: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.error,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Text(
                itemCount > 99 ? '99+' : '$itemCount',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onError,
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

class _ChargeBar extends StatelessWidget {
  final int count;
  final int total;
  final int problems;
  final VoidCallback onTap;

  const _ChargeBar({
    required this.count,
    required this.total,
    required this.problems,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary,
                    Color.lerp(scheme.primary, Colors.black, 0.25)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
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
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.shopping_bag_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CHARGE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: total.toDouble()),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => Text(
                            _peso(v.round()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (problems > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.error_rounded,
                        color: Colors.amber.shade300,
                      ),
                    ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
