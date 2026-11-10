import 'dart:math' as math;

import 'package:bos_application/features/customer/presentation/customer_checkout_screen.dart';
import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_customization_sheet.dart';
import 'package:bos_application/features/customer/presentation/customer_design.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:bos_application/core/location/location_picker_map.dart';
import 'package:bos_application/core/location/location_services.dart';
import 'package:bos_application/core/location/external_navigation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class _StorePageData {
  const _StorePageData({
    required this.storefront,
    required this.branches,
    this.items,
    this.catalogError,
    this.choosing = false,
  });

  final CustomerStorefront storefront;
  final List<CustomerStoreBranchWithCity> branches;
  final List<CustomerCatalogItem>? items;
  final Object? catalogError;

  /// True when no branch was picked yet and the customer must choose one.
  final bool choosing;
}

class CustomerStoreScreen extends ConsumerStatefulWidget {
  const CustomerStoreScreen({
    required this.businessId,
    this.branchId,
    super.key,
  });

  final String businessId;
  final String? branchId;

  @override
  ConsumerState<CustomerStoreScreen> createState() =>
      _CustomerStoreScreenState();
}

class _CustomerStoreScreenState extends ConsumerState<CustomerStoreScreen> {
  /// Content never gets wider than this, so tablets/desktop stay readable.
  static const _maxContentWidth = 1040.0;

  final List<CustomerCartLine> _cart = [];
  final _catalogSearch = TextEditingController();
  late Future<_StorePageData?> _page;
  bool _loadingFollow = true;
  bool _following = false;
  bool _savingFollow = false;
  String? _category;
  String _query = '';
  bool _forwarding = false;
  bool _showBranchMap = false;

