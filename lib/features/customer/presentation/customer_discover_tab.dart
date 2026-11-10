import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_design.dart';
import 'package:bos_application/features/customer/presentation/customer_location_sheet.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:bos_application/features/customer/presentation/customer_store_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomerDiscoverTab extends ConsumerWidget {
  const CustomerDiscoverTab({
    super.key,
    required this.userId,
    required this.search,
    required this.onSearchChanged,
  });

  final String userId;
  final String search;
  final ValueChanged<String> onSearchChanged;

  Future<void> _openBranch(
    BuildContext context,
    WidgetRef ref, {
    required StoreBranchListing listing,
    required String city,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerStoreScreen(
          businessId: listing.storefront.businessId,
          branchId: listing.branch.id,
        ),
      ),
    );
    if (context.mounted) {
      ref.invalidate(customerHomeBranchStoresProvider(city));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ref.watch(customerHomeProfileProvider(userId));
    final city = profile.value?.city?.trim() ?? '';
    final stores = ref.watch(customerHomeBranchStoresProvider(city));

    Widget header() => Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: customerHeroDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -60,
            child: CustomerRing(size: 160, color: scheme.onPrimary),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Find your next\nfavourite store',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: profile.isLoading
                    ? null
                    : () => editCustomerLocation(
                        context,
                        ref,
                        userId: userId,
                        profile: profile.value,
                      ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.onPrimary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: scheme.onPrimary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          city.isEmpty ? 'Set your city' : 'Stores near $city',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: scheme.onPrimary.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search stores',
                  filled: true,
                  fillColor: scheme.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final Widget content = profile.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => customerSliverMessage(
        CustomerStateMessage(
          icon: Icons.person_pin_circle_outlined,
          title: 'Location profile unavailable',
          message: friendlyError(error),
        ),
      ),
      data: (customerProfile) => city.isEmpty
          ? customerSliverMessage(
              CustomerStateMessage(
                icon: Icons.location_off_outlined,
                title: 'Set your city to discover stores',
                message:
                    'We use your city to show nearby storefronts. Your street address stays private.',
                action: FilledButton.icon(
                  onPressed: () => editCustomerLocation(
                    context,
                    ref,
                    userId: userId,
                    profile: customerProfile,
                  ),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add city'),
                ),
              ),
            )
          : stores.when(
              loading: () => const SliverToBoxAdapter(child: SkeletonList()),
              error: (error, _) => customerSliverMessage(
                CustomerStateMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Stores are unavailable',
                  message: friendlyError(error),
                  action: FilledButton.tonal(
                    onPressed: () =>
                        ref.invalidate(customerHomeBranchStoresProvider(city)),
                    child: const Text('Try again'),
                  ),
                ),
              ),
              data: (values) {
                final query = search.trim().toLowerCase();
                final filtered =
                    values.where((l) {
                      if (query.isEmpty) return true;
                      final s = l.storefront;
                      final b = l.branch;
                      return s.name.toLowerCase().contains(query) ||
                          b.name.toLowerCase().contains(query) ||
                          (b.address?.toLowerCase().contains(query) ?? false) ||
                          (s.description?.toLowerCase().contains(query) ??
                              false);
                    }).toList()..sort((a, b) {
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
                if (filtered.isEmpty) {
                  return customerSliverMessage(
                    CustomerStateMessage(
                      icon: Icons.store_mall_directory_outlined,
                      title: query.isEmpty
                          ? 'No stores in $city'
                          : 'No stores match “$search”',
                      message: query.isEmpty
                          ? 'Published stores in your city will appear here.'
                          : 'Try a different name or clear the search.',
                    ),
                  );
                }
                return SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                query.isEmpty ? 'Stores near you' : 'Results',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              '${filtered.length} location'
                              '${filtered.length == 1 ? '' : 's'}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final listing = filtered[index];
                          return _BranchStoreCard(
                            listing: listing,
                            onTap: () => _openBranch(
                              context,
                              ref,
                              listing: listing,
                              city: city,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(customerHomeProfileProvider(userId));
        ref.invalidate(customerHomeBranchStoresProvider(city));
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(child: header()),
          ),
          content,
        ],
      ),
    );
  }
}

class _BranchStoreCard extends StatelessWidget {
  const _BranchStoreCard({required this.listing, required this.onTap});

  final StoreBranchListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = listing.storefront;
    final branch = listing.branch;
    final open = branchIsOpen(branch);

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
                            maxLines: 2,
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
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  customerOpenPill(open),
                  if (store.pointsPerCurrencyUnit != 0)
                    CustomerPill(
                      label:
                          'Earn ${store.pointsPerCurrencyUnit} pt per ${store.currencyCode} 1',
                      color: kCustomerWarn,
                      icon: Icons.stars_rounded,
                    ),
                  if (store.offlineEnabled)
                    CustomerPill(
                      label: 'Offline catalog',
                      color: scheme.secondary,
                      icon: Icons.download_done_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
