import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_design.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:bos_application/features/customer/presentation/customer_store_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _FollowFilter { all, open, points }

class CustomerFollowingTab extends ConsumerStatefulWidget {
  const CustomerFollowingTab({
    super.key,
    required this.userId,
    required this.onDiscover,
  });

  final String userId;

  /// Called from the empty state to jump to the Discover tab.
  final VoidCallback onDiscover;

  @override
  ConsumerState<CustomerFollowingTab> createState() =>
      _CustomerFollowingTabState();
}

class _CustomerFollowingTabState extends ConsumerState<CustomerFollowingTab> {
  _FollowFilter _filter = _FollowFilter.all;
  String _query = '';

  /// Stores swiped away / unfollowed, hidden instantly while the
  /// follow stream catches up.
  final Set<String> _hidden = {};

  Future<void> _unfollow(CustomerStorefront store) async {
    final service = ref.read(customerCommerceServiceProvider);
    HapticFeedback.mediumImpact();
    setState(() => _hidden.add(store.businessId));
    try {
      await service.unfollowStore(
        userId: widget.userId,
        businessId: store.businessId,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _hidden.remove(store.businessId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not unfollow: ${friendlyError(error)}'),
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unfollowed ${store.name}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await service.followStore(
                  userId: widget.userId,
                  businessId: store.businessId,
                );
              } catch (_) {}
              if (mounted) setState(() => _hidden.remove(store.businessId));
            },
          ),
        ),
      );
  }

  void _open(StoreBranchListing listing) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerStoreScreen(
          businessId: listing.storefront.businessId,
          branchId: listing.branch.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final userId = widget.userId;
    final follows = ref.watch(customerHomeFollowsProvider(userId));
    final city =
        ref.watch(customerHomeProfileProvider(userId)).value?.city?.trim() ??
        '';
    final storesAsync = ref.watch(customerHomeBranchStoresProvider(city));
    final listings = storesAsync.value ?? const <StoreBranchListing>[];

    Widget skeleton() => ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: const [SkeletonList()],
    );

    return follows.when(
      loading: skeleton,
      error: (error, _) => CustomerStateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load followed stores',
        message: friendlyError(error),
        action: FilledButton.tonal(
          onPressed: () => ref.invalidate(customerHomeFollowsProvider(userId)),
          child: const Text('Try again'),
        ),
      ),
      data: (values) {
        if (storesAsync.isLoading && !storesAsync.hasValue) return skeleton();

        final ids = values.map((f) => f.businessId).toSet();
        _hidden.removeWhere((id) => !ids.contains(id));

        if (ids.isEmpty || ids.difference(_hidden).isEmpty) {
          return _FollowingEmpty(onDiscover: widget.onDiscover);
        }

        final followed =
            listings
                .where(
                  (l) =>
                      ids.contains(l.storefront.businessId) &&
                      !_hidden.contains(l.storefront.businessId),
                )
                .toList()
              ..sort((a, b) {
                final ao = branchIsOpen(a.branch);
                final bo = branchIsOpen(b.branch);
                if (ao != bo) return ao ? -1 : 1;
                final c = a.storefront.name.toLowerCase().compareTo(
                  b.storefront.name.toLowerCase(),
                );
                return c != 0
                    ? c
                    : a.branch.name.toLowerCase().compareTo(
                        b.branch.name.toLowerCase(),
                      );
              });

        if (followed.isEmpty) {
          return CustomerStateMessage(
            icon: Icons.location_off_outlined,
            title: 'Your stores aren\u2019t in this area',
            message: city.isEmpty
                ? 'Set your city to see the stores you follow.'
                : 'None of the stores you follow are published in $city.',
          );
        }

        // Stats
        final openCount = followed.where((l) => branchIsOpen(l.branch)).length;
        // Points are per business, so count each store once.
        final pointsStores = <String, CustomerStorefront>{
          for (final l in followed)
            if (l.storefront.pointsPerCurrencyUnit != 0)
              l.storefront.businessId: l.storefront,
        };
        var totalPoints = 0;
        for (final s in pointsStores.values) {
          totalPoints +=
              ref
                  .watch(
                    customerHomePointsProvider((
                      userId: userId,
                      businessId: s.businessId,
                    )),
                  )
                  .value ??
              0;
        }

        // Filter + search
        final q = _query.trim().toLowerCase();
        final shown = followed.where((l) {
          switch (_filter) {
            case _FollowFilter.open:
              if (!branchIsOpen(l.branch)) return false;
            case _FollowFilter.points:
              if (l.storefront.pointsPerCurrencyUnit == 0) return false;
            case _FollowFilter.all:
              break;
          }
          if (q.isEmpty) return true;
          return l.storefront.name.toLowerCase().contains(q) ||
              l.branch.name.toLowerCase().contains(q) ||
              (l.branch.address?.toLowerCase().contains(q) ?? false);
        }).toList();

        Widget chip(_FollowFilter f, String label, int count) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text('$label  $count'),
            selected: _filter == f,
            showCheckmark: false,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              setState(() => _filter = f);
            },
          ),
        );

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(customerHomeBranchStoresProvider(city));
            ref.invalidate(customerHomeFollowsProvider(userId));
            await Future<void>.delayed(const Duration(milliseconds: 350));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _FollowHero(
                    following: followed
                        .map((l) => l.storefront.businessId)
                        .toSet()
                        .length,
                    open: openCount,
                    points: totalPoints,
                    hasPoints: pointsStores.isNotEmpty,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (followed.length > 5) ...[
                        TextField(
                          onChanged: (v) => setState(() => _query = v),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search your stores',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: scheme.surfaceContainerLow,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            chip(_FollowFilter.all, 'All', followed.length),
                            chip(_FollowFilter.open, 'Open now', openCount),
                            if (pointsStores.isNotEmpty)
                              chip(
                                _FollowFilter.points,
                                'Earning points',
                                pointsStores.length,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (shown.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 42,
                          color: scheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No stores match',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Try a different filter or search.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final listing = shown[i];
                      final store = listing.storefront;
                      return _FollowFadeIn(
                        key: ValueKey(listing.branch.id),
                        index: i,
                        child: Dismissible(
                          key: ValueKey('dismiss-${listing.branch.id}'),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => _unfollow(store),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Unfollow',
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.heart_broken_rounded,
                                  color: scheme.onErrorContainer,
                                ),
                              ],
                            ),
                          ),
                          child: _FollowedStoreCard(
                            store: store,
                            branch: listing.branch,
                            userId: userId,
                            onTap: () => _open(listing),
                            onUnfollow: () => _unfollow(store),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FollowHero extends StatelessWidget {
  const _FollowHero({
    required this.following,
    required this.open,
    required this.points,
    required this.hasPoints,
  });

  final int following;
  final int open;
  final int points;
  final bool hasPoints;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget stat(String value, String label, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        decoration: BoxDecoration(
          color: scheme.onPrimary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.onPrimary.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 16,
              color: scheme.onPrimary.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: scheme.onPrimary.withValues(alpha: 0.85),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: customerHeroDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -60,
            child: CustomerRing(size: 170, color: scheme.onPrimary),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: scheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      color: scheme.onPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your stores',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'Everything you follow, in one place',
                          style: TextStyle(
                            color: scheme.onPrimary.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  stat('$following', 'Following', Icons.favorite_rounded),
                  const SizedBox(width: 8),
                  stat('$open', 'Open now', Icons.storefront_rounded),
                  if (hasPoints) ...[
                    const SizedBox(width: 8),
                    stat(
                      NumberFormat.compact().format(points),
                      'Points',
                      Icons.stars_rounded,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FollowedStoreCard extends ConsumerWidget {
  const _FollowedStoreCard({
    required this.store,
    required this.userId,
    required this.onTap,
    required this.onUnfollow,
    required this.branch,
  });

  final CustomerStorefront store;
  final String userId;
  final VoidCallback onTap;
  final VoidCallback onUnfollow;
  final CustomerStoreBranchWithCity branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = branchIsOpen(branch);
    final hasPoints = store.pointsPerCurrencyUnit != 0;
    final int? points = hasPoints
        ? ref
              .watch(
                customerHomePointsProvider((
                  userId: userId,
                  businessId: store.businessId,
                )),
              )
              .value
        : null;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomerStoreAvatar(name: store.name, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          branch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (branch.address?.isNotEmpty == true)
                          Text(
                            branch.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                branchHoursToday(branch),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Unfollow',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.errorContainer.withValues(
                        alpha: 0.55,
                      ),
                      foregroundColor: scheme.error,
                    ),
                    onPressed: onUnfollow,
                    icon: const Icon(Icons.favorite_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  customerOpenPill(open),
                  if (store.offlineEnabled)
                    CustomerPill(
                      label: 'Offline catalog',
                      color: scheme.secondary,
                      icon: Icons.download_done_rounded,
                    ),
                ],
              ),
              if (hasPoints) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: kCustomerWarn.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.stars_rounded,
                        color: kCustomerWarn,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${NumberFormat.decimalPattern().format(points ?? 0)} points',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Earn ${store.pointsPerCurrencyUnit} per ${store.currencyCode} 1 spent',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowingEmpty extends StatelessWidget {
  const _FollowingEmpty({required this.onDiscover});
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                  ),
                ),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primaryContainer,
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 44,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'No followed stores yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Follow your favourite stores to order faster, '
              'see their catalog and earn points.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onDiscover,
              icon: const Icon(Icons.explore_rounded),
              label: const Text(
                'Discover stores',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft staggered entrance for list items.
class _FollowFadeIn extends StatelessWidget {
  const _FollowFadeIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + (index > 8 ? 8 : index) * 60),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: c),
      ),
      child: child,
    );
  }
}