  @override
  void initState() {
    super.initState();
    _page = _loadPage();
    _loadFollowing();
    final branchId = widget.branchId;
    if (branchId != null) {
      _cart.addAll(
        ref.read(
          customerCartProvider(customerCartKey(widget.businessId, branchId)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _catalogSearch.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────

  Future<String> _customerCity(CustomerCommerceService service) async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return '';
    final profile = await service.loadCustomerProfile(userId);
    return normalizeStoreCity(profile?.city ?? '');
  }

  Future<_StorePageData?> _loadPage() async {
    final service = ref.read(customerCommerceServiceProvider);
    final city = await _customerCity(service);
    if (city.isEmpty) return null;
    final storefront = await service.loadStorefrontForCity(
      widget.businessId,
      city: city,
    );
    if (storefront == null) return null;
    final branches = await service.loadStoreBranches(
      widget.businessId,
      city: city,
    );
    if (branches.isEmpty) return null;

    final wanted = widget.branchId;
    if (wanted == null) {
      return _StorePageData(
        storefront: storefront,
        branches: branches,
        choosing: true,
      );
    }
    final branch = branches.where((b) => b.id == wanted).firstOrNull;
    if (branch == null) return null;
    try {
      final items = await service.loadCatalog(
        widget.businessId,
        city: city,
        branchId: branch.id,
      );
      return _StorePageData(
        storefront: storefront,
        branches: [branch],
        items: items,
      );
    } catch (error) {
      return _StorePageData(
        storefront: storefront,
        branches: [branch],
        catalogError: error,
      );
    }
  }

  Future<void> _loadFollowing() async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    var following = false;
    try {
      following = await ref
          .read(customerCommerceServiceProvider)
          .isFollowing(userId, widget.businessId);
    } catch (_) {
      // Treat as not following so the screen never gets stuck loading.
    }
    if (mounted) {
      setState(() {
        _following = following;
        _loadingFollow = false;
      });
    }
  }

  /// Pull-to-refresh: keeps the current page on screen while reloading.
  Future<void> _refresh() async {
    final future = _loadPage();
    setState(() => _page = future);
    try {
      await future;
    } catch (_) {}
  }

  // ── Actions ───────────────────────────────────────────────────────────

  void _saveCart() {
    final branchId = widget.branchId;
    if (branchId == null) return;
    ref
        .read(
          customerCartProvider(
            customerCartKey(widget.businessId, branchId),
          ).notifier,
        )
        .state = List.of(
      _cart,
    );
  }

  void _setQuantity(String id, double value) {
    setState(() {
      final index = _cart.indexWhere(
        (line) => line.itemId == id && line.options.isEmpty,
      );
      if (value <= 0) {
        if (index >= 0) _cart.removeAt(index);
      } else if (index >= 0) {
        _cart[index] = _cart[index].copyWith(quantity: value);
      } else {
        _cart.add(CustomerCartLine(itemId: id, quantity: value));
      }
    });
    _saveCart();
  }

  double _quantityFor(String id) => _cart
      .where((line) => line.itemId == id)
      .fold(0, (total, line) => total + line.quantity);

  Future<void> _addItem(CustomerCatalogItem item) async {
    if (item.priceCents == null) return;
    final groups = await ref
        .read(customerCommerceServiceProvider)
        .loadCustomerProductOptions(item.id);
    if (!mounted) return;
    final options = await showCustomerCustomizationSheet(
      context,
      productName: item.name,
      basePriceCents: item.priceCents!,
      groups: groups,
    );
    if (!mounted || options == null) return;
    setState(() {
      final candidate = CustomerCartLine(
        itemId: item.id,
        quantity: 1,
        options: options,
      );
      final index = _cart.indexWhere((line) => line.key == candidate.key);
      if (index >= 0) {
        _cart[index] = _cart[index].copyWith(
          quantity: _cart[index].quantity + 1,
        );
      } else {
        _cart.add(candidate);
      }
    });
    _saveCart();
  }

  Future<void> _toggleFollow() async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    HapticFeedback.selectionClick();
    setState(() => _savingFollow = true);
    try {
      final service = ref.read(customerCommerceServiceProvider);
      if (_following) {
        await service.unfollowStore(
          userId: userId,
          businessId: widget.businessId,
        );
      } else {
        await service.followStore(
          userId: userId,
          businessId: widget.businessId,
        );
      }
      if (!mounted) return;
      setState(() => _following = !_following);
      ref.invalidate(customerHomeFollowsProvider(userId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Could not update following: ${friendlyError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingFollow = false);
    }
  }

  void _retry() => setState(() => _page = _loadPage());

  void _goCheckout(
    CustomerStorefront storefront,
    List<CustomerCatalogItem> catalog,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerCheckoutScreen(
          store: storefront,
          items: List.of(_cart),
          catalog: catalog,
          branchId: widget.branchId!,
        ),
      ),
    );
  }

  /// Scrollable cart review with quantity editing.
  Future<void> _showCart(
    CustomerStorefront storefront,
    List<CustomerCatalogItem> catalog,
    bool canCheckout,
  ) {
    final byId = {for (final i in catalog) i.id: i};
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final scheme = theme.colorScheme;
          final entries = _cart
              .where((line) => byId.containsKey(line.itemId))
              .toList();
          if (entries.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) Navigator.of(ctx).pop();
            });
            return const SizedBox(height: 80);
          }
          var total = 0.0;
          for (final entry in entries) {
            final price = byId[entry.itemId]!.priceCents;
            if (price != null) {
              total +=
                  (price +
                      entry.options.fold<int>(
                        0,
                        (sum, option) => sum + option.priceDeltaCents,
                      )) *
                  entry.quantity;
            }
          }
          void change(CustomerCartLine entry, double v) {
            final index = _cart.indexWhere((line) => line.key == entry.key);
            if (index >= 0) {
              setState(() {
                if (v <= 0) {
                  _cart.removeAt(index);
                } else {
                  _cart[index] = entry.copyWith(quantity: v);
                }
              });
              _saveCart();
            }
            setSheet(() {});
          }

