import 'dart:async';

import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_discover_tab.dart';
import 'package:bos_application/features/customer/presentation/customer_following_tab.dart';
import 'package:bos_application/features/customer/presentation/customer_location_sheet.dart';
import 'package:bos_application/features/customer/presentation/customer_menu_drawer.dart';
import 'package:bos_application/features/customer/presentation/customer_orders_tab.dart';
import 'package:bos_application/features/customer/presentation/customer_addresses_screen.dart';
import 'package:bos_application/features/customer/presentation/customer_points_tab.dart';
import 'package:bos_application/features/customer/presentation/customer_profile_screen.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:bos_application/features/customer/presentation/customer_store_screen.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Keep older imports of this file working.
export 'package:bos_application/features/customer/presentation/customer_checkout_screen.dart'
    show CustomerCheckoutScreen;
export 'package:bos_application/features/customer/presentation/customer_store_screen.dart'
    show CustomerStoreScreen;

/// Shell for the customer app: app bar, bottom navigation, drawer and the
/// four tabs. Each tab lives in `tabs/`.
class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key, this.onSwitchToBusiness});

  final VoidCallback? onSwitchToBusiness;

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  static const _discoverTab = 0;
  static const _ordersTab = 2;
  static const _titles = ['Discover', 'Following', 'Orders', 'Points'];

  int _tab = _discoverTab;
  String _search = '';
  Timer? _poll;
  Timer? _storePoll;

  @override
  void initState() {
    super.initState();
    // Refresh orders every 45s, but only while something is in progress.
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      final id = ref.read(authenticatedUserIdProvider);
      if (id == null) return;
      final hasLive =
          ref
              .read(customerHomeOrdersProvider(id))
              .value
              ?.any((o) => customerLiveOrderStatuses.contains(o.status)) ??
          false;
      if (hasLive) {
        unawaited(
          ref
              .refresh(customerHomeOrdersProvider(id).future)
              .catchError((_) => <CustomerOrder>[]),
        );
      }
    });
    _storePoll = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_tab != _discoverTab) return;
      final id = ref.read(authenticatedUserIdProvider);
      if (id == null) return;
      final city =
          ref.read(customerHomeProfileProvider(id)).value?.city?.trim() ?? '';
      if (city.isNotEmpty) {
        ref.invalidate(customerHomeBranchStoresProvider(city));
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _storePoll?.cancel();
    super.dispose();
  }

  void _goToTab(int index) => setState(() => _tab = index);

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String? _firstName(String? displayName) {
    final name = (displayName ?? '').trim();
    if (name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }

  /// Personal one-liner under the tab title.
  String _subtitle(String? firstName, int activeOrders) => switch (_tab) {
    0 => firstName == null ? _greeting() : '${_greeting()}, $firstName',
    1 =>
      firstName == null
          ? 'Your favourite spots'
          : '$firstName\u2019s favourite spots',
    2 =>
      activeOrders > 0
          ? '$activeOrders order${activeOrders == 1 ? '' : 's'} on the way'
          : 'Everything you\u2019ve ordered',
    _ => 'Rewards you\u2019ve earned',
  };

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
          behavior: SnackBarBehavior.floating,
          content: Text('That QR code is not a store invitation.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerStoreScreen(
          businessId: businessId,
          branchId: branchIdFromStorefrontInvite(payload),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authenticatedUserIdProvider);
    if (userId == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final displayName = ref.watch(currentUserProvider).value?.displayName;
    final hasName = (displayName ?? '').trim().isNotEmpty;
    final activeOrders =
        ref
            .watch(customerHomeOrdersProvider(userId))
            .value
            ?.where((o) => customerLiveOrderStatuses.contains(o.status))
            .length ??
        0;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _titles[_tab],
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              _subtitle(_firstName(displayName), activeOrders),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Scan a store QR code',
            onPressed: _scanStoreInvite,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          Builder(
            builder: (ctx) => Padding(
              padding: const EdgeInsets.only(left: 4, right: 6),
              child: IconButton(
                tooltip: 'Menu',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Scaffold.of(ctx).openEndDrawer();
                },
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: hasName
                      ? Text(
                          customerInitials(displayName),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : const Icon(Icons.person_rounded, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          CustomerDiscoverTab(
            userId: userId,
            search: _search,
            onSearchChanged: (value) => setState(() => _search = value),
          ),
          CustomerFollowingTab(
            userId: userId,
            onDiscover: () => _goToTab(_discoverTab),
          ),
          CustomerOrdersTab(
            userId: userId,
            onDiscover: () => _goToTab(_discoverTab),
          ),
          CustomerPointsTab(userId: userId),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          _goToTab(index);
        },
        backgroundColor: scheme.surfaceContainerLow,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Discover',
          ),
          const NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Following',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeOrders > 0,
              label: Text('$activeOrders'),
              child: const Icon(Icons.receipt_long_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: activeOrders > 0,
              label: Text('$activeOrders'),
              child: const Icon(Icons.receipt_long_rounded),
            ),
            label: 'Orders',
          ),
          const NavigationDestination(
            icon: Icon(Icons.stars_outlined),
            selectedIcon: Icon(Icons.stars_rounded),
            label: 'Points',
          ),
        ],
      ),
      endDrawer: CustomerMenuDrawer(
        displayName: displayName,
        activeOrders: activeOrders,
        onOrders: () => _goToTab(_ordersTab),
        onAddresses: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CustomerAddressesScreen(),
            ),
          );
        },
        city:
            ref
                .watch(customerHomeProfileProvider(userId))
                .value
                ?.city
                ?.trim() ??
            '',
        onSwitchToBusiness: widget.onSwitchToBusiness,
        onScan: _scanStoreInvite,
        onLocation: () => editCustomerLocation(
          context,
          ref,
          userId: userId,
          profile: ref.read(customerHomeProfileProvider(userId)).value,
        ),
        onProfile: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const CustomerProfileScreen()),
          );
          if (saved == true) {
            ref.invalidate(customerHomeProfileProvider(userId));
          }
        },
        onSignOut: () async {
          if (await confirmCustomerSignOut(context) && mounted) {
            endWidgetSessionLocally(ref);
          }
        },
      ),
    );
  }
}
