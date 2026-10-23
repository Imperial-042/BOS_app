// lib/features/auth/presentation/screens/users_roles_screen.dart
//
// Administration -> Users & Roles. Lists everyone with access to the
// selected business, lets an authorized member generate invite codes for
// new roles, change roles, suspend/reactivate, remove, or (owner only)
// hand over ownership. All mutations go through MembershipService, which
// re-checks permissions and writes the audit trail - this screen only
// renders state and asks for confirmation before anything destructive.

import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/features/transactions/presentation/screens/custom_roles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/authorization_service.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/auth/membership_service.dart';
import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/supabase/cloud_business_service.dart';
import '../../../../core/supabase/supabase_service.dart';

final _syncUsersProvider = FutureProvider.autoDispose<void>((ref) async {
  if (!ref.read(supabaseAvailableProvider)) return;
  try {
    await syncBusinessUsers(
      ref.read(databaseProvider),
      ref.read(supabaseClientProvider),
      businessId: ref.read(selectedBusinessIdProvider),
    );
  } catch (_) {
    // Best-effort: local data still shows if offline.
  }
});

// ============================================================
// STYLE HELPERS
// ============================================================

const _activeColor = Color(0xFF159B67);
const _slate = Color(0xFF64748B);

/// Color, icon and one-line description for each role.
class _RoleStyle {
  const _RoleStyle(this.color, this.icon, this.blurb);

  final Color color;
  final IconData icon;
  final String blurb;

  static _RoleStyle of(String? roleId) {
    if (roleId != null && roleId.startsWith(kCustomRolePrefix)) {
      const colors = [
        Color(0xFF6366F1),
        Color(0xFF0EA5E9),
        Color(0xFFEC4899),
        Color(0xFF14B8A6),
        Color(0xFFF59E0B),
        Color(0xFF8B5CF6),
      ];
      return _RoleStyle(
        colors[roleId.hashCode.abs() % colors.length],
        Icons.tune_rounded,
        'Custom role',
      );
    }
    return switch (BosRole.fromId(roleId)) {
      BosRole.owner => const _RoleStyle(
        Color(0xFFB7791F),
        Icons.workspace_premium_rounded,
        'Full control of the business',
      ),
      BosRole.manager => const _RoleStyle(
        Color(0xFF3B82F6),
        Icons.supervisor_account_rounded,
        'Runs sales, stock, purchasing and the team',
      ),
      BosRole.accountant => const _RoleStyle(
        Color(0xFF8B5CF6),
        Icons.calculate_rounded,
        'Finance, receivables, payables and reports',
      ),
      BosRole.cashier => const _RoleStyle(
        Color(0xFF10B981),
        Icons.point_of_sale_rounded,
        'Rings up sales and adds customers',
      ),
      BosRole.inventory => const _RoleStyle(
        Color(0xFFF59E0B),
        Icons.inventory_2_rounded,
        'Stock, purchasing and suppliers',
      ),
      BosRole.employee => const _RoleStyle(
        _slate,
        Icons.badge_rounded,
        'Basic view access and own time records',
      ),
      BosRole.hr => const _RoleStyle(
        Color(0xFFEC4899),
        Icons.groups_rounded,
        'Schedules, attendance, leave and payroll',
      ),
      BosRole.staff => const _RoleStyle(
        Color(0xFF14B8A6),
        Icons.storefront_rounded,
        'Sells, looks up stock, own time and leave',
      ),
      null => const _RoleStyle(
        _slate,
        Icons.help_outline_rounded,
        'Unknown role',
      ),
    };
  }
}

// String _roleLabel(String roleId) => BosRole.fromId(roleId)?.label ?? roleId;

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final list = parts.toList();
  if (list.isEmpty) return '?';
  if (list.length == 1) return list.first[0].toUpperCase();
  return (list.first[0] + list.last[0]).toUpperCase();
}

BoxDecoration _cardDecoration(ColorScheme scheme) => BoxDecoration(
  color: scheme.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
);

// ============================================================
// SCREEN
// ============================================================

class UsersRolesScreen extends ConsumerStatefulWidget {
  const UsersRolesScreen({super.key});

  @override
  ConsumerState<UsersRolesScreen> createState() => _UsersRolesScreenState();
}

class _UsersRolesScreenState extends ConsumerState<UsersRolesScreen> {
  String? _roleFilter;

  Future<void> _refresh() async {
    ref.invalidate(_syncUsersProvider);
    await ref.read(_syncUsersProvider.future);
  }

