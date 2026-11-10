// lib/features/people/hr_providers.dart
//
// People roster, HR service (all writes + validation) and stream providers.

import 'dart:async';

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/features/people/hr_common.dart';
import 'package:bos_application/features/branch_people.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

bool _visibleEmployee(Ref ref, String employeeId) {
  return employeeVisibleToViewer(
    employeeId: employeeId,
    viewerId: ref.watch(authenticatedUserIdProvider),
    ownerId: ref.watch(currentBusinessProvider).value?.ownerUserId,
    assigned: ref.watch(assignedBranchesByUserProvider),
  );
}

// ============================================================================
// PEOPLE
// ============================================================================

class HrPerson {
  const HrPerson({
    required this.userId,
    required this.name,
    required this.roleLabel,
  });

  final String userId;
  final String name;
  final String roleLabel;
}

/// Keeps member names and roles fresh: once now, then every 30 seconds while
/// a people screen is using it. Updates land in the local users table, and the
/// roster stream below refreshes on its own when that table changes.
final hrRosterSyncProvider = Provider<void>((ref) {
  if (!ref.watch(supabaseAvailableProvider)) return;
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.read(databaseProvider);
  final client = ref.read(supabaseClientProvider);
  var busy = false;

  Future<void> run() async {
    if (busy) return;
    busy = true;
    try {
      await syncBusinessUsers(db, client, businessId: businessId);
    } catch (_) {
      // Offline: keep what is stored locally.
    } finally {
      busy = false;
    }
  }

  unawaited(run());
  final timer = Timer.periodic(const Duration(seconds: 30), (_) => run());
  ref.onDispose(timer.cancel);
});

/// Active members of the selected business.
final hrPeopleProvider = StreamProvider<List<HrPerson>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final viewerId = ref.watch(authenticatedUserIdProvider);
  final ownerId = ref.watch(currentBusinessProvider).value?.ownerUserId;
  final assigned = ref.watch(assignedBranchesByUserProvider);
  ref.watch(hrRosterSyncProvider); // loads other members' names once
  final labels =
      ref.watch(roleLabelsProvider).value ?? const <String, String>{};

  final query =
      db.select(db.businessMembers).join([
        leftOuterJoin(
          db.users,
          db.users.id.equalsExp(db.businessMembers.userId),
        ),
      ])..where(
        db.businessMembers.businessId.equals(businessId) &
            db.businessMembers.status.equals('active'),
      );

  return query.watch().map((rows) {
    final list = rows
        .map((row) {
          final m = row.readTable(db.businessMembers);
          final u = row.readTableOrNull(db.users);
          final display = (u?.displayName ?? '').trim();
          final email = (u?.email ?? '').trim();
          final name = display.isNotEmpty
              ? display
              : (email.isNotEmpty ? email.split('@').first : 'Team member');
          return HrPerson(
            userId: m.userId,
            name: name,
            roleLabel: roleLabelFor(labels, m.role),
          );
        })
        .where((person) {
          return employeeVisibleToViewer(
            employeeId: person.userId,
            viewerId: viewerId,
            ownerId: ownerId,
            assigned: assigned,
          );
        })
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });
});

final hrNamesProvider = Provider<Map<String, String>>((ref) {
  final people = ref.watch(hrPeopleProvider).value ?? const <HrPerson>[];
  return {for (final p in people) p.userId: p.name};
});

final hrRolesProvider = Provider<Map<String, String>>((ref) {
  final people = ref.watch(hrPeopleProvider).value ?? const <HrPerson>[];
  return {for (final p in people) p.userId: p.roleLabel};
});

// ============================================================================
// SERVICE
// ============================================================================

class HrService {
  HrService(this.db);

  final AppDatabase db;

  // ---------------- attendance ----------------

