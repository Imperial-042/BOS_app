import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId, transactionServiceProvider;

// ============================================================================
// HELPERS
// ============================================================================

String _peso(int cents) {
  return '₱${NumberFormat('#,##0.00').format(cents / 100)}';
}

String _formatDate(DateTime date) {
  return DateFormat('MMM d, yyyy').format(date);
}

String _formatDateShort(DateTime date) {
  return DateFormat('MMM d').format(date);
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

// ============================================================================
// SUPPLIES PROVIDERS
// ============================================================================

final suppliesProvider = StreamProvider<List<Supply>>((ref) {
  final db = ref.watch(databaseProvider);

  return (db.select(db.supplies)
        ..where(
          (s) =>
              s.businessId.equals(kCurrentBusinessId) & s.isActive.equals(true),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch();
});

final priceHistoryProvider =
    StreamProvider.family<List<SupplyPriceHistoryData>, String>((
      ref,
      supplyId,
    ) {
      final db = ref.watch(databaseProvider);

      return (db.select(db.supplyPriceHistory)
            ..where((h) => h.supplyId.equals(supplyId))
            ..orderBy([
              (h) => OrderingTerm(
                expression: h.recordedDate,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();
    });

// ============================================================================
// CART
// ============================================================================

class CartItem {
  final String id;
  final String? supplyId;
  final String name;
  final String? unit;
  final int unitPrice;
  final int quantity;

  const CartItem({
    required this.id,
    this.supplyId,
    required this.name,
    this.unit,
    required this.unitPrice,
    required this.quantity,
  });

  int get lineTotal => unitPrice * quantity;

  CartItem copyWith({
    String? id,
    String? supplyId,
    String? name,
    String? unit,
    int? unitPrice,
    int? quantity,
  }) {
    return CartItem(
      id: id ?? this.id,
      supplyId: supplyId ?? this.supplyId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addOrIncrement(Supply supply) {
    final existingIndex = state.indexWhere(
      (item) => item.supplyId == supply.id,
    );

    if (existingIndex >= 0) {
      final existing = state[existingIndex];

      final updated = existing.copyWith(quantity: existing.quantity + 1);

      state = [
        ...state.sublist(0, existingIndex),
        updated,
        ...state.sublist(existingIndex + 1),
      ];

      return;
    }

    state = [
      ...state,
      CartItem(
        id: const Uuid().v4(),
        supplyId: supply.id,
        name: supply.name,
        unit: supply.unit,
        unitPrice: supply.currentPrice,
        quantity: 1,
      ),
    ];
  }

  void addCustomItem({
    required String name,
    required int unitPrice,
    String? unit,
  }) {
    state = [
      ...state,
      CartItem(
        id: const Uuid().v4(),
        name: name,
        unit: unit,
        unitPrice: unitPrice,
        quantity: 1,
      ),
    ];
  }

  void updateQuantity(String id, int quantity) {
    if (quantity <= 0) {
      removeItem(id);
      return;
    }

    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(quantity: quantity) else item,
    ];
  }

  void updatePrice(String id, int price) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(unitPrice: price) else item,
    ];
  }

  void updateName(String id, String name) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(name: name) else item,
    ];
  }

  void removeItem(String id) {
    state = state.where((item) => item.id != id).toList();
  }

  void clear() {
    state = [];
  }

  int get total {
    return state.fold<int>(0, (sum, item) => sum + item.lineTotal);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

// ============================================================================
// PRICE TREND
// ============================================================================

enum _Trend { up, down, same, none }

_Trend _trendFor(List<SupplyPriceHistoryData> history) {
  if (history.length < 2) {
    return _Trend.none;
  }

  final latest = history[0].price;
  final previous = history[1].price;

  if (latest > previous) return _Trend.up;
  if (latest < previous) return _Trend.down;

  return _Trend.same;
}

// ============================================================================
// MAIN PAGE
// ============================================================================

class SuppliesPriceListPage extends ConsumerStatefulWidget {
  const SuppliesPriceListPage({super.key});

  @override
  ConsumerState<SuppliesPriceListPage> createState() =>
      _SuppliesPriceListPageState();
}

class _SuppliesPriceListPageState extends ConsumerState<SuppliesPriceListPage> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Supply> _filterSupplies(List<Supply> supplies) {
    final query = _query.trim().toLowerCase();

    if (query.isEmpty) {
      return supplies;
    }

    return supplies.where((supply) {
      final name = supply.name.toLowerCase();
      final unit = (supply.unit ?? '').toLowerCase();

      return name.contains(query) || unit.contains(query);
    }).toList();
  }

  Future<void> _refresh() async {
    ref.invalidate(suppliesProvider);

    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _openAddSupplySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupplyForm(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final suppliesAsync = ref.watch(suppliesProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Supplies',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Prices & suppliers',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          _CartHeaderButton(
            itemCount: cart.length,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartPage()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: suppliesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorState(
          message: 'Unable to load supplies.',
          onRetry: () => ref.invalidate(suppliesProvider),
        ),
        data: (supplies) {
          final filteredSupplies = _filterSupplies(supplies);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (supplies.isEmpty)
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.62,
                          child: _EmptyState(onAdd: _openAddSupplySheet),
                        )
                      else ...[
                        _SupplyOverviewCard(
                          totalSupplies: supplies.length,
                          visibleSupplies: filteredSupplies.length,
                          cartCount: cart.length,
                        ),
                        const SizedBox(height: 16),
                        _SearchField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _query = value;
                            });
                          },
                          onClear: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                            });
                          },
                        ),
                        const SizedBox(height: 22),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                _query.trim().isEmpty
                                    ? 'Price catalog'
                                    : 'Search results',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${filteredSupplies.length}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (filteredSupplies.isEmpty)
                          _NoSearchResults(
                            query: _query,
                            onClear: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                              });
                            },
                          )
                        else
                          ...filteredSupplies.map(
                            (supply) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SupplyCard(supply: supply),
                            ),
                          ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddSupplySheet,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

// ============================================================================
// HEADER CART BUTTON
// ============================================================================

class _CartHeaderButton extends StatelessWidget {
  final int itemCount;
  final VoidCallback onPressed;

  const _CartHeaderButton({required this.itemCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Shopping cart',
          onPressed: onPressed,
          icon: const Icon(Icons.shopping_cart_outlined),
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

// ============================================================================
// OVERVIEW CARD
// ============================================================================

class _SupplyOverviewCard extends StatelessWidget {
  final int totalSupplies;
  final int visibleSupplies;
  final int cartCount;

  const _SupplyOverviewCard({
    required this.totalSupplies,
    required this.visibleSupplies,
    required this.cartCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bool isSearching = visibleSupplies != totalSupplies;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          // Use the available width of THIS CARD.
          // This is more reliable than MediaQuery for nested layouts.
          final bool compact = width < 380;
          final bool ultraCompact = width < 330;

          final double padding = ultraCompact
              ? 12
              : compact
              ? 14
              : 18;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ============================================================
                // HEADER
                // ============================================================

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Container(
                      width: compact ? 40 : 44,
                      height: compact ? 40 : 44,
                      decoration: BoxDecoration(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: compact ? 20 : 22,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),

                    SizedBox(width: compact ? 8 : 12),

                    // Text MUST be constrained.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isSearching
                                ? '$visibleSupplies matching supplies'
                                : '$totalSupplies supply items',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: compact ? 16 : null,
                              fontWeight: FontWeight.w900,
                              color: scheme.onPrimaryContainer,
                              letterSpacing: -0.4,
                            ),
                          ),

                          const SizedBox(height: 3),

                          Text(
                            'Keep your frequently purchased prices in one place.',
                            maxLines: compact ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: compact ? 10.5 : null,
                              color: scheme.onPrimaryContainer.withValues(
                                alpha: 0.78,
                              ),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: compact ? 14 : 18),

                // ============================================================
                // METRICS
                // ============================================================
                if (ultraCompact)
                  // ----------------------------------------------------------
                  // VERY SMALL PHONE
                  // ----------------------------------------------------------
                  Column(
                    children: [
                      _OverviewMetric(
                        icon: Icons.sell_outlined,
                        label: 'Catalog',
                        value: '$totalSupplies',
                        foreground: scheme.onPrimaryContainer,
                        vertical: true,
                      ),

                      const SizedBox(height: 10),

                      Container(
                        width: double.infinity,
                        height: 1,
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.12,
                        ),
                      ),

                      const SizedBox(height: 10),

                      _OverviewMetric(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Cart',
                        value: '$cartCount',
                        foreground: scheme.onPrimaryContainer,
                        vertical: true,
                      ),
                    ],
                  )
                else
                  // ----------------------------------------------------------
                  // NORMAL PHONE
                  // ----------------------------------------------------------
                  Row(
                    children: [
                      Expanded(
                        child: _OverviewMetric(
                          icon: Icons.sell_outlined,
                          label: 'Catalog',
                          value: '$totalSupplies',
                          foreground: scheme.onPrimaryContainer,
                        ),
                      ),

                      Container(
                        width: 1,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.12,
                        ),
                      ),

                      Expanded(
                        child: _OverviewMetric(
                          icon: Icons.shopping_cart_outlined,
                          label: 'Cart',
                          value: '$cartCount',
                          foreground: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// OVERVIEW METRIC
// ============================================================================

class _OverviewMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color foreground;
  final bool vertical;

  const _OverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.foreground,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground.withValues(alpha: 0.72)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$value $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground.withValues(alpha: 0.72)),

          const SizedBox(width: 6),

          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.68),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================================
// SEARCH
// ============================================================================

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search supplies...',
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
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
    );
  }
}

// ============================================================================
// SUPPLY CARD
// ============================================================================

class _SupplyCard extends ConsumerWidget {
  final Supply supply;

  const _SupplyCard({required this.supply});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final historyAsync = ref.watch(priceHistoryProvider(supply.id));

    final cart = ref.watch(cartProvider);

    final inCart = cart.where((item) => item.supplyId == supply.id);

    final quantityInCart = inCart.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SupplyDetailPage(supply: supply)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              _SupplyAvatar(name: supply.name),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supply.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (supply.unit != null &&
                            supply.unit!.trim().isNotEmpty) ...[
                          Icon(
                            Icons.straighten_outlined,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'per ${supply.unit}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        historyAsync.when(
                          data: (history) {
                            final trend = _trendFor(history);

                            if (trend == _Trend.none) {
                              return const SizedBox.shrink();
                            }

                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _TrendBadge(trend: trend),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _peso(supply.currentPrice),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.primary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filled(
                    tooltip: 'Add to cart',
                    onPressed: () {
                      ref.read(cartProvider.notifier).addOrIncrement(supply);

                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(milliseconds: 1100),
                            content: Text('${supply.name} added to cart'),
                          ),
                        );
                    },
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                  ),
                  if (quantityInCart > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$quantityInCart in cart',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SUPPLY AVATAR
// ============================================================================

class _SupplyAvatar extends StatelessWidget {
  final String name;

  const _SupplyAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ============================================================================
// TREND BADGE
// ============================================================================

class _TrendBadge extends StatelessWidget {
  final _Trend trend;

  const _TrendBadge({required this.trend});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    late final IconData icon;
    late final String label;
    late final Color color;

    switch (trend) {
      case _Trend.up:
        icon = Icons.trending_up_rounded;
        label = 'Higher';
        color = scheme.error;
        break;

      case _Trend.down:
        icon = Icons.trending_down_rounded;
        label = 'Lower';
        color = Colors.green;
        break;

      case _Trend.same:
        icon = Icons.trending_flat_rounded;
        label = 'Same';
        color = scheme.onSurfaceVariant;
        break;

      case _Trend.none:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// NO SEARCH RESULTS
// ============================================================================

class _NoSearchResults extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _NoSearchResults({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              color: scheme.onSurfaceVariant,
              size: 27,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No supplies found',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Nothing matches "$query".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 15),
          OutlinedButton(onPressed: onClear, child: const Text('Clear search')),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

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
                Icons.inventory_2_outlined,
                size: 34,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No supplies yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Create your first supply item to start building your price catalog.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add supply'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ERROR STATE
// ============================================================================

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

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
            Icon(Icons.error_outline_rounded, size: 46, color: scheme.error),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ADD SUPPLY FORM
// ============================================================================

class _SupplyForm extends ConsumerStatefulWidget {
  const _SupplyForm();

  @override
  ConsumerState<_SupplyForm> createState() => _SupplyFormState();
}

class _SupplyFormState extends ConsumerState<_SupplyForm> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _storeController = TextEditingController();
  final _addressController = TextEditingController();

  String? _selectedUnit;
  bool _saving = false;

  static const List<String> _units = [
    'sack',
    'kg',
    'box',
    'pack',
    'liter',
    'piece',
    'roll',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _storeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final normalizedPrice = _priceController.text.replaceAll(',', '').trim();

    final price = double.tryParse(normalizedPrice);

    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid price.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = ref.read(databaseProvider);

      final supplyId = const Uuid().v4();
      final now = DateTime.now();
      final priceCents = (price * 100).round();

      await db
          .into(db.supplies)
          .insert(
            SuppliesCompanion.insert(
              id: supplyId,
              businessId: kCurrentBusinessId,
              name: _nameController.text.trim(),
              unit: Value(_selectedUnit),
              currentPrice: priceCents,
              updatedAt: Value(now),
              isActive: const Value(true),
            ),
          );

      await db
          .into(db.supplyPriceHistory)
          .insert(
            SupplyPriceHistoryCompanion.insert(
              id: const Uuid().v4(),
              supplyId: supplyId,
              price: priceCents,
              storeName: _storeController.text.trim(),
              storeAddress: Value(
                _addressController.text.trim().isEmpty
                    ? null
                    : _addressController.text.trim(),
              ),
              recordedDate: now,
            ),
          );

      ref.invalidate(suppliesProvider);
      ref.invalidate(priceHistoryProvider(supplyId));

      if (mounted) {
        final savedName = _nameController.text.trim();

        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('$savedName added to your catalog'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to save supply: $e'),
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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive horizontal padding.
            final horizontalPadding = constraints.maxWidth < 360 ? 14.0 : 20.0;

            // Below 390px, stack Price + Unit vertically.
            final isNarrow = constraints.maxWidth < 390;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                10,
                horizontalPadding,
                24,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ----------------------------------------------------------
                    // SHEET HANDLE
                    // ----------------------------------------------------------
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

                    const SizedBox(height: 20),

                    // ----------------------------------------------------------
                    // HEADER
                    // ----------------------------------------------------------
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.add_box_outlined,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add supply item',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Add the current price to your catalog.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),

                    // ----------------------------------------------------------
                    // ITEM DETAILS
                    // ----------------------------------------------------------
                    const _SectionLabel(
                      title: 'Item details',
                      icon: Icons.inventory_2_outlined,
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Supply name',
                        hintText: 'e.g. Rice fertilizer',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a supply name';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    // ----------------------------------------------------------
                    // RESPONSIVE PRICE + UNIT
                    // ----------------------------------------------------------
                    if (isNarrow) ...[
                      // SMALL PHONE
                      TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Current price',
                          prefixText: '₱ ',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (value) {
                          final normalized = value?.replaceAll(',', '').trim();

                          final parsed = double.tryParse(normalized ?? '');

                          if (parsed == null || parsed < 0) {
                            return 'Enter a valid price';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: _selectedUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          prefixIcon: Icon(Icons.straighten_outlined),
                        ),
                        items: _units
                            .map(
                              (unit) => DropdownMenuItem<String>(
                                value: unit,
                                child: Text(
                                  _capitalize(unit),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedUnit = value;
                          });
                        },
                      ),
                    ] else ...[
                      // NORMAL / LARGE PHONE / TABLET
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Current price',
                                prefixText: '₱ ',
                                prefixIcon: Icon(Icons.payments_outlined),
                              ),
                              validator: (value) {
                                final normalized = value
                                    ?.replaceAll(',', '')
                                    .trim();

                                final parsed = double.tryParse(
                                  normalized ?? '',
                                );

                                if (parsed == null || parsed < 0) {
                                  return 'Enter a valid price';
                                }

                                return null;
                              },
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedUnit,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                prefixIcon: Icon(Icons.straighten_outlined),
                              ),
                              items: _units
                                  .map(
                                    (unit) => DropdownMenuItem<String>(
                                      value: unit,
                                      child: Text(
                                        _capitalize(unit),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedUnit = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ----------------------------------------------------------
                    // SUPPLIER DETAILS
                    // ----------------------------------------------------------
                    const _SectionLabel(
                      title: 'Where you bought it',
                      icon: Icons.storefront_outlined,
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _storeController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Store / supplier',
                        hintText: 'Optional',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _addressController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        hintText: 'Optional',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),

                    const SizedBox(height: 26),

                    // ----------------------------------------------------------
                    // SAVE BUTTON
                    // ----------------------------------------------------------
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          _saving ? 'Saving...' : 'Save supply',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// SECTION LABEL
// ============================================================================

class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionLabel({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.primary),
        const SizedBox(width: 7),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SUPPLY DETAIL
// ============================================================================

class SupplyDetailPage extends ConsumerWidget {
  final Supply supply;

  const SupplyDetailPage({super.key, required this.supply});

  Future<void> _addPriceEntry(BuildContext context, WidgetRef ref) async {
    final priceController = TextEditingController();
    final storeController = TextEditingController();
    final addressController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          title: const Text('Record new price'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  supply.name,
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixText: '₱ ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: storeController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Store / supplier',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final normalized = priceController.text
                    .replaceAll(',', '')
                    .trim();

                final price = double.tryParse(normalized);

                if (price == null || price < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid price.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                final db = ref.read(databaseProvider);
                final now = DateTime.now();
                final cents = (price * 100).round();

                await db
                    .into(db.supplyPriceHistory)
                    .insert(
                      SupplyPriceHistoryCompanion.insert(
                        id: const Uuid().v4(),
                        supplyId: supply.id,
                        price: cents,
                        storeName: storeController.text.trim().isEmpty
                            ? 'Unknown store'
                            : storeController.text.trim(),
                        storeAddress: Value(
                          addressController.text.trim().isEmpty
                              ? null
                              : addressController.text.trim(),
                        ),
                        recordedDate: now,
                      ),
                    );

                await (db.update(
                  db.supplies,
                )..where((s) => s.id.equals(supply.id))).write(
                  SuppliesCompanion(
                    currentPrice: Value(cents),
                    updatedAt: Value(now),
                  ),
                );

                ref.invalidate(priceHistoryProvider(supply.id));
                ref.invalidate(suppliesProvider);

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save price'),
            ),
          ],
        );
      },
    );

    priceController.dispose();
    storeController.dispose();
    addressController.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete supply?'),
          content: Text(
            'This will remove "${supply.name}" and its recorded price history.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final db = ref.read(databaseProvider);

    await (db.delete(
      db.supplyPriceHistory,
    )..where((h) => h.supplyId.equals(supply.id))).go();

    await (db.delete(db.supplies)..where((s) => s.id.equals(supply.id))).go();

    ref.invalidate(suppliesProvider);
    ref.invalidate(priceHistoryProvider(supply.id));

    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final historyAsync = ref.watch(priceHistoryProvider(supply.id));

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              supply.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              supply.unit == null
                  ? 'Price history'
                  : 'Price per ${supply.unit}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add price',
            onPressed: () => _addPriceEntry(context, ref),
            icon: const Icon(Icons.add_chart_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete(context, ref);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded),
                    SizedBox(width: 10),
                    Text('Delete supply'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorState(
          message: 'Unable to load price history.',
          onRetry: () {
            ref.invalidate(priceHistoryProvider(supply.id));
          },
        ),
        data: (history) {
          final cheapest = history.isEmpty
              ? null
              : history.reduce((a, b) => a.price <= b.price ? a : b);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _CurrentPriceCard(supply: supply, history: history),
              if (cheapest != null) ...[
                const SizedBox(height: 12),
                _CheapestPriceCard(
                  price: cheapest.price,
                  store: cheapest.storeName,
                  date: cheapest.recordedDate,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Price history',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${history.length} record${history.length == 1 ? '' : 's'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'No price history recorded yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                ...history.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _PriceHistoryCard(entry: entry),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// CURRENT PRICE CARD
// ============================================================================

class _CurrentPriceCard extends StatelessWidget {
  final Supply supply;
  final List<SupplyPriceHistoryData> history;

  const _CurrentPriceCard({required this.supply, required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final trend = _trendFor(history);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sell_outlined,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 7),
              Text(
                'CURRENT PRICE',
                style: TextStyle(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.70),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (trend != _Trend.none) _TrendBadge(trend: trend),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _peso(supply.currentPrice),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          if (supply.unit != null) ...[
            const SizedBox(height: 3),
            Text(
              'per ${supply.unit}',
              style: TextStyle(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// CHEAPEST PRICE
// ============================================================================

class _CheapestPriceCard extends StatelessWidget {
  final int price;
  final String? store;
  final DateTime date;

  const _CheapestPriceCard({
    required this.price,
    required this.store,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.savings_outlined, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BEST RECORDED PRICE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _peso(price),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (store != null && store!.trim().isNotEmpty) store!,
                    _formatDateShort(date),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PRICE HISTORY CARD
// ============================================================================

class _PriceHistoryCard extends StatelessWidget {
  final SupplyPriceHistoryData entry;

  const _PriceHistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _peso(entry.price),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (entry.storeName.trim().isNotEmpty) entry.storeName,
                    _formatDate(entry.recordedDate),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (entry.storeAddress != null &&
                    entry.storeAddress!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.storeAddress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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

// ============================================================================
// CART PAGE
// ============================================================================

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  final _storeController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _storeController.dispose();
    super.dispose();
  }

  Future<void> _addCustomItem() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final unitController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add custom item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Unit price',
                    prefixText: '₱ ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    hintText: 'Optional',
                    prefixIcon: Icon(Icons.straighten_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();

                final normalized = priceController.text
                    .replaceAll(',', '')
                    .trim();

                final price = double.tryParse(normalized);

                if (name.isEmpty || price == null || price < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid item name and price.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                ref
                    .read(cartProvider.notifier)
                    .addCustomItem(
                      name: name,
                      unitPrice: (price * 100).round(),
                      unit: unitController.text.trim().isEmpty
                          ? null
                          : unitController.text.trim(),
                    );

                Navigator.pop(dialogContext);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    priceController.dispose();
    unitController.dispose();
  }

  Future<void> _saveCart() async {
    final cart = ref.read(cartProvider);

    if (cart.isEmpty) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = ref.read(databaseProvider);

      // ----------------------------------------------------------------------
      // Find the "Supplies" expense category using the current categories
      // table/API.
      // ----------------------------------------------------------------------

      final categories =
          await (db.select(db.categories)..where(
                (c) =>
                    c.businessId.equals(kCurrentBusinessId) &
                    c.txnType.equals('expense') &
                    c.isActive.equals(true),
              ))
              .get();

      Category? suppliesCategory;

      for (final category in categories) {
        if (category.name.trim().toLowerCase() == 'supplies') {
          suppliesCategory = category;
          break;
        }
      }

      if (suppliesCategory == null) {
        throw Exception('The "Supplies" expense category was not found.');
      }

      // ----------------------------------------------------------------------
      // Find an active payment account.
      //
      // The current Account schema does not expose "isDefault", so we use
      // the first active payment account.
      // ----------------------------------------------------------------------

      final paymentAccounts =
          await (db.select(db.accounts)..where(
                (a) =>
                    a.businessId.equals(kCurrentBusinessId) &
                    a.isPaymentAccount.equals(true) &
                    a.isActive.equals(true),
              ))
              .get();

      if (paymentAccounts.isEmpty) {
        throw Exception('No active payment account is configured.');
      }

      final paymentAccount = paymentAccounts.first;

      final total = cart.fold<int>(0, (sum, item) => sum + item.lineTotal);

      // ----------------------------------------------------------------------
      // Record the purchase through the same transaction service used by
      // the normal Expense screen.
      // ----------------------------------------------------------------------

      final transactionService = ref.read(transactionServiceProvider);

      final purchaseDate = DateTime.now();

      await transactionService.saveExpense(
        date: purchaseDate,
        categoryId: suppliesCategory.id,
        amount: total,
        paymentAccountId: paymentAccount.id,
        description: 'Supplies purchase',
        markAsPending: false,
      );

      // ----------------------------------------------------------------------
      // Save the shopping cart record.
      // ----------------------------------------------------------------------

      final cartId = const Uuid().v4();

      final storeName = _storeController.text.trim().isEmpty
          ? null
          : _storeController.text.trim();

      await db
          .into(db.shoppingCarts)
          .insert(
            ShoppingCartsCompanion.insert(
              id: cartId,
              businessId: kCurrentBusinessId,
              cartDate: purchaseDate,
              storeName: Value(storeName),
              storeAddress: const Value(null),
              totalAmount: total,
            ),
          );

      // ----------------------------------------------------------------------
      // Save each cart line.
      // ----------------------------------------------------------------------

      for (final item in cart) {
        await db
            .into(db.shoppingCartItems)
            .insert(
              ShoppingCartItemsCompanion.insert(
                id: const Uuid().v4(),
                cartId: cartId,
                supplyId: Value(item.supplyId),
                itemName: item.name,
                unitPrice: item.unitPrice,
                quantity: Value(item.quantity),
                lineTotal: item.lineTotal,
              ),
            );
      }

      ref.read(cartProvider.notifier).clear();

      // Force dashboard/ledger listeners to refresh.
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Purchase saved and recorded as an expense.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to save purchase: $e'),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final cart = ref.watch(cartProvider);

    final total = cart.fold<int>(0, (sum, item) => sum + item.lineTotal);

    final totalQuantity = cart.fold<int>(0, (sum, item) => sum + item.quantity);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shopping cart',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 2),
            Text(
              'Review your purchase',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: cart.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shopping_cart_outlined,
                        size: 35,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your cart is empty',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Add supplies from your price catalog to build a purchase.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Browse supplies'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 170),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shopping_basket_outlined,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$totalQuantity units · ${cart.length} line${cart.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _peso(total),
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Purchase details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _storeController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Store / supplier',
                    hintText: 'Optional',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                ...cart.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CartItemTile(item: item),
                  ),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _addCustomItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add custom item'),
                ),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _peso(total),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveCart,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _saving ? 'Saving...' : 'Save & Record',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ============================================================================
// CART ITEM TILE
// ============================================================================

class _CartItemTile extends ConsumerWidget {
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: scheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) {
        ref.read(cartProvider.notifier).removeItem(item.id);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(
                item.name.trim().isEmpty
                    ? '?'
                    : item.name.trim()[0].toUpperCase(),
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(width: 11),
            // THE FIX: wrap the whole text column in Expanded so it can
            // never claim more width than what's left after the avatar
            // and quantity control take theirs.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit name',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _editName(context, ref),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                      ),
                    ],
                  ),
                  if (item.unit != null) ...[
                    Text(
                      'per ${item.unit}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  // THE FIX: every piece of text in this row is now
                  // Flexible + ellipsis, so the row shrinks instead of
                  // overflowing, however narrow its available space is.
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _editPrice(context, ref),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: Text(
                              '${_peso(item.unitPrice)} each',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '·',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _peso(item.lineTotal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _QuantityControl(
              quantity: item.quantity,
              onDecrease: () {
                ref
                    .read(cartProvider.notifier)
                    .updateQuantity(item.id, item.quantity - 1);
              },
              onIncrease: () {
                ref
                    .read(cartProvider.notifier)
                    .updateQuantity(item.id, item.quantity + 1);
              },
              onTapQuantity: () => _editQuantity(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: item.name);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit item name'),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Item name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();

                if (value.isEmpty) return;

                Navigator.pop(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result != null && result.isNotEmpty) {
      ref.read(cartProvider.notifier).updateName(item.id, result);
    }
  }

  Future<void> _editPrice(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: (item.unitPrice / 100).toStringAsFixed(2),
    );

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit unit price'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Unit price',
              prefixText: '₱ ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = controller.text.replaceAll(',', '').trim();

                final price = double.tryParse(normalized);

                if (price == null || price < 0) {
                  return;
                }

                Navigator.pop(dialogContext, (price * 100).round());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result != null) {
      ref.read(cartProvider.notifier).updatePrice(item.id, result);
    }
  }

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: '${item.quantity}');

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit quantity'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final quantity = int.tryParse(controller.text.trim());

                if (quantity == null || quantity <= 0) {
                  return;
                }

                Navigator.pop(dialogContext, quantity);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result != null) {
      ref.read(cartProvider.notifier).updateQuantity(item.id, result);
    }
  }
}

// ============================================================================
// QUANTITY CONTROL
// ============================================================================

class _QuantityControl extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onTapQuantity;

  const _QuantityControl({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    required this.onTapQuantity,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease',
            visualDensity: VisualDensity.compact,
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          InkWell(
            onTap: onTapQuantity,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Text(
                '$quantity',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase',
            visualDensity: VisualDensity.compact,
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
