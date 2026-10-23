// lib/features/people/presentation/leave_screen.dart
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/people/hr_common.dart';
import 'package:bos_application/features/people/hr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Map<String, String> kLeaveTypes = {
  'vacation': 'Vacation',
  'sick': 'Sick',
  'emergency': 'Emergency',
  'unpaid': 'Unpaid',
  'other': 'Other',
};

const Map<String, IconData> kLeaveIcons = {
  'vacation': Icons.beach_access_rounded,
  'sick': Icons.local_hospital_rounded,
  'emergency': Icons.warning_amber_rounded,
  'unpaid': Icons.money_off_rounded,
  'other': Icons.event_note_rounded,
};

Color _typeColor(String t) => switch (t) {
  'vacation' => const Color(0xFF0EA5E9),
  'sick' => const Color(0xFFEF4444),
  'emergency' => const Color(0xFFF59E0B),
  'unpaid' => const Color(0xFF64748B),
  _ => const Color(0xFF8B5CF6),
};

Color _statusColor(String s) => switch (s) {
  'approved' => Colors.green.shade700,
  'rejected' => Colors.red.shade700,
  'cancelled' => Colors.grey.shade600,
  _ => Colors.orange.shade800,
};

String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String _range(LeaveRequest r) {
  final same = dateOnly(r.startDate) == dateOnly(r.endDate);
  return same
      ? '${fmtDate(r.startDate)} · 1 day'
      : '${fmtDate(r.startDate)} – ${fmtDate(r.endDate)} · ${_n(r.days)} days';
}

class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(canProvider(BosPermission.hrManage));
    if (!canManage) return const Scaffold(body: _MyLeave());

    final pending =
        (ref.watch(leaveRequestsProvider).value ?? const <LeaveRequest>[])
            .where((r) => r.status == 'pending')
            .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            HrTabBar(
              tabs: [
                'My leave',
                pending > 0 ? 'Approvals ($pending)' : 'Approvals',
              ],
            ),
            const Expanded(
              child: TabBarView(children: [_MyLeave(), _Approvals()]),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MY LEAVE
// ============================================================================

class _MyLeave extends ConsumerWidget {
  const _MyLeave();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authenticatedUserIdProvider);
    final mine =
        (ref.watch(leaveRequestsProvider).value ?? const <LeaveRequest>[])
            .where((r) => r.userId == me)
            .toList();

    final year = DateTime.now().year;
    final used = <String, double>{};
    for (final r in mine.where(
      (r) => r.status == 'approved' && r.startDate.year == year,
    )) {
      used[r.leaveType] = (used[r.leaveType] ?? 0) + r.days;
    }
    final usedTotal = used.values.fold<double>(0, (a, b) => a + b);
    final pending = mine.where((r) => r.status == 'pending').length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _RequestDialog(),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Request leave'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          HrHero(
            icon: Icons.beach_access_rounded,
            title: 'Time off',
            subtitle: '$year',
            colors: const [Color(0xFF0369A1), Color(0xFF38BDF8)],
            stats: [
              HrStat(_n(usedTotal), 'Days taken'),
              HrStat('$pending', 'Pending'),
              HrStat('${mine.length}', 'Requests'),
            ],
          ),
          if (used.isNotEmpty) ...[
            const SizedBox(height: 20),
            const HrSectionLabel('Approved this year'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in used.entries)
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                    decoration: BoxDecoration(
                      color: _typeColor(e.key).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          kLeaveIcons[e.key],
                          size: 16,
                          color: _typeColor(e.key),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${kLeaveTypes[e.key] ?? e.key} · ${_n(e.value)} d',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: _typeColor(e.key),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const HrSectionLabel('My requests'),
          if (mine.isEmpty)
            const SizedBox(
              height: 240,
              child: HrEmpty(
                icon: Icons.beach_access_outlined,
                title: 'No leave requests',
                message: 'Tap "Request leave" to ask for time off.',
              ),
            )
          else
            for (var i = 0; i < mine.length; i++)
              HrFadeIn(
                index: i,
                child: _LeaveCard(req: mine[i], showCancel: true),
              ),
        ],
      ),
    );
  }
}

class _LeaveCard extends ConsumerWidget {
  const _LeaveCard({
    super.key,
    required this.req,
    this.name,
    this.showCancel = false,
    this.actions,
  });