  Future<void> clockIn({
    required String businessId,
    required String userId,
    String? branchId, // NEW
  }) async {
    final open =
        await (db.select(db.attendanceRecords)..where(
              (a) =>
                  a.businessId.equals(businessId) &
                  a.userId.equals(userId) &
                  a.clockOut.isNull(),
            ))
            .get();
    if (open.isNotEmpty) throw StateError('You are already clocked in.');

    final now = DateTime.now();
    await db
        .into(db.attendanceRecords)
        .insert(
          AttendanceRecordsCompanion.insert(
            id: _uuid.v4(),
            businessId: businessId,
            userId: userId,
            workDate: dateOnly(now),
            clockIn: now,
            branchId: Value(branchId), // NEW
            createdBy: Value(userId),
          ),
        );
  }

  Future<void> clockOut(String recordId, {int breakMinutes = 0}) async {
    final rec = await (db.select(
      db.attendanceRecords,
    )..where((a) => a.id.equals(recordId))).getSingleOrNull();
    if (rec == null || rec.clockOut != null) {
      throw StateError('This shift is already closed.');
    }
    final now = DateTime.now();
    if (breakMinutes < 0 ||
        breakMinutes > now.difference(rec.clockIn).inMinutes) {
      throw StateError('The break is longer than the time worked.');
    }
    await (db.update(
      db.attendanceRecords,
    )..where((a) => a.id.equals(recordId))).write(
      AttendanceRecordsCompanion(
        clockOut: Value(now),
        breakMinutes: Value(breakMinutes),
      ),
    );
  }

  Future<void> addManualAttendance({
    required String businessId,
    required String userId,
    required DateTime date,
    required int inMinutes,
    required int outMinutes,
    required int breakMinutes,
    String? note,
    String? enteredBy,
    String? branchId, // NEW
  }) async {
    if (outMinutes <= inMinutes) {
      throw StateError('The time out must be after the time in.');
    }
    if (breakMinutes < 0 || breakMinutes >= outMinutes - inMinutes) {
      throw StateError('The break must be shorter than the shift.');
    }
    final d = dateOnly(date);
    await db
        .into(db.attendanceRecords)
        .insert(
          AttendanceRecordsCompanion.insert(
            id: _uuid.v4(),
            businessId: businessId,
            userId: userId,
            workDate: d,
            clockIn: DateTime(
              d.year,
              d.month,
              d.day,
              inMinutes ~/ 60,
              inMinutes % 60,
            ),
            clockOut: Value(
              DateTime(
                d.year,
                d.month,
                d.day,
                outMinutes ~/ 60,
                outMinutes % 60,
              ),
            ),
            breakMinutes: Value(breakMinutes),
            source: const Value('manual'),
            note: Value((note ?? '').trim().isEmpty ? null : note!.trim()),
            branchId: Value(branchId),
            createdBy: Value(enteredBy),
          ),
        );
  }

  Future<void> deleteAttendance(String id) =>
      (db.delete(db.attendanceRecords)..where((a) => a.id.equals(id))).go();

  // ---------------- schedules ----------------

  Future<void> addShift({
    required String businessId,
    required String userId,
    required DateTime date,
    required int startMinutes,
    required int endMinutes,
    String? note,
    String? createdBy,
  }) async {
    if (endMinutes <= startMinutes) {
      throw StateError('The shift must end after it starts.');
    }
    await db
        .into(db.scheduleShifts)
        .insert(
          ScheduleShiftsCompanion.insert(
            id: _uuid.v4(),
            businessId: businessId,
            userId: userId,
            shiftDate: dateOnly(date),
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            note: Value((note ?? '').trim().isEmpty ? null : note!.trim()),
            createdBy: Value(createdBy),
          ),
        );
  }

  Future<void> deleteShift(String id) =>
      (db.delete(db.scheduleShifts)..where((s) => s.id.equals(id))).go();

