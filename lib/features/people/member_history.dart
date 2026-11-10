// lib/features/people/member_history.dart
//
// Attendance / Pay / Leave history for one employee. Drop it into any
// scroll view (the member detail sheet uses it).

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/people/hr_common.dart';
import 'package:bos_application/features/people/hr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Change this (or swap _money for your app's formatter).
const _currency = '₱';

String _money(int cents) =>
    '$_currency${NumberFormat('#,##0.00').format(cents / 100)}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _num(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

const _green = Color(0xFF159B67);
const _orange = Color(0xFFF59E0B);
const _red = Color(0xFFDC2626);
const _slate = Color(0xFF64748B);

enum MemberHistoryKind {
  attendance('Attendance', Icons.schedule_rounded),
  pay('Pay', Icons.payments_rounded),
  leave('Leave', Icons.beach_access_rounded);

  const MemberHistoryKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class MemberHistory extends ConsumerStatefulWidget {
  const MemberHistory({super.key, required this.userId, required this.kinds});

  final String userId;

  /// Which tabs this viewer may see.
  final List<MemberHistoryKind> kinds;

  @override
  ConsumerState<MemberHistory> createState() => _MemberHistoryState();
}

class _MemberHistoryState extends ConsumerState<MemberHistory> {
  late MemberHistoryKind _kind = widget.kinds.first;

