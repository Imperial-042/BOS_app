// lib/features/people/presentation/attendance_screen.dart
//
// People -> Attendance, now branch-aware:
//   My time : clock in/out stamped with the branch you work in, a weekly
//             hours chart, and your recent records (with branch tags)
//   Team    : "branch pulse" strip (who is on the clock and how many hours per
//             branch, tap to filter), branch tags on every record, and a
//             branch picker when adding time manually
//
// Branch: clockIn / addManualAttendance take a branchId and save it with the
// record (see HrService), so every record knows where the work happened.

import 'dart:async';

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/branch_people.dart';
import 'package:bos_application/features/people/hr_common.dart';
import 'package:bos_application/features/people/hr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(canProvider(BosPermission.hrManage));
    if (!canManage) return const Scaffold(body: _MyTime());

    return const DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            HrTabBar(tabs: ['My time', 'Team']),
            Expanded(child: TabBarView(children: [_MyTime(), _TeamTime()])),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MY TIME
// ============================================================================

class _MyTime extends ConsumerWidget {
  const _MyTime();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history =
        ref.watch(myAttendanceProvider).value ?? const <AttendanceRecord>[];
    final shifts =
        ref.watch(recentShiftsProvider).value ?? const <ScheduleShift>[];
    final multi = ref.watch(branchesProvider).length >= 2;
    final byId = ref.watch(branchByIdProvider);

