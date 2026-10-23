// lib/features/people/presentation/attendance_screen.dart
import 'dart:async';

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/people/hr_common.dart';
import 'package:bos_application/features/people/hr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final ws = weekStartOf(DateTime.now());
    final week = history.where((r) => !dateOnly(r.workDate).isBefore(ws));
    final weekMin = week.fold<int>(
      0,
      (s, r) => s + workedMinutes(r.clockIn, r.clockOut, r.breakMinutes),
    );
    final weekDays = {for (final r in week) dateOnly(r.workDate)}.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _ClockCard(weekMinutes: weekMin, weekDays: weekDays),
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
  });

  final AttendanceRecord rec;
  final String? name;
  final String? role;
  final int? lateMinutes;
  final VoidCallback? onDelete;
  final bool showBar;

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
    final open =
        ref.watch(openClocksProvider).value ?? const <AttendanceRecord>[];
    final records =
        ref.watch(attendanceForDayProvider(_day)).value ??
        const <AttendanceRecord>[];
    final totalMinutes = records.fold<int>(
      0,
      (s, r) => s + workedMinutes(r.clockIn, r.clockOut, r.breakMinutes),
    );
    final isToday = _day == dateOnly(DateTime.now());

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
            title: 'Team attendance',
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
            const HrEmpty(
              icon: Icons.event_busy_outlined,
              title: 'No time records',
              message: 'Nobody clocked in on this day.',
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
// TEAM
// ============================================================================

class _ManualEntryDialog extends ConsumerStatefulWidget {
  const _ManualEntryDialog({required this.day});

  final DateTime day;

  @override
  ConsumerState<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends ConsumerState<_ManualEntryDialog> {
  String? _userId;
  late DateTime _date = widget.day;
  TimeOfDay _in = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _out = const TimeOfDay(hour: 17, minute: 0);
  final _break = TextEditingController(text: '60');
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

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

    return AlertDialog(
      title: const Text('Add time record'),
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
            const SizedBox(height: 10),
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
                  color: Theme.of(context).colorScheme.error,
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
