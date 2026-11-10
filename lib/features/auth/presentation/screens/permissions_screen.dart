// lib/features/auth/presentation/screens/permissions_screen.dart
//
// Administration -> Permissions. Pick a role (built-in or custom), then flip
// individual permissions on/off for it in this business. Everything starts at
// the role's compiled-in defaults (bos_access.dart); toggling writes a
// RolePermissionOverrides row, and flipping back to the default removes it.
// The owner role is fixed (always every permission), so it isn't shown.
//
// Live: overrides are synced, so changes reach everyone with the role. The
// chip in the app bar shows Live / Saving / Sync failed.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:bos_application/core/sync/sync_trigger_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/custom_roles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/authorization_service.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/auth/membership_service.dart';
import '../../../../core/auth/permission_overrides.dart';
import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

// ============================================================
// STATIC CONTENT
// ============================================================

const Map<String, String> _groupLabels = {
  'dashboard': 'Dashboard',
  'sales': 'Sales',
  'online_store': 'Online store',
  'customers': 'Customers',
  'inventory': 'Inventory',
  'purchasing': 'Purchasing',
  'suppliers': 'Suppliers',
  'finance': 'Finance',
  'receivables': 'Receivables',
  'payables': 'Payables',
  'reports': 'Reports',
  'employees': 'Employees',
  'hr': 'HR & attendance',
  'users': 'Users & roles',
  'business': 'Business',
  'security': 'Security',
};

const Map<String, IconData> _groupIcons = {
  'dashboard': Icons.dashboard_outlined,
  'sales': Icons.point_of_sale_outlined,
  'customers': Icons.people_outline_rounded,
  'inventory': Icons.inventory_2_outlined,
  'purchasing': Icons.shopping_cart_outlined,
  'suppliers': Icons.local_shipping_outlined,
  'finance': Icons.account_balance_wallet_outlined,
  'receivables': Icons.request_quote_outlined,
  'payables': Icons.payments_outlined,
  'reports': Icons.bar_chart_outlined,
  'employees': Icons.badge_outlined,
  'hr': Icons.event_available_outlined,
  'users': Icons.manage_accounts_outlined,
  'business': Icons.store_outlined,
  'security': Icons.shield_outlined,
};

const Map<BosRole, IconData> _roleIcons = {
  BosRole.manager: Icons.supervisor_account_outlined,
  BosRole.accountant: Icons.calculate_outlined,
  BosRole.cashier: Icons.point_of_sale_outlined,
  BosRole.inventory: Icons.inventory_2_outlined,
  BosRole.employee: Icons.badge_outlined,
  BosRole.hr: Icons.groups_outlined,
  BosRole.staff: Icons.storefront_outlined,
};

const Map<BosRole, String> _roleBlurbs = {
  BosRole.manager: 'Runs sales, stock, purchasing and the team.',
  BosRole.accountant: 'Finance, receivables, payables and reports.',
  BosRole.cashier: 'Rings up sales and adds customers.',
  BosRole.inventory: 'Stock, purchasing and suppliers.',
  BosRole.employee: 'Basic view access and own time records.',
  BosRole.hr: 'Schedules, attendance, leave and payroll.',
  BosRole.staff: 'Sells, looks up stock, own time and leave.',
};

IconData _iconOf(RoleRef r) => r.custom
    ? Icons.tune_rounded
    : (_roleIcons[r.base] ?? Icons.person_outline_rounded);

String _blurbOf(RoleRef r) => r.custom
    ? 'Custom role, starts as ${r.base.label}.'
    : (_roleBlurbs[r.base] ?? '');