    final ws = weekStartOf(DateTime.now());
    final week = history
        .where((r) => !dateOnly(r.workDate).isBefore(ws))
        .toList();
    final weekMin = week.fold<int>(
      0,
      (s, r) => s + workedMinutes(r.clockIn, r.clockOut, r.breakMinutes),
    );
    final perDay = <DateTime, int>{};
    for (final r in week) {
      final d = dateOnly(r.workDate);
      perDay[d] =
          (perDay[d] ?? 0) +
          workedMinutes(r.clockIn, r.clockOut, r.breakMinutes);
    }
    final weekDays = perDay.keys.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _ClockCard(weekMinutes: weekMin, weekDays: weekDays),
        const SizedBox(height: 16),
        _WeekBars(weekStart: ws, minutes: perDay),
        const SizedBox(height: 24),
        const HrSectionLabel('Last 45 days'),
        if (history.isEmpty)
          const HrEmpty(
            icon: Icons.event_available_outlined,
            title: 'No time records yet',
            message: 'Clock in to start recording your attendance.',
          )
        else
          HrCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 74),
                  HrFadeIn(
                    index: i,
                    child: _RecordTile(
                      rec: history[i],
                      lateMinutes: lateMinutesFor(history[i], shifts),
                      branch: multi ? byId[history[i].branchId] : null,
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

class _ClockCard extends ConsumerStatefulWidget {
  const _ClockCard({required this.weekMinutes, required this.weekDays});

  final int weekMinutes;
  final int weekDays;

  @override
  ConsumerState<_ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends ConsumerState<_ClockCard> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _clockIn() async {
    final me = ref.read(authenticatedUserIdProvider);
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(hrServiceProvider)
          .clockIn(
            businessId: ref.read(selectedBusinessIdProvider),
            userId: me,
            branchId: ref.read(selectedBranchIdProvider),
          );
    } catch (e) {
      if (mounted) hrSnack(context, hrError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clockOut(AttendanceRecord rec) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _BreakSheet(),
    );
    if (minutes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(hrServiceProvider).clockOut(rec.id, breakMinutes: minutes);
    } catch (e) {
      if (mounted) hrSnack(context, hrError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(myOpenClockProvider).value;
    final working = open != null;
    final multi = ref.watch(branchesProvider).length >= 2;
    final byId = ref.watch(branchByIdProvider);
    // While on the clock, show the branch the shift belongs to; otherwise the
    // branch this device is working in (where a clock-in will be recorded).
    final branch = working && open.branchId != null
        ? byId[open.branchId]
        : ref.watch(selectedBranchProvider);

    final now = DateTime.now();
    final elapsed = working ? now.difference(open.clockIn) : Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final big = working
        ? '${two(elapsed.inHours)}:${two(elapsed.inMinutes % 60)}:'
              '${two(elapsed.inSeconds % 60)}'
        : fmtTime(now);

    return HrHero(
      icon: working ? Icons.timer_rounded : Icons.schedule_rounded,
      title: working ? 'You are on the clock' : 'Ready to start?',
      subtitle: working ? 'Since ${fmtTime(open.clockIn)}' : fmtShortDate(now),
      colors: working ? const [Color(0xFF047857), Color(0xFF10B981)] : null,
      stats: [
        HrStat(fmtDuration(widget.weekMinutes), 'This week'),
        HrStat('${widget.weekDays}', 'Days worked'),
      ],
      child: Column(
        children: [
          if (multi && branch != null) ...[
            Center(
              child: _WhereChip(
                name: branch.name,
                live: working,
                label: working ? 'Working at' : 'Clocking in at',
              ),
            ),
            const SizedBox(height: 10),
          ],
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                big,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : (working ? () => _clockOut(open) : _clockIn),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: working
                    ? const Color(0xFFB91C1C)
                    : AppColors.primary,
                minimumSize: const Size(64, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: Icon(working ? Icons.logout_rounded : Icons.login_rounded),
              label: Text(
                working ? 'Clock out' : 'Clock in',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass pill on the clock card: where the shift is / will be recorded.
class _WhereChip extends StatelessWidget {
  const _WhereChip({
    required this.name,
    required this.live,
    required this.label,
  });

  final String name;
  final bool live;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            live ? Icons.location_on_rounded : Icons.place_outlined,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven bars, one per day of the current week. 8 hours = a full bar.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.weekStart, required this.minutes});

  final DateTime weekStart;
  final Map<DateTime, int> minutes;

  static String _hours(int m) {
    if (m <= 0) return '';
    final h = m / 60;
    return '${h.toStringAsFixed(m % 60 == 0 ? 0 : 1)}h';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 0; i < 7; i++) addDays(weekStart, i)];
    final total = days.fold<int>(0, (s, d) => s + (minutes[d] ?? 0));

    return HrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'This week',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                fmtDuration(total),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 98,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: _Bar(
                      label: DateFormat('E').format(d).substring(0, 1),
                      hours: _hours(minutes[d] ?? 0),
                      fraction: ((minutes[d] ?? 0) / 480).clamp(0.0, 1.0),
                      isToday: d == today,
                      isFuture: d.isAfter(today),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.hours,
    required this.fraction,
    required this.isToday,
    required this.isFuture,
  });

  final String label;
  final String hours;
  final double fraction;
  final bool isToday;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isToday
        ? AppColors.accent
        : AppColors.primary.withValues(alpha: 0.6);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 14,
          child: Text(
            hours,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: fraction),
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Container(
            width: 18,
            height: 4 + 54 * v,
            decoration: BoxDecoration(
              color: fraction == 0
                  ? scheme.surfaceContainerHigh.withValues(
                      alpha: isFuture ? 0.5 : 1,
                    )
                  : color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
            color: isToday ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BreakSheet extends StatefulWidget {
  const _BreakSheet();

  @override
  State<_BreakSheet> createState() => _BreakSheetState();
}

class _BreakSheetState extends State<_BreakSheet> {
  int _m = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Clock out',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How long was your unpaid break?',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [0, 15, 30, 45, 60, 90])
                  ChoiceChip(
                    label: Text(m == 0 ? 'No break' : '$m min'),
                    selected: _m == m,
                    onSelected: (_) => setState(() => _m = m),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _m),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Clock out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.rec,
    this.name,
    this.role,
    this.lateMinutes,
    this.onDelete,
    this.showBar = false,
    this.branch,
  });

  final AttendanceRecord rec;
  final String? name;
  final String? role;
  final int? lateMinutes;
  final VoidCallback? onDelete;
  final bool showBar;

  /// Shown as a tag under the times (null hides it).
  final Branch? branch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = rec.clockOut == null;
    final mins = workedMinutes(rec.clockIn, rec.clockOut, rec.breakMinutes);
    final range =
        '${fmtTime(rec.clockIn)} – ${open ? 'now' : fmtTime(rec.clockOut!)}';
    final brk = rec.breakMinutes > 0 ? ' · ${rec.breakMinutes}m break' : '';
    final late = (lateMinutes ?? 0) > 0;
    final roleText = (role ?? '').isEmpty ? '' : '$role · ';
    final lateText = late
        ? (lateMinutes! >= 60
              ? '${lateMinutes! ~/ 60}h ${lateMinutes! % 60}m'
              : '${lateMinutes}m')
        : '';
    final b = branch;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          name == null
              ? HrDateBadge(rec.workDate)
              : HrAvatar(name: name!, seed: rec.userId, radius: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name == null
                      ? '${fmtShortDate(rec.workDate)}$brk'
                      : '$roleText$range$brk',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (b != null) ...[
                  const SizedBox(height: 6),
                  BranchTag.branch(b),
                ],
                if (showBar && !open) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: (mins / 480).clamp(0.0, 1.0).toDouble(),
                      backgroundColor: scheme.surfaceContainerHigh,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (open)
                HrTag('Live', Colors.green.shade700)
              else
                Text(
                  fmtDuration(mins),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              if (late) ...[
                const SizedBox(height: 4),
                HrTag('Late $lateText', Colors.red.shade700),
              ],
              if (rec.source == 'manual') ...[
                const SizedBox(height: 4),
                HrTag('Manual', Colors.orange.shade800),
              ],
            ],
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// TEAM
// ============================================================================

class _TeamTime extends ConsumerStatefulWidget {
  const _TeamTime();

  @override
  ConsumerState<_TeamTime> createState() => _TeamTimeState();
}

class _TeamTimeState extends ConsumerState<_TeamTime> {
  DateTime _day = dateOnly(DateTime.now());
  String? _branchId; // null = every branch you can see

  Future<void> _delete(AttendanceRecord rec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this time record?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hrServiceProvider).deleteAttendance(rec.id);
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(hrNamesProvider);
    final roles = ref.watch(hrRolesProvider);
    final shifts = [
      ...(ref.watch(recentShiftsProvider).value ?? const <ScheduleShift>[]),
      ...(ref.watch(shiftsForWeekProvider(weekStartOf(_day))).value ??
          const <ScheduleShift>[]),
    ];
    final openAll =
        ref.watch(openClocksProvider).value ?? const <AttendanceRecord>[];
    final recordsAll =
        ref.watch(attendanceForDayProvider(_day)).value ??
        const <AttendanceRecord>[];

    // ---- branches ----
    final multi = ref.watch(branchesProvider).length >= 2;
    final branches = ref.watch(allowedBranchesProvider);
    final businessId = ref.watch(selectedBusinessIdProvider);
    final byId = ref.watch(branchByIdProvider);
    final mainId = AppDatabase.mainBranchId(businessId);
    final allowedIds = {for (final b in branches) b.id};
    String branchOf(AttendanceRecord r) => r.branchId ?? mainId;

    // What this person is allowed to see (everything for single-branch
    // businesses, or while branches are still loading).
    bool visible(AttendanceRecord r) =>
        !multi || allowedIds.isEmpty || allowedIds.contains(branchOf(r));

    final filter = multi && branches.any((b) => b.id == _branchId)
        ? _branchId
        : null;
    bool inFilter(AttendanceRecord r) =>
        visible(r) && (filter == null || branchOf(r) == filter);

    final visibleRecords = recordsAll.where(visible).toList();
    final visibleOpen = openAll.where(visible).toList();
    final records = recordsAll.where(inFilter).toList();
    final open = openAll.where(inFilter).toList();

    final totalMinutes = records.fold<int>(
      0,
      (s, r) => s + workedMinutes(r.clockIn, r.clockOut, r.breakMinutes),
    );
    final isToday = _day == dateOnly(DateTime.now());

    // ---- branch pulse stats (always across everything visible) ----
    final minsBy = <String, int>{};
    final recBy = <String, int>{};
    final liveBy = <String, int>{};
    for (final r in visibleRecords) {
      final k = branchOf(r);
      minsBy[k] =
          (minsBy[k] ?? 0) +
          workedMinutes(r.clockIn, r.clockOut, r.breakMinutes);
      recBy[k] = (recBy[k] ?? 0) + 1;
    }
    for (final r in visibleOpen) {
      final k = branchOf(r);
      liveBy[k] = (liveBy[k] ?? 0) + 1;
    }
    final stats = [
      for (final b in branches)
        BranchStat(
          key: b.id,
          title: b.name,
          icon: branchIconOf(b),
          color: branchColorOf(b),
          value: fmtDuration(minsBy[b.id] ?? 0),
          caption: '${liveBy[b.id] ?? 0} live · ${recBy[b.id] ?? 0} records',
        ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _ManualEntryDialog(day: _day),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add time'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          HrHero(
            icon: Icons.groups_rounded,
            title: filter == null
                ? 'Team attendance'
                : (byId[filter]?.name ?? 'Team attendance'),
            subtitle: isToday ? 'Today' : fmtShortDate(_day),
            stats: [
              HrStat('${open.length}', 'On the clock'),
              HrStat('${records.length}', 'Records'),
              HrStat(fmtDuration(totalMinutes), 'Total hours'),
            ],
          ),
          const SizedBox(height: 16),
          HrNavPill(
            label: isToday
                ? 'Today · ${fmtShortDate(_day)}'
                : fmtShortDate(_day),
            onPrev: () => setState(() => _day = addDays(_day, -1)),
            onNext: () => setState(() => _day = addDays(_day, 1)),
            onTap: () async {
              final d = await pickDate(context, _day);
              if (d != null) setState(() => _day = dateOnly(d));
            },
          ),
          if (multi && stats.isNotEmpty) ...[
            const SizedBox(height: 20),
            BranchStatStrip(
              title: 'Branch pulse',
              stats: stats,
              selected: filter,
              onSelect: (k) => setState(() => _branchId = k),
            ),
          ],
          const SizedBox(height: 20),
          if (open.isNotEmpty) ...[
            HrSectionLabel('On the clock now (${open.length})'),
            HrCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < open.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 74),
                    _RecordTile(
                      rec: open[i],
                      name: names[open[i].userId] ?? 'Team member',
                      role: roles[open[i].userId],
                      lateMinutes: lateMinutesFor(open[i], shifts),
                      branch: multi ? byId[branchOf(open[i])] : null,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          HrSectionLabel(
            records.isEmpty
                ? 'Time records'
                : '${records.length} record${records.length == 1 ? '' : 's'}',
          ),
          if (records.isEmpty)
            HrEmpty(
              icon: Icons.event_busy_outlined,
              title: 'No time records',
              message: filter == null
                  ? 'Nobody clocked in on this day.'
                  : 'Nobody clocked in at this branch on this day.',
            )
          else
            HrCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < records.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 74),
                    HrFadeIn(
                      index: i,
                      child: _RecordTile(
                        rec: records[i],
                        name: names[records[i].userId] ?? 'Team member',
                        role: roles[records[i].userId],
                        lateMinutes: lateMinutesFor(records[i], shifts),
                        showBar: true,
                        branch: multi ? byId[branchOf(records[i])] : null,
                        onDelete: () => _delete(records[i]),
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

// ============================================================================
// MANUAL ENTRY
// ============================================================================

class _ManualEntryDialog extends ConsumerStatefulWidget {
  const _ManualEntryDialog({required this.day});

  final DateTime day;

  @override
  ConsumerState<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends ConsumerState<_ManualEntryDialog> {
  String? _userId;
  String? _branchId;
  late DateTime _date = widget.day;
  TimeOfDay _in = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _out = const TimeOfDay(hour: 17, minute: 0);
  final _break = TextEditingController(text: '60');
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _branchId = ref.read(selectedBranchIdProvider);
  }

  @override
  void dispose() {
    _break.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_userId == null) {
      setState(() => _error = 'Choose a person.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(hrServiceProvider)
          .addManualAttendance(
            businessId: ref.read(selectedBusinessIdProvider),
            userId: _userId!,
            date: _date,
            inMinutes: _in.hour * 60 + _in.minute,
            outMinutes: _out.hour * 60 + _out.minute,
            breakMinutes: int.tryParse(_break.text.trim()) ?? 0,
            note: _note.text,
            enteredBy: ref.read(authenticatedUserIdProvider),
            branchId: _branchId ?? ref.read(selectedBranchIdProvider),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = hrError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(hrPeopleProvider).value ?? const <HrPerson>[];
    final multi = ref.watch(branchesProvider).length >= 2;
    final branches = ref.watch(allowedBranchesProvider);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      icon: const Icon(Icons.more_time_rounded),
      title: const Text(
        'Add time record',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _userId,
              decoration: const InputDecoration(labelText: 'Person'),
              items: [
                for (final p in people)
                  DropdownMenuItem(value: p.userId, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _userId = v),
            ),
            if (multi && branches.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Branch',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in branches)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(
                        branchIconOf(b),
                        size: 16,
                        color: branchColorOf(b),
                      ),
                      selectedColor: branchColorOf(b).withValues(alpha: 0.16),
                      label: Text(b.name),
                      selected: _branchId == b.id,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _branchId = b.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await pickDate(context, _date);
                if (d != null) setState(() => _date = dateOnly(d));
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(fmtDate(_date)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _in,
                      );
                      if (t != null) setState(() => _in = t);
                    },
                    child: Text('In ${_in.format(context)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _out,
                      );
                      if (t != null) setState(() => _out = t);
                    },
                    child: Text('Out ${_out.format(context)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _break,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Unpaid break (minutes)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}