  void _showInviteSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _InviteCodeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(_syncUsersProvider); // pulls members + invite codes from cloud
    final auth = ref.watch(authorizationServiceProvider);
    final canInvite = ref.watch(canProvider(BosPermission.usersInvite));
    final membersAsync = ref.watch(businessMembersProvider);
    final invitesAsync = ref.watch(pendingBusinessInvitesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Roles'),
        actions: [
          if (auth.isOwner)
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Manage custom roles',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomRolesScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),

      floatingActionButton: canInvite
          ? FloatingActionButton.extended(
              onPressed: _showInviteSheet,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Invite'),
            )
          : null,
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const _MessageState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn\'t load users',
          message: 'Pull down to try again.',
        ),
        data: (members) {
          final active = members.where((m) => m.status == 'active').toList();
          final invited = members.where((m) => m.status == 'invited').toList();
          final suspended = members
              .where((m) => m.status == 'suspended')
              .toList();
          final invites = invitesAsync.value ?? const <BusinessInvite>[];

          if (members.isEmpty && invites.isEmpty) {
            return const _MessageState(
              icon: Icons.manage_accounts_outlined,
              title: 'Nobody here yet',
              message: 'Invite a teammate to give them sign-in access.',
            );
          }

          // Role counts among people who can sign in right now.
          final counts = <String, int>{};
          for (final r in BosRole.values) {
            final n = active.where((m) => m.role == r.id).length;
            if (n > 0) counts[r.id] = n;
          }
          for (final m in active) {
            if (BosRole.fromId(m.role) == null) {
              counts[m.role] = (counts[m.role] ?? 0) + 1;
            }
          }
          final filter = counts.containsKey(_roleFilter) ? _roleFilter : null;

          List<BusinessMember> pass(List<BusinessMember> l) =>
              filter == null ? l : l.where((m) => m.role == filter).toList();

          final shownActive = pass(active);
          final shownInvited = pass(invited);
          final shownSuspended = pass(suspended);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: LayoutBuilder(
              builder: (context, c) {
                final side = (c.maxWidth - 720) / 2;
                final pad = side < 16 ? 16.0 : side;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(pad, 16, pad, 96),
                  children: [
                    _AccessHero(
                      active: active.length,
                      invited: invited.length,
                      suspended: suspended.length,
                    ),
                    if (counts.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _RoleMixCard(
                        counts: counts,
                        selected: filter,
                        onSelect: (v) => setState(() => _roleFilter = v),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (invites.isNotEmpty)
                      _InviteCodeSection(
                        invites: invites,
                        canManage: canInvite,
                      ),
                    if (shownActive.isNotEmpty)
                      _MemberSection(
                        title: 'Active',
                        color: _activeColor,
                        members: shownActive,
                        auth: auth,
                      ),
                    if (shownInvited.isNotEmpty)
                      _MemberSection(
                        title: 'Pending invitations',
                        color: _slate,
                        members: shownInvited,
                        auth: auth,
                      ),
                    if (shownSuspended.isNotEmpty)
                      _MemberSection(
                        title: 'Suspended',
                        color: AppColors.warning,
                        members: shownSuspended,
                        auth: auth,
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// HERO + ROLE MIX
// ============================================================

class _AccessHero extends StatelessWidget {
  const _AccessHero({
    required this.active,
    required this.invited,
    required this.suspended,
  });

  final int active;
  final int invited;
  final int suspended;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -60,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Team access',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Decide who can sign in and what they can do',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _HeroStat('$active', 'Active')),
                    const SizedBox(width: 8),
                    Expanded(child: _HeroStat('$invited', 'Invited')),
                    const SizedBox(width: 8),
                    Expanded(child: _HeroStat('$suspended', 'Suspended')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

/// Segmented bar of who holds which role. The chips under it double as
/// filters for the lists below.
class _RoleMixCard extends StatelessWidget {
  const _RoleMixCard({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = counts.entries.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Roles in use',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected != null)
                TextButton(
                  onPressed: () => onSelect(null),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Show all'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 12,
              color: scheme.surfaceContainerHigh,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: child,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      Expanded(
                        flex: entries[i].value,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(
                            right: i == entries.length - 1 ? 0 : 2,
                          ),
                          color: _RoleStyle.of(entries[i].key).color.withValues(
                            alpha:
                                selected == null || selected == entries[i].key
                                ? 1
                                : 0.22,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in entries)
                _RoleFilterChip(
                  roleId: e.key,
                  count: e.value,
                  selected: selected == e.key,
                  onTap: () => onSelect(selected == e.key ? null : e.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleFilterChip extends ConsumerWidget {
  const _RoleFilterChip({
    required this.roleId,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String roleId;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels =
        ref.watch(roleLabelsProvider).value ?? const <String, String>{};
    final scheme = Theme.of(context).colorScheme;
    final style = _RoleStyle.of(roleId);

    return Material(
      color: selected
          ? style.color.withValues(alpha: 0.14)
          : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? style.color
              : scheme.outlineVariant.withValues(alpha: 0.7),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 16, color: style.color),
              const SizedBox(width: 6),
              Text(
                roleLabelFor(labels, roleId),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                  color: style.color,
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
// SMALL SHARED WIDGETS
// ============================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTag extends ConsumerWidget {
  const _RoleTag(this.roleId);

  final String roleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels =
        ref.watch(roleLabelsProvider).value ?? const <String, String>{};
    final style = _RoleStyle.of(roleId);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 13, color: style.color),
          const SizedBox(width: 4),
          Text(
            roleLabelFor(labels, roleId),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: style.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _BranchTag extends StatelessWidget {
  const _BranchTag(this.label, {this.all = false});

  final String label;
  final bool all;

  @override
  Widget build(BuildContext context) {
    final color = all ? _slate : const Color(0xFF0E7490);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 13, color: color),
          const SizedBox(width: 4),
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
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.name,
    required this.roleId,
    required this.status,
    this.radius = 24,
  });

  final String name;
  final String roleId;
  final String status;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _RoleStyle.of(roleId);
    final dot = switch (status) {
      'active' => _activeColor,
      'suspended' => AppColors.warning,
      _ => _slate,
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: style.color.withValues(alpha: 0.15),
          child: Text(
            _initials(name),
            style: TextStyle(
              color: style.color,
              fontWeight: FontWeight.w800,
              fontSize: radius * 0.72,
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * 0.55,
            height: radius * 0.55,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable role row, shared by the role picker and the invite sheet.
class _RoleOption extends ConsumerWidget {
  const _RoleOption({
    required this.roleId,
    required this.selected,
    required this.onTap,
  });

  final String roleId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels =
        ref.watch(roleLabelsProvider).value ?? const <String, String>{};
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _RoleStyle.of(roleId);

    return Material(
      color: selected ? style.color.withValues(alpha: 0.10) : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? style.color
              : scheme.outlineVariant.withValues(alpha: 0.6),
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, color: style.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roleLabelFor(labels, roleId),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      style.blurb,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? style.color : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = destructive ? scheme.error : AppColors.primary;

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: tone),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: destructive ? scheme.error : null,
        ),
      ),
      subtitle: hint == null ? null : Text(hint!),
      onTap: onTap,
    );
  }
}

// ============================================================
// INVITE CODES
// ============================================================

class _InviteCodeSection extends ConsumerWidget {
  const _InviteCodeSection({required this.invites, required this.canManage});

  final List<BusinessInvite> invites;
  final bool canManage;

  Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Code copied.')));
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    BusinessInvite invite,
  ) async {
    final businessId = ref.read(selectedBusinessIdProvider);
    try {
      if (ref.read(supabaseAvailableProvider)) {
        await ref
            .read(supabaseClientProvider)
            .from('business_invites')
            .update({'status': 'revoked'})
            .eq('code', invite.code)
            .eq('status', 'pending');
      }
      await ref
          .read(membershipServiceProvider)
          .revokeInviteCode(businessId: businessId, inviteId: invite.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not revoke that code.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Invite codes',
            count: invites.length,
            color: AppColors.accent,
          ),
          for (final invite in invites)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: _cardDecoration(scheme),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 5,
                        color: _RoleStyle.of(invite.role).color,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                invite.code,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _RoleTag(invite.role),
                                  Text(
                                    'Works once',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'Copy code',
                        onPressed: () => _copy(context, invite.code),
                      ),
                      if (canManage)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Revoke',
                          onPressed: () => _revoke(context, ref, invite),
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// MEMBERS
// ============================================================

class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.title,
    required this.color,
    required this.members,
    required this.auth,
  });

  final String title;
  final Color color;
  final List<BusinessMember> members;
  final AuthorizationService auth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, count: members.length, color: color),
          for (final m in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MemberTile(member: m, auth: auth),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member, required this.auth});

  final BusinessMember member;
  final AuthorizationService auth;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on PermissionDeniedException catch (e) {
      if (context.mounted) _showError(context, e.message);
    } on StateError catch (e) {
      if (context.mounted) _showError(context, e.message);
    } catch (_) {
      if (context.mounted) {
        _showError(context, 'Something went wrong. Please try again.');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(title),
        content: Text(message),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          destructive
              ? FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel),
                )
              : FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel),
                ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showRoleSheet(BuildContext context, WidgetRef ref, String businessId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Change role',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick what this person can access.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                for (final r in ref.read(roleRefsProvider))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RoleOption(
                      roleId: r.id,
                      selected: r.id == member.role,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        if (r.id == member.role) return;
                        await _act(context, ref, () async {
                          await ref
                              .read(membershipServiceProvider)
                              .changeRoleToId(
                                businessId: businessId,
                                targetUserId: member.userId,
                                newRoleId: r.id,
                              );
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showActions(
    BuildContext context,
    WidgetRef ref, {
    required String displayName,
    required String? email,
    required bool canManageRoles,
    required bool canRemove,
  }) {
    final businessId = member.businessId;
    final nameForText = displayName;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        void close() => Navigator.pop(sheetContext);

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _MemberAvatar(
                      name: displayName,
                      roleId: member.role,
                      status: member.status,
                      radius: 26,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (email != null && email != displayName)
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(height: 6),
                          _RoleTag(member.role),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (canManageRoles && member.status != 'invited')
                  _ActionTile(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Change role',
                    hint:
                        'Currently ${roleLabelFor(ref.read(roleLabelsProvider).value ?? const <String, String>{}, member.role)}',
                    onTap: () {
                      close();
                      _showRoleSheet(context, ref, businessId);
                    },
                  ),
                if (canManageRoles && member.status == 'active')
                  _ActionTile(
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Suspend',
                    hint: 'Block sign-in without removing them',
                    onTap: () async {
                      close();
                      await _act(context, ref, () async {
                        await ref
                            .read(membershipServiceProvider)
                            .setSuspended(
                              businessId: businessId,
                              targetUserId: member.userId,
                              suspended: true,
                            );
                      });
                    },
                  ),
                if (canManageRoles && member.status == 'suspended')
                  _ActionTile(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Reactivate',
                    hint: 'Let them sign in again',
                    onTap: () async {
                      close();
                      await _act(context, ref, () async {
                        await ref
                            .read(membershipServiceProvider)
                            .setSuspended(
                              businessId: businessId,
                              targetUserId: member.userId,
                              suspended: false,
                            );
                      });
                    },
                  ),
                if (canManageRoles && auth.isOwner && member.status == 'active')
                  _ActionTile(
                    icon: Icons.workspace_premium_rounded,
                    label: 'Make owner',
                    hint: 'Transfer ownership to this person',
                    onTap: () async {
                      close();
                      final ok = await _confirm(
                        context,
                        title: 'Transfer ownership?',
                        message:
                            'You will become a Manager and $nameForText '
                            'will become the owner. This can\'t be undone by '
                            'you alone.',
                        confirmLabel: 'Transfer',
                        destructive: true,
                      );
                      if (!ok || !context.mounted) return;
                      await _act(context, ref, () async {
                        await ref
                            .read(membershipServiceProvider)
                            .transferOwnership(
                              businessId: businessId,
                              newOwnerUserId: member.userId,
                            );
                      });
                    },
                  ),
                if (canRemove)
                  _ActionTile(
                    icon: Icons.person_remove_alt_1_rounded,
                    label: 'Remove access',
                    hint: 'They can no longer sign in to this business',
                    destructive: true,
                    onTap: () async {
                      close();
                      final ok = await _confirm(
                        context,
                        title: 'Remove access?',
                        message:
                            '$nameForText will no longer be able to sign in '
                            'to this business.',
                        confirmLabel: 'Remove',
                        destructive: true,
                      );
                      if (!ok || !context.mounted) return;
                      await _act(context, ref, () async {
                        await ref
                            .read(membershipServiceProvider)
                            .removeMember(
                              businessId: businessId,
                              targetUserId: member.userId,
                            );
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(userByIdProvider(member.userId));
    final role = BosRole.fromId(member.role);
    final isSelf = member.userId == auth.userId;
    final isOwnerRow = role == BosRole.owner;
    final branchNames =
        ref.watch(branchNamesByUserProvider)[member.userId] ?? const <String>[];
    final allBranches = isOwnerRow || branchNames.isEmpty;

    final canManageRoles = ref.watch(
      canProvider(BosPermission.usersManageRoles),
    );
    final canRemove = ref.watch(canProvider(BosPermission.usersRemove));
    final canManage = !isSelf && !isOwnerRow;
    final actionable = canManage && (canManageRoles || canRemove);

    final name = user.maybeWhen(
      data: (u) => u?.displayName,
      orElse: () => null,
    );
    final email = user.maybeWhen(data: (u) => u?.email, orElse: () => null);
    final hasName = name?.isNotEmpty == true;
    final displayName = hasName ? name! : (email ?? member.userId);

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: actionable
            ? () => _showActions(
                context,
                ref,
                displayName: displayName,
                email: email,
                canManageRoles: canManageRoles,
                canRemove: canRemove,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _MemberAvatar(
                name: displayName,
                roleId: member.role,
                status: member.status,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (hasName && email != null)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _RoleTag(member.role),
                        if (member.status != 'invited' && allBranches)
                          const _BranchTag('All branches', all: true),
                        if (member.status != 'invited' && !allBranches)
                          for (final n in branchNames) _BranchTag(n),
                        if (member.status == 'suspended')
                          const _StatusTag('Suspended', Color(0xFF8A5A00)),
                        if (member.status == 'invited')
                          const _StatusTag('Invited', _slate),
                        if (isSelf) _StatusTag('You', scheme.tertiary),
                      ],
                    ),
                  ],
                ),
              ),
              if (actionable)
                Icon(Icons.more_horiz_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// INVITE SHEET
// ============================================================

class _InviteCodeSheet extends ConsumerStatefulWidget {
  const _InviteCodeSheet();

  @override
  ConsumerState<_InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends ConsumerState<_InviteCodeSheet> {
  String _roleId = BosRole.employee.id;
  bool _submitting = false;
  bool _pushing = false;
  String? _error;
  String? _cloudWarning; // set when the code exists on this device only
  bool _cloudSynced = false;
  BusinessInvite? _created;

  Future<void> _generate() async {
    setState(() {
      _submitting = true;
      _error = null;
      _cloudWarning = null;
      _cloudSynced = false;
    });

    try {
      final businessId = ref.read(selectedBusinessIdProvider);
      final invite = await ref
          .read(membershipServiceProvider)
          .createInviteCodeForId(businessId: businessId, roleId: _roleId);

      setState(() => _created = invite);
      await _pushToCloud();
    } on PermissionDeniedException catch (e) {
      setState(() => _error = e.message);
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Pushes the created code to Supabase. Never throws; records the outcome
  /// so the UI can say honestly whether the code works on other devices.
  Future<void> _pushToCloud() async {
    final invite = _created;
    if (invite == null) return;

    if (!ref.read(supabaseAvailableProvider)) {
      if (mounted) {
        setState(
          () => _cloudWarning =
              'Cloud is not configured in this build. This code only works '
              'on this device.',
        );
      }
      return;
    }

    // Cloud business ids are UUIDs. A local-only id (e.g. 'biz_123...') can
    // never be saved in Supabase, so say so instead of failing obscurely.
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(invite.businessId);
    if (!isUuid) {
      if (mounted) {
        setState(
          () => _cloudWarning =
              'This business only exists on this device (it is not linked to '
              'the cloud), so this code only works here.',
        );
      }
      return;
    }

    if (mounted) setState(() => _pushing = true);
    try {
      await ref
          .read(cloudBusinessServiceProvider)
          .pushInviteCode(
            businessId: invite.businessId,
            code: invite.code,
            role: invite.role,
          );
      if (mounted) {
        setState(() {
          _cloudSynced = true;
          _cloudWarning = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _cloudWarning =
              'Not saved to the cloud, so it will NOT work on other devices. '
              '$e',
        );
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _copy() async {
    final code = _created?.code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Code copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final created = _created;
    final labels =
        ref.watch(roleLabelsProvider).value ?? const <String, String>{};

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: created == null
              ? [
                  Text(
                    'Invite someone',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a role, then share the code with them. They enter '
                    'it while creating their account.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  for (final r in ref.watch(roleRefsProvider))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RoleOption(
                        roleId: r.id,
                        selected: r.id == _roleId,
                        onTap: () => setState(() => _roleId = r.id),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _submitting ? null : _generate,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Text(
                            'Generate ${roleLabelFor(labels, _roleId)} code',
                          ),
                  ),
                ]
              : [
                  Text(
                    'Code ready',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'It works once, for the ${roleLabelFor(labels, created.role)} role.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 22,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _RoleStyle.of(
                        created.role,
                      ).color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _RoleStyle.of(
                          created.role,
                        ).color.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        _RoleTag(created.role),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            created.code,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: _RoleStyle.of(created.role).color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_pushing)
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Saving to cloud…'),
                      ],
                    )
                  else if (_cloudSynced)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        const Text('Works on any device'),
                      ],
                    )
                  else if (_cloudWarning != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _cloudWarning!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pushToCloud,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry cloud save'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy code'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
        ),
      ),
    );
  }
}