/// (title, description) for every permission.
const Map<BosPermission, (String, String)> _info = {
  BosPermission.dashboardView: (
    'View dashboard',
    'See the business summary, alerts and quick actions.',
  ),
  BosPermission.salesView: (
    'View sales',
    'Open the POS and see sales history.',
  ),
  BosPermission.salesCreate: ('Create sales', 'Ring up new customer orders.'),
  BosPermission.salesEdit: ('Edit sales', 'Change a sale after it is saved.'),
  BosPermission.salesVoid: (
    'Void sales',
    'Cancel a completed sale or receipt.',
  ),
  BosPermission.salesDiscount: (
    'Give discounts',
    'Apply discounts at the register.',
  ),
  BosPermission.salesStockOnly: (
    'Stock-only sales',
    'Record sales that only move stock.',
  ),
  BosPermission.salesOnCredit: (
    'Sell on credit',
    'Let customers pay later (creates receivables).',
  ),
  BosPermission.onlineStoreManage: (
    'Manage online store',
    'Publish this branch online, manage its products and handle online orders.',
  ),
  BosPermission.customersView: (
    'View customers',
    'See the customer list and details.',
  ),
  BosPermission.customersCreate: ('Add customers', 'Create new customers.'),
  BosPermission.customersEdit: (
    'Edit customers',
    'Change existing customer details.',
  ),
  BosPermission.inventoryView: (
    'View inventory',
    'See supplies, stock levels and reports.',
  ),
  BosPermission.inventoryCreate: ('Add items', 'Create supplies and products.'),
  BosPermission.inventoryEdit: (
    'Edit items',
    'Change prices, units and recipes.',
  ),
  BosPermission.inventoryAdjust: (
    'Adjust stock',
    'Make corrections, waste and write-offs.',
  ),
  BosPermission.purchasingView: (
    'View purchasing',
    'See carts and purchase history.',
  ),
  BosPermission.purchasingCreate: (
    'Create purchases',
    'Build carts and record purchases.',
  ),
  BosPermission.purchasingEdit: (
    'Edit purchases',
    'Change a purchase after it is saved.',
  ),
  BosPermission.purchasingReceive: (
    'Receive stock',
    'Confirm delivered items into inventory.',
  ),
  BosPermission.suppliersView: ('View suppliers', 'See who you buy from.'),
  BosPermission.suppliersCreate: ('Add suppliers', 'Create new suppliers.'),
  BosPermission.suppliersEdit: (
    'Edit suppliers',
    'Change existing supplier details.',
  ),
  BosPermission.financeView: (
    'View finance',
    'See journal, income, expenses and accounts.',
  ),
  BosPermission.financeCreate: (
    'Record transactions',
    'Create income, expenses and transfers.',
  ),
  BosPermission.financeEdit: (
    'Edit finance',
    'Change transactions, accounts and categories.',
  ),
  BosPermission.financePost: (
    'Post entries',
    'Finalize journal entries into the ledger.',
  ),
  BosPermission.financeVoid: (
    'Void transactions',
    'Reverse posted financial records.',
  ),
  BosPermission.receivablesView: (
    'View receivables',
    'See money customers still owe.',
  ),
  BosPermission.receivablesCreate: (
    'Record receipts',
    'Log payments from customers.',
  ),
  BosPermission.payablesView: (
    'View payables',
    'See money still owed to suppliers.',
  ),
  BosPermission.payablesCreate: (
    'Record payments',
    'Log payments to suppliers.',
  ),
  BosPermission.reportsView: (
    'View reports',
    'Open financial and aging reports.',
  ),
  BosPermission.employeesView: (
    'View employees',
    'See the team list and their details.',
  ),
  BosPermission.employeesManage: (
    'Manage employees',
    'Edit employees and run payroll.',
  ),
  BosPermission.hrSelf: (
    'Own time records',
    'See own attendance, schedule and leave.',
  ),
  BosPermission.hrManage: (
    'Manage HR',
    'Manage everyone\'s attendance, shifts and leave.',
  ),
  BosPermission.usersView: (
    'View users',
    'See who has access to the business.',
  ),
  BosPermission.usersInvite: (
    'Invite users',
    'Generate invite codes for new members.',
  ),
  BosPermission.usersRemove: ('Remove users', 'Take away someone\'s access.'),
  BosPermission.usersManageRoles: (
    'Manage roles',
    'Change roles, suspend and transfer ownership.',
  ),
  BosPermission.businessSettings: (
    'Business settings',
    'Edit the profile and turn modules on or off.',
  ),
  BosPermission.businessManage: (
    'Manage business',
    'Archive, import/export and other business-wide tools.',
  ),
  BosPermission.businessDelete: (
    'Delete business',
    'Permanently delete the business.',
  ),
  BosPermission.securityManage: (
    'Manage security',
    'Change permissions and security settings.',
  ),
};

