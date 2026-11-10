// lib/features/branches/branches_screen.dart
// Administration -> Branches: add / edit / deactivate branches, assign staff.

import 'dart:math' as math;
import 'dart:async';

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart'
    show businessMembersProvider;
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branch/branch_service.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/location/location_models.dart';
import 'package:bos_application/core/location/location_picker_map.dart';
import 'package:bos_application/core/location/location_permissions.dart';
import 'package:bos_application/core/location/location_services.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:bos_application/features/people/hr_providers.dart'
    show hrNamesProvider;
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ------------------------------------------------------------ helpers --

const _green = Color(0xFF159B67);
const _amber = Color(0xFFB7791F);

String _err(Object e) => e is StateError ? e.message : e.toString();

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Text(m),
    ),
  );

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

Color _roleColor(String roleId) {
  if (roleId == 'owner') return _amber;
  const palette = [
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
  ];
  return palette[roleId.hashCode.abs() % palette.length];
}

/// Soft entrance: fades and slides up, staggered by [index].
class _FadeSlide extends StatelessWidget {
  const _FadeSlide({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + math.min(index, 8) * 70),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c),
      ),
      child: child,
    );
  }
}

// ------------------------------------------------------------- screen --

enum _Filter { all, active, inactive }

enum _CardAction { edit, staff, toggle }

