import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_design.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CustomerPointsTab extends ConsumerWidget {
  const CustomerPointsTab({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(customerHomeFollowsProvider(userId));
    final city =
        ref.watch(customerHomeProfileProvider(userId)).value?.city?.trim() ??
        '';
    final stores =
        ref.watch(customerHomeStoresProvider(city)).value ??
        const <CustomerStorefront>[];

    return follows.when(
      loading: () => ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [SkeletonList(kind: SkeletonKind.order, count: 3)],
      ),
      error: (error, _) => CustomerStateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load points',
        message: friendlyError(error),
        action: FilledButton.tonal(
          onPressed: () => ref.invalidate(customerHomeFollowsProvider(userId)),
          child: const Text('Try again'),
        ),
      ),
      data: (values) {
        final storeById = {for (final s in stores) s.businessId: s};
        final followed = values
            .map((follow) => storeById[follow.businessId])
            .whereType<CustomerStorefront>()
            .toList();
        if (followed.isEmpty) {
          return const CustomerStateMessage(
            icon: Icons.stars_outlined,
            title: 'Loyalty points',
            message: 'Follow stores to see their loyalty programs here.',
          );
        }

        var total = 0;
        for (final store in followed) {
          if (store.pointsPerCurrencyUnit == 0) continue;
          total +=
              ref
                  .watch(
                    customerHomePointsProvider((
                      userId: userId,
                      businessId: store.businessId,
                    )),
                  )
                  .value ??
              0;
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(customerHomeFollowsProvider(userId));
            ref.invalidate(customerHomeStoresProvider(city));
            await Future<void>.delayed(const Duration(milliseconds: 350));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _PointsHero(total: total, storeCount: followed.length),
              const SizedBox(height: 18),
              for (final store in followed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PointsStoreCard(userId: userId, store: store),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PointsHero extends StatelessWidget {
  const _PointsHero({required this.total, required this.storeCount});

  final int total;
  final int storeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: customerHeroDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: CustomerRing(size: 150, color: scheme.onPrimary),
          ),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.onPrimary.withValues(alpha: 0.18),
                ),
                child: Icon(
                  Icons.stars_rounded,
                  color: scheme.onPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total points',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        NumberFormat.decimalPattern().format(total),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1.05,
                        ),
                      ),
                    ),
                    Text(
                      'across $storeCount followed store'
                      '${storeCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointsStoreCard extends ConsumerWidget {
  const _PointsStoreCard({required this.userId, required this.store});

  final String userId;
  final CustomerStorefront store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = store.pointsPerCurrencyUnit != 0;
    final int? points = active
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
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CustomerStoreAvatar(name: store.name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active
                        ? 'Earn ${store.pointsPerCurrencyUnit} point(s) per ${store.currencyCode} 1 spent.'
                        : 'This store has not started a points program.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      NumberFormat.decimalPattern().format(points ?? 0),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    Text(
                      'pts',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}