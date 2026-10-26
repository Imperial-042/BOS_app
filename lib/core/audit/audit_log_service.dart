// lib/core/audit/audit_log_service.dart
//
// Context-aware front door for NEW code. All writes go through AuditWriter
// (audit_writer.dart), the same path the existing AuditLogger uses.
//
// ATOMICITY: call record() inside the SAME db.transaction as the business
// change (or use runAudited). If audit context is missing, record() THROWS so
// an unaudited financial change can never commit silently.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart' show currentUserProvider;
import '../auth/authorization_providers.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'audit_enums.dart';
import 'audit_writer.dart';

export 'audit_writer.dart' show AuditRedactor, AuditDiff, AuditDeviceId;

class AuditContextException implements Exception {
  final String message;
  const AuditContextException(this.message);
  @override
  String toString() => message;
}

/// Who/where an event is attributed to. Resolved synchronously at record
/// time so no network wait ever happens inside a DB transaction.
class AuditContext {
  const AuditContext({
    required this.userId,
    required this.businessId,
    this.actorName,
    this.actorRole,
    this.deviceId,
  });
  final String userId;
  final String businessId;
  final String? actorName;
  final String? actorRole;
  final String? deviceId;
}

typedef AuditContextResolver = AuditContext? Function();

class AuditEvent {
  const AuditEvent({
    required this.module,
    required this.actionType,
    required this.action,
    required this.entityType,
    this.entityId,
    this.entityLabel,
    this.reason,
    this.before,
    this.after,
    this.details,
    this.businessId,
    this.eventId,
    this.occurredAt,
    this.changedFieldsOnly = true,
  });

  final AuditModule module;
  final AuditActionType actionType;

  /// An entity-and-verb code, such as `user.role_changed`.
  final String action;
  final String entityType;
  final String? entityId;

  /// Human-readable record name, snapshot at the time (e.g. 'Flour').
  final String? entityLabel;
  final String? reason;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
  final Map<String, Object?>? details;
  final String? businessId;

  /// Supply a stable id when an operation can be replayed.
  final String? eventId;
  final DateTime? occurredAt;
  final bool changedFieldsOnly;
}

class AuditLogService {
  AuditLogService(this._db, {required AuditContextResolver resolveContext})
    : _resolve = resolveContext;

  final AppDatabase _db;
  final AuditContextResolver _resolve;

  Future<String> record(AuditEvent e) async {
    final ctx = _resolve();
    if (ctx == null ||
        ctx.userId.trim().isEmpty ||
        ctx.businessId.trim().isEmpty) {
      throw const AuditContextException(
        'Cannot record audit event: no signed-in user or selected business.',
      );
    }
    if (e.businessId != null && e.businessId != ctx.businessId) {
      throw ArgumentError.value(
        e.businessId,
        'businessId',
        'Audit event business must match the resolved business context.',
      );
    }
    return AuditWriter.write(
      _db,
      businessId: e.businessId ?? ctx.businessId,
      userId: ctx.userId,
      action: e.action,
      entityType: e.entityType,
      entityId: e.entityId,
      module: e.module,
      actionType: e.actionType,
      entityLabel: e.entityLabel,
      reason: e.reason,
      before: e.before,
      after: e.after,
      details: e.details,
      changedFieldsOnly: e.changedFieldsOnly,
      eventId: e.eventId,
      occurredAt: e.occurredAt,
      actorName: ctx.actorName,
      actorRole: ctx.actorRole,
      deviceId: ctx.deviceId,
    );
  }

  /// For non-transactional events (sign-out, export) where failing the
  /// user's action over a logging problem is worse than a missed row.
  /// Do NOT use for financial/inventory writes.
  Future<bool> tryRecord(AuditEvent e) async {
    try {
      await record(e);
      return true;
    } on Object catch (error) {
      debugPrint('[audit] event skipped (${error.runtimeType})');
      return false;
    }
  }

  /// Business change + audit event in ONE transaction.
  Future<T> runAudited<T>({
    required Future<T> Function() change,
    required AuditEvent Function(T result) event,
  }) {
    return _db.transaction(() async {
      final result = await change();
      await record(event(result));
      return result;
    });
  }
}

final auditLogServiceProvider = Provider<AuditLogService>((ref) {
  final db = ref.watch(databaseProvider);
  return AuditLogService(
    db,
    resolveContext: () {
      final userId = ref.read(authenticatedUserIdProvider);
      if (userId == null) return null;
      final user = ref.read(currentUserProvider).value;
      final name = (user?.displayName ?? '').trim();
      return AuditContext(
        userId: userId,
        businessId: ref.read(selectedBusinessIdProvider),
        actorName: name.isNotEmpty ? name : user?.email,
        actorRole: ref.read(currentBusinessMembershipProvider).value?.role,
        deviceId: AuditDeviceId.current,
      );
    },
  );
});