  @override
  Widget build(BuildContext context) {
    if (widget.kinds.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = widget.kinds.contains(_kind) ? _kind : widget.kinds.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'HISTORY',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        _Switch(
          kinds: widget.kinds,
          selected: kind,
          onChanged: (k) {
            HapticFeedback.selectionClick();
            setState(() => _kind = k);
          },
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(kind),
            child: switch (kind) {
              MemberHistoryKind.attendance => _AttendanceSection(
                userId: widget.userId,
              ),
              MemberHistoryKind.pay => _PaySection(userId: widget.userId),
              MemberHistoryKind.leave => _LeaveSection(userId: widget.userId),
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TAB SWITCH
// ============================================================

class _Switch extends StatelessWidget {
  const _Switch({
    required this.kinds,
    required this.selected,
    required this.onChanged,
  });

  final List<MemberHistoryKind> kinds;
  final MemberHistoryKind selected;
  final ValueChanged<MemberHistoryKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final k in kinds)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: k == selected ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: k == selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        k.icon,
                        size: 17,
                        color: k == selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            k.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: k == selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: k == selected
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
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

// ============================================================
// SHARED PIECES
// ============================================================

class _StatRow extends StatelessWidget {
  const _StatRow(this.stats);

  final List<(String, String, Color)> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: stats[i].$3.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      stats[i].$1,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: stats[i].$3,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Text(
                    stats[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );
}

/// A rounded card holding rows separated by hairlines.
class _Rows extends StatelessWidget {
  const _Rows(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.label, this.trailing);

  final String label;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            trailing,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Shows the first [limit] rows, then a "Show all" button.
class _Capped extends StatefulWidget {
  const _Capped({
    required this.total,
    required this.builder,
    this.limit = 8,
  });

  final int total;
  final int limit;
  final Widget Function(int count) builder;

  @override
  State<_Capped> createState() => _CappedState();
}

class _CappedState extends State<_Capped> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final more = widget.total > widget.limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.builder(_all ? widget.total : widget.limit),
        if (more)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(
              _all ? 'Show less' : 'Show all ${widget.total}',
            ),
          ),
      ],
    );
  }
}

// ============================================================
// ATTENDANCE
// ============================================================

class _AttendanceSection extends ConsumerWidget {
  const _AttendanceSection({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records =
        ref.watch(employeeAttendanceProvider(userId)).value ??
        const <AttendanceRecord>[];
    final scheme = Theme.of(context).colorScheme;

    if (records.isEmpty) {
      return const _Empty(
        Icons.event_busy_outlined,
        'No attendance recorded yet.',
      );
    }

    int mins(AttendanceRecord r) =>
        workedMinutes(r.clockIn, r.clockOut, r.breakMinutes);
    final now = DateTime.now();
    final total = records.fold<int>(0, (s, r) => s + mins(r));
    final month = records
        .where((r) => r.clockIn.year == now.year && r.clockIn.month == now.month)
        .fold<int>(0, (s, r) => s + mins(r));
    final days = {
      for (final r in records) DateTime(r.clockIn.year, r.clockIn.month, r.clockIn.day),
    }.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow([
          ('$days', 'Days worked', scheme.primary),
          (fmtDuration(month), 'This month', _green),
          (fmtDuration(total), 'All time', _slate),
        ]),
        const SizedBox(height: 12),
        _Capped(
          total: records.length,
          builder: (count) {
            final shown = records.take(count).toList();
            final byMonth = <String, List<AttendanceRecord>>{};
            for (final r in shown) {
              byMonth
                  .putIfAbsent(DateFormat('MMMM yyyy').format(r.clockIn), () => [])
                  .add(r);
            }
            return _Rows([
              for (final e in byMonth.entries) ...[
                _MonthHeader(
                  e.key,
                  fmtDuration(e.value.fold<int>(0, (s, r) => s + mins(r))),
                ),
                for (final r in e.value) _AttendanceRow(rec: r),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.rec});

  final AttendanceRecord rec;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = rec.clockOut == null;
    final mins = workedMinutes(rec.clockIn, rec.clockOut, rec.breakMinutes);
    final out = rec.clockOut;
    final overnight = out != null && !_sameDay(rec.clockIn, out);

    final sub = [
      DateFormat('EEE, MMM d').format(rec.clockIn),
      if (overnight) 'ends ${DateFormat('MMM d').format(out)}',
      if (rec.breakMinutes > 0) '${rec.breakMinutes}m break',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('MMM').format(rec.clockIn).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  '${rec.clockIn.day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtTime(rec.clockIn)}  →  '
                  '${open ? 'now' : fmtTime(out!)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (open)
                const _Pill('Live', _green)
              else
                Text(
                  fmtDuration(mins),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              if (rec.source == 'manual') ...[
                const SizedBox(height: 4),
                const _Pill('Manual', _orange),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PAY
// ============================================================

class _PaySection extends ConsumerWidget {
  const _PaySection({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(employeePayHistoryProvider(userId)).value ??
        const <EmployeePayEntry>[];
    final scheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) {
      return const _Empty(
        Icons.payments_outlined,
        'No pay runs include this person yet.',
      );
    }

    final paid = entries.where((e) => e.run.status == 'finalized').toList();
    final totalPaid = paid.fold<int>(0, (s, e) => s + e.item.netPay);
    final yearPaid = paid
        .where((e) => e.run.periodEnd.year == DateTime.now().year)
        .fold<int>(0, (s, e) => s + e.item.netPay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow([
          (
            paid.isEmpty ? '—' : _money(paid.first.item.netPay),
            'Last pay',
            scheme.primary,
          ),
          (_money(yearPaid), 'This year', _green),
          (_money(totalPaid), 'All time', _slate),
        ]),
        const SizedBox(height: 12),
        _Capped(
          limit: 6,
          total: entries.length,
          builder: (count) =>
              _Rows([for (final e in entries.take(count)) _PayRow(entry: e)]),
        ),
      ],
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({required this.entry});

  final EmployeePayEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = entry.item;
    final r = entry.run;
    final final_ = r.status == 'finalized';
    final period =
        '${DateFormat('MMM d').format(r.periodStart)} – '
        '${DateFormat('MMM d, yyyy').format(r.periodEnd)}';

    final detail = [
      if (i.payType == 'hourly') '${_num(i.hoursWorked)} h',
      if (i.payType != 'fixed') '${_num(i.daysWorked)} days',
      if (i.paidLeaveDays > 0) '${_num(i.paidLeaveDays)} paid leave',
    ].join(' · ');

    final lines = <(String, int, Color?)>[
      ('Gross pay', i.grossPay, null),
      if (i.additions > 0) ('Additions', i.additions, _green),
      if (i.deductions > 0) ('Deductions', -i.deductions, _red),
    ];

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                period,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              _money(i.netPay),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              _Pill(final_ ? 'Paid' : 'Draft', final_ ? _green : _orange),
              if (detail.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.$1,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    l.$2 < 0 ? '−${_money(-l.$2)}' : _money(l.$2),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: l.$3,
                    ),
                  ),
                ],
              ),
            ),
          if ((i.note ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  i.note!,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
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
// LEAVE
// ============================================================

Color _leaveColor(String status) => switch (status) {
  'approved' => _green,
  'pending' => _orange,
  'rejected' => _red,
  _ => _slate,
};

IconData _leaveIcon(String status) => switch (status) {
  'approved' => Icons.check_circle_rounded,
  'pending' => Icons.hourglass_top_rounded,
  'rejected' => Icons.cancel_rounded,
  _ => Icons.remove_circle_rounded,
};

class _LeaveSection extends ConsumerWidget {
  const _LeaveSection({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaves =
        ref.watch(employeeLeaveProvider(userId)).value ??
        const <LeaveRequest>[];
    final scheme = Theme.of(context).colorScheme;

    if (leaves.isEmpty) {
      return const _Empty(
        Icons.beach_access_outlined,
        'No leave requests yet.',
      );
    }

    final year = DateTime.now().year;
    final pending = leaves.where((l) => l.status == 'pending').length;
    final approvedDays = leaves
        .where((l) => l.status == 'approved' && l.startDate.year == year)
        .fold<double>(0, (s, l) => s + l.days);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow([
          ('$pending', 'Pending', _orange),
          (_num(approvedDays), 'Days taken $year', _green),
          ('${leaves.length}', 'Requests', scheme.primary),
        ]),
        const SizedBox(height: 12),
        _Capped(
          limit: 6,
          total: leaves.length,
          builder: (count) =>
              _Rows([for (final l in leaves.take(count)) _LeaveRow(leave: l)]),
        ),
      ],
    );
  }
}

class _LeaveRow extends StatelessWidget {
  const _LeaveRow({required this.leave});

  final LeaveRequest leave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _leaveColor(leave.status);
    final same = _sameDay(leave.startDate, leave.endDate);
    final range = same
        ? DateFormat('EEE, MMM d, yyyy').format(leave.startDate)
        : '${DateFormat('MMM d').format(leave.startDate)} – '
              '${DateFormat('MMM d, yyyy').format(leave.endDate)}';
    final type = leave.leaveType.isEmpty
        ? 'Leave'
        : leave.leaveType[0].toUpperCase() + leave.leaveType.substring(1);
    final status =
        leave.status[0].toUpperCase() + leave.status.substring(1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_leaveIcon(leave.status), size: 20, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$type · ${_num(leave.days)} day${leave.days == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  range,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if ((leave.reason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    leave.reason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Pill(status, c),
        ],
      ),
    );
  }
}