/// Permissions that get a visible "Sensitive" badge.
const Set<BosPermission> _sensitive = {
  BosPermission.salesVoid,
  BosPermission.financeVoid,
  BosPermission.financePost,
  BosPermission.inventoryAdjust,
  BosPermission.usersRemove,
  BosPermission.usersManageRoles,
  BosPermission.businessManage,
  BosPermission.businessDelete,
  BosPermission.securityManage,
};

/// Granting these asks for confirmation first.
const Set<BosPermission> _critical = {
  BosPermission.usersRemove,
  BosPermission.usersManageRoles,
  BosPermission.businessManage,
  BosPermission.businessDelete,
  BosPermission.securityManage,
};

String _groupOf(BosPermission p) => p.id.split('.').first;
String _titleOf(BosPermission p) => _info[p]?.$1 ?? p.id;
String _hintOf(BosPermission p) => _info[p]?.$2 ?? '';

/// The permission that must be on for [p] to be useful (its group's "view").
BosPermission? _requires(BosPermission p) {
  if (p == BosPermission.hrManage) return BosPermission.hrSelf;
  final parts = p.id.split('.');
  if (parts.last == 'view') return null;
  return BosPermission.fromId('${parts.first}.view');
}

// ============================================================
// LIVE SYNC STATUS
// ============================================================

bool _isPermissionEntity(String t) =>
    t == 'role_permission_overrides' || t == 'custom_roles';

final _pendingProvider = StreamProvider.autoDispose<int>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  return ref
      .watch(syncStatusServiceProvider)
      .watchPending(businessId)
      .map(
        (rows) => rows.where((r) => _isPermissionEntity(r.entityType)).length,
      );
});

final _failedProvider = StreamProvider.autoDispose<int>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  return ref
      .watch(syncStatusServiceProvider)
      .watchFailed(businessId)
      .map(
        (rows) => rows.where((r) => _isPermissionEntity(r.entityType)).length,
      );
});

