import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/features/auth/presentation/screens/users_roles_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
}

String _s(Object? v) => (v ?? '').toString().trim();

final _rosterProvider = FutureProvider.autoDispose<List<_Member>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final labels =
      ref.watch(roleLabelsProvider).value ?? const <String, String>{};
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  final me = ref.watch(authenticatedUserIdProvider);
  ref.watch(roleLabelsProvider).value ?? const <String, String>{};
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

  final query = db.select(db.businessMembers).join([
    leftOuterJoin(db.users, db.users.id.equalsExp(db.businessMembers.userId)),
  ])..where(db.businessMembers.businessId.equals(businessId));

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

// ============================================================
// SCREEN
// ============================================================

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  static const _inactiveKey = '__inactive__';

  final _search = TextEditingController();
  String _query = '';
  String? _filter; // null = all, role label, or _inactiveKey

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Member> _apply(List<_Member> all) {
    final q = _query.trim().toLowerCase();
    return all.where((m) {
      if (_filter == _inactiveKey) {
        if (m.isActive) return false;
      } else if (_filter != null && m.roleLabel != _filter) {
        return false;
      }
      if (q.isEmpty) return true;
      return m.name.toLowerCase().contains(q) ||
          m.email.toLowerCase().contains(q) ||
          m.roleLabel.toLowerCase().contains(q) ||
          _s(m.profile?.jobTitle).toLowerCase().contains(q) ||
          _s(m.profile?.phone).toLowerCase().contains(q);
    }).toList();
  }

  void _clear() {
    _search.clear();
    setState(() {
      _query = '';
      _filter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_rosterProvider);

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _ErrorState(onRetry: () => ref.invalidate(_rosterProvider)),
        data: (all) {
          if (all.isEmpty) {
            return _EmptyState(
              onRefresh: () => ref.invalidate(_rosterProvider),
            );
          }

          final shown = _apply(all);
          final roles = <String>{for (final m in all) m.roleLabel}.toList()
            ..sort();
          final hasInactive = all.any((m) => !m.isActive);
          final filtering = _query.trim().isNotEmpty || _filter != null;

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
                        child: _TeamSummary(members: all),
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
                          selected: _filter,
                          inactiveKey: _inactiveKey,
                          onSelect: (v) => setState(() => _filter = v),
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
                          child: _MemberGrid(members: shown),
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
// SUMMARY
// ============================================================

class _TeamSummary extends StatelessWidget {
  const _TeamSummary({required this.members});

  final List<_Member> members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = members.where((m) => m.isActive).length;
    final roles = members.map((m) => m.roleLabel).toSet().length;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 140,
              height: 140,
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
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Your team',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _Stat(value: '${members.length}', label: 'Members'),
                    _Stat(value: '$active', label: 'Active'),
                    _Stat(value: '$roles', label: 'Roles'),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
    required this.inactiveKey,
    required this.onSelect,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onQuery;
  final List<String> roles;
  final bool hasInactive;
  final String? selected;
  final String inactiveKey;
  final ValueChanged<String?> onSelect;

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
            hintText: 'Search name, email, role or phone…',
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
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              chip('All', null, icon: Icons.apps_rounded),
              for (final r in roles) ...[const SizedBox(width: 8), chip(r, r)],
              if (hasInactive) ...[
                const SizedBox(width: 8),
                chip('Inactive', inactiveKey, icon: Icons.pause_circle_outline),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// GRID + CARD
// ============================================================

class _MemberGrid extends StatelessWidget {
  const _MemberGrid({required this.members});

  final List<_Member> members;

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
            for (final m in members)
              SizedBox(
                width: cardWidth,
                child: _MemberCard(member: m),
              ),
          ],
        );
      },
    );
  }
}

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

Color _colorFor(String seed) =>
    _avatarPalette[seed.hashCode.abs() % _avatarPalette.length];

String _initials(String name) {
  final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.member, this.radius = 26});

  final _Member member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = _colorFor(member.userId.isEmpty ? member.name : member.userId);
    return CircleAvatar(
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member});

  final _Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = member.isActive
        ? const Color(0xFF159B67)
        : scheme.onSurfaceVariant;
    final jobTitle = _s(member.profile?.jobTitle);

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showMemberSheet(context, member),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Avatar(member: member),
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
                    if (jobTitle.isNotEmpty)
                      Text(
                        jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
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
                            Color(0xFFB7791F),
                            icon: Icons.workspace_premium_rounded,
                          ),
                        _Tag(member.roleLabel, scheme.primary),
                        _Tag(
                          member.isActive
                              ? 'Active'
                              : (member.status.isEmpty
                                    ? 'Inactive'
                                    : member.status[0].toUpperCase() +
                                          member.status.substring(1)),
                          statusColor,
                        ),
                        if (member.isYou) _Tag('You', scheme.tertiary),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
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
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (_) => _MemberSheet(member: member),
  );
}

class _MemberSheet extends ConsumerWidget {
  const _MemberSheet({required this.member});

  final _Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canManage = ref.watch(canProvider(BosPermission.usersView));
    final p = member.profile;

    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final personal = <(IconData, String, String)>[
      if (clean(p?.nickname) != null)
        (Icons.tag_faces_outlined, 'Nickname', clean(p!.nickname)!),
      if (clean(p?.jobTitle) != null)
        (Icons.work_outline_rounded, 'Position', clean(p!.jobTitle)!),
      if (clean(p?.phone) != null)
        (Icons.phone_outlined, 'Mobile', clean(p!.phone)!),
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
      (
        Icons.verified_user_outlined,
        'Status',
        member.isActive
            ? 'Active'
            : (member.status.isEmpty ? 'Inactive' : member.status),
      ),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _Avatar(member: member, radius: 40)),
                const SizedBox(height: 12),
                Text(
                  member.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (member.isOwner)
                      const _Tag(
                        'Owner',
                        Color(0xFFB7791F),
                        icon: Icons.workspace_premium_rounded,
                      ),
                    _Tag(member.roleLabel, scheme.primary),
                    if (member.isYou) _Tag('You', scheme.tertiary),
                  ],
                ),
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
                                ? 'Complete your profile to see your personal '
                                      'details here.'
                                : 'No personal details have been added by this '
                                      'member yet, or you don\'t have access to '
                                      'them.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (canManage && !member.isYou)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UsersRolesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Manage access'),
                      ),
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
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: rows[i].$3));
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(content: Text('${rows[i].$2} copied')),
                      );
                  },
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
    message: 'Try a different name, email or role.',
    actionLabel: 'Clear filters',
    actionIcon: Icons.filter_alt_off_rounded,
    onAction: onClear,
  );
}
