import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_order_state.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ============================================================================
// DESIGN TOKENS & SHARED WIDGETS
// ============================================================================

const _kGood = Color(0xFF1F9D74);
const _kGoodDeep = Color(0xFF136F52);
const _kWarn = Color(0xFFE08A1E);

const _kGap = 12.0;
const _kPad = 16.0;
const _kCardRadius = 24.0;
const _kInnerRadius = 16.0;

final _cloudIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.dot = false});

  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(20),
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
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

Color _statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'pending' => _kWarn,
    'accepted' || 'preparing' => scheme.primary,
    'ready' || 'completed' => _kGood,
    'rejected' || 'cancelled' => scheme.error,
    _ => scheme.onSurfaceVariant,
  };
}

String _statusLabel(String status) => switch (status) {
  'pending' => 'New order',
  'accepted' => 'Accepted',
  'preparing' => 'Preparing',
  'ready' => 'Ready for pickup',
  'completed' => 'Completed',
  'rejected' => 'Declined',
  'cancelled' => 'Cancelled',
  _ => status,
};

/// Titled, rounded section container.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(_kPad),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_kCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: _kGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: _kPad),
          child,
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text, this.error = false, this.bottom = 12});

  final String text;
  final bool error;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = error ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = error ? scheme.onErrorContainer : scheme.onSurface;
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 20,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, height: 1.35, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 28),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 38, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.caption});

  final IconData icon;
  final String text;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small tappable time value used in the opening-hours editor.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.done, required this.label});

  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done ? _kGood : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
      decoration: BoxDecoration(
        color: done
            ? _kGood.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, required this.fg});

  final String value;
  final String label;
  final Color fg;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: fg,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: fg.withValues(alpha: 0.75),
          ),
        ),
      ],
    ),
  );
}

/// Thin 4-segment progress bar for an order's lifecycle.
class _OrderProgress extends StatelessWidget {
  const _OrderProgress({required this.status, required this.color});

  final String status;
  final Color color;

  static const _steps = ['pending', 'accepted', 'preparing', 'ready'];

