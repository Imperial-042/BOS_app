// lib/features/customer/presentation/customer_widgets.dart
//
// Shared helpers for the customer app: persistent cart, friendly errors and
// skeleton loaders.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/features/transactions/domain/product_variants.dart';

class CustomerCartLine {
  const CustomerCartLine({
    required this.itemId,
    required this.quantity,
    this.options = const [],
  });

  final String itemId;
  final double quantity;
  final List<ProductOptionSelection> options;

  String get key =>
      '$itemId:${options.map((option) => option.choiceId).join(',')}';

  CustomerCartLine copyWith({double? quantity}) => CustomerCartLine(
    itemId: itemId,
    quantity: quantity ?? this.quantity,
    options: options,
  );
}

// ------------------------------------------------------------------ cart --

/// Cart per store (keyed by businessId). Lives for the app session, so
/// leaving a store and coming back keeps what the customer picked.
final customerCartProvider =
    StateProvider.family<List<CustomerCartLine>, String>(
      (ref, businessId) => const <CustomerCartLine>[],
    );

// ---------------------------------------------------------------- errors --

/// Turns raw exceptions into messages a customer can act on.
String friendlyError(Object error) {
  if (error is StateError) return error.message; // intentional messages
  final t = error.toString().toLowerCase();
  if (t.contains('socketexception') ||
      t.contains('failed host lookup') ||
      t.contains('network') ||
      t.contains('connection') ||
      t.contains('timeout') ||
      t.contains('timed out') ||
      t.contains('clientexception')) {
    return 'Check your internet connection and try again.';
  }
  if (t.contains('permission') ||
      t.contains('not authorized') ||
      t.contains('unauthorized') ||
      t.contains('403') ||
      t.contains('row-level security')) {
    return 'You don\u2019t have access to this right now.';
  }
  if (t.contains('not found') || t.contains('404')) {
    return 'We couldn\u2019t find that. It may have been removed.';
  }
  return 'Something went wrong. Please try again.';
}

// ------------------------------------------------------------- skeletons --

/// Pulses all [Bone]s inside it together (one controller, no shaders).
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});
  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.45,
    end: 1,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

enum SkeletonKind { store, order }

/// A column of placeholder cards. Use inside a ListView or SliverToBoxAdapter.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.kind = SkeletonKind.store,
    this.count = 4,
  });

  final SkeletonKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: SkeletonPulse(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < count; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: kind == SkeletonKind.store
                        ? const _StoreBones()
                        : const _OrderBones(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreBones extends StatelessWidget {
  const _StoreBones();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Bone(width: 52, height: 52, radius: 17),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone(width: 150, height: 14),
              SizedBox(height: 8),
              Bone(height: 10),
              SizedBox(height: 10),
              Row(
                children: [
                  Bone(width: 62, height: 20, radius: 10),
                  SizedBox(width: 6),
                  Bone(width: 78, height: 20, radius: 10),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderBones extends StatelessWidget {
  const _OrderBones();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Bone(width: 46, height: 46, radius: 15),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone(width: 120, height: 14),
                  SizedBox(height: 8),
                  Bone(width: 84, height: 18, radius: 9),
                ],
              ),
            ),
            Bone(width: 64, height: 16),
          ],
        ),
        SizedBox(height: 16),
        Bone(height: 8, radius: 4),
      ],
    );
  }
}
