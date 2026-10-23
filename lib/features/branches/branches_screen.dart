// lib/features/branches/branches_screen.dart
// Administration -> Branches: add / edit / deactivate branches, assign staff.

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart'
    show businessMembersProvider;
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branch/branch_service.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/people/hr_providers.dart'
    show hrNamesProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ------------------------------------------------------------ helpers --

const _green = Color(0xFF159B67);
const _amber = Color(0xFFB7791F);

String _err(Object e) => e is StateError ? e.message : e.toString();

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

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

// ------------------------------------------------------------- screen --

class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, Branch? b) async {
    final businessId = ref.read(selectedBusinessIdProvider);
    final service = ref.read(branchServiceProvider);
    final result =
        await showDialog<({String name, String address, String phone})>(
          context: context,
          builder: (_) => _BranchDialog(existing: b),
        );
    if (result == null) return;
    try {
      if (b == null) {
        await service.createBranch(
          businessId: businessId,
          name: result.name,
          address: result.address,
          phone: result.phone,
        );
      } else {
        await service.updateBranch(
          b.id,
          name: result.name,
          address: result.address,
          phone: result.phone,
        );
      }
    } catch (e) {
      if (context.mounted) _snack(context, _err(e));
    }
  }

  void _staff(BuildContext context, Branch b) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _StaffSheet(branch: b),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Branch b,
  ) async {
    final deactivating = b.isActive;
    if (deactivating) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Deactivate ${b.name}?'),
          content: const Text(
            'It will disappear from branch pickers. History is kept and you '
            'can reactivate it any time.',
          ),
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
    } catch (e) {
      if (context.mounted) _snack(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final canManage = ref.watch(canProvider(BosPermission.branchManage));
    final branches = ref.watch(allBranchesProvider).value ?? const <Branch>[];
    final activeCount = branches.where((b) => b.isActive).length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Branches',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'add_branch',
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add branch'),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, c) {
          final side = ((c.maxWidth - 760) / 2).clamp(16.0, 9999.0);
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 12, side, 110),
            children: [
              _Hero(
                active: activeCount,
                inactive: branches.length - activeCount,
                total: branches.length,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Each branch has its own stock, register, cash drawer '
                        'and team. Suppliers, customers, products and the '
                        'chart of accounts are shared.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (branches.isEmpty)
                const _EmptyState()
              else
                for (final b in branches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BranchCard(
                      branch: b,
                      canManage: canManage,
                      onEdit: () => _edit(context, ref, b),
                      onStaff: () => _staff(context, b),
                      onToggle: () => _toggleActive(context, ref, b),
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
          Positioned(
            right: 30,
            bottom: -50,
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
                        Icons.store_mall_directory_rounded,
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
                            'Your locations',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _HeroStat('$active', 'Active')),
                    const SizedBox(width: 8),
                    Expanded(child: _HeroStat('$inactive', 'Inactive')),
                    const SizedBox(width: 8),
                    Expanded(child: _HeroStat('$total', 'Total')),
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
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
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
    final staffCount =
        ref.watch(branchMembersOfProvider(b.id)).value?.length ?? 0;
    final accent = !b.isActive
        ? scheme.outline
        : (b.isHeadquarters ? _amber : scheme.primary);
    final hasAddress = (b.address ?? '').isNotEmpty;
    final hasPhone = (b.phone ?? '').isNotEmpty;

    return Opacity(
      opacity: b.isActive ? 1 : 0.65,
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              b.isHeadquarters
                                  ? Icons.home_work_rounded
                                  : Icons.store_mall_directory_rounded,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
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
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (canManage && !b.isHeadquarters)
                            PopupMenuButton<String>(
                              tooltip: 'More',
                              onSelected: (_) => onToggle(),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(
                                    b.isActive ? 'Deactivate' : 'Reactivate',
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (hasAddress || hasPhone) ...[
                        const SizedBox(height: 12),
                        if (hasAddress)
                          _InfoRow(Icons.place_outlined, b.address!),
                        if (hasPhone) _InfoRow(Icons.phone_outlined, b.phone!),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.groups_outlined,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            staffCount == 0
                                ? 'No one assigned'
                                : '$staffCount assigned',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          if (canManage) ...[
                            TextButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit'),
                            ),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(64, 40),
                              ),
                              onPressed: onStaff,
                              icon: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 18,
                              ),
                              label: const Text('Staff'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
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
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.store_mall_directory_outlined,
              size: 38,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No branches yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "Add branch" to create your first one.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- dialog --

class _BranchDialog extends StatefulWidget {
  const _BranchDialog({this.existing});
  final Branch? existing;

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _address = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a branch name');
      return;
    }
    Navigator.pop(context, (
      name: _name.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(
            isNew ? Icons.add_business_rounded : Icons.edit_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(isNew ? 'Add branch' : 'Edit branch'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Branch name',
                hintText: 'e.g. Downtown',
                prefixIcon: const Icon(Icons.store_mall_directory_outlined),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
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