  final LeaveRequest req;
  final String? name;
  final bool showCancel;
  final Widget? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tc = _typeColor(req.leaveType);
    final sc = _statusColor(req.status);
    final typeLabel = kLeaveTypes[req.leaveType] ?? req.leaveType;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                name != null
                    ? HrAvatar(name: name!, seed: req.userId, radius: 22)
                    : Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: tc.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          kLeaveIcons[req.leaveType] ??
                              Icons.event_note_rounded,
                          color: tc,
                        ),
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? typeLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (name != null) ...[
                            Icon(
                              kLeaveIcons[req.leaveType],
                              size: 14,
                              color: tc,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              typeLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: tc,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                HrTag(
                  req.status[0].toUpperCase() + req.status.substring(1),
                  sc,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.date_range_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _range(req),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if ((req.reason ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  req.reason!,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            if ((req.decisionNote ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Manager note: ${req.decisionNote}',
                  style: TextStyle(color: sc, fontWeight: FontWeight.w700),
                ),
              ),
            if (showCancel && req.status == 'pending')
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(hrServiceProvider).cancelLeave(req.id);
                    } catch (e) {
                      if (context.mounted) hrSnack(context, hrError(e));
                    }
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Cancel request'),
                ),
              ),
            if (actions != null) ...[const SizedBox(height: 10), actions!],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// APPROVALS (managers)
// ============================================================================

class _Approvals extends ConsumerWidget {
  const _Approvals();

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    LeaveRequest r,
    bool approve,
  ) async {
    // Grab everything we need BEFORE any await.
    final me = ref.read(authenticatedUserIdProvider);
    final service = ref.read(hrServiceProvider);
    final allowSelf = ref.read(authorizationServiceProvider).isOwner;
    if (me == null) return;

    String? note;
    if (!approve) {
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => const _RejectReasonDialog(),
      );
      if (reason == null) return; // cancelled or dismissed
      note = reason.trim().isEmpty ? null : reason.trim();
    }

    try {
      await service.decideLeave(
        requestId: r.id,
        approve: approve,
        deciderId: me,
        allowSelf: allowSelf,
        note: note,
      );
    } catch (e) {
      if (context.mounted) hrSnack(context, hrError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(hrNamesProvider);
    final all =
        ref.watch(leaveRequestsProvider).value ?? const <LeaveRequest>[];
    final pending = all.where((r) => r.status == 'pending').toList();
    final history = all.where((r) => r.status != 'pending').take(30).toList();
    final approved = all.where((r) => r.status == 'approved').length;
    final rejected = all.where((r) => r.status == 'rejected').length;

    if (all.isEmpty) {
      return const HrEmpty(
        icon: Icons.inbox_outlined,
        title: 'No leave requests',
        message: 'Requests from your team will show up here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        HrHero(
          icon: Icons.fact_check_rounded,
          title: 'Leave approvals',
          subtitle: pending.isEmpty
              ? 'All caught up'
              : '${pending.length} waiting for you',
          colors: pending.isEmpty
              ? null
              : const [Color(0xFFC2410C), Color(0xFFF59E0B)],
          stats: [
            HrStat('${pending.length}', 'Pending'),
            HrStat('$approved', 'Approved'),
            HrStat('$rejected', 'Rejected'),
          ],
        ),
        const SizedBox(height: 20),
        if (pending.isNotEmpty) ...[
          const HrSectionLabel('Needs a decision'),
          for (var i = 0; i < pending.length; i++)
            HrFadeIn(
              key: ValueKey(pending[i].id),
              index: i,
              child: _LeaveCard(
                req: pending[i],
                name: names[pending[i].userId] ?? 'Team member',
                actions: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _decide(context, ref, pending[i], false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _decide(context, ref, pending[i], true),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          const HrSectionLabel('Recent decisions'),
          for (final r in history)
            _LeaveCard(
              key: ValueKey(r.id),
              req: r,
              name: names[r.userId] ?? 'Team member',
            ),
        ],
      ],
    );
  }
}

class _RequestDialog extends ConsumerStatefulWidget {
  const _RequestDialog();

  @override
  ConsumerState<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends ConsumerState<_RequestDialog> {
  String _type = 'vacation';
  DateTime _start = dateOnly(DateTime.now());
  DateTime _end = dateOnly(DateTime.now());
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final me = ref.read(authenticatedUserIdProvider);
    if (me == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(hrServiceProvider)
          .requestLeave(
            businessId: ref.read(selectedBusinessIdProvider),
            userId: me,
            leaveType: _type,
            start: _start,
            end: _end,
            reason: _reason.text,
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
    return AlertDialog(
      title: const Text('Request leave'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final e in kLeaveTypes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickDate(
                        context,
                        _start,
                        first: DateTime.now().subtract(
                          const Duration(days: 30),
                        ),
                      );
                      if (d != null) {
                        setState(() {
                          _start = dateOnly(d);
                          if (_end.isBefore(_start)) _end = _start;
                        });
                      }
                    },
                    child: Text('From ${fmtDate(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickDate(context, _end, first: _start);
                      if (d != null) setState(() => _end = dateOnly(d));
                    },
                    child: Text('To ${fmtDate(_end)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
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
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject this request?'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Reason (optional)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
