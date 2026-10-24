// lib/features/transactions/presentation/screens/employees_screen.dart
//
// People -> Employees. The team roster, now branch-aware:
//   * hero summary (members / active / roles / branches)
//   * branch overview strip: tap a branch to filter, with stacked avatars
//   * search + role filters, and a "By branch" grouped view
//   * member cards show role + branch tags
//   * detail sheet with branch access: people who can manage branches can
//     assign / unassign a person to branches right here
//
// Branch rule (same as the rest of the app): a person with NO branch
// assignment can work in every branch; once assigned, only in those branches.
// The owner always works in every branch.

import 'dart:math' as math;

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branch/branch_service.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/features/auth/presentation/screens/users_roles_screen.dart';
import 'package:bos_application/features/branches/branches_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// ============================================================
// CONSTANTS + COLOURS
// ============================================================

const _inactiveKey = '__inactive__';
const _anyBranchKey = '__any__';

const _amber = Color(0xFFB7791F);
const _green = Color(0xFF159B67);
const _orange = Color(0xFFF59E0B);
const _slate = Color(0xFF64748B);

const _rolePalette = <Color>[
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
  Color(0xFF6366F1),
];

const _branchPalette = <Color>[
  Color(0xFF0E7490),
  Color(0xFF6366F1),
  Color(0xFFDB2777),
  Color(0xFF16A34A),
  Color(0xFFEA580C),
  Color(0xFF7C3AED),
];

const _avatarPalette = <Color>[
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF06B6D4),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

Color _roleColor(String roleId) {
  if (roleId == 'owner') return _amber;
  return _rolePalette[roleId.hashCode.abs() % _rolePalette.length];
}

Color _branchColor(Branch b) => b.isHeadquarters
    ? _amber
    : _branchPalette[b.id.hashCode.abs() % _branchPalette.length];

Color _colorFor(String seed) =>
    _avatarPalette[seed.hashCode.abs() % _avatarPalette.length];

