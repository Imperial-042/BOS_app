import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_design.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _OrderFilter { all, active, past }

// ============================================================================
// STATUS PRESENTATION
// ============================================================================

IconData _statusIcon(String status) => switch (status) {
  'pending' => Icons.schedule_rounded,
  'accepted' => Icons.thumb_up_alt_rounded,
  'preparing' => Icons.takeout_dining_rounded,
  'ready' => Icons.shopping_bag_rounded,
  'completed' => Icons.check_circle_rounded,
  'rejected' => Icons.block_rounded,
  'cancelled' => Icons.cancel_rounded,
  _ => Icons.receipt_long_rounded,
};

String _statusMessage(String status) => switch (status) {
  'pending' => 'Waiting for the store to confirm your order',
  'accepted' => 'The store accepted your order',
  'preparing' => 'Your order is being prepared',
  'ready' => 'Ready! Head over to pick it up',
  'completed' => 'Picked up. Enjoy!',
  'rejected' => 'The store couldn\u2019t take this order',
  'cancelled' => 'This order was cancelled',
  _ => status,
};

// ============================================================================
// TAB
// ============================================================================

class CustomerOrdersTab extends ConsumerStatefulWidget {
  const CustomerOrdersTab({
    super.key,
    required this.userId,
    required this.onDiscover,
  });

  final String userId;

  /// Jumps to the Discover tab from the empty state.
  final VoidCallback onDiscover;

  @override
  ConsumerState<CustomerOrdersTab> createState() => _CustomerOrdersTabState();
}

class _CustomerOrdersTabState extends ConsumerState<CustomerOrdersTab> {
  _OrderFilter _filter = _OrderFilter.all;

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final orders = ref.watch(customerHomeOrdersProvider(userId));