          // useSafeArea only protects the top, so guard the bottom here.
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Your order',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(_cart.clear);
                            _saveCart();
                            setSheet(() {});
                          },
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                          ),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final entry = entries[i];
                        final item = byId[entry.itemId]!;
                        final unitPrice = item.priceCents == null
                            ? null
                            : item.priceCents! +
                                  entry.options.fold<int>(
                                    0,
                                    (sum, option) =>
                                        sum + option.priceDeltaCents,
                                  );
                        final line = unitPrice == null
                            ? '—'
                            : formatCustomerPrice(
                                (unitPrice * entry.quantity).round(),
                                storefront.currencyCode,
                              );
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      entry.options.isEmpty
                                          ? line
                                          : '${entry.options.map((o) => o.choiceName).join(', ')}\n$line',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _QuantityStepper(
                                quantity: entry.quantity,
                                onChanged: (v) => change(entry, v),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Estimated total',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                formatCustomerPrice(
                                  total.round(),
                                  storefront.currencyCode,
                                ),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(140, 50),
                          ),
                          onPressed: canCheckout
                              ? () {
                                  Navigator.of(ctx).pop();
                                  _goCheckout(storefront, catalog);
                                }
                              : null,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Checkout'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StorePageData?>(
      future: _page,
      builder: (context, snapshot) {
        // While refreshing, FutureBuilder keeps the previous data, so the
        // page stays visible instead of flashing a full-screen loader.
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: CustomerStateMessage(
              icon: Icons.store_outlined,
              title: 'Store unavailable',
              message: friendlyError(snapshot.error!),
              action: FilledButton.tonal(
                onPressed: _retry,
                child: const Text('Try again'),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const CustomerStateMessage(
              icon: Icons.store_outlined,
              title: 'Store unavailable',
              message:
                  'Add your city in your profile to view stores in your area, or this store may be unpublished.',
            ),
          );
        }
        if (data.choosing) return _buildBranchChooser(context, data);
        return _buildStore(context, data);
      },
    );
  }

  Widget _buildStore(BuildContext context, _StorePageData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final storefront = data.storefront;
    final branches = data.branches;
    final isOpen = branches.any((b) => branchIsOpen(b));
    final cityLabel = {
      for (final b in branches)
        if (b.city?.trim().isNotEmpty == true) b.city!.trim(),
    }.join(', ');
    final canOrder = _following && isOpen;

    final storeTitle = branches.length == 1
        ? '${storefront.name} · ${branches.first.name}'
        : storefront.name;

    // Adaptive layout: 1 / 2 / 3 catalog columns, centred on wide screens.
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final compactHeight = size.height < 500;
    final columns = width >= 1000 ? 3 : (width >= 640 ? 2 : 1);
    final side = math.max(16.0, (width - _maxContentWidth) / 2);
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.6).toDouble();

    // Catalog filtering
    final allItems = data.items ?? const <CustomerCatalogItem>[];
    final categories = <String>{
      for (final i in allItems)
        if (i.category?.isNotEmpty == true) i.category!,
    }.toList()..sort();
    final q = _query.trim().toLowerCase();
    final items = allItems.where((i) {
      if (_category != null && i.category != _category) return false;
      if (q.isEmpty) return true;
      return i.name.toLowerCase().contains(q) ||
          (i.description?.toLowerCase().contains(q) ?? false);
    }).toList();
    final grouped = _category == null && q.isEmpty && categories.length > 1;

    // Cart summary (drops items the store no longer sells)
    final byId = {for (final i in allItems) i.id: i};
    if (data.items != null) {
      _cart.removeWhere((line) => !byId.containsKey(line.itemId));
    }
    var cartTotal = 0.0;
    for (final line in _cart) {
      final price = byId[line.itemId]?.priceCents;
      if (price != null) {
        cartTotal +=
            (price +
                line.options.fold<int>(
                  0,
                  (sum, option) => sum + option.priceDeltaCents,
                )) *
            line.quantity;
      }
    }
    final cartCount = _cart.fold<double>(
      0,
      (total, line) => total + line.quantity,
    );

    String? orderingHint;
    if (!_loadingFollow && !_following) {
      orderingHint = 'Follow this store to start an order.';
    } else if (!isOpen) {
      orderingHint = 'All branches are closed right now. You can still browse.';
    }

    // Sticky search + category header
    final showSearch = allItems.length > 6;
    final showChips = categories.length > 1;
    final headerHeight =
        8.0 +
        (showSearch ? 48 * textScale + 8 : 0) +
        (showChips ? 38 * textScale + 8 : 0);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(
              scheme,
              storefront,
              storeTitle,
              isOpen,
              cityLabel,
              compactHeight,
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 16, side, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (storefront.description?.isNotEmpty == true) ...[
                    Text(
                      storefront.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildInfoPills(scheme, storefront),
                  if (!_loadingFollow && !_following)
                    _buildFollowBanner(scheme, storefront),
                  _buildBranches(theme, branches),
                  if (orderingHint != null) ...[
                    const SizedBox(height: 12),
                    _buildHint(theme, orderingHint),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Menu & catalog',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (data.items != null)
                        Text(
                          '${items.length} item${items.length == 1 ? '' : 's'}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ]),
              ),
            ),
            if (showSearch || showChips)
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  height: headerHeight,
                  color: scheme.surface,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: side,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showSearch) ...[
                          SizedBox(
                            height: 48 * textScale,
                            child: _buildCatalogSearch(scheme),
                          ),
                          if (showChips) const SizedBox(height: 8),
                        ],
                        if (showChips)
                          SizedBox(
                            height: 38 * textScale,
                            child: _buildCategoryChips(categories),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (data.catalogError != null)
              customerSliverMessage(
                CustomerStateMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Catalog unavailable',
                  message: friendlyError(data.catalogError!),
                  action: FilledButton.tonal(
                    onPressed: _retry,
                    child: const Text('Try again'),
                  ),
                ),
              )
            else if (allItems.isEmpty)
              customerSliverMessage(
                const CustomerStateMessage(
                  icon: Icons.menu_book_outlined,
                  title: 'No catalog items',
                  message: 'This store has not published items yet.',
                ),
              )
            else if (items.isEmpty)
              customerSliverMessage(
                const CustomerStateMessage(
                  icon: Icons.search_off_rounded,
                  title: 'Nothing found',
                  message: 'Try a different search or category.',
                ),
              )
            else
              ..._catalogSlivers(
                items: items,
                storefront: storefront,
                canOrder: canOrder,
                columns: columns,
                side: side,
                grouped: grouped,
                bottomPadding: 24 + MediaQuery.viewPaddingOf(context).bottom,
              ),
          ],
        ),
      ),
      bottomNavigationBar: cartCount == 0
          ? null
          : _buildCartBar(
              scheme,
              storefront,
              allItems,
              cartCount.round(),
              cartTotal,
              canOrder,
            ),
    );
  }

  // ── Catalog layout ────────────────────────────────────────────────────

  List<Widget> _catalogSlivers({
    required List<CustomerCatalogItem> items,
    required CustomerStorefront storefront,
    required bool canOrder,
    required int columns,
    required double side,
    required bool grouped,
    required double bottomPadding,
  }) {
    // Group by category (uncategorised last) or one flat group.
    final groups = <String, List<CustomerCatalogItem>>{};
    if (grouped) {
      for (final i in items) {
        final key = i.category?.isNotEmpty == true ? i.category! : 'Other';
        groups.putIfAbsent(key, () => []).add(i);
      }
    } else {
      groups[''] = items;
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'Other') return 1;
        if (b == 'Other') return -1;
        return a.compareTo(b);
      });

    Widget card(CustomerCatalogItem item) {
      final quantity = _quantityFor(item.id);
      final purchasable = item.priceCents != null;
      return _CatalogItemCard(
        item: item,
        currency: storefront.currencyCode,
        quantity: quantity,
        showCategory: !grouped,
        canAdd: purchasable && canOrder,
        unavailableReason: !purchasable
            ? 'Price not set'
            : (!canOrder ? (!_following ? 'Follow to order' : 'Closed') : null),
        onAdd: () {
          HapticFeedback.selectionClick();
          _addItem(item);
        },
        onChanged: (value) => _setQuantity(item.id, value),
      );
    }

    Widget row(List<CustomerCatalogItem> list, int r) {
      if (columns == 1) return card(list[r]);
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final idx = r * columns + c;
        cells.add(
          Expanded(
            child: idx < list.length ? card(list[idx]) : const SizedBox(),
          ),
        );
        if (c < columns - 1) cells.add(const SizedBox(width: 10));
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      );
    }

    final slivers = <Widget>[];
    for (final key in keys) {
      final list = groups[key]!;
      if (grouped) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 14, side, 8),
            sliver: SliverToBoxAdapter(
              child: _CategoryHeader(title: key, count: list.length),
            ),
          ),
        );
      }
      final rowCount = (list.length / columns).ceil();
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverList.separated(
            itemCount: rowCount,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, r) => row(list, r),
          ),
        ),
      );
    }
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottomPadding)));
    return slivers;
  }

  Widget _buildBranchChooser(BuildContext context, _StorePageData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final branches = data.branches;

    if (branches.length == 1) {
      if (!_forwarding) {
        _forwarding = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => CustomerStoreScreen(
                businessId: widget.businessId,
                branchId: branches.first.id,
              ),
            ),
          );
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          data.storefront.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Choose a branch',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Each branch has its own hours and menu.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final b in branches)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.store_mall_directory_outlined),
                  title: Text(
                    b.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    [
                      if (b.address?.isNotEmpty == true) b.address!,
                      branchHoursToday(b),
                    ].join('\n'),
                  ),
                  trailing: customerOpenPill(branchIsOpen(b)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CustomerStoreScreen(
                        businessId: widget.businessId,
                        branchId: b.id,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Build helpers ─────────────────────────────────────────────────────

  Widget _buildAppBar(
    ColorScheme scheme,
    CustomerStorefront storefront,
    String title,
    bool isOpen,
    String cityLabel,
    bool compact,
  ) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: compact ? null : 210,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      surfaceTintColor: Colors.transparent,
      title: compact
          ? Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            )
          : null,
      actions: [
        IconButton(
          tooltip: _following ? 'Unfollow store' : 'Follow store',
          onPressed: _loadingFollow || _savingFollow ? null : _toggleFollow,
          icon: Icon(
            _following ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          ),
        ),
      ],
      flexibleSpace: compact
          ? null
          : FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 56,
                bottom: 14,
                end: 56,
              ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary,
                      Color.alphaBlend(
                        scheme.tertiary.withValues(alpha: 0.55),
                        scheme.primary,
                      ),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -40,
                      top: -30,
                      child: CustomerRing(size: 190, color: scheme.onPrimary),
                    ),
                    Positioned(
                      left: -50,
                      bottom: -70,
                      child: CustomerRing(size: 140, color: scheme.onPrimary),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 54,
                      child: Row(
                        children: [
                          CustomerStoreAvatar(name: storefront.name, size: 60),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                customerOpenPill(isOpen, solid: true),
                                if (cityLabel.isNotEmpty)
                                  CustomerPill(
                                    label: cityLabel,
                                    color: scheme.primary,
                                    icon: Icons.location_on_rounded,
                                    solid: true,
                                  ),
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
    );
  }

  Widget _buildInfoPills(ColorScheme scheme, CustomerStorefront storefront) {
    final pills = <Widget>[
      if (storefront.pointsPerCurrencyUnit != 0)
        CustomerPill(
          label:
              'Earn ${storefront.pointsPerCurrencyUnit} pt per ${storefront.currencyCode} 1',
          color: kCustomerWarn,
          icon: Icons.stars_rounded,
        ),
      if (storefront.offlineEnabled)
        CustomerPill(
          label: 'Offline catalog',
          color: scheme.secondary,
          icon: Icons.download_done_rounded,
        ),
    ];
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(spacing: 6, runSpacing: 6, children: pills),
    );
  }

  Widget _buildFollowBanner(ColorScheme scheme, CustomerStorefront storefront) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.favorite_rounded, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Follow ${storefront.name} to order and earn points.',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _savingFollow ? null : _toggleFollow,
            child: _savingFollow
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Follow'),
          ),
        ],
      ),
    );
  }

  Widget _buildBranches(
    ThemeData theme,
    List<CustomerStoreBranchWithCity> branches,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                branches.length == 1 ? 'Pickup branch' : 'Pickup branches',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (branches.any((branch) => branch.coordinate != null))
              IconButton(
                tooltip: _showBranchMap
                    ? 'Show branch list'
                    : 'Show branch map',
                onPressed: () =>
                    setState(() => _showBranchMap = !_showBranchMap),
                icon: Icon(
                  _showBranchMap
                      ? Icons.view_list_outlined
                      : Icons.map_outlined,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_showBranchMap)
          LocationPickerMap(
            provider: const OpenStreetMapTileProvider(),
            markers: [
              for (final branch in branches)
                if (branch.coordinate case final coordinate?)
                  Marker(
                    point: LatLng(coordinate.latitude, coordinate.longitude),
                    width: 48,
                    height: 48,
                    child: Tooltip(
                      message: branch.name,
                      child: const Icon(
                        Icons.store_mall_directory_rounded,
                        color: Colors.indigo,
                        size: 34,
                      ),
                    ),
                  ),
            ],
          ),
        if (!_showBranchMap)
          for (final b in branches)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BranchTile(branch: b),
            ),
      ],
    );
  }

  Widget _buildHint(ThemeData theme, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kCustomerWarn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: kCustomerWarn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogSearch(ColorScheme scheme) {
    return TextField(
      controller: _catalogSearch,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search this store',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _catalogSearch.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildCategoryChips(List<String> categories) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: const Text('All'),
            selected: _category == null,
            onSelected: (_) => setState(() => _category = null),
          ),
        ),
        for (final c in categories)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(c),
              selected: _category == c,
              onSelected: (_) => setState(() => _category = c),
            ),
          ),
      ],
    );
  }

  Widget _buildCartBar(
    ColorScheme scheme,
    CustomerStorefront storefront,
    List<CustomerCatalogItem> catalog,
    int cartCount,
    double cartTotal,
    bool canOrder,
  ) {
    return SafeArea(
      top: false,
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            decoration: BoxDecoration(
              color: scheme.inverseSurface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  // Tapping the summary opens the scrollable cart review.
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _showCart(storefront, catalog, canOrder),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$cartCount',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    cartCount == 1
                                        ? '1 item · View order'
                                        : '$cartCount items · View order',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onInverseSurface.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    formatCustomerPrice(
                                      cartTotal.round(),
                                      storefront.currencyCode,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onInverseSurface,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: scheme.onInverseSurface.withValues(
                                alpha: 0.75,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilledButton.icon(
                      onPressed: canOrder
                          ? () => _goCheckout(storefront, catalog)
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Continue'),
                    ),
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

// ============================================================================
// PINNED SEARCH / CATEGORY HEADER
// ============================================================================

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: color,
      elevation: overlapsContent ? 1.5 : 0,
      surfaceTintColor: Colors.transparent,
      child: child,
    );
  }

  // The header holds live state (search text, selected chip).
  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) => true;
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CATALOG ITEM CARD
// ============================================================================

class _CatalogItemCard extends StatelessWidget {
  const _CatalogItemCard({
    required this.item,
    required this.currency,
    required this.quantity,
    required this.showCategory,
    required this.canAdd,
    required this.unavailableReason,
    required this.onAdd,
    required this.onChanged,
  });

  final CustomerCatalogItem item;
  final String currency;
  final double quantity;
  final bool showCategory;
  final bool canAdd;
  final String? unavailableReason;
  final VoidCallback onAdd;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inCart = quantity > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: inCart
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: inCart
              ? scheme.primary.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomerStoreAvatar(name: item.name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.priceCents == null
                          ? 'Price not set'
                          : formatCustomerPrice(item.priceCents!, currency),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '/ ${item.unit}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (showCategory && item.category?.isNotEmpty == true)
                      CustomerPill(
                        label: item.category!,
                        color: scheme.secondary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!inCart)
            Column(
              children: [
                IconButton.filled(
                  tooltip: 'Add to order',
                  onPressed: canAdd ? onAdd : null,
                  icon: const Icon(Icons.add_rounded),
                ),
                if (unavailableReason != null)
                  SizedBox(
                    width: 64,
                    child: Text(
                      unavailableReason!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            )
          else
            _QuantityStepper(quantity: quantity, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Remove one',
            visualDensity: VisualDensity.compact,
            color: scheme.onPrimary,
            onPressed: () => onChanged(quantity - 1),
            icon: Icon(
              quantity <= 1
                  ? Icons.delete_outline_rounded
                  : Icons.remove_rounded,
              size: 20,
            ),
          ),
          Text(
            NumberFormat('0.###').format(quantity),
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            tooltip: 'Add one',
            visualDensity: VisualDensity.compact,
            color: scheme.onPrimary,
            onPressed: () => onChanged(quantity + 1),
            icon: const Icon(Icons.add_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({required this.branch});

  final CustomerStoreBranchWithCity branch;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = branchIsOpen(branch);
    final hours = parseStoreHours(branch.openingHoursJson);
    final today = DateTime.now().weekday;
    final place = [
      if (branch.address?.isNotEmpty == true) branch.address!,
    ].join();

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Icon(
            Icons.store_mall_directory_outlined,
            color: open ? kCustomerGood : scheme.error,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  branch.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              customerOpenPill(open),
            ],
          ),
          subtitle: Text(
            [if (place.isNotEmpty) place, branchHoursToday(branch)].join('\n'),
          ),
          children: [
            if (branch.phone?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.call_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(branch.phone!),
                  ],
                ),
              ),
            if (branch.coordinate != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await openExternalNavigation(
                          coordinate: branch.coordinate!,
                          label: branch.name,
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Navigate'),
                  ),
                ),
              ),
            if (hours.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Orders accepted any time'),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  children: [
                    for (var d = 1; d <= 7; d++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              _days[d - 1],
                              style: TextStyle(
                                fontWeight: d == today
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              hours[d] == null
                                  ? 'Closed'
                                  : '${hours[d]!.open}–${hours[d]!.close}',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
