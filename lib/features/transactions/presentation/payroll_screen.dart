// lib/features/people/presentation/payroll_screen.dart
//
// People -> Payroll, now branch-aware:
//   Pay rates : branch filter chips + branch tags on every person
//   Pay run   : "Payroll by branch" strip (net pay per branch, tap to filter
//               the payslips), a share-of-total bar, branch tags on payslips,
//               and the branch breakdown in the copied summary
//
// Pay runs themselves are business-wide (payroll_runs has no branch column),
// so the branch view is DERIVED from each person's current branch assignment:
// someone assigned to exactly one branch counts there; everyone else
// (unrestricted, or in several branches) is grouped as "Any / several".
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/branch_people.dart';
import 'package:bos_application/features/people/hr_common.dart';
import 'package:bos_application/features/people/hr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

const Map<String, String> kPayTypes = {
  'daily': 'Daily rate',
  'hourly': 'Hourly rate',
  'fixed': 'Fixed per pay period',
};

const Map<String, IconData> _payTypeIcons = {
  'daily': Icons.wb_sunny_outlined,
  'hourly': Icons.schedule_rounded,
  'fixed': Icons.event_repeat_rounded,
};

String _period(PayrollRun r) =>
    '${DateFormat('MMM d').format(r.periodStart)} – '
    '${DateFormat('MMM d, yyyy').format(r.periodEnd)}';

String _basis(PayrollItem i) {
  String n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  return switch (i.payType) {
    // Parentheses matter: the rate applies to worked days AND paid leave.
    'daily' =>
      '(${n(i.daysWorked)} days worked + ${n(i.paidLeaveDays)} paid leave) '
          '× ${formatPeso(i.rate)}',
    'hourly' =>
      '${i.hoursWorked.toStringAsFixed(2)} hrs × ${formatPeso(i.rate)}',
    _ => 'Fixed ${formatPeso(i.rate)} per pay period',
  };
}

/// The name saved on a payslip is a snapshot taken when the run was created.
/// If the names weren't loaded at that moment it holds a placeholder like
/// "Team member", so fall back to the live name from the people list.
String _displayName(PayrollItem i, List<HrPerson> people) {
  final saved = i.userName.trim();
  final isPlaceholder = saved.isEmpty || saved.toLowerCase() == 'team member';
  if (!isPlaceholder) return saved;
  final live = people.where((p) => p.userId == i.userId).firstOrNull?.name;
  return (live != null && live.trim().isNotEmpty) ? live.trim() : saved;
}

String _people(int n) => '$n ${n == 1 ? 'person' : 'people'}';

List<Color> _heroColors(bool negative) => negative
    ? const [Color(0xFFB91C1C), Color(0xFFEF4444)]
    : AppColors.heroGradient;

// ============================================================================
// SHELL
// ============================================================================

