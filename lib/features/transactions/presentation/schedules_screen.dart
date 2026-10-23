// lib/features/people/presentation/schedules_screen.dart
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/people/hr_common.dart';
import 'package:bos_application/features/people/hr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  DateTime _week = weekStartOf(DateTime.now());
  DateTime _sel = dateOnly(DateTime.now());

  void _goWeek(DateTime w) => setState(() {
    _week = w;
    _sel = addDays(w, _sel.weekday - 1);
  });

  Future<void> _copyWeek() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy this week to next week?'),
        content: const Text(
          'Every shift in this week is repeated one week later. Shifts that '
          'already exist next week are skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await ref
          .read(hrServiceProvider)
          .copyWeekForward(
            businessId: ref.read(selectedBusinessIdProvider),
            fromWeekStart: _week,
            createdBy: ref.read(authenticatedUserIdProvider),
          );
      if (mounted) {
        _goWeek(addDays(_week, 7));
        hrSnack(context, n == 0 ? 'Nothing new to copy.' : '$n shifts copied.');
      }
    } catch (e) {
      if (mounted) hrSnack(context, hrError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canManage = ref.watch(canProvider(BosPermission.hrManage));
    final me = ref.watch(authenticatedUserIdProvider);
    final names = ref.watch(hrNamesProvider);
    final roles = ref.watch(hrRolesProvider);
    final all =
        ref.watch(shiftsForWeekProvider(_week)).value ??
        const <ScheduleShift>[];
    final shifts = canManage ? all : all.where((s) => s.userId == me).toList();

    final minutes = shifts.fold<int>(
      0,
      (s, x) => s + (x.endMinutes - x.startMinutes),
    );
    final people = {for (final s in shifts) s.userId}.length;
    final days = {for (final s in shifts) dateOnly(s.shiftDate)}.length;
    final dayShifts = shifts
        .where((s) => dateOnly(s.shiftDate) == _sel)
        .toList();
    final selIsToday = _sel == dateOnly(DateTime.now());

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _ShiftDialog(initialDate: _sel),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add shift'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          HrHero(
            icon: Icons.calendar_month_rounded,
            title: canManage ? 'Team schedule' : 'My schedule',
            subtitle:
                '${DateFormat('MMM d').format(_week)} – '
                '${DateFormat('MMM d, yyyy').format(addDays(_week, 6))}',
            stats: [
              HrStat('${shifts.length}', 'Shifts'),
              HrStat(
                canManage ? '$people' : '$days',
                canManage ? 'People' : 'Days',
              ),
              HrStat(fmtDuration(minutes), 'Scheduled'),
            ],
          ),
          const SizedBox(height: 16),
          HrNavPill(
            label: 'Week of ${DateFormat('MMM d').format(_week)}',
            onPrev: () => _goWeek(addDays(_week, -7)),
            onNext: () => _goWeek(addDays(_week, 7)),
            onTap: () => setState(() {
              _week = weekStartOf(DateTime.now());
              _sel = dateOnly(DateTime.now());
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayChip(
                    day: addDays(_week, i),
                    selected: addDays(_week, i) == _sel,
                    count: shifts
                        .where(
                          (s) => dateOnly(s.shiftDate) == addDays(_week, i),
                        )
                        .length,
                    onTap: () => setState(() => _sel = addDays(_week, i)),
                  ),
                ),
            ],
          ),
          if (canManage)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: shifts.isEmpty ? null : _copyWeek,
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: const Text('Copy week forward'),
              ),
            ),
          const SizedBox(height: 8),
          HrSectionLabel(
            selIsToday ? 'Today · ${fmtShortDate(_sel)}' : fmtShortDate(_sel),
            trailing: dayShifts.isEmpty
                ? null
                : HrTag(
                    '${dayShifts.length} shift${dayShifts.length == 1 ? '' : 's'}',
                    scheme.primary,
                  ),
          ),
          if (dayShifts.isEmpty)
            HrEmpty(
              icon: canManage
                  ? Icons.event_available_outlined
                  : Icons.weekend_outlined,
              title: canManage ? 'Nothing scheduled' : 'Day off',
              message: canManage
                  ? 'Tap "Add shift" to schedule someone on this day.'
                  : 'You have no shifts on this day.',
            )
          else
            for (var i = 0; i < dayShifts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HrFadeIn(
                  index: i,
                  child: _ShiftCard(
                    shift: dayShifts[i],
                    name: names[dayShifts[i].userId] ?? 'Team member',
                    role: roles[dayShifts[i].userId] ?? '',
                    showName: canManage,
                    onDelete: canManage
                        ? () => ref
                              .read(hrServiceProvider)
                              .deleteShift(dayShifts[i].id)
                        : null,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = day == dateOnly(DateTime.now());
    final fg = selected ? scheme.onPrimary : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : (today
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.5)),
              width: today && !selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                DateFormat('EEE').format(day),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: fg.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: count > 0
                      ? (selected ? scheme.onPrimary : scheme.primary)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.name,
    required this.role,
    required this.showName,
    this.onDelete,
  });

  final ScheduleShift shift;
  final String name;
  final String role;
  final bool showName;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hrColorFor(shift.userId);
    final dur = shift.endMinutes - shift.startMinutes;

    return HrCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: color),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fmtMinutesOfDay(shift.startMinutes),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'to',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    fmtMinutesOfDay(shift.endMinutes),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showName)
                      Row(
                        children: [
                          HrAvatar(name: name, seed: shift.userId, radius: 14),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (role.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            HrTag(role, scheme.primary),
                          ],
                        ],
                      ),
                    if (showName) const SizedBox(height: 6),
                    HrTag(fmtDuration(dur), color),
                    if ((shift.note ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        shift.note!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove shift',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftDialog extends ConsumerStatefulWidget {
  const _ShiftDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  ConsumerState<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends ConsumerState<_ShiftDialog> {
  String? _userId;
  late DateTime _date = widget.initialDate;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
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
          .addShift(
            businessId: ref.read(selectedBusinessIdProvider),
            userId: _userId!,
            date: _date,
            startMinutes: _start.hour * 60 + _start.minute,
            endMinutes: _end.hour * 60 + _end.minute,
            note: _note.text,
            createdBy: ref.read(authenticatedUserIdProvider),
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
      title: const Text('Add shift'),
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
                  DropdownMenuItem(
                    value: p.userId,
                    child: Text(
                      p.roleLabel.isEmpty
                          ? p.name
                          : '${p.name} · ${p.roleLabel}',
                    ),
                  ),
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
              label: Text(fmtShortDate(_date)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _start,
                      );
                      if (t != null) setState(() => _start = t);
                    },
                    child: Text('Start ${_start.format(context)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _end,
                      );
                      if (t != null) setState(() => _end = t);
                    },
                    child: Text('End ${_end.format(context)}'),
                  ),
                ),
              ],
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