class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';
  bool _tipOpen = true;

  Future<void> _edit(Branch? b) async {
    final businessId = ref.read(selectedBusinessIdProvider);
    final service = ref.read(branchServiceProvider);
    final db = ref.read(databaseProvider);
    final existingLocation = b == null
        ? null
        : await db
              .customSelect(
                'SELECT country, province_state, city, street_barangay, '
                'postal_code FROM branches WHERE id = ?',
                variables: [Variable<String>(b.id)],
              )
              .getSingleOrNull();
    final existingCoordinate = b == null
        ? null
        : await db
              .customSelect(
                'SELECT latitude, longitude, location_accuracy_meters '
                'FROM branch_locations WHERE branch_id = ?',
                variables: [Variable<String>(b.id)],
              )
              .getSingleOrNull();
    if (!mounted) return;
    final result =
        await showDialog<
          ({
            String name,
            String country,
            String province,
            String city,
            String streetBarangay,
            String postalCode,
            String phone,
            GeoCoordinate? coordinate,
          })
        >(
          context: context,
          builder: (_) => _BranchDialog(
            existing: b,
            country: existingLocation?.read<String?>('country'),
            province: existingLocation?.read<String?>('province_state'),
            city: existingLocation?.read<String?>('city'),
            streetBarangay:
                existingLocation?.read<String?>('street_barangay') ??
                b?.address,
            postalCode: existingLocation?.read<String?>('postal_code'),
            coordinate:
                existingCoordinate == null ||
                    existingCoordinate.read<double?>('latitude') == null ||
                    existingCoordinate.read<double?>('longitude') == null
                ? null
                : GeoCoordinate(
                    latitude: existingCoordinate.read<double>('latitude'),
                    longitude: existingCoordinate.read<double>('longitude'),
                    accuracyMeters: existingCoordinate.read<double?>(
                      'location_accuracy_meters',
                    ),
                  ),
          ),
        );
    if (result == null) return;
    try {
      if (b == null) {
        final created = await service.createBranch(
          businessId: businessId,
          name: result.name,
          country: result.country,
          province: result.province,
          city: result.city,
          streetBarangay: result.streetBarangay,
          postalCode: result.postalCode,
          phone: result.phone,
        );
        await _saveBranchCoordinate(created.id, businessId, result.coordinate);
        await _updatePublishedBranchAddress(
          businessId,
          created.id,
          result.streetBarangay,
          result.city,
        );
      } else {
        await service.updateBranch(
          b.id,
          name: result.name,
          country: result.country,
          province: result.province,
          city: result.city,
          streetBarangay: result.streetBarangay,
          postalCode: result.postalCode,
          phone: result.phone,
        );
        await _saveBranchCoordinate(b.id, businessId, result.coordinate);
        await _updatePublishedBranchAddress(
          businessId,
          b.id,
          result.streetBarangay,
          result.city,
        );
      }

      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    }
  }

  Future<void> _updatePublishedBranchAddress(
    String businessId,
    String branchId,
    String address,
    String city,
  ) async {
    await ref
        .read(customerCommerceServiceProvider)
        .updateBranchStorefrontAddress(
          businessId: businessId,
          branchId: branchId,
          address: address,
          city: city,
        );
  }

  Future<void> _saveBranchCoordinate(
    String branchId,
    String businessId,
    GeoCoordinate? coordinate,
  ) async {
    if (coordinate == null) return;
    await ref
        .read(databaseProvider)
        .customStatement(
          '''
      INSERT INTO branch_locations (
        branch_id, business_id, latitude, longitude,
        location_accuracy_meters, location_verified, location_updated_at
      ) VALUES (?, ?, ?, ?, ?, 'unverified', ?)
      ON CONFLICT(branch_id) DO UPDATE SET
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        location_accuracy_meters = excluded.location_accuracy_meters,
        location_verified = CASE
          WHEN branch_locations.latitude != excluded.latitude
            OR branch_locations.longitude != excluded.longitude
          THEN 'updated' ELSE branch_locations.location_verified END,
        location_updated_at = excluded.location_updated_at
      ''',
          [
            branchId,
            businessId,
            coordinate.latitude,
            coordinate.longitude,
            coordinate.accuracyMeters,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ],
        );
  }

  void _staff(Branch b) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _StaffSheet(branch: b),
    );
  }

  Future<void> _toggleActive(Branch b) async {
    final deactivating = b.isActive;
    if (deactivating) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.pause_circle_outline_rounded,
              color: _amber,
              size: 30,
            ),
          ),
          title: Text('Deactivate ${b.name}?'),
          content: const Text(
            'It will disappear from branch pickers. History is kept and you '
            'can reactivate it any time.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(branchServiceProvider).setActive(b.id, !deactivating);
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    }
  }

  List<Branch> _visible(List<Branch> all) {
    final q = _query.trim().toLowerCase();
    final list = all.where((b) {
      switch (_filter) {
        case _Filter.active:
          if (!b.isActive) return false;
        case _Filter.inactive:
          if (b.isActive) return false;
        case _Filter.all:
          break;
      }
      if (q.isEmpty) return true;
      return b.name.toLowerCase().contains(q) ||
          (b.code ?? '').toLowerCase().contains(q) ||
          (b.address ?? '').toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      if (a.isHeadquarters != b.isHeadquarters) {
        return a.isHeadquarters ? -1 : 1;
      }
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canManage = ref.watch(canProvider(BosPermission.branchManage));
    final branches = ref.watch(allBranchesProvider).value ?? const <Branch>[];
    final activeCount = branches.where((b) => b.isActive).length;
    final inactiveCount = branches.length - activeCount;
    final shown = _visible(branches);

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'add_branch',
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add_business_rounded),
              label: const Text(
                'Add branch',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, c) {
          final side = ((c.maxWidth - 760) / 2).clamp(16.0, 9999.0);
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                titleSpacing: 20,
                title: const Text(
                  'Branches',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 4, side, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _FadeSlide(
                      index: 0,
                      child: _Hero(
                        active: activeCount,
                        inactive: inactiveCount,
                        total: branches.length,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FadeSlide(
                      index: 1,
                      child: _TipCard(
                        open: _tipOpen,
                        onToggle: () => setState(() => _tipOpen = !_tipOpen),
                      ),
                    ),
                    if (branches.length > 1) ...[
                      const SizedBox(height: 16),
                      _FadeSlide(
                        index: 2,
                        child: _Toolbar(
                          filter: _filter,
                          all: branches.length,
                          active: activeCount,
                          inactive: inactiveCount,
                          showSearch: branches.length > 3,
                          onFilter: (f) => setState(() => _filter = f),
                          onQuery: (q) => setState(() => _query = q),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
              if (branches.isEmpty)
                SliverToBoxAdapter(
                  child: _EmptyState(
                    canManage: canManage,
                    onAdd: () => _edit(null),
                  ),
                )
              else if (shown.isEmpty)
                SliverToBoxAdapter(child: _NoMatches(scheme: scheme))
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, 120),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (_, i) {
                      final b = shown[i];
                      return _FadeSlide(
                        key: ValueKey(b.id),
                        index: i + 3,
                        child: _BranchCard(
                          branch: b,
                          canManage: canManage,
                          onEdit: () => _edit(b),
                          onStaff: () => _staff(b),
                          onToggle: () => _toggleActive(b),
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
  }
}

// --------------------------------------------------------------- hero --

class _Hero extends StatelessWidget {
  const _Hero({
    required this.active,
    required this.inactive,
    required this.total,
  });
  final int active;
  final int inactive;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : active / total;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.heroGradient.first.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -50, top: -70, child: _Orb(size: 200, alpha: 0.09)),
          Positioned(
            right: 40,
            bottom: -60,
            child: _Orb(size: 120, alpha: 0.07),
          ),
          Positioned(
            left: -30,
            bottom: -40,
            child: _Orb(size: 90, alpha: 0.05),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Icon(
                        Icons.hub_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your locations',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Branches, teams and cash drawers',
                            style: TextStyle(
                              color: Color(0xD9FFFFFF),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        '$active',
                        'Active',
                        Icons.check_circle_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStat(
                        '$inactive',
                        'Inactive',
                        Icons.pause_circle_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStat(
                        '$total',
                        'Total',
                        Icons.store_mall_directory_rounded,
                      ),
                    ),
                  ],
                ),
                if (total > 0) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: ratio),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    active == total
                        ? 'All branches are open for business'
                        : '$active of $total branches open for business',
                    style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- tip --

class _TipCard extends StatelessWidget {
  const _TipCard({required this.open, required this.onToggle});
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'How branches work',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (open) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Each branch has its own stock, register, cash drawer '
                    'and team. Suppliers, customers, products and the '
                    'chart of accounts are shared. Set each branch address, '
                    'then save the storefront settings to publish its '
                    'customer pickup location.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
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

// ------------------------------------------------------------ toolbar --

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.filter,
    required this.all,
    required this.active,
    required this.inactive,
    required this.showSearch,
    required this.onFilter,
    required this.onQuery,
  });

  final _Filter filter;
  final int all;
  final int active;
  final int inactive;
  final bool showSearch;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (showSearch) ...[
          TextField(
            onChanged: onQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search name, code or address',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Filter>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
            segments: [
              ButtonSegment(value: _Filter.all, label: Text('All  $all')),
              ButtonSegment(
                value: _Filter.active,
                label: Text('Active  $active'),
              ),
              ButtonSegment(
                value: _Filter.inactive,
                label: Text('Inactive  $inactive'),
              ),
            ],
            selected: {filter},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              onFilter(s.first);
            },
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------- branch card --

class _BranchCard extends ConsumerWidget {
  const _BranchCard({
    required this.branch,
    required this.canManage,
    required this.onEdit,
    required this.onStaff,
    required this.onToggle,
  });

  final Branch branch;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onStaff;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = branch;
    final memberIds =
        (ref.watch(branchMembersOfProvider(b.id)).value ??
                const <BranchMember>[])
            .map((m) => m.userId)
            .toList();
    final names = ref.watch(hrNamesProvider);
    final staffNames = [for (final id in memberIds) names[id] ?? 'Team member'];

    final accent = !b.isActive
        ? scheme.outline
        : (b.isHeadquarters ? _amber : scheme.primary);
    final hasAddress = (b.address ?? '').isNotEmpty;
    final hasPhone = (b.phone ?? '').isNotEmpty;

    return Opacity(
      opacity: b.isActive ? 1 : 0.7,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: b.isHeadquarters && b.isActive
                ? _amber.withValues(alpha: 0.4)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canManage ? onEdit : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.9),
                              accent.withValues(alpha: 0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          b.isHeadquarters
                              ? Icons.home_work_rounded
                              : Icons.store_mall_directory_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (b.code != null)
                                    _Pill(b.code!, scheme.primary),
                                  if (b.isHeadquarters)
                                    const _Pill('Main branch', _amber),
                                  _Pill(
                                    b.isActive ? 'Active' : 'Inactive',
                                    b.isActive ? _green : scheme.outline,
                                    dot: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (canManage)
                        PopupMenuButton<_CardAction>(
                          tooltip: 'More',
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          onSelected: (a) {
                            switch (a) {
                              case _CardAction.edit:
                                onEdit();
                              case _CardAction.staff:
                                onStaff();
                              case _CardAction.toggle:
                                onToggle();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: _CardAction.edit,
                              child: _MenuRow(Icons.edit_outlined, 'Edit'),
                            ),
                            const PopupMenuItem(
                              value: _CardAction.staff,
                              child: _MenuRow(
                                Icons.groups_outlined,
                                'Manage staff',
                              ),
                            ),
                            if (!b.isHeadquarters)
                              PopupMenuItem(
                                value: _CardAction.toggle,
                                child: _MenuRow(
                                  b.isActive
                                      ? Icons.pause_circle_outline_rounded
                                      : Icons.play_circle_outline_rounded,
                                  b.isActive ? 'Deactivate' : 'Reactivate',
                                ),
                              ),
                          ],
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasAddress)
                            _InfoRow(Icons.place_rounded, b.address!)
                          else
                            _InfoRow(
                              Icons.add_location_alt_outlined,
                              'No address yet. Add one so customers can find '
                              'this branch.',
                              color: _amber,
                            ),
                          if (hasPhone) _InfoRow(Icons.phone_rounded, b.phone!),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        if (staffNames.isNotEmpty) ...[
                          _AvatarStack(staffNames),
                          const SizedBox(width: 10),
                        ] else ...[
                          Icon(
                            Icons.groups_outlined,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            staffNames.isEmpty
                                ? 'No one assigned'
                                : '${staffNames.length} assigned',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (canManage)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(64, 40),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: onStaff,
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 18,
                            ),
                            label: const Text('Staff'),
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
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack(this.names);
  final List<String> names;
  static const int max = 4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    const size = 32.0;
    const overlap = 21.0;

    Widget bubble(String text, Color color) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.2), scheme.surface),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    return SizedBox(
      height: size,
      width: (count - 1) * overlap + size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * overlap,
              child: bubble(_initials(shown[i]), _roleColor(shown[i])),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * overlap,
              child: bubble('+$extra', scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.dot = false});
  final String text;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: c),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, height: 1.35, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canManage, required this.onAdd});
  final bool canManage;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 32),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                ),
              ),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: Icon(
                  Icons.add_business_rounded,
                  size: 42,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'No branches yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Create your first location to start tracking stock, '
            'registers and teams per branch.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          if (canManage) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add your first branch'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 44, color: scheme.outline),
          const SizedBox(height: 10),
          const Text(
            'No branches match',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different filter or search.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- dialog --

class _BranchDialog extends StatefulWidget {
  const _BranchDialog({
    this.existing,
    this.country,
    this.province,
    this.city,
    this.streetBarangay,
    this.postalCode,
    this.coordinate,
  });

  final Branch? existing;
  final String? country;
  final String? province;
  final String? city;
  final String? streetBarangay;
  final String? postalCode;
  final GeoCoordinate? coordinate;

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _country = TextEditingController(text: widget.country ?? '');
  late final _province = TextEditingController(text: widget.province ?? '');
  late final _city = TextEditingController(text: widget.city ?? '');
  late final _streetBarangay = TextEditingController(
    text: widget.streetBarangay ?? '',
  );
  late final _postalCode = TextEditingController(text: widget.postalCode ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final Listenable _all = Listenable.merge([
    _name,
    _country,
    _province,
    _city,
    _streetBarangay,
    _postalCode,
    _phone,
  ]);
  String? _nameError;
  final _locationErrors = <String, String>{};
  GeoCoordinate? _coordinate;
  late final _geocoder = CachedGeocodingProvider(
    const NominatimGeocodingProvider(),
  );
  bool _lookingUpAddress = false;

  @override
  void initState() {
    super.initState();
    _coordinate = widget.coordinate;
  }

  @override
  void dispose() {
    _geocoder.dispose();
    _name.dispose();
    _country.dispose();
    _province.dispose();
    _city.dispose();
    _streetBarangay.dispose();
    _postalCode.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _selectCoordinate(GeoCoordinate coordinate) async {
    setState(() {
      _coordinate = coordinate;
      _lookingUpAddress = true;
    });
    try {
      final address = await _geocoder.reverse(coordinate);
      if (!mounted || address == null) return;
      void replace(TextEditingController controller, String? value) {
        if (value != null && value.trim().isNotEmpty) {
          controller.text = value.trim();
        }
      }

      replace(_country, address.country);
      replace(_province, address.province ?? address.region);
      replace(_city, address.city);
      final street =
          [address.streetAddress, address.buildingOrUnit, address.barangay]
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .join(', ');
      replace(_streetBarangay, street);
      replace(_postalCode, address.postalCode);
    } catch (error) {
      if (mounted) {
        _snack(context, 'Pin saved, but address lookup failed: $error');
      }
    } finally {
      if (mounted) setState(() => _lookingUpAddress = false);
    }
  }

  int get _filled => [
    _name,
    _country,
    _province,
    _city,
    _streetBarangay,
    _postalCode,
  ].where((c) => c.text.trim().isNotEmpty).length;

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Enter a branch name');
    } else if (_nameError != null) {
      setState(() => _nameError = null);
    }
    final values = {
      'country': _country.text,
      'province': _province.text,
      'city': _city.text,
      'street': _streetBarangay.text,
      'postalCode': _postalCode.text,
    };
    final errors = <String, String>{};
    for (final entry in values.entries) {
      if (entry.value.trim().isEmpty) errors[entry.key] = 'Required';
    }
    if (errors.isNotEmpty || _name.text.trim().isEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _locationErrors
          ..clear()
          ..addAll(errors);
      });
      return;
    }
    Navigator.pop(context, (
      name: _name.text.trim(),
      country: _country.text.trim(),
      province: _province.text.trim(),
      city: _city.text.trim(),
      streetBarangay: _streetBarangay.text.trim(),
      postalCode: _postalCode.text.trim(),
      phone: _phone.text.trim(),
      coordinate: _coordinate,
    ));
  }

  Future<void> _useCurrentLocation() async {
    try {
      final coordinate = await requestCurrentLocation();
      if (mounted) await _selectCoordinate(coordinate);
    } catch (error) {
      if (mounted) _snack(context, error.toString());
    }
  }

  void _clearLocationError(String field) {
    if (_locationErrors.containsKey(field)) {
      setState(() => _locationErrors.remove(field));
    }
  }

  InputDecoration _dec(
    BuildContext context, {
    required String label,
    required IconData icon,
    String? hint,
    String? error,
  }) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(scheme.primary, 1.8),
      errorBorder: border(scheme.error, 1.2),
      focusedErrorBorder: border(scheme.error, 1.8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;
    final isPhilippines = isPhilippinesCountry(_country.text);
    final selectedProvince = philippineProvinces.contains(_province.text)
        ? _province.text
        : null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- header with live progress ----
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 10, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: AppColors.heroGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ListenableBuilder(
                listenable: _all,
                builder: (_, _) {
                  final filled = _filled;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              isNew
                                  ? Icons.add_business_rounded
                                  : Icons.edit_location_alt_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isNew ? 'Add branch' : 'Edit branch',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  isNew
                                      ? 'Set up a new location'
                                      : 'Update details for this location',
                                  style: const TextStyle(
                                    color: Color(0xD9FFFFFF),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(end: filled / 6),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                  builder: (_, v, _) => LinearProgressIndicator(
                                    value: v,
                                    minHeight: 6,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.22,
                                    ),
                                    valueColor: const AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              filled == 6 ? 'Ready' : '$filled / 6 required',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // ---- form ----
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel(Icons.badge_outlined, 'Basics'),
                    TextField(
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(
                        context,
                        label: 'Branch name *',
                        hint: 'e.g. Downtown',
                        icon: Icons.store_mall_directory_outlined,
                        error: _nameError,
                      ),
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(
                        context,
                        label: 'Phone (optional)',
                        icon: Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel(Icons.location_on_outlined, 'Location'),
                    TextField(
                      controller: _country,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(
                        context,
                        label: 'Country *',
                        icon: Icons.public_outlined,
                        error: _locationErrors['country'],
                      ),
                      onChanged: (_) {
                        setState(() => _locationErrors.remove('country'));
                      },
                    ),
                    const SizedBox(height: 12),
                    if (isPhilippines)
                      DropdownButtonFormField<String>(
                        key: const ValueKey('province-ph'),
                        initialValue: selectedProvince,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        borderRadius: BorderRadius.circular(16),
                        decoration: _dec(
                          context,
                          label: 'Province / state *',
                          icon: Icons.map_outlined,
                          error: _locationErrors['province'],
                        ),
                        items: [
                          for (final province in philippineProvinces)
                            DropdownMenuItem(
                              value: province,
                              child: Text(province),
                            ),
                        ],
                        onChanged: (province) {
                          _province.text = province ?? '';
                          setState(() => _locationErrors.remove('province'));
                        },
                      )
                    else
                      TextField(
                        key: const ValueKey('province-text'),
                        controller: _province,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: _dec(
                          context,
                          label: 'Province / state *',
                          icon: Icons.map_outlined,
                          error: _locationErrors['province'],
                        ),
                        onChanged: (_) => _clearLocationError('province'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(
                        context,
                        label: 'City *',
                        icon: Icons.location_city_outlined,
                        error: _locationErrors['city'],
                      ),
                      onChanged: (_) => _clearLocationError('city'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _streetBarangay,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(
                        context,
                        label: 'Street / barangay *',
                        icon: Icons.place_outlined,
                        error: _locationErrors['street'],
                      ),
                      onChanged: (_) => _clearLocationError('street'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _postalCode,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: _dec(
                        context,
                        label: 'Postal code *',
                        icon: Icons.markunread_mailbox_outlined,
                        error: _locationErrors['postalCode'],
                      ),
                      onChanged: (_) => _clearLocationError('postalCode'),
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel(
                      Icons.map_outlined,
                      'Precise map location',
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _useCurrentLocation,
                            icon: const Icon(Icons.my_location_outlined),
                            label: const Text('Use current location'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _lookingUpAddress
                              ? 'Looking up address...'
                              : _coordinate == null
                              ? 'Not set'
                              : 'Pin selected',
                          style: TextStyle(
                            color: _coordinate == null
                                ? scheme.onSurfaceVariant
                                : _green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LocationPickerMap(
                      provider: const OpenStreetMapTileProvider(),
                      selected: _coordinate,
                      onSelected: (coordinate) =>
                          unawaited(_selectCoordinate(coordinate)),
                      height: 190,
                    ),
                    const SizedBox(height: 20),
                    ListenableBuilder(
                      listenable: _all,
                      builder: (_, _) => _PreviewCard(
                        name: _name.text.trim(),
                        phone: _phone.text.trim(),
                        address:
                            [
                                  _streetBarangay.text,
                                  _city.text,
                                  _province.text,
                                  _postalCode.text,
                                  _country.text,
                                ]
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .join(', '),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // ---- sticky footer ----
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _submit,
                      icon: Icon(
                        isNew ? Icons.add_rounded : Icons.check_rounded,
                      ),
                      label: Text(
                        isNew ? 'Create branch' : 'Save changes',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live preview of how the branch will read to staff and pickup customers.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.name,
    required this.address,
    required this.phone,
  });
  final String name;
  final String address;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasName = name.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.storefront_rounded,
              color: scheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PICKUP PREVIEW',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasName ? name : 'Branch name',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: hasName ? scheme.onSurface : scheme.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address.isEmpty ? 'Address will appear here' : address,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: address.isEmpty
                        ? scheme.outline
                        : scheme.onSurfaceVariant,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: TextStyle(
                      fontSize: 12.5,
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

// -------------------------------------------------------- staff sheet --

class _StaffSheet extends ConsumerWidget {
  const _StaffSheet({required this.branch});
  final Branch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final members = ref.watch(businessMembersProvider).value ?? const [];
    final names = ref.watch(hrNamesProvider);
    // THE FIX: resolve custom role ids (c_<uuid>) to their names.
    final labels =
        ref.watch(roleLabelsProvider).value ?? const <String, String>{};
    final assigned = {
      for (final m
          in ref.watch(branchMembersOfProvider(branch.id)).value ??
              const <BranchMember>[])
        m.userId,
    };
    final active = members.where((m) => m.status == 'active').toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.groups_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staff at ${branch.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${assigned.length} of ${active.length} assigned',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'People with no branch assigned can work in every branch. '
                  'Once assigned, they only see their branches. Owners '
                  'always see all.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final m in active)
                    _StaffTile(
                      name: names[m.userId] ?? 'Team member',
                      roleLabel: roleLabelFor(labels, m.role),
                      roleId: m.role,
                      checked: assigned.contains(m.userId),
                      onChanged: (v) async {
                        try {
                          await ref
                              .read(branchServiceProvider)
                              .setAssignment(
                                businessId: branch.businessId,
                                branchId: branch.id,
                                userId: m.userId,
                                assigned: v,
                              );
                        } catch (e) {
                          if (context.mounted) _snack(context, _err(e));
                        }
                      },
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

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.name,
    required this.roleLabel,
    required this.roleId,
    required this.checked,
    required this.onChanged,
  });

  final String name;
  final String roleLabel;
  final String roleId;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _roleColor(roleId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: checked
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: checked
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.6),
            width: checked ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!checked),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(
                    _initials(name),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _Pill(roleLabel, color),
                    ],
                  ),
                ),
                Icon(
                  checked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: checked ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