  @override
  Widget build(BuildContext context) {
    if (status == 'rejected' || status == 'cancelled') {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final reached = status == 'completed' ? 4 : _steps.indexOf(status);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= reached - 1 || (status != 'completed' && i == reached)
                      ? color
                      : scheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatPrice(int cents, String currency) =>
    '${currency.toUpperCase()} ${(cents / 100).toStringAsFixed(2)}';

String _formatQty(num q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toString();

// ============================================================================
// STOREFRONT MANAGEMENT
// ============================================================================

class _BranchDraft {
  _BranchDraft(ManagedBranchStorefront b)
    : id = b.id,
      name = b.name,
      address = b.address,
      city = b.city,
      isActive = b.isActive,
      published = b.published,
      phone = TextEditingController(text: b.phone),
      hours = Map.of(b.openingHours),
      products = Set.of(b.productIds),
      availabilityOverride = b.availabilityOverride;
  final String id;
  final String name;
  final String? address;
  final String? city;
  final bool isActive;
  bool published;
  final TextEditingController phone;
  final Map<int, StoreHours> hours;
  final Set<String> products;
  StoreAvailabilityOverride? availabilityOverride;
  final TextEditingController search = TextEditingController();
  String query = '';

  bool get live => published && isActive;
}

class CustomerStorefrontManagementScreen extends ConsumerStatefulWidget {
  const CustomerStorefrontManagementScreen({super.key, this.initialTab = 0})
    : assert(initialTab >= 0 && initialTab < 2);

  final int initialTab;

  @override
  ConsumerState<CustomerStorefrontManagementScreen> createState() =>
      _CustomerStorefrontManagementScreenState();
}

class _CustomerStorefrontManagementScreenState
    extends ConsumerState<CustomerStorefrontManagementScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _points = TextEditingController(text: '0');
  List<Product>? _products;
  String? _currencyCode;
  bool _offline = false;
  bool _loading = true;
  bool _loadError = false;
  bool _saving = false;
  String? _savingBranchId;
  String? _focusBranchId;
  String? _orderBranchId; // null = all branches
  String? _error;
  int _tab = 0;

  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  List<_BranchDraft> _branches = [];

  /// Branches this user may manage (owners: all).
  List<_BranchDraft> _selectable() {
    if (ref.watch(authorizationServiceProvider).isOwner) return _branches;
    final allowed = ref.watch(allowedBranchesProvider).map((b) => b.id).toSet();
    return _branches.where((b) => allowed.contains(b.id)).toList();
  }

  _BranchDraft? _focusDraft() {
    final list = _selectable();
    if (list.isEmpty) return null;
    final current = ref.watch(selectedBranchIdProvider);
    for (final id in [_focusBranchId, current]) {
      final hit = list.where((b) => b.id == id).firstOrNull;
      if (hit != null) return hit;
    }
    return list.first;
  }

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _loadLocal();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _points.dispose();
    for (final b in _branches) {
      b.phone.dispose();
      b.search.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLocal() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = false;
        _error = null;
      });
    }
    try {
      final db = ref.read(databaseProvider);
      final businessId = ref.read(selectedBusinessIdProvider);
      final business = await (db.select(
        db.businesses,
      )..where((b) => b.id.equals(businessId))).getSingleOrNull();
      final managed = await ref
          .read(customerCommerceServiceProvider)
          .loadManagedStorefront(businessId);
      final branches = await ref
          .read(customerCommerceServiceProvider)
          .loadManagedBranches(
            businessId,
            allowedBranchIds: ref
                .read(allowedBranchesProvider)
                .map((branch) => branch.id)
                .toSet(),
          );
      final products =
          await (db.select(db.products)..where(
                (p) =>
                    p.businessId.equals(businessId) &
                    p.isActive.equals(true) &
                    p.isSellable.equals(true),
              ))
              .get();
      if (!mounted) return;
      setState(() {
        _name.text = managed.storefront?.name ?? business?.name ?? '';
        _description.text =
            managed.storefront?.description ?? business?.description ?? '';
        _points.text = '${managed.storefront?.pointsPerCurrencyUnit ?? 0}';
        _currencyCode =
            managed.storefront?.currencyCode ?? business?.currency ?? 'PHP';
        _offline = managed.storefront?.offlineEnabled ?? false;
        _products = products;
        _branches = [for (final b in branches) _BranchDraft(b)];
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = true;
          _error = 'Could not load online store settings: $error';
          _loading = false;
        });
      }
    }
  }

  bool get _isCloudId =>
      _cloudIdPattern.hasMatch(ref.read(selectedBusinessIdProvider));

  Future<void> _saveBranch(_BranchDraft d) async {
    final businessId = ref.read(selectedBusinessIdProvider);
    final points = int.tryParse(_points.text.trim());
    if (points == null || points < 0 || points > 1000) {
      setState(
        () => _error = 'Points per currency unit must be between 0 and 1000.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _savingBranchId = d.id;
      _error = null;
    });
    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.onlineStoreManage, businessId: businessId);
      await ref
          .read(customerCommerceServiceProvider)
          .publishBranchStorefront(
            businessId: businessId,
            branchId: d.id,
            name: _name.text,
            description: _description.text,
            currencyCode: _currencyCode ?? 'PHP',
            offlineEnabled: _offline,
            pointsPerCurrencyUnit: points,
            settings: BranchStorefrontSettings(
              published: d.published,
              phone: d.phone.text,
              openingHours: Map.of(d.hours),
              productIds: Set.of(d.products),
              availabilityOverride: d.availabilityOverride,
            ),
            allowedBranchIds: ref
                .read(allowedBranchesProvider)
                .map((branch) => branch.id)
                .toSet(),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            d.live ? '${d.name} is live.' : '${d.name} saved (not published).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '${d.name}: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not save ${d.name}: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingBranchId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessId = ref.watch(selectedBusinessIdProvider);
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final focus = _focusDraft();
    final isOwner = ref.watch(authorizationServiceProvider).isOwner;
    final live = focus?.live ?? false;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Online store',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              live ? 'This branch is live' : 'This branch is not published',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: live ? _kGood : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_kPad, 4, _kPad, 10),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.storefront_outlined, size: 18),
                    label: Text('Publish online'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text('Orders'),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
          ),
        ),
      ),
      body: _tab == 0
          ? _buildSettings(context, businessId, focus)
          : _buildOrdersTab(context, businessId, isOwner, focus),
    );
  }

  // --------------------------------------------------------------------------
  // Orders tab
  // --------------------------------------------------------------------------

  Widget _buildOrdersTab(
    BuildContext context,
    String businessId,
    bool isOwner,
    _BranchDraft? focus,
  ) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(_kPad, 10, _kPad, 6),
            children: [
              if (isOwner)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.all_inclusive_rounded, size: 16),
                    label: const Text('All branches'),
                    selected: _orderBranchId == null,
                    onSelected: (_) => setState(() => _orderBranchId = null),
                  ),
                ),
              for (final b in _branches)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(b.name),
                    selected: _orderBranchId == b.id,
                    onSelected: (_) => setState(() => _orderBranchId = b.id),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _StoreOrderInbox(
            key: ValueKey(_orderBranchId ?? focus?.id ?? 'none'),
            businessId: businessId,
            branchId: isOwner ? _orderBranchId : (_orderBranchId ?? focus?.id),
            returnToPosOnImport: false,
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Publish tab
  // --------------------------------------------------------------------------

  Widget _buildSettings(
    BuildContext context,
    String businessId,
    _BranchDraft? focus,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isCloudId = _cloudIdPattern.hasMatch(businessId);
    final selectable = _selectable();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(_kPad, 8, _kPad, 24),
            children: [
              if (!isCloudId)
                const _InfoCard(
                  text:
                      'This business is local-only. Link it to the cloud before customers can discover the online store.',
                  error: true,
                ),
              if (_error != null) _InfoCard(text: _error!, error: true),
              if (_loadError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _loadLocal,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry loading settings'),
                  ),
                ),
              if (focus == null)
                const _InfoCard(
                  text: 'No branches available for you in this business.',
                  error: true,
                )
              else ...[
                if (selectable.length > 1) ...[
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final b in selectable)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(
                                Icons.circle,
                                size: 10,
                                color: b.live ? _kGood : scheme.outline,
                              ),
                              label: Text(b.name),
                              selected: focus.id == b.id,
                              onSelected: (_) =>
                                  setState(() => _focusBranchId = b.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                _buildHero(context, focus, isCloudId),
                const SizedBox(height: _kGap),
                _buildChecklist(context, focus, isCloudId),
                const SizedBox(height: _kGap),
              ],
              _SectionCard(
                icon: Icons.badge_outlined,
                title: 'Store profile',
                subtitle: 'Shared by all branches.',
                child: Column(
                  children: [
                    TextField(
                      controller: _name,
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Online store name',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: _kGap),
                    TextField(
                      controller: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Public description',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              if (focus != null) ...[
                const SizedBox(height: _kGap),
                _buildBranchDetails(context, focus),
                const SizedBox(height: _kGap),
                _buildHoursCard(context, focus),
                const SizedBox(height: _kGap),
                _availabilityOverrideCard(context, focus),
                const SizedBox(height: _kGap),
                _buildProductsCard(context, focus),
              ],
              const SizedBox(height: _kGap),
              _SectionCard(
                icon: Icons.stars_rounded,
                title: 'Loyalty points',
                subtitle:
                    'Points are added only after you mark an order completed. Set 0 to turn off.',
                child: TextField(
                  controller: _points,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Points per ${_currencyCode ?? 'PHP'} 1 spent',
                    prefixIcon: const Icon(Icons.stars_outlined),
                  ),
                ),
              ),
              const SizedBox(height: _kGap),
              _SectionCard(
                icon: Icons.download_for_offline_outlined,
                title: 'Offline access',
                subtitle:
                    'Customers can keep viewing the last loaded catalog while offline.',
                trailing: Switch(
                  value: _offline,
                  onChanged: (value) => setState(() => _offline = value),
                ),
                child: Row(
                  children: [
                    Icon(
                      _offline
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _offline
                          ? 'Cached catalog is allowed'
                          : 'Catalog needs a connection',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (focus != null && focus.live) ...[
                const SizedBox(height: _kGap),
                _buildQrCard(context, businessId, focus),
              ],
            ],
          ),
        ),
        if (focus != null) _buildSaveBar(context, focus, isCloudId),
      ],
    );
  }

  // ── Hero: status, visibility switch, key numbers ──
  Widget _buildHero(BuildContext context, _BranchDraft d, bool isCloudId) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final live = d.live;
    final fg = live ? Colors.white : scheme.onPrimaryContainer;
    final place = [
      d.name,
      if ((d.city ?? '').trim().isNotEmpty) d.city!.trim(),
    ].join(' • ');
    final storeName = _name.text.trim().isEmpty
        ? 'Your online store'
        : _name.text.trim();

    final switchTheme = SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white.withValues(alpha: 0.35)
            : null,
      ),
      trackOutlineColor: WidgetStatePropertyAll(
        live ? Colors.white.withValues(alpha: 0.5) : null,
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: live
              ? const [_kGood, _kGoodDeep]
              : [scheme.primaryContainer, scheme.secondaryContainer],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      live ? Icons.public_rounded : Icons.edit_note_rounded,
                      size: 14,
                      color: fg,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      live ? 'Live' : 'Draft',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            storeName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            place,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(_kInnerRadius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visible to customers',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                      Text(
                        !d.isActive
                            ? 'This branch is deactivated'
                            : (d.published
                                  ? 'Customers can find and order here'
                                  : 'Turn on to publish this branch'),
                        style: TextStyle(
                          fontSize: 12,
                          color: fg.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Theme(
                  data: live
                      ? theme.copyWith(switchTheme: switchTheme)
                      : theme,
                  child: Switch(
                    value: d.live,
                    onChanged: (!d.isActive || _saving)
                        ? null
                        : (v) {
                            HapticFeedback.selectionClick();
                            setState(() => d.published = v);
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroStat(
                value: '${d.products.length}',
                label: 'Products',
                fg: fg,
              ),
              _HeroStat(
                value: '${d.hours.length}/7',
                label: 'Open days',
                fg: fg,
              ),
              _HeroStat(
                value: (int.tryParse(_points.text.trim()) ?? 0) == 0
                    ? 'Off'
                    : '${_points.text.trim()}×',
                label: 'Loyalty',
                fg: fg,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Go-live checklist ──
  Widget _buildChecklist(BuildContext context, _BranchDraft d, bool isCloudId) {
    final checks = <(bool, String)>[
      (isCloudId, 'Linked to cloud'),
      ((d.city ?? '').trim().isNotEmpty, 'City added'),
      (d.hours.isNotEmpty, 'Hours set'),
      (d.products.isNotEmpty, 'Products chosen'),
    ];
    final done = checks.where((c) => c.$1).length;
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.checklist_rounded,
      title: 'Ready to go live',
      subtitle: done == checks.length
          ? 'Everything is in place.'
          : 'Finish these before you publish.',
      trailing: _Pill(
        label: '$done/${checks.length}',
        color: done == checks.length ? _kGood : scheme.primary,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final c in checks) _CheckChip(done: c.$1, label: c.$2)],
      ),
    );
  }

  // ── Branch details ──
  Widget _buildBranchDetails(BuildContext context, _BranchDraft d) {
    final address = (d.address ?? '').trim();
    final missingCity = (d.city ?? '').trim().isEmpty;
    return _SectionCard(
      icon: Icons.store_mall_directory_outlined,
      title: 'Branch details',
      subtitle: d.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!d.isActive) const _InfoCard(text: 'This branch is deactivated.'),
          if (missingCity)
            const _InfoCard(
              text:
                  'Add a city to this branch in Branches before publishing it.',
              error: true,
            ),
          _InfoRow(
            icon: Icons.place_outlined,
            text: address.isEmpty ? 'No address yet' : address,
            caption: address.isEmpty
                ? 'Add one in Branches'
                : 'Edit address in Branches',
          ),
          const SizedBox(height: _kPad),
          TextField(
            controller: d.phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Branch phone (optional)',
              prefixIcon: Icon(Icons.call_outlined),
            ),
          ),
        ],
      ),
    );
  }

  // ── Opening hours ──
  Widget _buildHoursCard(BuildContext context, _BranchDraft d) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.schedule_rounded,
      title: 'Opening hours',
      subtitle: d.hours.isEmpty
          ? 'Closed every day until you add hours.'
          : 'Open ${d.hours.length} ${d.hours.length == 1 ? 'day' : 'days'} a week.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.today_rounded, size: 16),
                label: const Text('Every day 9–5'),
                onPressed: _saving
                    ? null
                    : () => _applyHours(d, const [1, 2, 3, 4, 5, 6, 7]),
              ),
              ActionChip(
                avatar: const Icon(Icons.work_outline_rounded, size: 16),
                label: const Text('Weekdays 9–5'),
                onPressed: _saving
                    ? null
                    : () => _applyHours(d, const [1, 2, 3, 4, 5]),
              ),
              ActionChip(
                avatar: const Icon(Icons.layers_clear_outlined, size: 16),
                label: const Text('Clear'),
                onPressed: _saving ? null : () => setState(d.hours.clear),
              ),
            ],
          ),
          const SizedBox(height: _kGap),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(_kInnerRadius),
            ),
            child: Column(
              children: [
                for (var day = 1; day <= 7; day++) ...[
                  if (day > 1)
                    Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  _hoursRow(context, d, day),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hoursRow(BuildContext context, _BranchDraft d, int day) {
    final scheme = Theme.of(context).colorScheme;
    final hours = d.hours[day];
    final open = hours != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              _dayNames[day - 1].substring(0, 3),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: open ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          Switch(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            value: open,
            onChanged: _saving
                ? null
                : (enabled) => setState(() {
                    if (enabled) {
                      d.hours[day] = (open: '09:00', close: '17:00');
                    } else {
                      d.hours.remove(day);
                    }
                  }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hours == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Closed',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _TimeChip(
                          label: _timeLabel(hours.open, context),
                          onTap: _saving
                              ? null
                              : () => _chooseTime(d, day, opening: true),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: _TimeChip(
                          label: _timeLabel(hours.close, context),
                          onTap: _saving
                              ? null
                              : () => _chooseTime(d, day, opening: false),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _applyHours(_BranchDraft d, Iterable<int> days) {
    setState(() {
      d.hours.clear();
      for (final day in days) {
        d.hours[day] = (open: '09:00', close: '17:00');
      }
    });
  }

  // ── Special opening override ──
  Widget _availabilityOverrideCard(BuildContext context, _BranchDraft d) {
    final scheme = Theme.of(context).colorScheme;
    final override = d.availabilityOverride;
    final isOpen = override?.mode == StoreAvailabilityMode.open;
    return _SectionCard(
      icon: Icons.event_available_outlined,
      title: 'Special opening override',
      subtitle: 'Temporarily open or close for holidays and special occasions.',
      trailing: override == null
          ? null
          : _Pill(
              label: isOpen ? 'Open' : 'Closed',
              color: isOpen ? _kGood : scheme.error,
              dot: true,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (override != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(_kInnerRadius),
              ),
              child: _InfoRow(
                icon: Icons.date_range_outlined,
                text:
                    '${_formatDate(override.startDate)} – ${_formatDate(override.endDate)}',
                caption: override.reason == null || override.reason!.isEmpty
                    ? null
                    : override.reason,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _editAvailabilityOverride(d),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(override == null ? 'Set dates' : 'Edit override'),
                ),
              ),
              if (override != null)
                IconButton(
                  tooltip: 'Clear override',
                  onPressed: _saving
                      ? null
                      : () => setState(() => d.availabilityOverride = null),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

  Future<void> _editAvailabilityOverride(_BranchDraft d) async {
    final current = d.availabilityOverride;
    final mode = await showDialog<StoreAvailabilityMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Override mode'),
        children: [
          for (final value in StoreAvailabilityMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text(
                value == StoreAvailabilityMode.open ? 'Open' : 'Closed',
              ),
            ),
        ],
      ),
    );
    if (!mounted || mode == null) return;
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: current?.startDate ?? DateTime.now(),
    );
    if (!mounted || start == null) return;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: current != null && !current.endDate.isBefore(start)
          ? current.endDate
          : start,
    );
    if (!mounted || end == null) return;
    final reason = await _reasonDialog(current?.reason);
    if (!mounted) return;
    setState(() {
      d.availabilityOverride = StoreAvailabilityOverride(
        mode: mode,
        startDate: start,
        endDate: end,
        reason: (reason == null || reason.isEmpty) ? null : reason,
      );
    });
  }

  /// The dialog owns its controller, so it is only disposed after the route
  /// has fully left the tree (disposing it right after `showDialog` returns
  /// triggers the `_dependents.isEmpty` assertion while the pop animation
  /// is still running).
  Future<String?> _reasonDialog(String? initial) => showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(initial: initial),
  );

  // ── Products ──
  Widget _buildProductsCard(BuildContext context, _BranchDraft d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.live && d.products.isEmpty)
          const _InfoCard(
            text: 'No products selected. Customers will see an empty menu.',
            error: true,
          ),
        _BranchProductPicker(
          key: ValueKey('picker-${d.id}'),
          products: _products ?? const <Product>[],
          selected: d.products,
          currency: _currencyCode ?? 'PHP',
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }

  // ── QR invite ──
  Widget _buildQrCard(BuildContext context, String businessId, _BranchDraft d) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.qr_code_2_rounded,
      title: 'Invite customers',
      subtitle: 'Customers scan this QR to open ${d.name} and follow.',
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: QrImageView(
            data: storefrontInvitePayload(businessId, branchId: d.id),
            size: 200,
            backgroundColor: Colors.white,
            semanticsLabel: 'Branch invitation QR code',
          ),
        ),
      ),
    );
  }

  // ── Sticky save bar ──
  Widget _buildSaveBar(BuildContext context, _BranchDraft d, bool isCloudId) {
    final scheme = Theme.of(context).colorScheme;
    final saving = _savingBranchId == d.id;
    final disabled = _saving || _loadError || !isCloudId;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_kPad, 12, _kPad, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        d.live ? 'Goes live when saved' : 'Saved as a draft',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: d.live ? _kGood : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: _kGap),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: disabled ? null : () => _saveBranch(d),
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            d.live
                                ? Icons.rocket_launch_rounded
                                : Icons.save_rounded,
                          ),
                    label: Text(
                      saving ? 'Saving…' : (d.live ? 'Publish' : 'Save draft'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTime(
    _BranchDraft d,
    int day, {
    required bool opening,
  }) async {
    final hours = d.hours[day];
    if (hours == null) return;
    final value = opening ? hours.open : hours.close;
    final parts = value.split(':');
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (selected == null || !mounted) return;
    final formatted =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    setState(() {
      d.hours[day] = opening
          ? (open: formatted, close: hours.close)
          : (open: hours.open, close: formatted);
    });
  }

  String _timeLabel(String value, BuildContext context) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    ).format(context);
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({this.initial});

  final String? initial;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reason (optional)'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 120,
      textInputAction: TextInputAction.done,
      onSubmitted: (v) => Navigator.pop(context, v.trim()),
      decoration: const InputDecoration(
        hintText: 'Holiday, private event, maintenance…',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('Skip'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.currency,
    required this.selected,
    required this.onChanged,
  });

  final Product product;
  final String currency;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final needsPrice = product.sellPrice == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : scheme.surface,
        borderRadius: BorderRadius.circular(_kInnerRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kInnerRadius),
          onTap: () => onChanged(!selected),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kInnerRadius),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => onChanged(v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        needsPrice
                            ? '${product.unit} • Price needed before customer ordering'
                            : '${product.unit} • ${_formatPrice(product.sellPrice!, currency)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: needsPrice ? _kWarn : scheme.onSurfaceVariant,
                          fontWeight: needsPrice
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (needsPrice)
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: _kWarn,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ORDER INBOX
// ============================================================================

enum _InboxFilter { all, pending, active, done }

class _StoreOrderInbox extends ConsumerStatefulWidget {
  const _StoreOrderInbox({
    super.key,
    required this.businessId,
    this.branchId,
    this.returnToPosOnImport = false,
  });

  final String businessId;
  final String? branchId;
  final bool returnToPosOnImport;

  @override
  ConsumerState<_StoreOrderInbox> createState() => _StoreOrderInboxState();
}

class CustomerOrdersInboxScreen extends StatelessWidget {
  const CustomerOrdersInboxScreen({
    required this.businessId,
    required this.branchId,
    super.key,
  });

  final String businessId;
  final String branchId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      title: const Text(
        'Customer orders',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: _StoreOrderInbox(
      businessId: businessId,
      branchId: branchId,
      returnToPosOnImport: true,
    ),
  );
}

class _StoreOrderInboxState extends ConsumerState<_StoreOrderInbox> {
  late Future<List<CustomerOrder>> _orders;
  String? _workingOrderId;
  _InboxFilter _filter = _InboxFilter.all;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _orders = ref
        .read(customerCommerceServiceProvider)
        .loadOrders(businessId: widget.businessId, branchId: widget.branchId);
  }

  bool _matches(_InboxFilter filter, String status) => switch (filter) {
    _InboxFilter.all => true,
    _InboxFilter.pending => status == 'pending',
    _InboxFilter.active =>
      status == 'accepted' || status == 'preparing' || status == 'ready',
    _InboxFilter.done =>
      status == 'completed' || status == 'rejected' || status == 'cancelled',
  };

  Future<void> _setStatus(CustomerOrder order, String status) async {
    setState(() => _workingOrderId = order.id);
    try {
      ref
          .read(authorizationServiceProvider)
          .require(
            BosPermission.onlineStoreManage,
            businessId: widget.businessId,
          );
      await ref
          .read(customerCommerceServiceProvider)
          .updateOrderStatus(
            orderId: order.id,
            businessId: widget.businessId,
            status: status,
          );
      if (status == 'cancelled') {
        if (ref.read(posOrderDetailsProvider).customerOrderId == order.id) {
          ref.read(posOrderProvider.notifier).clear();
        }
        ref
            .read(heldOrdersProvider.notifier)
            .discardByCustomerOrderId(order.id);
      }
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not update order: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _workingOrderId = null);
    }
  }

  Future<void> _addToPos(CustomerOrder order) async {
    if (order.status != 'accepted') return;
    if (!widget.returnToPosOnImport || widget.branchId == null) return;
    if (order.branchId != widget.branchId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Select the order’s pickup branch in the POS first.'),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _workingOrderId = order.id);
    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.salesCreate, businessId: widget.businessId);
      ref
          .read(authorizationServiceProvider)
          .require(
            BosPermission.onlineStoreManage,
            businessId: widget.businessId,
          );
      final service = ref.read(customerCommerceServiceProvider);
      final items = await service.loadOrderItems(order.id);
      if (items.isEmpty) throw StateError('This order has no items.');

      final db = ref.read(databaseProvider);
      final products =
          await (db.select(db.products)..where(
                (product) =>
                    product.businessId.equals(widget.businessId) &
                    product.id.isIn(items.map((item) => item.catalogItemId)) &
                    product.isActive.equals(true) &
                    product.isSellable.equals(true),
              ))
              .get();
      final productsById = {
        for (final product in products) product.id: product,
      };
      final lines = <POSLineItem>[];
      for (final item in items) {
        final product = productsById[item.catalogItemId];
        if (product == null) {
          throw StateError(
            '${item.itemName} is no longer an active POS product.',
          );
        }
        final quantity = item.quantity.round();
        if (quantity <= 0 || (item.quantity - quantity).abs() > 0.000001) {
          throw StateError(
            '${item.itemName} has a fractional quantity that the POS order '
            'cannot represent.',
          );
        }
        lines.add(
          POSLineItem(
            productId: product.id,
            name: item.itemName,
            unit: item.unit,
            unitPriceCents: item.unitPriceCents,
            quantity: quantity,
          ),
        );
      }

      final currentLines = ref.read(posOrderProvider);
      final currentDetails = ref.read(posOrderDetailsProvider);
      final currentOrderType = ref.read(posOrderTypeProvider);
      final heldOrders = ref.read(heldOrdersProvider);
      if (currentDetails.customerOrderId == order.id ||
          heldOrders.any((held) => held.details.customerOrderId == order.id)) {
        throw StateError('This customer order is already in the POS.');
      }
      await service.updateOrderStatus(
        orderId: order.id,
        businessId: widget.businessId,
        status: 'preparing',
      );
      if (currentLines.isNotEmpty) {
        ref
            .read(heldOrdersProvider.notifier)
            .hold(
              currentLines,
              orderType: currentOrderType,
              details: currentDetails,
            );
      }
      ref.read(posOrderProvider.notifier).replaceAll(lines);
      ref
          .read(posOrderDetailsProvider.notifier)
          .replace(
            OrderDetails(
              contactName: order.customerName,
              contactPhone: order.customerPhone,
              customerOrderId: order.id,
            ),
          );

      if (mounted) {
        if (!widget.returnToPosOnImport) setState(_refresh);
        if (widget.returnToPosOnImport) Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              currentLines.isEmpty
                  ? 'Customer order added to the POS and marked as preparing.'
                  : 'Customer order added to the POS and marked as preparing. Previous draft held.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not add order to POS: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _workingOrderId = null);
    }
  }

  Future<void> _confirmCancel(CustomerOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.cancel_outlined, size: 30),
        title: const Text('Cancel customer order?'),
        content: Text('Cancel the order from ${order.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _setStatus(order, 'cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<List<CustomerOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(_kPad),
            child: _InfoCard(
              text: 'Could not load orders: ${snapshot.error}',
              error: true,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final shown = all.where((o) => _matches(_filter, o.status)).toList();

        int count(_InboxFilter f) =>
            all.where((o) => _matches(f, o.status)).length;

        String filterLabel(_InboxFilter f) => switch (f) {
          _InboxFilter.all => 'All',
          _InboxFilter.pending => 'New',
          _InboxFilter.active => 'In progress',
          _InboxFilter.done => 'Finished',
        };

        return RefreshIndicator(
          onRefresh: () async => setState(_refresh),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(_kPad, 4, _kPad, 28),
            children: [
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in _InboxFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                          label: Text('${filterLabel(f)} (${count(f)})'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: _kGap),
              if (shown.isEmpty)
                _EmptyMessage(
                  icon: Icons.inbox_outlined,
                  title: all.isEmpty
                      ? 'No customer orders yet'
                      : 'Nothing in this view',
                  message: all.isEmpty
                      ? 'New orders from your followers will show up here.'
                      : 'Try another filter.',
                )
              else
                for (final order in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildOrderCard(context, order),
                  ),
              if (shown.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Pull down to refresh',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderCard(BuildContext context, CustomerOrder order) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _statusColor(context, order.status);
    final transitions = _availableTransitions(order.status);
    final busy = _workingOrderId != null;
    final initial = order.customerName.trim().isEmpty
        ? '?'
        : order.customerName.trim()[0].toUpperCase();

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('order-${order.id}'),
          tilePadding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: color,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  order.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatPrice(order.totalCents, order.currencyCode),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Pill(
                      label: _statusLabel(order.status),
                      color: color,
                      dot: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.branchName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                _OrderProgress(status: order.status, color: color),
              ],
            ),
          ),
          children: [
            // Contact + receipt + notes
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(_kInnerRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    text: order.customerPhone,
                    caption: 'Shared for this order only',
                  ),
                  if (order.requestsOfficialReceipt) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.receipt_outlined,
                      text: 'Official receipt • TIN ${order.customerTin}',
                    ),
                  ],
                  if (order.notes?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.sticky_note_2_outlined,
                      text: order.notes!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Items
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(_kInnerRadius),
              ),
              child: FutureBuilder<List<CustomerOrderItem>>(
                future: ref
                    .read(customerCommerceServiceProvider)
                    .loadOrderItems(order.id),
                builder: (context, items) {
                  if (items.hasError) {
                    return Text(
                      'Items unavailable: ${items.error}',
                      style: TextStyle(color: scheme.error),
                    );
                  }
                  if (!items.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
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
                      for (final item in items.data!)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                constraints: const BoxConstraints(minWidth: 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  '${_formatQty(item.quantity)}×',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
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
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      item.unit,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _formatPrice(
                                  item.totalCents,
                                  order.currencyCode,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
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

            // Actions
            if (transitions.isNotEmpty) ...[
              const SizedBox(height: _kGap),
              Row(
                children: [
                  for (var i = 0; i < transitions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      flex: i == 0 ? 2 : 1,
                      child: i == 0
                          ? FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => _setStatus(order, transitions[i].$1),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(transitions[i].$2),
                              ),
                            )
                          : OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _setStatus(order, transitions[i].$1),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                foregroundColor: scheme.error,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(transitions[i].$2),
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ],
            if (order.status == 'accepted' && widget.returnToPosOnImport) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: !busy ? () => _addToPos(order) : null,
                  icon: const Icon(Icons.point_of_sale_outlined),
                  label: Text(
                    _workingOrderId == order.id
                        ? 'Adding to POS...'
                        : 'Add to POS current order',
                  ),
                ),
              ),
            ],
            if (_canCancelCustomerOrder(order.status)) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: !busy ? () => _confirmCancel(order) : null,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel order'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<(String, String)> _availableTransitions(String status) => switch (status) {
  'pending' => [('accepted', 'Accept'), ('rejected', 'Decline')],
  'accepted' => [('preparing', 'Start preparing')],
  'preparing' => [('ready', 'Ready for pickup')],
  'ready' => [('completed', 'Complete and award points')],
  _ => const [],
};

bool _canCancelCustomerOrder(String status) =>
    status == 'pending' ||
    status == 'accepted' ||
    status == 'preparing' ||
    status == 'ready';

// ============================================================================
// PRODUCT PICKER
// ============================================================================

class _BranchProductPicker extends StatefulWidget {
  const _BranchProductPicker({
    super.key,
    required this.products,
    required this.selected,
    required this.currency,
    required this.onChanged,
  });

  final List<Product> products;
  final Set<String> selected;
  final String currency;
  final VoidCallback onChanged;

  @override
  State<_BranchProductPicker> createState() => _BranchProductPickerState();
}

class _BranchProductPickerState extends State<_BranchProductPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _change(void Function() fn) {
    setState(fn);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = _query.trim().toLowerCase();
    final visible = widget.products
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_kCardRadius),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(_kPad, 6, _kPad, 6),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
          ),
          title: const Text(
            'Products sold here',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Only active POS products selected here appear online.',
            style: TextStyle(fontSize: 12.5),
          ),
          trailing: _Pill(
            label: '${widget.selected.length}/${widget.products.length}',
            color: scheme.primary,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            if (widget.products.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'No active sellable products.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else ...[
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search products',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: visible.isEmpty
                        ? null
                        : () => _change(
                            () => widget.selected.addAll(
                              visible.map((p) => p.id),
                            ),
                          ),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text(q.isEmpty ? 'Select all' : 'Select shown'),
                  ),
                  TextButton.icon(
                    onPressed: visible.isEmpty
                        ? null
                        : () => _change(
                            () => widget.selected.removeAll(
                              visible.map((p) => p.id),
                            ),
                          ),
                    icon: const Icon(Icons.remove_done_rounded, size: 18),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              for (final product in visible)
                _ProductTile(
                  key: ValueKey(product.id),
                  product: product,
                  currency: widget.currency,
                  selected: widget.selected.contains(product.id),
                  onChanged: (value) => _change(() {
                    if (value) {
                      widget.selected.add(product.id);
                    } else {
                      widget.selected.remove(product.id);
                    }
                  }),
                ),
            ],
          ],
        ),
      ),
    );
  }
}