    return orders.when(
      loading: () => ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [SkeletonList()],
      ),
      error: (error, _) => CustomerStateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Orders are unavailable',
        message: friendlyError(error),
        action: FilledButton.tonal(
          onPressed: () => ref.invalidate(customerHomeOrdersProvider(userId)),
          child: const Text('Refresh'),
        ),
      ),
      data: (values) {
        if (values.isEmpty) {
          return CustomerStateMessage(
            icon: Icons.receipt_long_outlined,
            title: 'No orders yet',
            message:
                'Follow a store and place your first order. '
                'It will show up here, live.',
            action: FilledButton.icon(
              onPressed: widget.onDiscover,
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Discover stores'),
            ),
          );
        }

        final live = values
            .where((o) => customerLiveOrderStatuses.contains(o.status))
            .toList();
        final past = values
            .where((o) => !customerLiveOrderStatuses.contains(o.status))
            .toList();
        final completed = values.where((o) => o.status == 'completed').length;

        Widget chip(_OrderFilter f, String label, int count) => Padding(
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

        final children = <Widget>[];
        var n = 0;
        void addSection(String title, IconData icon, List<CustomerOrder> list) {
          if (list.isEmpty) return;
          children.add(_SectionHeader(title: title, icon: icon, count: list.length));
          for (final o in list) {
            children.add(
              _FadeIn(
                key: ValueKey('fade-${o.id}'),
                index: n++,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OrderCard(key: ValueKey(o.id), order: o),
                ),
              ),
            );
          }
        }

        if (_filter != _OrderFilter.past) {
          addSection('In progress', Icons.bolt_rounded, live);
        }
        if (_filter != _OrderFilter.active) {
          addSection('Order history', Icons.history_rounded, past);
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(customerHomeOrdersProvider(userId));
            await Future<void>.delayed(const Duration(milliseconds: 350));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _OrdersHero(
                    active: live.length,
                    completed: completed,
                    total: values.length,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        chip(_OrderFilter.all, 'All', values.length),
                        chip(_OrderFilter.active, 'In progress', live.length),
                        chip(_OrderFilter.past, 'Past', past.length),
                      ],
                    ),
                  ),
                ),
              ),
              if (children.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 56),
                    child: Column(
                      children: [
                        Icon(
                          Icons.done_all_rounded,
                          size: 42,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nothing in progress',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'New orders will appear here instantly.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList(delegate: SliverChildListDelegate(children)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// HERO + SECTION HEADER
// ============================================================================

class _OrdersHero extends StatelessWidget {
  const _OrdersHero({
    required this.active,
    required this.completed,
    required this.total,
  });

  final int active;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget stat(String value, String label, IconData icon, {bool glow = false}) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: glow ? 0.26 : 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.onPrimary.withValues(alpha: glow ? 0.4 : 0.14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: scheme.onPrimary.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    height: 1,
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
                      active > 0
                          ? Icons.local_shipping_rounded
                          : Icons.receipt_long_rounded,
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
                          'Your orders',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          active > 0
                              ? '$active order${active == 1 ? ' is' : 's are'} on the way'
                              : 'Nothing in progress right now',
                          style: TextStyle(
                            color: scheme.onPrimary.withValues(alpha: 0.88),
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
                  stat('$active', 'In progress', Icons.bolt_rounded,
                      glow: active > 0),
                  const SizedBox(width: 8),
                  stat('$completed', 'Completed', Icons.check_circle_rounded),
                  const SizedBox(width: 8),
                  stat('$total', 'All orders', Icons.receipt_long_rounded),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.count,
  });

  final String title;
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ORDER CARD
// ============================================================================

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({super.key, required this.order});

  final CustomerOrder order;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _expanded = false;
  Future<List<CustomerOrderItem>>? _items;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() {
      _expanded = !_expanded;
      _items ??= ref
          .read(customerCommerceServiceProvider)
          .loadOrderItems(widget.order.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final order = widget.order;
    final isLive = customerLiveOrderStatuses.contains(order.status);
    final color = customerStatusColor(context, order.status);
    final showMessage = isLive ||
        order.status == 'rejected' ||
        order.status == 'cancelled';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: isLive
            ? Color.alphaBlend(
                color.withValues(alpha: 0.07),
                scheme.surfaceContainerLow,
              )
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isLive ? color.withValues(alpha: 0.4) : Colors.transparent,
          width: 1.4,
        ),
        boxShadow: isLive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CustomerStoreAvatar(name: order.branchName, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.branchName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: CustomerPill(
                                label: customerStatusLabel(order.status),
                                color: color,
                                icon: _statusIcon(order.status),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatCustomerPrice(
                              order.totalCents,
                              order.currencyCode,
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.expand_more_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (showMessage) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(_statusIcon(order.status), size: 18, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMessage(order.status),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isLive) _OrderStepper(status: order.status),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: _Receipt(order: order, items: _items),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RECEIPT
// ============================================================================

class _Receipt extends StatelessWidget {
  const _Receipt({required this.order, required this.items});

  final CustomerOrder order;
  final Future<List<CustomerOrderItem>>? items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: FutureBuilder<List<CustomerOrderItem>>(
        future: items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              'Unable to load items: ${friendlyError(snapshot.error!)}',
              style: TextStyle(color: scheme.error),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(14),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Order details',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final item in snapshot.data!)
                _OrderItemRow(item: item, currencyCode: order.currencyCode),
              const SizedBox(height: 6),
              _DashedLine(color: scheme.outlineVariant),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatCustomerPrice(order.totalCents, order.currencyCode),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item, required this.currencyCode});

  final CustomerOrderItem item;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${NumberFormat('0.###').format(item.quantity)}×',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${item.unit} · ${formatCustomerPrice(item.unitPriceCents, currencyCode)} each',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatCustomerPrice(item.totalCents, currencyCode),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 9).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(width: 5, height: 1.5, color: color),
          ),
        );
      },
    );
  }
}

// ============================================================================
// LIVE STEPPER
// ============================================================================

class _OrderStepper extends StatelessWidget {
  const _OrderStepper({required this.status});

  final String status;

  static const _steps = [
    ('pending', 'Sent'),
    ('accepted', 'Accepted'),
    ('preparing', 'Preparing'),
    ('ready', 'Ready'),
    ('completed', 'Done'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = _steps.indexWhere((s) => s.$1 == status);
    if (index < 0) return const SizedBox.shrink();
    final color = customerStatusColor(context, status);
    final off = scheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 2),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i == 0
                              ? Colors.transparent
                              : (i <= index ? color : off),
                        ),
                      ),
                      _StepDot(
                        icon: _statusIcon(_steps[i].$1),
                        reached: i <= index,
                        current: i == index,
                        pulse: i == index && status != 'completed',
                        color: color,
                      ),
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i == _steps.length - 1
                              ? Colors.transparent
                              : (i < index ? color : off),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _steps[i].$2,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                      color: i <= index ? color : scheme.onSurfaceVariant,
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

class _StepDot extends StatefulWidget {
  const _StepDot({
    required this.icon,
    required this.reached,
    required this.current,
    required this.pulse,
    required this.color,
  });

  final IconData icon;
  final bool reached;
  final bool current;
  final bool pulse;
  final Color color;

  @override
  State<_StepDot> createState() => _StepDotState();
}

class _StepDotState extends State<_StepDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _StepDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.pulse && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.current ? 30.0 : 24.0;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulse)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Container(
                width: size + 14 * _c.value,
                height: size + 14 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - _c.value)),
                ),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.reached ? widget.color : scheme.surfaceContainerHighest,
            ),
            child: Icon(
              widget.icon,
              size: widget.current ? 16 : 13,
              color: widget.reached
                  ? Colors.white
                  : scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ENTRANCE
// ============================================================================

class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.index, required this.child});

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