  /// Copies every shift of the week starting [fromWeekStart] to the next
  /// week, skipping shifts that already exist. Returns how many were added.
  Future<int> copyWeekForward({
    required String businessId,
    required DateTime fromWeekStart,
    String? createdBy,
  }) async {
    final from = dateOnly(fromWeekStart);
    final to = addDays(from, 7);
    final src =
        await (db.select(db.scheduleShifts)..where(
              (s) =>
                  s.businessId.equals(businessId) &
                  s.shiftDate.isBiggerOrEqualValue(from) &
                  s.shiftDate.isSmallerThanValue(to),
            ))
            .get();
    final dst =
        await (db.select(db.scheduleShifts)..where(
              (s) =>
                  s.businessId.equals(businessId) &
                  s.shiftDate.isBiggerOrEqualValue(to) &
                  s.shiftDate.isSmallerThanValue(addDays(to, 7)),
            ))
            .get();

    String key(String u, DateTime d, int a, int b) =>
        '$u|${dateOnly(d).millisecondsSinceEpoch}|$a|$b';
    final existing = {
      for (final s in dst)
        key(s.userId, s.shiftDate, s.startMinutes, s.endMinutes),
    };

    var added = 0;
    await db.transaction(() async {
      for (final s in src) {
        final newDate = addDays(s.shiftDate, 7);
        if (existing.contains(
          key(s.userId, newDate, s.startMinutes, s.endMinutes),
        )) {
          continue;
        }
        await db
            .into(db.scheduleShifts)
            .insert(
              ScheduleShiftsCompanion.insert(
                id: _uuid.v4(),
                businessId: businessId,
                userId: s.userId,
                shiftDate: newDate,
                startMinutes: s.startMinutes,
                endMinutes: s.endMinutes,
                note: Value(s.note),
                createdBy: Value(createdBy),
              ),
            );
        added++;
      }
    });
    return added;
  }

  // ---------------- leave ----------------

  Future<void> requestLeave({
    required String businessId,
    required String userId,
    required String leaveType,
    required DateTime start,
    required DateTime end,
    String? reason,
  }) async {
    final s = dateOnly(start);
    final e = dateOnly(end);
    if (e.isBefore(s)) {
      throw StateError('The end date is before the start date.');
    }

    final mine =
        await (db.select(db.leaveRequests)..where(
              (l) =>
                  l.businessId.equals(businessId) &
                  l.userId.equals(userId) &
                  l.status.isIn(['pending', 'approved']) &
                  l.startDate.isSmallerOrEqualValue(e) &
                  l.endDate.isBiggerOrEqualValue(s),
            ))
            .get();
    if (mine.isNotEmpty) {
      throw StateError('You already have a leave request on those dates.');
    }

    await db
        .into(db.leaveRequests)
        .insert(
          LeaveRequestsCompanion.insert(
            id: _uuid.v4(),
            businessId: businessId,
            userId: userId,
            leaveType: leaveType,
            startDate: s,
            endDate: e,
            days: Value((e.difference(s).inDays + 1).toDouble()),
            reason: Value(
              (reason ?? '').trim().isEmpty ? null : reason!.trim(),
            ),
          ),
        );
  }

  Future<void> decideLeave({
    required String requestId,
    required bool approve,
    required String deciderId,
    bool allowSelf = false,
    String? note,
  }) async {
    final req = await (db.select(
      db.leaveRequests,
    )..where((l) => l.id.equals(requestId))).getSingleOrNull();
    if (req == null) throw StateError('That request no longer exists.');
    if (req.status != 'pending') {
      throw StateError('This request was already ${req.status}.');
    }
    if (req.userId == deciderId && !allowSelf) {
      throw StateError('You can\'t decide your own request.');
    }
    await (db.update(
      db.leaveRequests,
    )..where((l) => l.id.equals(requestId))).write(
      LeaveRequestsCompanion(
        status: Value(approve ? 'approved' : 'rejected'),
        decidedBy: Value(deciderId),
        decidedAt: Value(DateTime.now()),
        decisionNote: Value((note ?? '').trim().isEmpty ? null : note!.trim()),
      ),
    );
  }

  Future<void> cancelLeave(String requestId) async {
    final req = await (db.select(
      db.leaveRequests,
    )..where((l) => l.id.equals(requestId))).getSingleOrNull();
    if (req == null || req.status != 'pending') {
      throw StateError('Only pending requests can be cancelled.');
    }
    await (db.update(db.leaveRequests)..where((l) => l.id.equals(requestId)))
        .write(const LeaveRequestsCompanion(status: Value('cancelled')));
  }

