// lib/features/people/branch_people.dart  (NEW FILE)
//
// Shared branch building blocks for the People screens (payroll, attendance,
// and anything else that shows people next to branches):
//   * assignedBranchesByUserProvider  userId -> active branches they're assigned to
//   * branchByIdProvider              branchId -> Branch (including inactive)
//   * BranchTag / UserBranchTags      small coloured pills
//   * BranchFilterChips               "All branches / Downtown / Any branch" chips
//   * BranchStatStrip                 horizontal cards (a number per branch) that
//                                     double as filters
//
// Rule used everywhere: a person with NO branch assignment works in every
// branch ("any branch"); an assigned person only in their branches.

import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filter / group key for people who aren't tied to a single branch.
const kAnyBranch = '__any__';

const _amber = Color(0xFFB7791F);
const _slate = Color(0xFF64748B);

const _branchPalette = <Color>[
  Color(0xFF0E7490),
  Color(0xFF6366F1),
  Color(0xFFDB2777),
  Color(0xFF16A34A),
  Color(0xFFEA580C),
  Color(0xFF7C3AED),
];

Color branchColorOf(Branch b) => b.isHeadquarters
    ? _amber
    : _branchPalette[b.id.hashCode.abs() % _branchPalette.length];

IconData branchIconOf(Branch b) => b.isHeadquarters
    ? Icons.home_work_rounded
    : Icons.store_mall_directory_rounded;

// ------------------------------------------------------------ providers --

/// userId -> the ACTIVE branches that person is assigned to (main first).
/// A user missing from the map has no assignment = works in every branch.
final assignedBranchesByUserProvider = Provider<Map<String, List<Branch>>>((
  ref,
) {
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

/// Every branch of the business by id (inactive ones too, so old records
/// still resolve to a name).
final branchByIdProvider = Provider<Map<String, Branch>>((ref) {
  final all = ref.watch(allBranchesProvider).value ?? const <Branch>[];
  return {for (final b in all) b.id: b};
});

/// The single branch a person belongs to, or null when they are unrestricted
/// or assigned to several (used to group money / hours per branch).
String? primaryBranchId(String userId, Map<String, List<Branch>> assigned) {
  final list = assigned[userId];
  return (list != null && list.length == 1) ? list.first.id : null;
}

/// null filter = everyone; [kAnyBranch] = unrestricted people; otherwise
/// people assigned to that branch.
bool matchesBranchFilter(
  String userId,
  String? filter,
  Map<String, List<Branch>> assigned,
) {
  if (filter == null) return true;
  final mine = assigned[userId] ?? const <Branch>[];
  if (filter == kAnyBranch) return mine.isEmpty;
  return mine.any((b) => b.id == filter);
}

bool employeeVisibleToViewer({
  required String employeeId,
  required String? viewerId,
  required String? ownerId,
  required Map<String, List<Branch>> assigned,
}) {
  if (viewerId == null || viewerId == ownerId || employeeId == viewerId) {
    return true;
  }
  final viewerBranches = {
    for (final branch in assigned[viewerId] ?? const <Branch>[]) branch.id,
  };
  if (viewerBranches.isEmpty) return true;
  final employeeBranches = assigned[employeeId] ?? const <Branch>[];
  return employeeBranches.isEmpty ||
      employeeBranches.any((branch) => viewerBranches.contains(branch.id));
}

// ----------------------------------------------------------------- tags --

class BranchTag extends StatelessWidget {
  const BranchTag({
    super.key,
    required this.label,
    required this.color,
    this.icon = Icons.storefront_outlined,
  });

  BranchTag.branch(Branch b, {Key? key})
    : this(key: key, label: b.name, color: branchColorOf(b));

  final String label;
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
              label,
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

/// A person's branches as pills ("Any branch" when they aren't limited).
class UserBranchTags extends ConsumerWidget {
  const UserBranchTags({super.key, required this.userId, this.max = 2});

  final String userId;
  final int max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine =
        ref.watch(assignedBranchesByUserProvider)[userId] ?? const <Branch>[];
    if (mine.isEmpty) {
      return const BranchTag(
        label: 'Any branch',
        color: _slate,
        icon: Icons.all_inclusive_rounded,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final b in mine.take(max)) BranchTag.branch(b),
        if (mine.length > max)
          BranchTag(label: '+${mine.length - max}', color: _slate, icon: null),
      ],
    );
  }
}

// -------------------------------------------------------- filter chips --

class BranchFilterChips extends StatelessWidget {
  const BranchFilterChips({
    super.key,
    required this.branches,
    required this.selected,
    required this.onSelect,
    this.showAny = true,
  });

  final List<Branch> branches;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final bool showAny;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget chip(String label, String? value, IconData icon, Color? color) {
      final isSelected = selected == value;
      final c = color ?? scheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          showCheckmark: false,
          selected: isSelected,
          selectedColor: (color ?? scheme.primary).withValues(alpha: 0.16),
          avatar: Icon(
            icon,
            size: 16,
            color: isSelected ? color ?? scheme.primary : c,
          ),
          label: Text(label),
          onSelected: (_) =>
              onSelect(value != null && selected == value ? null : value),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('All branches', null, Icons.apps_rounded, null),
          for (final b in branches)
            chip(b.name, b.id, branchIconOf(b), branchColorOf(b)),
          if (showAny)
            chip('Any branch', kAnyBranch, Icons.all_inclusive_rounded, _slate),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- stat strip --

class BranchStat {
  const BranchStat({
    required this.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.value,
    required this.caption,
  });

  /// A branch id, or [kAnyBranch].
  final String key;
  final String title;
  final IconData icon;
  final Color color;

  /// The headline number, already formatted ("₱12,400.00", "38h 20m").
  final String value;
  final String caption;
}

/// Horizontal cards, one per branch. Tapping a card selects it (the caller
/// decides what that filters); tapping the selected card again clears it.
class BranchStatStrip extends StatelessWidget {
  const BranchStatStrip({
    super.key,
    required this.title,
    required this.stats,
    required this.selected,
    required this.onSelect,
    this.hint,
    this.pad = 0,
  });

  final String title;
  final String? hint;
  final List<BranchStat> stats;
  final String? selected;
  final ValueChanged<String?> onSelect;

  /// Horizontal inset of the whole strip (0 when already inside padding).
  final double pad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad + 4, 0, pad, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  hint ??
                      (selected == null
                          ? 'Tap to filter'
                          : 'Tap again to clear'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              itemCount: stats.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final s = stats[i];
                return _StatCard(
                  stat: s,
                  selected: selected == s.key,
                  onTap: () => onSelect(selected == s.key ? null : s.key),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.stat,
    required this.selected,
    required this.onTap,
  });

  final BranchStat stat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = stat.color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 172,
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
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(stat.icon, size: 18, color: color),
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: selected ? 1 : 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: color,
                      ),
                    ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    stat.value,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: color,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      stat.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