class _SyncChip extends ConsumerWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cloud = ref.watch(supabaseAvailableProvider);
    final pending = ref.watch(_pendingProvider).value ?? 0;
    final failed = ref.watch(_failedProvider).value ?? 0;

    IconData icon;
    String label;
    Color color;
    VoidCallback? onTap;
    var spinning = false;

    if (!cloud) {
      icon = Icons.phone_android_rounded;
      label = 'This device only';
      color = scheme.onSurfaceVariant;
    } else if (failed > 0) {
      icon = Icons.sync_problem_rounded;
      label = 'Sync failed. Retry';
      color = scheme.error;
      onTap = () => _showFailures(context, ref);
    } else if (pending > 0) {
      icon = Icons.sync_rounded;
      label = 'Saving…';
      color = AppColors.warning;
      spinning = true;
    } else {
      icon = Icons.cloud_done_outlined;
      label = 'Live';
      color = const Color(0xFF159B67);
    }

    return Tooltip(
      message: 'Changes reach everyone with this role right away.',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              spinning
                  ? SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN
// ============================================================

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  String _roleId = BosRole.manager.id;

  final _search = TextEditingController();
  String _query = '';
  bool _onlyModified = false;
  bool _busy = false;
  final Set<String> _collapsed = {};

  RoleRef get _role {
    final roles = ref.read(roleRefsProvider);
    return roles.firstWhere((r) => r.id == _roleId, orElse: () => roles.first);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---------- helpers ----------

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  bool _isModified(BosPermission p, Set<BosPermission> effective) =>
      effective.contains(p) != RolePermissions.allows(_role.base, p);

  bool _matches(BosPermission p, Set<BosPermission> effective) {
    if (_onlyModified && !_isModified(p, effective)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay =
        '${_titleOf(p)} ${_hintOf(p)} ${_groupLabels[_groupOf(p)] ?? ''} ${p.id}'
            .toLowerCase();
    return hay.contains(q);
  }

  /// Applies permission changes for the selected role. Re-checks
  /// authorization here so the guard doesn't depend on the UI.
  Future<bool> _apply(Map<BosPermission, bool> changes) async {
    if (changes.isEmpty) return true;
    final businessId = ref.read(selectedBusinessIdProvider);
    final role = _role;
    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.securityManage, businessId: businessId);
      final db = ref.read(databaseProvider);
      for (final e in changes.entries) {
        await PermissionsResolver.setOverride(
          db,
          businessId: businessId,
          role: role.base,
          roleId: role.id,
          roleLabel: role.label,
          permission: e.key,
          granted: e.value,
        );
      }
      return true;
    } on PermissionDeniedException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Couldn\'t save that change. Please try again.');
    }
    return false;
  }

  Future<void> _toggle(
    BosPermission p,
    bool granted,
    Set<BosPermission> effective,
  ) async {
    if (granted && _critical.contains(p)) {
      final ok = await _confirm(
        title: 'Allow ${_role.label} to ${_titleOf(p).toLowerCase()}?',
        message: '${_hintOf(p)} Everyone with this role gets it right away.',
        action: 'Allow',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }

    HapticFeedback.selectionClick();
    final changes = <BosPermission, bool>{p: granted};
    String? note;

    if (granted) {
      final req = _requires(p);
      if (req != null && !effective.contains(req)) {
        changes[req] = true;
        note = 'Also turned on "${_titleOf(req)}", which this needs.';
      }
    } else {
      final deps = BosPermission.values
          .where((q) => _requires(q) == p && effective.contains(q))
          .toList();
      if (deps.isNotEmpty) {
        for (final d in deps) {
          changes[d] = false;
        }
        note =
            'Also turned off ${deps.length} permission${deps.length == 1 ? '' : 's'} that depend on it.';
      }
    }

    final ok = await _apply(changes);
    if (ok && note != null) _toast(note);
  }

  Future<void> _revert(BosPermission p) async {
    HapticFeedback.selectionClick();
    await _apply({p: RolePermissions.allows(_role.base, p)});
  }

  /// [target] null = put the whole group back to the role's defaults.
  Future<void> _bulk(
    List<BosPermission> permissions,
    Set<BosPermission> effective, {
    required bool? target,
  }) async {
    final changes = <BosPermission, bool>{};
    for (final p in permissions) {
      final want = target ?? RolePermissions.allows(_role.base, p);
      if (effective.contains(p) != want) changes[p] = want;
    }
    if (changes.isEmpty) {
      _toast('Nothing to change.');
      return;
    }
    if (target == true && changes.keys.any(_critical.contains)) {
      final ok = await _confirm(
        title: 'Turn on sensitive permissions?',
        message:
            'This includes permissions that can change roles, remove people '
            'or manage the whole business.',
        action: 'Turn on',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final ok = await _apply(changes);
    if (mounted) setState(() => _busy = false);
    if (ok) _toast('Updated ${changes.length} permission(s).');
  }

  Future<void> _confirmReset(List<RolePermissionOverride> overrides) async {
    final mine = overrides.where((o) => o.role == _role.id).length;
    final ok = await _confirm(
      title: 'Reset ${_role.label}?',
      message:
          'This removes $mine customization${mine == 1 ? '' : 's'} and puts '
          '${_role.label} back to its default permissions in this business.',
      action: 'Reset',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await _resetRole(overrides);
      _toast('${_role.label} reset to defaults.');
    } on PermissionDeniedException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Couldn\'t reset. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetRole(List<RolePermissionOverride> overrides) async {
    final businessId = ref.read(selectedBusinessIdProvider);
    ref
        .read(authorizationServiceProvider)
        .require(BosPermission.securityManage, businessId: businessId);

    final role = _role;
    final db = ref.read(databaseProvider);
    final audit = ref.read(auditLogServiceProvider);
    final mine = overrides.where((o) => o.role == role.id).toList();
    if (mine.isEmpty) return;

    await db.transaction(() async {
      for (final override in mine) {
        await (db.delete(
          db.rolePermissionOverrides,
        )..where((o) => o.id.equals(override.id))).go();
      }
      await audit.record(
        AuditEvent(
          module: AuditModule.security,
          actionType: AuditActionType.permission,
          action: 'permission.role_reset',
          entityType: 'role_permission_overrides',
          entityId: role.id,
          entityLabel: role.label,
          before: {for (final o in mine) o.permission: o.granted},
          after: {'customizations': 0},
          details: {'removedCount': mine.length},
        ),
      );
    });
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = ref.watch(roleRefsProvider);
    final canEdit = ref.watch(canProvider(BosPermission.securityManage));
    final isOwner = ref.watch(authorizationServiceProvider).isOwner;
    final overridesAsync = ref.watch(rolePermissionOverridesProvider);
    final members =
        ref.watch(businessMembersProvider).value ?? const <BusinessMember>[];

    final headcount = <String, int>{};
    for (final m in members) {
      if (m.status == 'active') {
        headcount[m.role] = (headcount[m.role] ?? 0) + 1;
      }
    }

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Permissions'),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Custom roles',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomRolesScreen()),
              ),
            ),
          const _SyncChip(),
          const SizedBox(width: 12),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: overridesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const Center(
          child: Text('Unable to load permissions. Go back and try again.'),
        ),
        data: (overrides) {
          final role = _role;
          final effective = PermissionsResolver.effectivePermissions(
            role.base,
            overrides,
            roleId: role.id,
          );
          final modifiedCount = BosPermission.values
              .where((p) => _isModified(p, effective))
              .length;

          final groups = <String, List<BosPermission>>{};
          for (final p in BosPermission.values) {
            groups.putIfAbsent(_groupOf(p), () => []).add(p);
          }

          final searching = _query.trim().isNotEmpty || _onlyModified;
          final visibleGroups = <MapEntry<String, List<BosPermission>>>[];
          for (final entry in _groupLabels.entries) {
            final all = groups[entry.key];
            if (all == null) continue;
            final shown = all.where((p) => _matches(p, effective)).toList();
            if (shown.isNotEmpty) {
              visibleGroups.add(MapEntry(entry.key, shown));
            }
          }

          return LayoutBuilder(
            builder: (context, c) {
              final side = ((c.maxWidth - 720) / 2).clamp(16.0, 9999.0);
              return Column(
                children: [
                  const SizedBox(height: 4),
                  _RoleSelector(
                    selected: role,
                    roles: roles,
                    overrides: overrides,
                    headcount: headcount,
                    padding: side,
                    onSelect: (r) => setState(() => _roleId = r.id),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(side, 8, side, 40),
                      children: [
                        _RoleSummaryCard(
                          role: role,
                          grantedCount: effective.length,
                          totalCount: BosPermission.values.length,
                          modifiedCount: modifiedCount,
                          people: headcount[role.id] ?? 0,
                          onReset: canEdit && modifiedCount > 0
                              ? () => _confirmReset(overrides)
                              : null,
                        ),
                        const SizedBox(height: 14),
                        if (!canEdit) ...[
                          const _ReadOnlyBanner(),
                          const SizedBox(height: 14),
                        ],
                        _SearchBar(
                          controller: _search,
                          onlyModified: _onlyModified,
                          modifiedCount: modifiedCount,
                          onChanged: (v) => setState(() => _query = v),
                          onToggleModified: () =>
                              setState(() => _onlyModified = !_onlyModified),
                        ),
                        const SizedBox(height: 16),
                        if (visibleGroups.isEmpty)
                          _EmptyResults(
                            onClear: () => setState(() {
                              _search.clear();
                              _query = '';
                              _onlyModified = false;
                            }),
                          )
                        else
                          for (final g in visibleGroups)
                            _PermissionGroupCard(
                              key: ValueKey('${role.id}:${g.key}'),
                              title: _groupLabels[g.key]!,
                              icon: _groupIcons[g.key] ?? Icons.circle,
                              permissions: g.value,
                              totalInGroup: groups[g.key]!.length,
                              effective: effective,
                              role: role,
                              canEdit: canEdit && !_busy,
                              collapsed:
                                  !searching && _collapsed.contains(g.key),
                              onToggleCollapsed: () => setState(() {
                                if (!_collapsed.remove(g.key)) {
                                  _collapsed.add(g.key);
                                }
                              }),
                              onChanged: (p, v) => _toggle(p, v, effective),
                              onRevert: _revert,
                              onEnableAll: () => _bulk(
                                groups[g.key]!,
                                effective,
                                target: true,
                              ),
                              onDisableAll: () => _bulk(
                                groups[g.key]!,
                                effective,
                                target: false,
                              ),
                              onDefaults: () => _bulk(
                                groups[g.key]!,
                                effective,
                                target: null,
                              ),
                            ),
                        const SizedBox(height: 4),
                        const _OwnerNote(),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// ROLE SELECTOR + SUMMARY
// ============================================================

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({
    required this.selected,
    required this.roles,
    required this.overrides,
    required this.headcount,
    required this.padding,
    required this.onSelect,
  });

  final RoleRef selected;
  final List<RoleRef> roles;
  final List<RolePermissionOverride> overrides;
  final Map<String, int> headcount;
  final double padding;
  final ValueChanged<RoleRef> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        children: [
          for (final role in roles)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _RoleChip(
                role: role,
                selected: role.id == selected.id,
                customized: overrides.any((o) => o.role == role.id),
                people: headcount[role.id] ?? 0,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(role);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.role,
    required this.selected,
    required this.customized,
    required this.people,
    required this.onTap,
  });

  final RoleRef role;
  final bool selected;
  final bool customized;
  final int people;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : theme.colorScheme.outlineVariant,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconOf(role), size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  role.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (people > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$people',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: fg.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (customized) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : AppColors.warning,
                      shape: BoxShape.circle,
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

class _RoleSummaryCard extends StatelessWidget {
  const _RoleSummaryCard({
    required this.role,
    required this.grantedCount,
    required this.totalCount,
    required this.modifiedCount,
    required this.people,
    required this.onReset,
  });

  final RoleRef role;
  final int grantedCount;
  final int totalCount;
  final int modifiedCount;
  final int people;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: grantedCount / totalCount),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: v,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                  Center(
                    child: Icon(_iconOf(role), color: Colors.white, size: 26),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  _blurbOf(role),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill('$grantedCount of $totalCount enabled'),
                    _Pill('$people ${people == 1 ? 'person' : 'people'}'),
                    if (modifiedCount > 0)
                      _Pill('$modifiedCount customized', highlight: true),
                  ],
                ),
              ],
            ),
          ),
          if (onReset != null)
            IconButton(
              tooltip: 'Reset to defaults',
              onPressed: onReset,
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
              ),
              icon: const Icon(Icons.restart_alt_rounded),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withValues(alpha: 0.30)
            : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================
// SEARCH, BANNERS, EMPTY
// ============================================================

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onlyModified,
    required this.modifiedCount,
    required this.onChanged,
    required this.onToggleModified,
  });

  final TextEditingController controller;
  final bool onlyModified;
  final int modifiedCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleModified;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search permissions',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            filled: true,
            fillColor: scheme.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilterChip(
          selected: onlyModified,
          onSelected: (_) => onToggleModified(),
          avatar: Icon(
            Icons.tune_rounded,
            size: 16,
            color: onlyModified ? scheme.onSecondaryContainer : null,
          ),
          label: Text('Customized only ($modifiedCount)'),
        ),
      ],
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'View only. Your role can\'t change permissions.',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerNote extends StatelessWidget {
  const _OwnerNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The Owner always has every permission and can\'t be '
              'customized, so a mistake here can never lock everyone out.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 32,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No matching permissions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

// ============================================================
// GROUP CARD + PERMISSION TILE
// ============================================================

class _PermissionGroupCard extends StatelessWidget {
  const _PermissionGroupCard({
    super.key,
    required this.title,
    required this.icon,
    required this.permissions,
    required this.totalInGroup,
    required this.effective,
    required this.role,
    required this.canEdit,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onChanged,
    required this.onRevert,
    required this.onEnableAll,
    required this.onDisableAll,
    required this.onDefaults,
  });

  final String title;
  final IconData icon;

  /// The rows to show (after search/filter).
  final List<BosPermission> permissions;
  final int totalInGroup;
  final Set<BosPermission> effective;
  final RoleRef role;
  final bool canEdit;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final Future<void> Function(BosPermission, bool) onChanged;
  final Future<void> Function(BosPermission) onRevert;
  final VoidCallback onEnableAll;
  final VoidCallback onDisableAll;
  final VoidCallback onDefaults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final granted = permissions.where(effective.contains).length;
    final allOn = granted == permissions.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: onToggleCollapsed,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, size: 18, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: allOn
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$granted/${permissions.length}'
                        '${permissions.length != totalInGroup ? '*' : ''}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: allOn
                              ? AppColors.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (canEdit)
                      PopupMenuButton<int>(
                        tooltip: 'Group actions',
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                        onSelected: (v) {
                          switch (v) {
                            case 0:
                              onEnableAll();
                            case 1:
                              onDisableAll();
                            case 2:
                              onDefaults();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 0, child: Text('Enable all')),
                          PopupMenuItem(value: 1, child: Text('Disable all')),
                          PopupMenuItem(
                            value: 2,
                            child: Text('Reset to defaults'),
                          ),
                        ],
                      )
                    else
                      const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: collapsed
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      children: [
                        for (final p in permissions) ...[
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                          _PermissionTile(
                            permission: p,
                            granted: effective.contains(p),
                            defaultGranted: RolePermissions.allows(
                              role.base,
                              p,
                            ),
                            canEdit: canEdit,
                            onChanged: (v) => onChanged(p, v),
                            onRevert: () => onRevert(p),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.permission,
    required this.granted,
    required this.defaultGranted,
    required this.canEdit,
    required this.onChanged,
    required this.onRevert,
  });

  final BosPermission permission;
  final bool granted;
  final bool defaultGranted;
  final bool canEdit;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final modified = granted != defaultGranted;
    final risky = _sensitive.contains(permission);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: modified
          ? AppColors.warning.withValues(alpha: 0.07)
          : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _titleOf(permission),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (risky)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 12,
                              color: scheme.onErrorContainer,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Sensitive',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _hintOf(permission),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
                if (modified)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 15,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Default is ${defaultGranted ? 'on' : 'off'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (canEdit) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: onRevert,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                'Revert',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: granted,
            activeThumbColor: AppColors.accent,
            onChanged: canEdit ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

// final _failedRowsProvider = StreamProvider.autoDispose<List<SyncOutboxData>>((
//   ref,
// ) {
//   final businessId = ref.watch(selectedBusinessIdProvider);
//   return ref
//       .watch(syncStatusServiceProvider)
//       .watchFailed(businessId)
//       .map(
//         (rows) => rows.where((r) => _isPermissionEntity(r.entityType)).toList(),
//       );
// });

Future<void> _showFailures(BuildContext context, WidgetRef ref) async {
  // Capture everything before any await.
  final businessId = ref.read(selectedBusinessIdProvider);
  final status = ref.read(syncStatusServiceProvider);
  final trigger = ref.read(syncTriggerServiceProvider);

  final failed = await status.watchFailed(businessId).first;
  final rows = failed.where((r) => _isPermissionEntity(r.entityType)).toList();

  for (final r in rows) {
    debugPrint(
      '[permissions] failed ${r.entityType}/${r.entityId} '
      'op=${r.operation} attempts=${r.attemptCount} error=${r.error}',
    );
  }

  if (!context.mounted) return;

  final retry = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Some changes didn\'t sync'),
      content: SingleChildScrollView(
        child: rows.isEmpty
            ? const Text('Nothing is failing right now.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in rows.take(6)) ...[
                    Text(
                      '${r.entityType} · ${r.operation}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SelectableText(r.error ?? 'No reason recorded'),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Retry now'),
        ),
      ],
    ),
  );

  if (retry == true) {
    await status.requeueFailed(businessId);
    await trigger.syncNow();
  }
}