class PayrollScreen extends StatelessWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            const _PillTabs(),
            const Expanded(
              child: TabBarView(children: [_RunsTab(), _RatesTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented pill tabs: the selected tab is a filled gradient pill.
class _PillTabs extends StatelessWidget {
  const _PillTabs();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Container(
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            splashBorderRadius: BorderRadius.circular(12),
            labelColor: Colors.white,
            unselectedLabelColor: scheme.onSurfaceVariant,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: AppColors.heroGradient),
            ),
            tabs: const [
              Tab(text: 'Pay runs'),
              Tab(text: 'Pay rates'),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PAY RATES
// ============================================================================

class _RatesTab extends ConsumerStatefulWidget {
  const _RatesTab();

  @override
  ConsumerState<_RatesTab> createState() => _RatesTabState();
}

class _RatesTabState extends ConsumerState<_RatesTab> {
  String? _branch; // null = everyone, a branch id, or kAnyBranch

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = ref.watch(hrPeopleProvider).value ?? const <HrPerson>[];
    final profiles = {
      for (final p
          in ref.watch(payrollProfilesProvider).value ??
              const <PayrollProfile>[])
        p.userId: p,
    };
    final branches = ref.watch(branchesProvider);
    final assigned = ref.watch(assignedBranchesByUserProvider);
    final multi = branches.length >= 2;

    if (people.isEmpty) {
      return const HrEmpty(
        icon: Icons.groups_outlined,
        title: 'No team members',
        message: 'Invite people in Users & Roles first.',
      );
    }

    final filter =
        multi &&
            (_branch == kAnyBranch || branches.any((b) => b.id == _branch))
        ? _branch
        : null;
    final shown = people
        .where((p) => matchesBranchFilter(p.userId, filter, assigned))
        .toList();

    final missing = people.where((p) => !profiles.containsKey(p.userId)).length;
    final done = people.length - missing;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _RatesProgress(done: done, total: people.length),
        if (missing > 0) ...[
          const SizedBox(height: 10),
          _Notice(
            icon: Icons.info_outline_rounded,
            color: Colors.orange.shade800,
            text:
                '$missing ${missing == 1 ? 'person has' : 'people have'} no '
                'pay rate. They get ₱0 in a pay run until you set one.',
          ),
        ],
        if (multi) ...[
          const SizedBox(height: 14),
          BranchFilterChips(
            branches: branches,
            selected: filter,
            onSelect: (v) => setState(() => _branch = v),
          ),
        ],
        const SizedBox(height: 14),
        if (shown.isEmpty)
          const HrEmpty(
            icon: Icons.filter_alt_off_rounded,
            title: 'No one here',
            message: 'Nobody matches this branch.',
          )
        else
          HrCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  HrFadeIn(
                    index: i,
                    child: Builder(
                      builder: (context) {
                        final p = shown[i];
                        final prof = profiles[p.userId];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: HrAvatar(
                            name: p.name,
                            seed: p.userId,
                            radius: 22,
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (prof == null)
                                Text(
                                  'No pay rate set',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Icon(
                                      _payTypeIcons[prof.payType] ??
                                          Icons.payments_outlined,
                                      size: 14,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        kPayTypes[prof.payType] ?? prof.payType,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              if (multi) ...[
                                const SizedBox(height: 6),
                                UserBranchTags(userId: p.userId),
                              ],
                            ],
                          ),
                          trailing: prof == null
                              ? HrTag('Set rate', Colors.orange.shade800)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formatPeso(prof.rate),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _RateDialog(person: p, existing: prof),
                          ),
                        );
                      },
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

/// "3 of 5 have a pay rate" with a progress bar.
class _RatesProgress extends StatelessWidget {
  const _RatesProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final complete = done == total;
    final fraction = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: _heroColors(false),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete
                    ? Icons.check_circle_rounded
                    : Icons.pending_actions_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                complete ? 'Everyone is ready for payroll' : 'Pay rates',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$done of $total have a pay rate',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateDialog extends ConsumerStatefulWidget {
  const _RateDialog({required this.person, this.existing});

  final HrPerson person;
  final PayrollProfile? existing;

  @override
  ConsumerState<_RateDialog> createState() => _RateDialogState();
}

// BUG FIX: this used to be an AlertDialog with a fixed Column, which overflowed
// by a few pixels once the keyboard opened (autofocus on the amount field).
// It is now a Dialog whose body scrolls, so it adapts to any height.
class _RateDialogState extends ConsumerState<_RateDialog> {
  static const _units = {
    'daily': 'per day',
    'hourly': 'per hour',
    'fixed': 'per pay period',
  };
  static const _hints = {
    'daily': 'Paid for each day worked and each paid leave day.',
    'hourly': 'Paid for every hour with a clock-in and clock-out.',
    'fixed': 'The same amount every pay period, whatever the attendance.',
  };

  late String _type = widget.existing?.payType ?? 'daily';
  late final TextEditingController _rate = TextEditingController(
    text: widget.existing == null ? '' : centsToInput(widget.existing!.rate),
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  /// Null when empty or not a valid amount.
  int? get _cents =>
      _rate.text.trim().isEmpty ? null : pesosToCents(_rate.text);

  Future<void> _save() async {
    final cents = _cents;
    if (cents == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(hrServiceProvider)
          .saveProfile(
            businessId: ref.read(selectedBusinessIdProvider),
            userId: widget.person.userId,
            payType: _type,
            rateCents: cents,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = hrError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final existing = widget.existing;
    final cents = _cents;
    final bad = _rate.text.trim().isNotEmpty && cents == null;
    final changed =
        cents != null &&
        (existing == null ||
            cents != existing.rate ||
            _type != existing.payType);
    final canSave = !_busy && changed;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RateHeader(
              name: widget.person.name,
              userId: widget.person.userId,
              isNew: existing == null,
              cents: cents,
              unit: _units[_type] ?? '',
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in kPayTypes.entries) ...[
                      _PayTypeTile(
                        icon: _payTypeIcons[e.key] ?? Icons.payments_outlined,
                        title: e.value,
                        selected: _type == e.key,
                        onTap: _busy
                            ? null
                            : () => setState(() {
                                _type = e.key;
                                _error = null;
                              }),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: _rate,
                      enabled: !_busy,
                      autofocus: existing == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) {
                        if (canSave) _save();
                      },
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                      decoration: InputDecoration(
                        labelText: switch (_type) {
                          'daily' => 'Amount per day',
                          'hourly' => 'Amount per hour',
                          _ => 'Amount per pay period',
                        },
                        prefixText: '₱ ',
                        errorText: bad ? 'Enter a valid amount.' : null,
                        suffixIcon: _rate.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _rate.clear();
                                        _error = null;
                                      }),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Notice(
                      icon: Icons.info_outline_rounded,
                      color: scheme.primary,
                      text: _hints[_type] ?? '',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      _Notice(
                        icon: Icons.error_outline_rounded,
                        color: scheme.error,
                        text: _error!,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
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
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: canSave ? _save : null,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(changed ? 'Save rate' : 'No changes'),
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

/// Gradient header: who the rate is for, and a live preview of the rate.
class _RateHeader extends ConsumerWidget {
  const _RateHeader({
    required this.name,
    required this.userId,
    required this.isNew,
    required this.cents,
    required this.unit,
  });

  final String name;
  final String userId;
  final bool isNew;
  final int? cents;
  final String unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multi = ref.watch(branchesProvider).length >= 2;
    final mine =
        ref.watch(assignedBranchesByUserProvider)[userId] ?? const <Branch>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _heroColors(false),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  hrInitials(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
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
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      isNew ? 'Set pay rate' : 'Update pay rate',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (multi)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    mine.isEmpty
                        ? 'Any branch'
                        : (mine.length == 1
                              ? mine.first.name
                              : '${mine.length} branches'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    cents == null ? '—' : formatPeso(cents!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A selectable pay-type card with an icon and a check when chosen.
class _PayTypeTile extends StatelessWidget {
  const _PayTypeTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 22,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PAY RUNS
// ============================================================================

class _RunsTab extends ConsumerWidget {
  const _RunsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(payrollRunsProvider).value ?? const <PayrollRun>[];
    final drafts = runs.where((r) => r.status == 'draft').toList();
    final finalized = runs.where((r) => r.status != 'draft').toList();
    final paidOut = finalized.fold<int>(0, (s, r) => s + r.totalNet);

    void open(String id) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PayrollRunPage(runId: id)),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final id = await showDialog<String>(
            context: context,
            builder: (_) => const _NewRunDialog(),
          );
          if (id != null && context.mounted) open(id);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New pay run'),
      ),
      body: runs.isEmpty
          ? const HrEmpty(
              icon: Icons.payments_outlined,
              title: 'No pay runs yet',
              message:
                  'Set pay rates first, then create a pay run for a pay '
                  'period. Hours come from Attendance and paid Leave.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _RunsSummary(
                  paidOut: paidOut,
                  finalizedCount: finalized.length,
                  draftCount: drafts.length,
                ),
                if (drafts.isNotEmpty) ...[
                  _SectionTitle('In progress', drafts.length),
                  for (final r in drafts)
                    _RunCard(run: r, onTap: () => open(r.id)),
                ],
                if (finalized.isNotEmpty) ...[
                  _SectionTitle('Finalized', finalized.length),
                  for (final r in finalized)
                    _RunCard(run: r, onTap: () => open(r.id)),
                ],
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.count);

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunsSummary extends StatelessWidget {
  const _RunsSummary({
    required this.paidOut,
    required this.finalizedCount,
    required this.draftCount,
  });

  final int paidOut;
  final int finalizedCount;
  final int draftCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: _heroColors(false),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total paid out',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatPeso(paidOut),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Figure('Finalized runs', '$finalizedCount')),
              const SizedBox(width: 8),
              Expanded(child: _Figure('Drafts', '$draftCount')),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, required this.onTap});

  final PayrollRun run;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final draft = run.status == 'draft';
    final color = draft ? Colors.orange.shade800 : Colors.green.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: HrCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  draft ? Icons.edit_note_rounded : Icons.verified_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _period(run),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    HrTag(draft ? 'Draft' : 'Finalized', color),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatPeso(run.totalNet),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Net pay',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewRunDialog extends ConsumerStatefulWidget {
  const _NewRunDialog();

  @override
  ConsumerState<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends ConsumerState<_NewRunDialog> {
  late DateTime _start;
  late DateTime _end;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Default: the most recent finished half-month.
    final now = DateTime.now();
    if (now.day >= 16) {
      _start = DateTime(now.year, now.month, 1);
      _end = DateTime(now.year, now.month, 15);
    } else {
      final prev = DateTime(now.year, now.month - 1, 1);
      _start = DateTime(prev.year, prev.month, 16);
      _end = DateTime(now.year, now.month, 0);
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(hrServiceProvider)
          .createPayrollRun(
            businessId: ref.read(selectedBusinessIdProvider),
            start: _start,
            end: _end,
            createdBy: ref.read(authenticatedUserIdProvider),
            names: ref.read(hrNamesProvider),
          );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _error = hrError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _end.isBefore(_start);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      icon: const Icon(Icons.payments_outlined),
      title: const Text(
        'New pay run',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Attendance without a clock-out is not counted. Fix those first '
            'in Attendance.',
          ),
          const SizedBox(height: 16),
          _DateTile(
            label: 'From',
            value: fmtDate(_start),
            onTap: _busy
                ? null
                : () async {
                    final d = await pickDate(context, _start);
                    if (d != null) setState(() => _start = dateOnly(d));
                  },
          ),
          const SizedBox(height: 8),
          _DateTile(
            label: 'To',
            value: fmtDate(_end),
            onTap: _busy
                ? null
                : () async {
                    final d = await pickDate(context, _end);
                    if (d != null) setState(() => _end = dateOnly(d));
                  },
          ),
          if (invalid) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              text: 'The end date must be on or after the start date.',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              text: _error!,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || invalid ? null : _create,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Text('Create pay run'),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.event_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// RUN DETAIL
// ============================================================================

class PayrollRunPage extends ConsumerStatefulWidget {
  const PayrollRunPage({super.key, required this.runId});

  final String runId;

  @override
  ConsumerState<PayrollRunPage> createState() => _PayrollRunPageState();
}

class _PayrollRunPageState extends ConsumerState<PayrollRunPage> {
  String? _branch; // null = everyone, a branch id, or kAnyBranch

  Future<void> _finalize() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: const Icon(Icons.lock_outline_rounded),
        title: const Text('Finalize this pay run?'),
        content: const Text(
          'Amounts are locked and the run can\'t be edited or deleted '
          'afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalize'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(hrServiceProvider).finalizeRun(widget.runId);
      if (mounted) hrSnack(context, 'Pay run finalized.');
    } catch (e) {
      if (mounted) hrSnack(context, hrError(e));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const Text('Delete this draft?'),
        content: const Text('You can create it again at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(hrServiceProvider).deleteDraftRun(widget.runId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) hrSnack(context, hrError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runs = ref.watch(payrollRunsProvider).value ?? const <PayrollRun>[];
    final found = runs.where((r) => r.id == widget.runId).firstOrNull;
    final List<PayrollItem> items =
        ref.watch(payrollItemsProvider(widget.runId)).value ??
        const <PayrollItem>[];
    final people = ref.watch(hrPeopleProvider).value ?? const <HrPerson>[];

    if (found == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pay run')),
        body: const Center(child: Text('This pay run no longer exists.')),
      );
    }
    // A final local, so it stays non-null inside the closures below.
    final run = found;
    final draft = run.status == 'draft';

    final gross = items.fold<int>(0, (s, i) => s + i.grossPay);
    final additions = items.fold<int>(0, (s, i) => s + i.additions);
    final deductions = items.fold<int>(0, (s, i) => s + i.deductions);

    // ---- branch breakdown (derived from current assignments) ----
    final branches = ref.watch(branchesProvider);
    final assigned = ref.watch(assignedBranchesByUserProvider);
    final multi = branches.length >= 2;

    String keyOf(PayrollItem i) =>
        primaryBranchId(i.userId, assigned) ?? kAnyBranch;

    final netBy = <String, int>{};
    final countBy = <String, int>{};
    for (final i in items) {
      final k = keyOf(i);
      netBy[k] = (netBy[k] ?? 0) + i.netPay;
      countBy[k] = (countBy[k] ?? 0) + 1;
    }

    final stats = <BranchStat>[
      for (final b in branches)
        BranchStat(
          key: b.id,
          title: b.name,
          icon: branchIconOf(b),
          color: branchColorOf(b),
          value: formatPeso(netBy[b.id] ?? 0),
          caption: _people(countBy[b.id] ?? 0),
        ),
      if ((countBy[kAnyBranch] ?? 0) > 0)
        BranchStat(
          key: kAnyBranch,
          title: 'Any / several',
          icon: Icons.all_inclusive_rounded,
          color: const Color(0xFF64748B),
          value: formatPeso(netBy[kAnyBranch] ?? 0),
          caption: _people(countBy[kAnyBranch] ?? 0),
        ),
    ];

    final filter =
        multi &&
            (_branch == kAnyBranch || branches.any((b) => b.id == _branch))
        ? _branch
        : null;
    final shownItems = filter == null
        ? items
        : items.where((i) => keyOf(i) == filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_period(run)),
        actions: [
          IconButton(
            tooltip: 'Copy summary',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              final text = StringBuffer('Payroll ${_period(run)}\n');
              for (final i in items) {
                text.writeln(
                  '${_displayName(i, people)}: ${formatPeso(i.netPay)}',
                );
              }
              text.writeln('TOTAL: ${formatPeso(run.totalNet)}');
              if (multi && items.isNotEmpty) {
                text.writeln('\nBy branch (current assignments):');
                for (final s in stats) {
                  if ((countBy[s.key] ?? 0) == 0) continue;
                  text.writeln('${s.title}: ${s.value}');
                }
              }
              await Clipboard.setData(ClipboardData(text: text.toString()));
              if (context.mounted) hrSnack(context, 'Summary copied.');
            },
          ),
          if (draft)
            IconButton(
              tooltip: 'Delete draft',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      bottomNavigationBar: draft
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _finalize,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('Finalize pay run'),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _RunHero(
            net: run.totalNet,
            gross: gross,
            additions: additions,
            deductions: deductions,
            draft: draft,
            people: items.length,
          ),
          if (multi && items.isNotEmpty) ...[
            const SizedBox(height: 20),
            BranchStatStrip(
              title: 'Payroll by branch',
              hint: filter == null
                  ? 'Tap a branch to filter payslips'
                  : 'Tap again to clear',
              stats: stats,
              selected: filter,
              onSelect: (k) => setState(() => _branch = k),
            ),
            const SizedBox(height: 12),
            _ShareBar(stats: stats, netBy: netBy),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                'Based on each person\'s current branch assignment.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    filter == null
                        ? 'Payslips'
                        : 'Payslips · ${shownItems.length} of ${items.length}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (filter != null)
                  TextButton(
                    onPressed: () => setState(() => _branch = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          if (shownItems.isEmpty)
            _Notice(
              icon: Icons.info_outline_rounded,
              color: Colors.blueGrey,
              text: items.isEmpty
                  ? 'No payslips in this run.'
                  : 'No payslips for this branch.',
            ),
          for (final i in shownItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  // The sheet looks up live data by id, so it never shows a
                  // stale payslip after an adjustment.
                  builder: (_) => _PayslipSheet(runId: run.id, itemId: i.id),
                ),
                child: HrCard(
                  child: Row(
                    children: [
                      HrAvatar(
                        name: _displayName(i, people),
                        seed: i.userId,
                        radius: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName(i, people),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _basis(i),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (multi) ...[
                              const SizedBox(height: 6),
                              UserBranchTags(userId: i.userId, max: 1),
                            ],
                            if (i.additions > 0 || i.deductions > 0) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (i.additions > 0)
                                    _MiniChip(
                                      '+${formatPeso(i.additions)}',
                                      Colors.green.shade700,
                                    ),
                                  if (i.deductions > 0)
                                    _MiniChip(
                                      '−${formatPeso(i.deductions)}',
                                      theme.colorScheme.error,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatPeso(i.netPay),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
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

/// Thin stacked bar: each branch's share of the positive net pay.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.stats, required this.netBy});

  final List<BranchStat> stats;
  final Map<String, int> netBy;

  @override
  Widget build(BuildContext context) {
    final segments = [
      for (final s in stats)
        if ((netBy[s.key] ?? 0) > 0) (s, netBy[s.key]!),
    ];
    if (segments.isEmpty) return const SizedBox.shrink();
    final total = segments.fold<int>(0, (a, e) => a + e.$2);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final e in segments)
                  Expanded(
                    flex: e.$2,
                    child: Container(
                      margin: const EdgeInsets.only(right: 2),
                      color: e.$1.color,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final e in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: e.$1.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${e.$1.title} ${(e.$2 / total * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// The one memorable element of the run page: total net pay, with the
/// gross / additions / deductions it is made of.
class _RunHero extends StatelessWidget {
  const _RunHero({
    required this.net,
    required this.gross,
    required this.additions,
    required this.deductions,
    required this.draft,
    required this.people,
  });

  final int net;
  final int gross;
  final int additions;
  final int deductions;
  final bool draft;
  final int people;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: _heroColors(false),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total net pay · $people ${people == 1 ? 'person' : 'people'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      draft ? Icons.edit_note_rounded : Icons.lock_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      draft ? 'Draft' : 'Finalized',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(end: net.toDouble()),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatPeso(v.round()),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Figure('Gross', formatPeso(gross))),
              const SizedBox(width: 8),
              Expanded(
                child: _Figure('Additions', '+${formatPeso(additions)}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Figure('Deductions', '−${formatPeso(deductions)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

// ============================================================================
// PAYSLIP SHEET
// ============================================================================

class _PayslipSheet extends ConsumerWidget {
  const _PayslipSheet({required this.runId, required this.itemId});

  final String runId;
  final String itemId;

  Future<void> _adjust(
    BuildContext context,
    PayrollItem item,
    PayrollRun run,
    String name,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AdjustDialog(item: item, run: run, name: name),
    );
    // The sheet stays open and refreshes itself from the live providers.
    if (saved == true && context.mounted) {
      hrSnack(context, 'Adjustments saved.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final run = ref
        .watch(payrollRunsProvider)
        .value
        ?.where((r) => r.id == runId)
        .firstOrNull;
    final item = ref
        .watch(payrollItemsProvider(runId))
        .value
        ?.where((i) => i.id == itemId)
        .firstOrNull;

    if (run == null || item == null) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('This payslip is no longer available.')),
        ),
      );
    }

    final people = ref.watch(hrPeopleProvider).value ?? const <HrPerson>[];
    final name = _displayName(item, people);
    final multi = ref.watch(branchesProvider).length >= 2;

    Widget line(String l, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              color: color,
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                HrAvatar(name: name, seed: item.userId, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _period(run),
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (multi) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: UserBranchTags(userId: item.userId, max: 3),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: _heroColors(item.netPay < 0),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Net pay',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatPeso(item.netPay),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _basis(item),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            line('Gross pay', formatPeso(item.grossPay)),
            line(
              'Additions',
              '+${formatPeso(item.additions)}',
              color: Colors.green.shade700,
            ),
            line(
              'Deductions',
              '−${formatPeso(item.deductions)}',
              color: theme.colorScheme.error,
            ),
            if ((item.note ?? '').isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sticky_note_2_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.note!)),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t =
                          'Payslip — $name\n${_period(run)}\n'
                          '${_basis(item)}\n'
                          'Gross: ${formatPeso(item.grossPay)}\n'
                          'Additions: ${formatPeso(item.additions)}\n'
                          'Deductions: ${formatPeso(item.deductions)}\n'
                          'NET PAY: ${formatPeso(item.netPay)}';
                      await Clipboard.setData(ClipboardData(text: t));
                      if (context.mounted) hrSnack(context, 'Payslip copied.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                if (run.status == 'draft') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _adjust(context, item, run, name),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Adjust'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ADJUST DIALOG
//
// BUG FIX: the old version created its TextEditingControllers in a method,
// awaited showDialog, then disposed them immediately. The dialog's close
// animation was still running, so its TextFields used disposed controllers.
// Here the dialog is its own widget: the controllers are created in
// initState and disposed in dispose(), which Flutter only calls after the
// route is fully gone.
// ============================================================================

class _AdjustDialog extends ConsumerStatefulWidget {
  const _AdjustDialog({
    required this.item,
    required this.run,
    required this.name,
  });

  final PayrollItem item;
  final PayrollRun run;
  final String name;

  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog> {
  static const _quickAmounts = [10000, 50000, 100000]; // cents
  static const _noteTags = [
    'Bonus',
    'Allowance',
    'SSS',
    'PhilHealth',
    'Pag-IBIG',
    'Loan',
    'Cash advance',
  ];

  late final TextEditingController _add;
  late final TextEditingController _ded;
  late final TextEditingController _note;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _add = TextEditingController(
      text: i.additions == 0 ? '' : centsToInput(i.additions),
    );
    _ded = TextEditingController(
      text: i.deductions == 0 ? '' : centsToInput(i.deductions),
    );
    _note = TextEditingController(text: i.note ?? '');
  }

  @override
  void dispose() {
    _add.dispose();
    _ded.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Empty = 0. Null = not a valid amount.
  int? _cents(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : pesosToCents(c.text);

  bool _isBad(TextEditingController c) =>
      c.text.trim().isNotEmpty && _cents(c) == null;

  void _setText(TextEditingController c, String text) {
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _bump(TextEditingController c, int deltaCents) {
    final current = _cents(c) ?? 0;
    setState(() {
      _setText(c, centsToInput(current + deltaCents));
      _error = null;
    });
    HapticFeedback.selectionClick();
  }

  void _tag(String tag) {
    final t = _note.text.trim();
    if (t.toLowerCase().contains(tag.toLowerCase())) return;
    setState(() => _setText(_note, t.isEmpty ? tag : '$t, $tag'));
    HapticFeedback.selectionClick();
  }

  void _clearAll() {
    setState(() {
      _add.clear();
      _ded.clear();
      _note.clear();
      _error = null;
    });
  }

  Future<void> _save(int additions, int deductions) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(hrServiceProvider)
          .updatePayrollItem(
            itemId: widget.item.id,
            additions: additions,
            deductions: deductions,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = hrError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;

    final a = _cents(_add);
    final d = _cents(_ded);
    final valid = a != null && d != null;
    final net = valid ? item.grossPay + a - d : null;
    final negative = net != null && net < 0;
    final changed =
        valid &&
        (a != item.additions ||
            d != item.deductions ||
            _note.text.trim() != (item.note ?? '').trim());
    final anyInput =
        _add.text.isNotEmpty || _ded.text.isNotEmpty || _note.text.isNotEmpty;
    final canSave = !_busy && valid && !negative && changed;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdjustHeader(
              name: widget.name,
              period: _period(widget.run),
              gross: item.grossPay,
              additions: a ?? 0,
              deductions: d ?? 0,
              net: net,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _moneyField(
                      controller: _add,
                      label: 'Additions',
                      hint: 'Bonus, allowance, overtime',
                      icon: Icons.add_rounded,
                      color: Colors.green.shade700,
                      bad: _isBad(_add),
                      action: TextInputAction.next,
                    ),
                    const SizedBox(height: 18),
                    _moneyField(
                      controller: _ded,
                      label: 'Deductions',
                      hint: 'SSS, loan, cash advance',
                      icon: Icons.remove_rounded,
                      color: scheme.error,
                      bad: _isBad(_ded),
                      action: TextInputAction.next,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _note,
                      enabled: !_busy,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => _error = null),
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        prefixIcon: Icon(Icons.sticky_note_2_outlined),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 0,
                      children: [
                        for (final t in _noteTags)
                          ActionChip(
                            label: Text(t),
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy ? null : () => _tag(t),
                          ),
                      ],
                    ),
                    if (negative) ...[
                      const SizedBox(height: 14),
                      _Notice(
                        icon: Icons.error_outline_rounded,
                        color: scheme.error,
                        text:
                            'Deductions are larger than the pay. Lower the '
                            'deductions to continue.',
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _Notice(
                        icon: Icons.error_outline_rounded,
                        color: scheme.error,
                        text: _error!,
                      ),
                    ],
                    if (anyInput)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _busy ? null : _clearAll,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('Clear adjustments'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
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
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: canSave ? () => _save(a, d) : null,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(changed ? 'Save changes' : 'No changes'),
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

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
    required bool bad,
    required TextInputAction action,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: action,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          onChanged: (_) => setState(() => _error = null),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixText: '₱ ',
            errorText: bad ? 'Enter a valid amount.' : null,
            prefixIcon: Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            controller.clear();
                            _error = null;
                          }),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 0,
          children: [
            for (final c in _quickAmounts)
              ActionChip(
                label: Text('+${formatPeso(c)}'),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: color.withValues(alpha: 0.4)),
                labelStyle: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
                onPressed: _busy ? null : () => _bump(controller, c),
              ),
          ],
        ),
      ],
    );
  }
}

/// Gradient header with the live result: net pay and a breakdown that
/// update as the amounts are typed. Turns red when the result is negative.
class _AdjustHeader extends StatelessWidget {
  const _AdjustHeader({
    required this.name,
    required this.period,
    required this.gross,
    required this.additions,
    required this.deductions,
    required this.net,
  });

  final String name;
  final String period;
  final int gross;
  final int additions;
  final int deductions;
  final int? net;

  @override
  Widget build(BuildContext context) {
    final negative = net != null && net! < 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _heroColors(negative),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  hrInitials(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adjust $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      period,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Net pay',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (net == null)
            const Text(
              '—',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            )
          else
            TweenAnimationBuilder<double>(
              tween: Tween(end: net!.toDouble()),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatPeso(v.round()),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Figure('Gross', formatPeso(gross))),
              const SizedBox(width: 8),
              Expanded(
                child: _Figure('Additions', '+${formatPeso(additions)}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Figure('Deductions', '−${formatPeso(deductions)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHARED BITS
// ============================================================================

/// Translucent stat tile for use on gradient surfaces.
class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
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
                fontSize: 13.5,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}