String _initials(String name) {
  final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _s(Object? v) => (v ?? '').toString().trim();

String _err(Object e) => e is StateError ? e.message : e.toString();

// ============================================================
// DATA
// ============================================================

class _Member {
  const _Member({
    required this.userId,
    required this.name,
    required this.email,
    required this.roleId,
    required this.roleLabel,
    required this.status,
    required this.joinedAt,
    required this.isOwner,
    required this.isYou,
    this.profile,
  });

  final String userId;
  final String name;
  final String email;
  final String roleId;
  final String roleLabel;
  final String status;
  final DateTime? joinedAt;
  final bool isOwner;
  final bool isYou;
  final EmployeeProfile? profile;

  bool get isActive => status.toLowerCase() == 'active';

  String get statusLabel => isActive
      ? 'Active'
      : (status.isEmpty
            ? 'Inactive'
            : status[0].toUpperCase() + status.substring(1));

  Color get statusColor => isActive
      ? _green
      : (status.toLowerCase() == 'suspended' ? _orange : _slate);
}

final _rosterProvider = FutureProvider.autoDispose<List<_Member>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final labels =
      ref.watch(roleLabelsProvider).value ?? const <String, String>{};
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  final me = ref.watch(authenticatedUserIdProvider);
  final ownerId = ref.watch(currentBusinessProvider).value?.ownerUserId;

  // Cloud profiles are best effort: offline or blocked by permissions, the
  // roster still loads from the local members table.
  var profiles = const <String, EmployeeProfile>{};
  try {
    profiles = await ref
        .read(employeeProfileServiceProvider)
        .fetchAllForBusiness(businessId)
        .timeout(const Duration(seconds: 6));
  } on Object {
    // ignored
  }

  final query =
      db.select(db.businessMembers).join([
        leftOuterJoin(
          db.users,
          db.users.id.equalsExp(db.businessMembers.userId),
        ),
      ])..where(
        db.businessMembers.businessId.equals(businessId) &
            db.businessMembers.status.equals('removed').not(),
      );

  final rows = await query.get();

  final members = rows.map((row) {
    final m = row.readTable(db.businessMembers);
    final u = row.readTableOrNull(db.users);
    final userId = _s(m.userId);
    final profile = profiles[userId];

    final email = _s(u?.email);
    final profileName = _s(profile?.fullName);
    final rawName = _s(u?.displayName);
    final name = profileName.isNotEmpty
        ? profileName
        : rawName.isNotEmpty
        ? rawName
        : (email.isNotEmpty ? email.split('@').first : 'Team member');

    final roleId = _s(m.role);
    return _Member(
      userId: userId,
      name: name,
      email: email,
      roleId: roleId,
      roleLabel: roleLabelFor(labels, roleId),
      status: _s(m.status),
      joinedAt: m.joinedAt,
      isOwner: ownerId != null && userId == ownerId,
      isYou: me != null && userId == me,
      profile: profile,
    );
  }).toList();

  members.sort((a, b) {
    if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
    if (a.isYou != b.isYou) return a.isYou ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return members;
});

/// userId -> the ACTIVE branches that person is assigned to (main first).
/// A user missing from the map has no assignment = works in every branch.
final _assignedBranchesProvider = Provider<Map<String, List<Branch>>>((ref) {
  final branches = ref.watch(allBranchesProvider).value ?? const <Branch>[];
  final rows =
      ref.watch(allBranchAssignmentsProvider).value ?? const <BranchMember>[];
  final byId = {
    for (final b in branches)
      if (b.isActive) b.id: b,
  };
  final out = <String, List<Branch>>{};
  for (final r in rows) {
    final b = byId[r.branchId];
    if (b != null) (out[r.userId] ??= []).add(b);
  }
  for (final list in out.values) {
    list.sort((a, b) {
      if (a.isHeadquarters != b.isHeadquarters) {
        return a.isHeadquarters ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }
  return out;
});

bool _unrestricted(_Member m, Map<String, List<Branch>> assigned) =>
    m.isOwner || (assigned[m.userId]?.isEmpty ?? true);

// ============================================================
// SCREEN
// ============================================================

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _roleFilter; // null = all, a role label, or _inactiveKey
  String? _branchFilter; // null = all, a branch id, or _anyBranchKey
  bool _byBranch = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Member> _apply(
    List<_Member> all,
    Map<String, List<Branch>> assigned,
    String? branchFilter,
    bool multi,
  ) {
    final q = _query.trim().toLowerCase();
    return all.where((m) {
      if (_roleFilter == _inactiveKey) {
        if (m.isActive) return false;
      } else if (_roleFilter != null && m.roleLabel != _roleFilter) {
        return false;
      }

      final mine = assigned[m.userId] ?? const <Branch>[];
      if (branchFilter != null) {
        if (branchFilter == _anyBranchKey) {
          if (!_unrestricted(m, assigned)) return false;
        } else if (m.isOwner || !mine.any((b) => b.id == branchFilter)) {
          return false;
        }
      }

      if (q.isEmpty) return true;
      final branchText = multi
          ? mine.map((b) => b.name).join(' ').toLowerCase()
          : '';
      return m.name.toLowerCase().contains(q) ||
          m.email.toLowerCase().contains(q) ||
          m.roleLabel.toLowerCase().contains(q) ||
          branchText.contains(q) ||
          _s(m.profile?.jobTitle).toLowerCase().contains(q) ||
          _s(m.profile?.phone).toLowerCase().contains(q);
    }).toList();
  }

  void _clear() {
    _search.clear();
    setState(() {
      _query = '';
      _roleFilter = null;
      _branchFilter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_rosterProvider);
    final branches = ref.watch(branchesProvider); // active, main first
    final assigned = ref.watch(_assignedBranchesProvider);
    final canManageBranches = ref.watch(
      canProvider(BosPermission.branchManage),
    );
    final multi = branches.length >= 2;

    // Ignore a stale branch filter (e.g. the branch was just deactivated).
    final branchFilter =
        multi &&
            (_branchFilter == _anyBranchKey ||
                branches.any((b) => b.id == _branchFilter))
        ? _branchFilter
        : null;

    return Scaffold(
      body: async.when(
        loading: () => const _LoadingSkeleton(),
        error: (e, _) =>
            _ErrorState(onRetry: () => ref.invalidate(_rosterProvider)),
        data: (all) {
          if (all.isEmpty) {
            return _EmptyState(
              onRefresh: () => ref.invalidate(_rosterProvider),
            );
          }

          final shown = _apply(all, assigned, branchFilter, multi);
          final roles = <String>{for (final m in all) m.roleLabel}.toList()
            ..sort();
          final hasInactive = all.any((m) => !m.isActive);
          final filtering =
              _query.trim().isNotEmpty ||
              _roleFilter != null ||
              branchFilter != null;

          // Strip data: active members per branch + unrestricted people.
          final byBranch = <String, List<_Member>>{
            for (final b in branches)
              b.id: [
                for (final m in all)
                  if (m.isActive &&
                      !m.isOwner &&
                      (assigned[m.userId]?.any((x) => x.id == b.id) ?? false))
                    m,
              ],
          };
          final unrestricted = [
            for (final m in all)
              if (m.isActive && _unrestricted(m, assigned)) m,
          ];

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_rosterProvider);
              await ref.read(_rosterProvider.future);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = (constraints.maxWidth - 1000) / 2;
                final pad = side < 16 ? 16.0 : side;

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
                      sliver: SliverToBoxAdapter(
                        child: _TeamHero(
                          members: all,
                          branchCount: multi ? branches.length : 0,
                          onBranches: canManageBranches
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const BranchesScreen(),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (multi)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.2,
                            child: _BranchStrip(
                              branches: branches,
                              byBranch: byBranch,
                              unrestricted: unrestricted,
                              selected: branchFilter,
                              pad: pad,
                              onSelect: (v) => setState(
                                () => _branchFilter = _branchFilter == v
                                    ? null
                                    : v,
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
                      sliver: SliverToBoxAdapter(
                        child: _SearchAndFilters(
                          controller: _search,
                          query: _query,
                          onQuery: (v) => setState(() => _query = v),
                          roles: roles,
                          hasInactive: hasInactive,
                          selected: _roleFilter,
                          onSelect: (v) => setState(() => _roleFilter = v),
                          showViewToggle: multi,
                          byBranch: _byBranch,
                          onToggleView: (v) => setState(() => _byBranch = v),
                        ),
                      ),
                    ),
                    if (filtering)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(pad + 4, 12, pad, 0),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${shown.length} of ${all.length} '
                                  'member${all.length == 1 ? '' : 's'}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                              TextButton(
                                onPressed: _clear,
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (shown.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _NoResults(onClear: _clear),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
                        sliver: SliverToBoxAdapter(
                          child: (_byBranch && multi)
                              ? _GroupedMembers(
                                  members: shown,
                                  branches: branches,
                                  assigned: assigned,
                                  onlyBranch: branchFilter,
                                )
                              : _MemberGrid(
                                  members: shown,
                                  assigned: assigned,
                                  showBranches: multi,
                                ),
                        ),
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
// SMALL ANIMATION HELPERS
// ============================================================

class _CountUp extends StatelessWidget {
  const _CountUp(this.value, {required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Text('${v.round()}', style: style),
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + math.min(index, 10) * 45),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 12),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ============================================================
// HERO
// ============================================================

class _TeamHero extends StatelessWidget {
  const _TeamHero({
    required this.members,
    required this.branchCount,
    required this.onBranches,
  });

  final List<_Member> members;

  /// 0 hides the branches stat (single-branch business).
  final int branchCount;
  final VoidCallback? onBranches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = members.where((m) => m.isActive).length;
    final roles = members.map((m) => m.roleLabel).toSet().length;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: 60,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
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
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your team',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            branchCount > 0
                                ? 'People, roles and where they work'
                                : 'People and their roles',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xD9FFFFFF),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onBranches != null) ...[
                      const SizedBox(width: 8),
                      _GlassButton(
                        icon: Icons.store_mall_directory_rounded,
                        label: 'Branches',
                        onTap: onBranches!,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(value: members.length, label: 'Members'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStat(value: active, label: 'Active'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStat(value: roles, label: 'Roles'),
                    ),
                    if (branchCount > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HeroStat(value: branchCount, label: 'Branches'),
                      ),
                    ],
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

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final int value;
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
            child: _CountUp(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BRANCH OVERVIEW STRIP
// ============================================================

class _BranchStrip extends StatelessWidget {
  const _BranchStrip({
    required this.branches,
    required this.byBranch,
    required this.unrestricted,
    required this.selected,
    required this.pad,
    required this.onSelect,
  });

  final List<Branch> branches;
  final Map<String, List<_Member>> byBranch;
  final List<_Member> unrestricted;
  final String? selected;
  final double pad;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad + 4, 0, pad, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Where they work',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                selected == null
                    ? 'Tap a branch to filter'
                    : 'Tap again to clear',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 136,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            children: [
              for (var i = 0; i < branches.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _FadeIn(
                    index: i,
                    child: _BranchCard(
                      title: branches[i].name,
                      subtitle: branches[i].isHeadquarters
                          ? 'Main branch'
                          : (branches[i].code ?? 'Branch'),
                      icon: branches[i].isHeadquarters
                          ? Icons.home_work_rounded
                          : Icons.store_mall_directory_rounded,
                      color: _branchColor(branches[i]),
                      people: byBranch[branches[i].id] ?? const [],
                      selected: selected == branches[i].id,
                      onTap: () => onSelect(branches[i].id),
                    ),
                  ),
                ),
              _FadeIn(
                index: branches.length,
                child: _BranchCard(
                  title: 'Any branch',
                  subtitle: 'Not limited',
                  icon: Icons.all_inclusive_rounded,
                  color: _slate,
                  people: unrestricted,
                  selected: selected == _anyBranchKey,
                  onTap: () => onSelect(_anyBranchKey),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.people,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_Member> people;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 176,
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected
              ? color
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (selected ? color : Colors.black).withValues(
              alpha: selected ? 0.18 : 0.04,
            ),
            blurRadius: selected ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              key: const ValueKey('on'),
                              size: 20,
                              color: color,
                            )
                          : Text(
                              '${people.length}',
                              key: const ValueKey('count'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),
                            ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                people.isEmpty
                    ? Text(
                        'No one yet',
                        style: TextStyle(fontSize: 11.5, color: scheme.outline),
                      )
                    : _AvatarStack(members: people),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members}) : max = 4, radius = 11;

  final List<_Member> members;
  final double radius;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final step = radius * 1.35;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final width = radius * 2 + step * (count - 1);

    Widget bubble(Color bg, Widget child) => Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 1.6),
      ),
      child: CircleAvatar(
        radius: radius - 1.6,
        backgroundColor: bg,
        child: child,
      ),
    );

    return SizedBox(
      width: width,
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: bubble(
                _colorFor(
                  shown[i].userId.isEmpty ? shown[i].name : shown[i].userId,
                ).withValues(alpha: 0.2),
                Text(
                  _initials(shown[i].name),
                  style: TextStyle(
                    fontSize: radius * 0.72,
                    fontWeight: FontWeight.w800,
                    color: _colorFor(
                      shown[i].userId.isEmpty ? shown[i].name : shown[i].userId,
                    ),
                  ),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: bubble(
                scheme.surfaceContainerHigh,
                Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: radius * 0.7,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
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
// SEARCH + FILTERS
// ============================================================

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.query,
    required this.onQuery,
    required this.roles,
    required this.hasInactive,
    required this.selected,
    required this.onSelect,
    required this.showViewToggle,
    required this.byBranch,
    required this.onToggleView,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onQuery;
  final List<String> roles;
  final bool hasInactive;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final bool showViewToggle;
  final bool byBranch;
  final ValueChanged<bool> onToggleView;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget chip(String label, String? value, {IconData? icon}) {
      final isSelected = selected == value;
      return ChoiceChip(
        showCheckmark: false,
        selected: isSelected,
        avatar: icon == null
            ? null
            : Icon(
                icon,
                size: 16,
                color: isSelected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
        label: Text(label),
        onSelected: (_) => onSelect(value),
      );
    }

    return Column(
      children: [
        TextField(
          controller: controller,
          onChanged: onQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search name, role, branch or phone…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      onQuery('');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    chip('All', null, icon: Icons.apps_rounded),
                    for (final r in roles) ...[
                      const SizedBox(width: 8),
                      chip(r, r),
                    ],
                    if (hasInactive) ...[
                      const SizedBox(width: 8),
                      chip(
                        'Inactive',
                        _inactiveKey,
                        icon: Icons.pause_circle_outline,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showViewToggle) ...[
              const SizedBox(width: 10),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.view_agenda_outlined, size: 18),
                    tooltip: 'List',
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.account_tree_outlined, size: 18),
                    tooltip: 'By branch',
                  ),
                ],
                selected: {byBranch},
                onSelectionChanged: (s) => onToggleView(s.first),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ============================================================
// GRID, GROUPS + CARD
// ============================================================

class _MemberGrid extends StatelessWidget {
  const _MemberGrid({
    required this.members,
    required this.assigned,
    required this.showBranches,
  });

  final List<_Member> members;
  final Map<String, List<Branch>> assigned;
  final bool showBranches;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    const minWidth = 440.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = ((w + gap) / (minWidth + gap)).floor().clamp(1, 2);
        final cardWidth = (w - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < members.length; i++)
              KeyedSubtree(
                key: ValueKey(members[i].userId),
                child: _FadeIn(
                  index: i,
                  child: SizedBox(
                    width: cardWidth,
                    child: _MemberCard(
                      member: members[i],
                      branches: assigned[members[i].userId] ?? const <Branch>[],
                      showBranches: showBranches,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GroupedMembers extends StatelessWidget {
  const _GroupedMembers({
    required this.members,
    required this.branches,
    required this.assigned,
    required this.onlyBranch,
  });

  final List<_Member> members;
  final List<Branch> branches;
  final Map<String, List<Branch>> assigned;
  final String? onlyBranch;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];

    void add(Widget header, List<_Member> list) {
      if (list.isEmpty) return;
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 22));
      sections.add(header);
      sections.add(const SizedBox(height: 10));
      sections.add(
        _MemberGrid(members: list, assigned: assigned, showBranches: true),
      );
    }

    for (final b in branches) {
      if (onlyBranch != null && onlyBranch != b.id) continue;
      final list = [
        for (final m in members)
          if (!m.isOwner &&
              (assigned[m.userId]?.any((x) => x.id == b.id) ?? false))
            m,
      ];
      add(
        _GroupHeader(
          icon: b.isHeadquarters
              ? Icons.home_work_rounded
              : Icons.store_mall_directory_rounded,
          color: _branchColor(b),
          title: b.name,
          subtitle: b.isHeadquarters ? 'Main branch' : (b.code ?? 'Branch'),
          count: list.length,
        ),
        list,
      );
    }

    if (onlyBranch == null || onlyBranch == _anyBranchKey) {
      final list = [
        for (final m in members)
          if (_unrestricted(m, assigned)) m,
      ];
      add(
        _GroupHeader(
          icon: Icons.all_inclusive_rounded,
          color: _slate,
          title: 'Any branch',
          subtitle: 'Not limited to one branch',
          count: list.length,
        ),
        list,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.member,
    this.radius = 26,
    this.showStatus = false,
  });

  final _Member member;
  final double radius;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _colorFor(member.userId.isEmpty ? member.name : member.userId);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: c.withValues(alpha: 0.15),
          child: Text(
            _initials(member.name),
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: radius * 0.72,
            ),
          ),
        ),
        if (showStatus)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: member.statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color, {this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.branches,
    required this.showBranches,
  });

  final _Member member;
  final List<Branch> branches;
  final bool showBranches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = member.isActive ? _roleColor(member.roleId) : scheme.outline;
    final jobTitle = _s(member.profile?.jobTitle);

    final branchTags = <Widget>[];
    if (showBranches) {
      if (member.isOwner || branches.isEmpty) {
        branchTags.add(
          const _Tag('Any branch', _slate, icon: Icons.all_inclusive_rounded),
        );
      } else {
        for (final b in branches.take(2)) {
          branchTags.add(
            _Tag(b.name, _branchColor(b), icon: Icons.storefront_outlined),
          );
        }
        if (branches.length > 2) {
          branchTags.add(_Tag('+${branches.length - 2}', _slate));
        }
      }
    }

    return Opacity(
      opacity: member.isActive ? 1 : 0.72,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _showMemberSheet(context, member),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                      child: Row(
                        children: [
                          _Avatar(member: member, showStatus: true),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (jobTitle.isNotEmpty)
                                  Text(
                                    jobTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (member.email.isNotEmpty)
                                  Text(
                                    member.email,
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
                                    if (member.isOwner)
                                      const _Tag(
                                        'Owner',
                                        _amber,
                                        icon: Icons.workspace_premium_rounded,
                                      ),
                                    _Tag(member.roleLabel, accent),
                                    if (!member.isActive)
                                      _Tag(
                                        member.statusLabel,
                                        member.statusColor,
                                      ),
                                    if (member.isYou)
                                      _Tag('You', scheme.tertiary),
                                    ...branchTags,
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

// ============================================================
// DETAIL SHEET
// ============================================================

void _showMemberSheet(BuildContext context, _Member member) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (_) => _MemberSheet(member: member),
  );
}

void _copy(BuildContext context, String label, String value) {
  Clipboard.setData(ClipboardData(text: value));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$label copied')));
}

class _MemberSheet extends ConsumerWidget {
  const _MemberSheet({required this.member});

  final _Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canManageUsers = ref.watch(canProvider(BosPermission.usersView));
    final multi = ref.watch(branchesProvider).length >= 2;
    final p = member.profile;

    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final phone = clean(p?.phone);

    final personal = <(IconData, String, String)>[
      if (clean(p?.nickname) != null)
        (Icons.tag_faces_outlined, 'Nickname', clean(p!.nickname)!),
      if (clean(p?.jobTitle) != null)
        (Icons.work_outline_rounded, 'Position', clean(p!.jobTitle)!),
      if (phone != null) (Icons.phone_outlined, 'Mobile', phone),
      if (clean(p?.address) != null)
        (Icons.home_outlined, 'Address', clean(p!.address)!),
      if (p?.birthDate != null)
        (
          Icons.cake_outlined,
          'Birth date',
          DateFormat('MMMM d, yyyy').format(p!.birthDate!),
        ),
      if (clean(p?.emergencyContactName) != null ||
          clean(p?.emergencyContactPhone) != null)
        (
          Icons.contact_emergency_outlined,
          'Emergency contact',
          [
            clean(p?.emergencyContactName),
            clean(p?.emergencyContactPhone),
          ].whereType<String>().join(' · '),
        ),
    ];

    final account = <(IconData, String, String)>[
      (Icons.badge_outlined, 'Role', member.roleLabel),
      (Icons.verified_user_outlined, 'Status', member.statusLabel),
      if (member.email.isNotEmpty)
        (Icons.email_outlined, 'Email', member.email),
      if (member.joinedAt != null)
        (
          Icons.event_available_outlined,
          'Member since',
          DateFormat('MMMM d, yyyy').format(member.joinedAt!),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(member: member),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (member.email.isNotEmpty)
                            _QuickAction(
                              icon: Icons.email_outlined,
                              label: 'Copy email',
                              onTap: () =>
                                  _copy(context, 'Email', member.email),
                            ),
                          if (phone != null)
                            _QuickAction(
                              icon: Icons.phone_outlined,
                              label: 'Copy phone',
                              onTap: () => _copy(context, 'Phone', phone),
                            ),
                          if (canManageUsers && !member.isYou)
                            _QuickAction(
                              icon: Icons.manage_accounts_outlined,
                              label: 'Manage access',
                              onTap: () {
                                final nav = Navigator.of(context);
                                nav.pop();
                                nav.push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const UsersRolesScreen(),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      if (multi) ...[
                        const SizedBox(height: 22),
                        _BranchAccess(member: member),
                      ],
                      const SizedBox(height: 22),
                      _DetailGroup(title: 'Account', rows: account),
                      const SizedBox(height: 18),
                      if (personal.isNotEmpty)
                        _DetailGroup(title: 'Personal details', rows: personal)
                      else
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  member.isYou
                                      ? 'Complete your profile to see your '
                                            'personal details here.'
                                      : 'No personal details have been added '
                                            'by this member yet, or you don\'t '
                                            'have access to them.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.member});

  final _Member member;

  @override
  Widget build(BuildContext context) {
    final jobTitle = _s(member.profile?.jobTitle);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: _Avatar(member: member, radius: 38, showStatus: true),
                ),
                const SizedBox(height: 12),
                Text(
                  member.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                if (jobTitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      jobTitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (member.isOwner)
                      const _GlassTag(
                        'Owner',
                        icon: Icons.workspace_premium_rounded,
                      ),
                    _GlassTag(member.roleLabel),
                    _GlassTag(member.statusLabel),
                    if (member.isYou) const _GlassTag('You'),
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

class _GlassTag extends StatelessWidget {
  const _GlassTag(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

// ============================================================
// BRANCH ACCESS (inside the detail sheet)
// ============================================================

Future<void> _toggleBranch(
  BuildContext context,
  WidgetRef ref, {
  required _Member member,
  required Branch branch,
  required bool assign,
  required int currentCount,
}) async {
  final service = ref.read(branchServiceProvider);

  if (!assign && currentCount == 1) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove their last branch?'),
        content: Text(
          'With no branch assigned, ${member.name} can work in every branch. '
          'Keep at least one ticked to limit where they work.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow every branch'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }

  HapticFeedback.selectionClick();
  try {
    await service.setAssignment(
      businessId: branch.businessId,
      branchId: branch.id,
      userId: member.userId,
      assigned: assign,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }
}

class _BranchAccess extends ConsumerWidget {
  const _BranchAccess({required this.member});

  final _Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final branches = ref.watch(branchesProvider);
    final mine =
        ref.watch(_assignedBranchesProvider)[member.userId] ?? const <Branch>[];
    final canManage = ref.watch(canProvider(BosPermission.branchManage));
    final mineIds = {for (final b in mine) b.id};
    final unrestricted = member.isOwner || mine.isEmpty;
    final editable = canManage && !member.isOwner;

    final color = unrestricted ? _slate : scheme.primary;
    final title = member.isOwner
        ? 'Works in every branch'
        : unrestricted
        ? 'Works in every branch'
        : 'Limited to ${mine.length} of ${branches.length} branches';
    final detail = member.isOwner
        ? 'The owner always has access to all branches.'
        : unrestricted
        ? 'Not assigned to a branch yet, so no limits apply.'
        : 'They only see and sell from the branches below.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'BRANCH ACCESS',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  unrestricted
                      ? Icons.all_inclusive_rounded
                      : Icons.pin_drop_rounded,
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (editable) ...[
          const SizedBox(height: 10),
          for (final b in branches)
            _BranchTile(
              branch: b,
              checked: mineIds.contains(b.id),
              onChanged: (v) => _toggleBranch(
                context,
                ref,
                member: member,
                branch: b,
                assign: v,
                currentCount: mine.length,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              'Tick branches to limit where they can work. With none ticked, '
              'they can work in every branch.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ] else if (!member.isOwner && mine.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final b in mine)
                _Tag(b.name, _branchColor(b), icon: Icons.storefront_outlined),
            ],
          ),
        ],
      ],
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.checked,
    required this.onChanged,
  });

  final Branch branch;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _branchColor(branch);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: checked ? color.withValues(alpha: 0.10) : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: checked
                ? color
                : scheme.outlineVariant.withValues(alpha: 0.6),
            width: checked ? 1.4 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onChanged(!checked),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      branch.isHeadquarters
                          ? Icons.home_work_rounded
                          : Icons.store_mall_directory_rounded,
                      size: 21,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          branch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            if (branch.code != null) branch.code!,
                            if (branch.isHeadquarters) 'Main branch',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      checked
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(checked),
                      color: checked ? color : scheme.outline,
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

class _DetailGroup extends StatelessWidget {
  const _DetailGroup({required this.title, required this.rows});

  final String title;
  final List<(IconData, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 62),
                InkWell(
                  onLongPress: () => _copy(context, rows[i].$2, rows[i].$3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            rows[i].$1,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rows[i].$2,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                rows[i].$3,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// STATES
// ============================================================

class _LoadingSkeleton extends StatefulWidget {
  const _LoadingSkeleton();

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget block(double h, {double radius = 22}) => Container(
      height: h,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          block(150, radius: 28),
          const SizedBox(height: 16),
          block(52, radius: 16),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...[
            block(92),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: error
                      ? scheme.errorContainer
                      : scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 38,
                  color: error
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CenteredState(
    icon: Icons.cloud_off_rounded,
    title: 'Couldn’t load your team',
    message: 'Something went wrong while loading your members.',
    actionLabel: 'Try again',
    actionIcon: Icons.refresh_rounded,
    onAction: onRetry,
    error: true,
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => _CenteredState(
    icon: Icons.groups_outlined,
    title: 'No team members yet',
    message:
        'People you invite to this business will appear here with their '
        'role and details.',
    actionLabel: 'Refresh',
    actionIcon: Icons.refresh_rounded,
    onAction: onRefresh,
  );
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => _CenteredState(
    icon: Icons.search_off_rounded,
    title: 'No matching members',
    message: 'Try a different name, role or branch.',
    actionLabel: 'Clear filters',
    actionIcon: Icons.filter_alt_off_rounded,
    onAction: onClear,
  );
}
