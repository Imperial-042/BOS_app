import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/session_end.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _customerProfileProvider =
    FutureProvider.family<CustomerLocationProfile?, String>((ref, userId) {
      return ref
          .watch(customerCommerceServiceProvider)
          .loadCustomerProfile(userId);
    });

final _customerStoresProvider =
    FutureProvider.family<List<CustomerStorefront>, String>((ref, city) {
      return ref
          .watch(customerCommerceServiceProvider)
          .discoverStores(city: city);
    });

final _customerFollowsProvider =
    StreamProvider.family<List<CustomerStoreFollow>, String>((ref, userId) {
      return ref.watch(customerCommerceServiceProvider).watchFollows(userId);
    });

final _customerOrdersProvider =
    FutureProvider.family<List<CustomerOrder>, String>((ref, userId) {
      return ref
          .watch(customerCommerceServiceProvider)
          .loadOrders(userId: userId);
    });

final _customerPointsProvider =
    FutureProvider.family<int, ({String userId, String businessId})>((
      ref,
      args,
    ) {
      return ref
          .watch(customerCommerceServiceProvider)
          .loyaltyBalance(userId: args.userId, businessId: args.businessId);
    });

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key, this.onSwitchToBusiness});

  final VoidCallback? onSwitchToBusiness;

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

Future<void> _editCustomerLocation(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required CustomerLocationProfile? profile,
}) async {
  final city = TextEditingController(text: profile?.city ?? '');
  final address = TextEditingController(text: profile?.address ?? '');
  try {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your store discovery area'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'City or area',
                helperText: 'Used to show stores in your city.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Street address (optional)',
                helperText:
                    'Private to your profile; it is not sent to stores.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save location'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (city.text.trim().isEmpty) {
      throw StateError('Enter your city or area.');
    }
    await ref
        .read(customerCommerceServiceProvider)
        .updateCustomerLocation(
          userId: userId,
          city: city.text,
          address: address.text,
        );
    ref.invalidate(_customerProfileProvider(userId));
    ref.invalidate(_customerStoresProvider(city.text.trim()));
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save location: $error')),
      );
    }
  } finally {
    city.dispose();
    address.dispose();
  }
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  int _tab = 0;
  String _search = '';

  Future<void> _scanStoreInvite() async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(
          title: 'Scan store invitation',
          instruction: 'Position the store QR code inside the box',
          qrMode: true,
        ),
      ),
    );
    if (!mounted || payload == null) return;
    final businessId = businessIdFromStorefrontInvite(payload);
    if (businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That QR code is not a store invitation.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerStoreScreen(businessId: businessId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authenticatedUserIdProvider);
    if (userId == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BOS Customer'),
        actions: [
          if (widget.onSwitchToBusiness != null)
            IconButton(
              tooltip: 'Switch to business mode',
              onPressed: widget.onSwitchToBusiness,
              icon: const Icon(Icons.storefront_outlined),
            ),
          IconButton(
            tooltip: 'Scan a store QR code',
            onPressed: _scanStoreInvite,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => endWidgetSessionLocally(ref),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _DiscoverTab(
            userId: userId,
            search: _search,
            onSearchChanged: (value) => setState(() => _search = value),
          ),
          _FollowingTab(userId: userId),
          _CustomerOrdersTab(userId: userId),
          _LoyaltyTab(userId: userId),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Following',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.stars_outlined),
            label: 'Points',
          ),
        ],
        backgroundColor: scheme.surface,
      ),
    );
  }
}

class _DiscoverTab extends ConsumerWidget {
  const _DiscoverTab({
    required this.userId,
    required this.search,
    required this.onSearchChanged,
  });