  // ---------------- payroll ----------------

  Future<void> saveProfile({
    required String businessId,
    required String userId,
    required String payType,
    required int rateCents,
  }) async {
    if (rateCents <= 0) throw StateError('Enter a rate greater than zero.');
    final existing =
        await (db.select(db.payrollProfiles)..where(
              (p) => p.businessId.equals(businessId) & p.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.payrollProfiles)
          .insert(
            PayrollProfilesCompanion.insert(
              id: _uuid.v4(),
              businessId: businessId,
              userId: userId,
              payType: payType,
              rate: rateCents,
            ),
          );
    } else {
      await (db.update(
        db.payrollProfiles,
      )..where((p) => p.id.equals(existing.id))).write(
        PayrollProfilesCompanion(
          payType: Value(payType),
          rate: Value(rateCents),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Builds a draft pay run from attendance and approved paid leave.
  ///   daily  : rate x (days with a completed clock-in + paid leave days)
  ///   hourly : rate x hours worked (after breaks)
  ///   fixed  : the rate itself, once per run
  Future<String> createPayrollRun({
    required String businessId,
    required DateTime start,
    required DateTime end,
    required String? createdBy,
    required Map<String, String> names,
  }) async {
    final s = dateOnly(start);
    final e = dateOnly(end);
    if (e.isBefore(s)) {
      throw StateError('The end date is before the start date.');
    }
    final endExcl = addDays(e, 1);

    final profiles = await (db.select(
      db.payrollProfiles,
    )..where((p) => p.businessId.equals(businessId))).get();
    final paid = profiles.where((p) => names.containsKey(p.userId)).toList();
    if (paid.isEmpty) {
      throw StateError(
        'No pay rates are set yet. Set them in the Pay rates tab first.',
      );
    }

    final att =
        await (db.select(db.attendanceRecords)..where(
              (a) =>
                  a.businessId.equals(businessId) &
                  a.clockOut.isNotNull() &
                  a.clockIn.isBiggerOrEqualValue(s) &
                  a.clockIn.isSmallerThanValue(endExcl),
            ))
            .get();
    final leaves =
        await (db.select(db.leaveRequests)..where(
              (l) =>
                  l.businessId.equals(businessId) &
                  l.status.equals('approved') &
                  l.leaveType.equals('unpaid').not() &
                  l.startDate.isSmallerOrEqualValue(e) &
                  l.endDate.isBiggerOrEqualValue(s),
            ))
            .get();

    final runId = _uuid.v4();
    var total = 0;

    await db.transaction(() async {
      final items = <PayrollItemsCompanion>[];
      for (final p in paid) {
        final recs = att.where((a) => a.userId == p.userId).toList();
        final days = recs.map((a) => dateOnly(a.clockIn)).toSet().length;
        var minutes = 0;
        for (final a in recs) {
          minutes += workedMinutes(a.clockIn, a.clockOut, a.breakMinutes);
        }
        final hours = minutes / 60;

        var leaveDays = 0;
        for (final l in leaves.where((l) => l.userId == p.userId)) {
          final a = dateOnly(l.startDate).isAfter(s)
              ? dateOnly(l.startDate)
              : s;
          final b = dateOnly(l.endDate).isBefore(e) ? dateOnly(l.endDate) : e;
          leaveDays += b.difference(a).inDays + 1;
        }

        final gross = switch (p.payType) {
          'daily' => (p.rate * (days + leaveDays)).round(),
          'hourly' => (p.rate * hours).round(),
          _ => p.rate,
        };
        total += gross;

        items.add(
          PayrollItemsCompanion.insert(
            id: _uuid.v4(),
            runId: runId,
            userId: p.userId,
            userName: names[p.userId] ?? 'Team member',
            payType: p.payType,
            rate: p.rate,
            daysWorked: Value(days.toDouble()),
            hoursWorked: Value(double.parse(hours.toStringAsFixed(2))),
            paidLeaveDays: Value(leaveDays.toDouble()),
            grossPay: Value(gross),
            netPay: Value(gross),
          ),
        );
      }

      await db
          .into(db.payrollRuns)
          .insert(
            PayrollRunsCompanion.insert(
              id: runId,
              businessId: businessId,
              periodStart: s,
              periodEnd: e,
              totalNet: Value(total),
              createdBy: Value(createdBy),
            ),
          );
      for (final i in items) {
        await db.into(db.payrollItems).insert(i);
      }
    });
    return runId;
  }

  Future<void> updatePayrollItem({
    required String itemId,
    required int additions,
    required int deductions,
    String? note,
  }) async {
    await db.transaction(() async {
      final item = await (db.select(
        db.payrollItems,
      )..where((i) => i.id.equals(itemId))).getSingle();
      final run = await (db.select(
        db.payrollRuns,
      )..where((r) => r.id.equals(item.runId))).getSingle();
      if (run.status != 'draft') {
        throw StateError('This pay run is finalized and can\'t be changed.');
      }
      final net = item.grossPay + additions - deductions;
      if (net < 0) throw StateError('Deductions are larger than the pay.');

      await (db.update(
        db.payrollItems,
      )..where((i) => i.id.equals(itemId))).write(
        PayrollItemsCompanion(
          additions: Value(additions),
          deductions: Value(deductions),
          netPay: Value(net),
          note: Value((note ?? '').trim().isEmpty ? null : note!.trim()),
        ),
      );

      final all = await (db.select(
        db.payrollItems,
      )..where((i) => i.runId.equals(run.id))).get();
      final total = all.fold<int>(0, (sum, i) => sum + i.netPay);
      await (db.update(db.payrollRuns)..where((r) => r.id.equals(run.id)))
          .write(PayrollRunsCompanion(totalNet: Value(total)));
    });
  }

  Future<void> finalizeRun(String runId) async {
    final run = await (db.select(
      db.payrollRuns,
    )..where((r) => r.id.equals(runId))).getSingleOrNull();
    if (run == null || run.status != 'draft') {
      throw StateError('This pay run is already finalized.');
    }
    await (db.update(db.payrollRuns)..where((r) => r.id.equals(runId))).write(
      PayrollRunsCompanion(
        status: const Value('finalized'),
        finalizedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteDraftRun(String runId) async {
    final run = await (db.select(
      db.payrollRuns,
    )..where((r) => r.id.equals(runId))).getSingleOrNull();
    if (run == null) return;
    if (run.status != 'draft') {
      throw StateError('Finalized pay runs can\'t be deleted.');
    }
    await db.transaction(() async {
      await (db.delete(
        db.payrollItems,
      )..where((i) => i.runId.equals(runId))).go();
      await (db.delete(db.payrollRuns)..where((r) => r.id.equals(runId))).go();
    });
  }
}

final hrServiceProvider = Provider<HrService>(
  (ref) => HrService(ref.watch(databaseProvider)),
);

// ============================================================================
// STREAMS
// ============================================================================

/// My currently open clock-in, if any.
final myOpenClockProvider = StreamProvider<AttendanceRecord?>((ref) {
  final db = ref.watch(databaseProvider);
  final b = ref.watch(selectedBusinessIdProvider);
  final me = ref.watch(authenticatedUserIdProvider);
  if (me == null) return Stream.value(null);
  return (db.select(db.attendanceRecords)
        ..where(
          (a) =>
              a.businessId.equals(b) &
              a.userId.equals(me) &
              a.clockOut.isNull(),
        )
        ..orderBy([(a) => OrderingTerm.desc(a.clockIn)])
        ..limit(1))
      .watchSingleOrNull();
});

/// My last 45 days of attendance.
final myAttendanceProvider = StreamProvider<List<AttendanceRecord>>((ref) {
  final db = ref.watch(databaseProvider);
  final b = ref.watch(selectedBusinessIdProvider);
  final me = ref.watch(authenticatedUserIdProvider);
  if (me == null) return Stream.value(const []);
  final since = addDays(DateTime.now(), -45);
  return (db.select(db.attendanceRecords)
        ..where(
          (a) =>
              a.businessId.equals(b) &
              a.userId.equals(me) &
              a.workDate.isBiggerOrEqualValue(dateOnly(since)),
        )
        ..orderBy([(a) => OrderingTerm.desc(a.clockIn)]))
      .watch();
});

/// All attendance records for one employee in the selected business,
/// newest first.
final employeeAttendanceProvider = StreamProvider.autoDispose
    .family<List<AttendanceRecord>, String>((ref, userId) {
      final db = ref.watch(databaseProvider);
      final b = ref.watch(selectedBusinessIdProvider);
      return (db.select(db.attendanceRecords)
            ..where((a) => a.businessId.equals(b) & a.userId.equals(userId))
            ..orderBy([(a) => OrderingTerm.desc(a.clockIn)]))
          .watch();
    });

/// All leave requests for one employee, newest first.
final employeeLeaveProvider = StreamProvider.autoDispose
    .family<List<LeaveRequest>, String>((ref, userId) {
      final db = ref.watch(databaseProvider);
      final b = ref.watch(selectedBusinessIdProvider);
      return (db.select(db.leaveRequests)
            ..where((l) => l.businessId.equals(b) & l.userId.equals(userId))
            ..orderBy([(l) => OrderingTerm.desc(l.startDate)]))
          .watch()
          .map(
            (rows) =>
                rows.where((row) => _visibleEmployee(ref, row.userId)).toList(),
          );
    });

class EmployeePayEntry {
  const EmployeePayEntry({required this.item, required this.run});
  final PayrollItem item;
  final PayrollRun run;
}

/// Every pay-run line for one employee, newest period first.
final employeePayHistoryProvider = StreamProvider.autoDispose
    .family<List<EmployeePayEntry>, String>((ref, userId) {
      final db = ref.watch(databaseProvider);
      final b = ref.watch(selectedBusinessIdProvider);
      final query =
          db.select(db.payrollItems).join([
              innerJoin(
                db.payrollRuns,
                db.payrollRuns.id.equalsExp(db.payrollItems.runId),
              ),
            ])
            ..where(
              db.payrollItems.userId.equals(userId) &
                  db.payrollRuns.businessId.equals(b),
            )
            ..orderBy([OrderingTerm.desc(db.payrollRuns.periodStart)]);
      return query.watch().map(
        (rows) => [
          for (final r in rows)
            if (_visibleEmployee(ref, r.readTable(db.payrollItems).userId))
              EmployeePayEntry(
                item: r.readTable(db.payrollItems),
                run: r.readTable(db.payrollRuns),
              ),
        ],
      );
    });

/// Everyone currently clocked in.
final openClocksProvider = StreamProvider<List<AttendanceRecord>>((ref) {
  final db = ref.watch(databaseProvider);
  final b = ref.watch(selectedBusinessIdProvider);
  return (db.select(db.attendanceRecords)
        ..where((a) => a.businessId.equals(b) & a.clockOut.isNull())
        ..orderBy([(a) => OrderingTerm.asc(a.clockIn)]))
      .watch();
});

final attendanceForDayProvider =
    StreamProvider.family<List<AttendanceRecord>, DateTime>((ref, day) {
      final db = ref.watch(databaseProvider);
      final b = ref.watch(selectedBusinessIdProvider);
      final start = dateOnly(day);
      final end = addDays(start, 1);
      return (db.select(db.attendanceRecords)
            ..where(
              (a) =>
                  a.businessId.equals(b) &
                  a.clockIn.isBiggerOrEqualValue(start) &
                  a.clockIn.isSmallerThanValue(end),
            )
            ..orderBy([(a) => OrderingTerm.asc(a.clockIn)]))
          .watch();
    });

final shiftsForWeekProvider =
    StreamProvider.family<List<ScheduleShift>, DateTime>((ref, weekStart) {
      final db = ref.watch(databaseProvider);
      final b = ref.watch(selectedBusinessIdProvider);
      final start = dateOnly(weekStart);
      return (db.select(db.scheduleShifts)
            ..where(
              (s) =>
                  s.businessId.equals(b) &
                  s.shiftDate.isBiggerOrEqualValue(start) &
                  s.shiftDate.isSmallerThanValue(addDays(start, 7)),
            )
            ..orderBy([
              (s) => OrderingTerm.asc(s.shiftDate),
              (s) => OrderingTerm.asc(s.startMinutes),
            ]))
          .watch();
    });

final leaveRequestsProvider = StreamProvider<List<LeaveRequest>>((ref) {
  final db = ref.watch(databaseProvider);
  final b = ref.watch(selectedBusinessIdProvider);
  return (db.select(db.leaveRequests)
        ..where((l) => l.businessId.equals(b))
        ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
      .watch()
      .map(
        (rows) =>
            rows.where((row) => _visibleEmployee(ref, row.userId)).toList(),
      );
});

final payrollProfilesProvider = StreamProvider<List<PayrollProfile>>((ref) {
  final db = ref.watch(databaseProvider);
  final b = ref.watch(selectedBusinessIdProvider);
  return (db.select(
    db.payrollProfiles,
  )..where((p) => p.businessId.equals(b))).watch().map(
    (rows) => rows.where((row) => _visibleEmployee(ref, row.userId)).toList(),
  );
});

final payrollRunsProvider = StreamProvider<List<PayrollRun>>((ref) {
  final db = ref.watch(databaseProvider);
  final b = ref.watch(selectedBusinessIdProvider);
  final query =
      db.select(db.payrollRuns).join([
          leftOuterJoin(
            db.payrollItems,
            db.payrollItems.runId.equalsExp(db.payrollRuns.id),
          ),
        ])
        ..where(db.payrollRuns.businessId.equals(b))
        ..orderBy([OrderingTerm.desc(db.payrollRuns.periodStart)]);
  return query.watch().map((rows) {
    final visible = <String, PayrollRun>{};
    for (final row in rows) {
      final run = row.readTable(db.payrollRuns);
      final item = row.readTableOrNull(db.payrollItems);
      if (item != null && _visibleEmployee(ref, item.userId)) {
        visible[run.id] = run;
      }
    }
    return visible.values.toList();
  });
});

final payrollItemsProvider = StreamProvider.family<List<PayrollItem>, String>((
  ref,
  runId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.payrollItems)
        ..where((i) => i.runId.equals(runId))
        ..orderBy([(i) => OrderingTerm.asc(i.userName)]))
      .watch()
      .map(
        (rows) =>
            rows.where((row) => _visibleEmployee(ref, row.userId)).toList(),
      );
});

/// Shifts from the last 60 days onward, for lateness checks.
final recentShiftsProvider = StreamProvider<List<ScheduleShift>>((ref) {
  final db = ref.watch(databaseProvider);
  final b = ref.watch(selectedBusinessIdProvider);
  final since = addDays(dateOnly(DateTime.now()), -60);
  return (db.select(db.scheduleShifts)..where(
        (s) => s.businessId.equals(b) & s.shiftDate.isBiggerOrEqualValue(since),
      ))
      .watch();
});

const int kLateGraceMinutes = 5;

/// null = no shift that day, 0 = on time, > 0 = minutes late.
int? lateMinutesFor(AttendanceRecord r, Iterable<ScheduleShift> shifts) {
  final day = dateOnly(r.clockIn);
  final mine = shifts
      .where((s) => s.userId == r.userId && dateOnly(s.shiftDate) == day)
      .toList();
  if (mine.isEmpty) return null;

  final inMin = r.clockIn.hour * 60 + r.clockIn.minute;
  mine.sort(
    (a, b) => (a.startMinutes - inMin).abs().compareTo(
      (b.startMinutes - inMin).abs(),
    ),
  );
  final late = inMin - mine.first.startMinutes;
  return late > kLateGraceMinutes ? late : 0;
}