  final String userId;
  final String search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_customerProfileProvider(userId));
    final city = profile.value?.city?.trim() ?? '';
    final stores = ref.watch(_customerStoresProvider(city));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search stores',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: OutlinedButton.icon(
            onPressed: profile.isLoading
                ? null
                : () => _editCustomerLocation(
                    context,
                    ref,
                    userId: userId,
                    profile: profile.value,
                  ),
            icon: const Icon(Icons.location_on_outlined),
            label: Text(city.isEmpty ? 'Set your city' : 'Stores near $city'),
          ),
        ),
        Expanded(
          child: profile.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _CustomerMessage(
              icon: Icons.person_pin_circle_outlined,
              title: 'Location profile unavailable',
              message: error.toString(),
            ),
            data: (customerProfile) => city.isEmpty
                ? _CustomerMessage(
                    icon: Icons.location_off_outlined,
                    title: 'Set your city to discover stores',
                    message:
                        'We use your city to show nearby storefronts. Your street address stays private.',
                    action: TextButton(
                      onPressed: () => _editCustomerLocation(
                        context,
                        ref,
                        userId: userId,
                        profile: customerProfile,
                      ),
                      child: const Text('Add city'),
                    ),
                  )
                : stores.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _CustomerMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Stores are unavailable',
                      message: error.toString(),
                      action: TextButton(
                        onPressed: () =>
                            ref.invalidate(_customerStoresProvider(city)),
                        child: const Text('Try again'),
                      ),
                    ),
                    data: (values) {
                      final query = search.trim().toLowerCase();
                      final filtered = values.where((store) {
                        return query.isEmpty ||
                            store.name.toLowerCase().contains(query) ||
                            (store.city?.toLowerCase().contains(query) ??
                                false) ||
                            (store.description?.toLowerCase().contains(query) ??
                                false);
                      }).toList();
                      if (filtered.isEmpty) {
                        return _CustomerMessage(
                          icon: Icons.store_mall_directory_outlined,
                          title: 'No stores in $city',
                          message:
                              'Published stores in your city will appear here.',
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _StoreCard(
                          store: filtered[index],
                          city: city,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CustomerStoreScreen(
                                businessId: filtered[index].businessId,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _FollowingTab extends ConsumerWidget {
  const _FollowingTab({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(_customerFollowsProvider(userId));
    final city = ref.watch(_customerProfileProvider(userId)).value?.city ?? '';
    final stores = ref.watch(_customerStoresProvider(city)).value ?? const [];
    return follows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Unable to load followed stores: $error')),
      data: (values) {
        final ids = values.map((f) => f.businessId).toSet();
        final followed = stores.where(
          (store) => ids.contains(store.businessId),
        );
        if (followed.isEmpty) {
          return const _CustomerMessage(
            icon: Icons.favorite_border_rounded,
            title: 'No followed stores',
            message: 'Follow a store to keep its catalog and offers here.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final store in followed)
              _StoreCard(
                store: store,
                city: city,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CustomerStoreScreen(businessId: store.businessId),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CustomerOrdersTab extends ConsumerWidget {
  const _CustomerOrdersTab({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(_customerOrdersProvider(userId));
    return orders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CustomerMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Orders are unavailable',
        message: error.toString(),
        action: TextButton(
          onPressed: () => ref.invalidate(_customerOrdersProvider(userId)),
          child: const Text('Refresh'),
        ),
      ),
      data: (values) {
        if (values.isEmpty) {
          return const _CustomerMessage(
            icon: Icons.receipt_long_outlined,
            title: 'No orders yet',
            message: 'Orders you place with followed stores will appear here.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final order in values)
              Card(
                child: ExpansionTile(
                  title: Text(order.branchName),
                  subtitle: Text(
                    '${_statusLabel(order.status)} • ${_formatPrice(order.totalCents, order.currencyCode)}',
                  ),
                  children: [
                    FutureBuilder<List<CustomerOrderItem>>(
                      future: ref
                          .read(customerCommerceServiceProvider)
                          .loadOrderItems(order.id),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Unable to load items: ${snapshot.error}',
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          );
                        }
                        return Column(
                          children: [
                            for (final item in snapshot.data!)
                              ListTile(
                                dense: true,
                                title: Text(item.itemName),
                                subtitle: Text(
                                  '${item.quantity} ${item.unit} × ${_formatPrice(item.unitPriceCents, order.currencyCode)}',
                                ),
                                trailing: Text(
                                  _formatPrice(
                                    item.totalCents,
                                    order.currencyCode,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    ListTile(
                      dense: true,
                      title: const Text('Order status'),
                      subtitle: Text(order.status),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LoyaltyTab extends ConsumerWidget {
  const _LoyaltyTab({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(_customerFollowsProvider(userId));
    final city = ref.watch(_customerProfileProvider(userId)).value?.city ?? '';
    final stores = ref.watch(_customerStoresProvider(city)).value ?? const [];
    return follows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Unable to load points: $error')),
      data: (values) {
        final storeById = {for (final store in stores) store.businessId: store};
        final followed = values
            .map((follow) => storeById[follow.businessId])
            .whereType<CustomerStorefront>()
            .toList();
        if (followed.isEmpty) {
          return const _CustomerMessage(
            icon: Icons.stars_outlined,
            title: 'Loyalty points',
            message: 'Follow stores to see their loyalty programs here.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final store in followed)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.stars_rounded)),
                  title: Text(store.name),
                  subtitle: Text(
                    store.pointsPerCurrencyUnit == 0
                        ? 'This store has not started a points program.'
                        : 'Earn ${store.pointsPerCurrencyUnit} point(s) per ${store.currencyCode} 1 spent.',
                  ),
                  trailing: store.pointsPerCurrencyUnit == 0
                      ? null
                      : FutureBuilder<int>(
                          future: ref.watch(
                            _customerPointsProvider((
                              userId: userId,
                              businessId: store.businessId,
                            )).future,
                          ),
                          builder: (context, snapshot) => Text(
                            '${snapshot.data ?? 0} pts',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class CustomerStoreScreen extends ConsumerStatefulWidget {
  const CustomerStoreScreen({required this.businessId, super.key});

  final String businessId;

  @override
  ConsumerState<CustomerStoreScreen> createState() =>
      _CustomerStoreScreenState();
}

class _CustomerStoreScreenState extends ConsumerState<CustomerStoreScreen> {
  final Map<String, double> _cart = {};
  bool _loadingFollow = true;
  bool _following = false;
  bool _savingFollow = false;

  Future<CustomerStorefront?> _loadStorefront(
    CustomerCommerceService service,
  ) async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return null;
    final profile = await service.loadCustomerProfile(userId);
    final city = normalizeStoreCity(profile?.city ?? '');
    if (city.isEmpty) return null;
    return service.loadStorefrontForCity(widget.businessId, city: city);
  }

  Future<List<CustomerCatalogItem>> _loadCatalog(
    CustomerCommerceService service,
  ) async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return const [];
    final profile = await service.loadCustomerProfile(userId);
    final city = normalizeStoreCity(profile?.city ?? '');
    if (city.isEmpty) return const [];
    return service.loadCatalog(widget.businessId, city: city);
  }

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    final following = await ref
        .read(customerCommerceServiceProvider)
        .isFollowing(userId, widget.businessId);
    if (mounted) {
      setState(() {
        _following = following;
        _loadingFollow = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
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
      setState(() => _following = !_following);
      ref.invalidate(_customerFollowsProvider(userId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update following: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(customerCommerceServiceProvider);
    return FutureBuilder<CustomerStorefront?>(
      future: _loadStorefront(store),
      builder: (context, storeSnapshot) {
        if (storeSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: _CustomerMessage(
              icon: Icons.store_outlined,
              title: 'Store unavailable',
              message: storeSnapshot.error.toString(),
            ),
          );
        }
        final storefront = storeSnapshot.data;
        if (storefront == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const _CustomerMessage(
              icon: Icons.store_outlined,
              title: 'Store unavailable',
              message:
                  'Add your city in your profile to view stores in your area, or this store may be unpublished.',
            ),
          );
        }
        final isOpen = storefrontIsOpen(storefront);
        final hours = parseStoreHours(storefrontOpeningHoursJson(storefront));
        const days = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(storefront.name),
            actions: [
              IconButton(
                tooltip: _following ? 'Unfollow store' : 'Follow store',
                onPressed: _loadingFollow || _savingFollow
                    ? null
                    : _toggleFollow,
                icon: Icon(
                  _following ? Icons.favorite_rounded : Icons.favorite_border,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              ExpansionTile(
                leading: Icon(
                  isOpen
                      ? Icons.storefront_rounded
                      : Icons.store_mall_directory_outlined,
                  color: isOpen
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(isOpen ? 'Open now' : 'Closed now'),
                subtitle: Text(storefrontHoursToday(storefront)),
                children: [
                  if (hours.isEmpty)
                    const ListTile(title: Text('Orders accepted any time'))
                  else
                    for (var day = 1; day <= 7; day++)
                      ListTile(
                        dense: true,
                        title: Text(days[day - 1]),
                        trailing: Text(
                          hours[day] == null
                              ? 'Closed'
                              : '${hours[day]!.open}–${hours[day]!.close}',
                        ),
                      ),
                ],
              ),
              if (storefront.description?.isNotEmpty == true ||
                  storefront.city?.isNotEmpty == true)
                ListTile(
                  title: Text(
                    storefront.description ?? storefront.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: storefront.city == null
                      ? null
                      : Text(storefront.city!),
                ),
              Expanded(
                child: FutureBuilder<List<CustomerCatalogItem>>(
                  future: _loadCatalog(store),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _CustomerMessage(
                        icon: Icons.cloud_off_outlined,
                        title: 'Catalog unavailable',
                        message: snapshot.error.toString(),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snapshot.data!;
                    if (items.isEmpty) {
                      return const _CustomerMessage(
                        icon: Icons.menu_book_outlined,
                        title: 'No catalog items',
                        message: 'This store has not published items yet.',
                      );
                    }
                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final quantity = _cart[item.id] ?? 0;
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                            [
                              if (item.category?.isNotEmpty == true)
                                item.category!,
                              if (item.priceCents != null)
                                _formatPrice(
                                  item.priceCents!,
                                  storefront.currencyCode,
                                ),
                              item.unit,
                              if (item.description?.isNotEmpty == true)
                                item.description!,
                            ].join(' • '),
                          ),
                          trailing: quantity == 0
                              ? IconButton(
                                  tooltip: 'Add to order',
                                  onPressed:
                                      item.priceCents == null ||
                                          !_following ||
                                          !isOpen
                                      ? null
                                      : () =>
                                            setState(() => _cart[item.id] = 1),
                                  icon: const Icon(Icons.add_shopping_cart),
                                )
                              : _QuantityStepper(
                                  quantity: quantity,
                                  onChanged: (value) => setState(() {
                                    if (value <= 0) {
                                      _cart.remove(item.id);
                                    } else {
                                      _cart[item.id] = value;
                                    }
                                  }),
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_cart.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: !_following || !storefrontIsOpen(storefront)
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CustomerCheckoutScreen(
                                  store: storefront,
                                  items: Map.of(_cart),
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: Text('Continue order (${_cart.length})'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class CustomerCheckoutScreen extends ConsumerStatefulWidget {
  const CustomerCheckoutScreen({
    required this.store,
    required this.items,
    super.key,
  });

  final CustomerStorefront store;
  final Map<String, double> items;

  @override
  ConsumerState<CustomerCheckoutScreen> createState() =>
      _CustomerCheckoutScreenState();
}

class _CustomerCheckoutScreenState
    extends ConsumerState<CustomerCheckoutScreen> {
  final _phone = TextEditingController();
  final _tin = TextEditingController();
  final _notes = TextEditingController();
  String? _branchId;
  bool _officialReceipt = false;
  bool _submitting = false;

  @override
  void dispose() {
    _phone.dispose();
    _tin.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(List<CustomerStoreBranch> branches) async {
    if (_branchId == null || branches.every((b) => b.id != _branchId)) {
      _showMessage('Select an active pickup branch.');
      return;
    }
    if (_phone.text.trim().length < 5) {
      _showMessage('Enter a valid contact phone number.');
      return;
    }
    if (_officialReceipt && _tin.text.trim().isEmpty) {
      _showMessage('Enter your TIN to request an official receipt.');
      return;
    }
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    setState(() => _submitting = true);
    try {
      final service = ref.read(customerCommerceServiceProvider);
      await service.submitOrder(
        userId: userId,
        businessId: widget.store.businessId,
        branchId: _branchId!,
        phone: _phone.text,
        requestsOfficialReceipt: _officialReceipt,
        tin: _tin.text,
        notes: _notes.text,
        items: [
          for (final entry in widget.items.entries)
            (itemId: entry.key, quantity: entry.value),
        ],
      );
      ref.invalidate(_customerOrdersProvider(userId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order sent to the store.')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      _showMessage('Could not submit order: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<CustomerStoreBranchWithCity>> _loadBranches(
    CustomerCommerceService service,
  ) async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return const [];
    final profile = await service.loadCustomerProfile(userId);
    return service.loadStoreBranches(
      widget.store.businessId,
      city: profile?.city ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(customerCommerceServiceProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Order from ${widget.store.name}')),
      body: FutureBuilder<List<CustomerStoreBranchWithCity>>(
        future: _loadBranches(service),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load pickup branches: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = snapshot.data!;
          if (branches.isEmpty) {
            return const _CustomerMessage(
              icon: Icons.location_off_outlined,
              title: 'No pickup branches',
              message: 'This store has not published an active pickup branch.',
            );
          }
          if (branches.every((branch) => branch.id != _branchId)) {
            _branchId = branches.first.id;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                decoration: const InputDecoration(labelText: 'Pickup branch'),
                items: [
                  for (final branch in branches)
                    DropdownMenuItem(
                      value: branch.id,
                      child: Text(
                        [
                          branch.name,
                          if (branch.city?.isNotEmpty == true) branch.city!,
                          if (branch.address?.isNotEmpty == true)
                            branch.address!,
                        ].join(' • '),
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _branchId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact phone',
                  helperText: 'Shared with this store for order fulfilment.',
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _officialReceipt,
                onChanged: _submitting
                    ? null
                    : (value) =>
                          setState(() => _officialReceipt = value ?? false),
                title: const Text('Request an official receipt'),
                subtitle: const Text(
                  'Your TIN is shared with this store for the receipt.',
                ),
              ),
              if (_officialReceipt) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _tin,
                  decoration: const InputDecoration(labelText: 'TIN'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes to the store (optional)',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'The store will confirm availability and pickup details. '
                'Payment is handled with the store.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(branches),
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('Send order'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StoreCard extends ConsumerWidget {
  const _StoreCard({
    required this.store,
    required this.city,
    required this.onTap,
  });

  final CustomerStorefront store;
  final String city;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: FutureBuilder<List<CustomerStoreBranchWithCity>>(
        future: ref
            .read(customerCommerceServiceProvider)
            .loadStoreBranches(store.businessId, city: city),
        builder: (context, snapshot) => ListTile(
          leading: const CircleAvatar(child: Icon(Icons.storefront_rounded)),
          title: Text(store.name),
          subtitle: Text(
            [
              if (snapshot.hasData && snapshot.data!.isNotEmpty)
                snapshot.data!
                    .map(
                      (branch) => [
                        branch.name,
                        if (branch.address?.isNotEmpty == true) branch.address!,
                      ].join(' · '),
                    )
                    .join(', ')
              else if (city.isNotEmpty)
                city,
              storefrontIsOpen(store) ? 'Open now' : 'Closed now',
              if (store.offlineEnabled) 'Offline catalog available',
            ].join(' • '),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Remove one',
        onPressed: () => onChanged(quantity - 1),
        icon: const Icon(Icons.remove_circle_outline),
      ),
      Text(NumberFormat('0.###').format(quantity)),
      IconButton(
        tooltip: 'Add one',
        onPressed: () => onChanged(quantity + 1),
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );
}

class _CustomerMessage extends StatelessWidget {
  const _CustomerMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

String _formatPrice(int cents, String currency) => NumberFormat.currency(
  name: currency,
  symbol: NumberFormat.simpleCurrency(name: currency).currencySymbol,
  decimalDigits: 2,
).format(cents / 100);

String _statusLabel(String status) => switch (status) {
  'pending' => 'Awaiting store',
  'accepted' => 'Accepted',
  'rejected' => 'Declined',
  'preparing' => 'Preparing',
  'ready' => 'Ready for pickup',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _ => status,
};
