// lib/core/audit/audit_writer.dart
//
// THE single write path into `audit_logs`. Both AuditLogService (new code,
// with resolved context) and the existing AuditLogger (membership_service.dart,
// used by TransactionService) delegate here, so there is one system, not two.
//
// Imports only database/sync_tracker/enums on purpose: it must be importable
// from low-level files (permission_overrides.dart, inventory_service.dart)
// without creating import cycles with the auth layer.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../sync/sync_tracker.dart';
import 'audit_enums.dart';

/// Removes secrets and normalizes values into JSON-safe form.
abstract final class AuditRedactor {
  static const _sensitive = [
    'password',
    'passcode',
    'secret',
    'token',
    'hash',
    'salt',
    'apikey',
    'api_key',
  ];

  static bool isSensitiveKey(String key) {
    final k = key.toLowerCase();
    return _sensitive.any(k.contains);
  }

  static Map<String, Object?>? sanitize(Map<String, Object?>? source) {
    if (source == null) return null;
    return {
      for (final e in source.entries)
        e.key: isSensitiveKey(e.key) ? '***' : _normalize(e.value),
    };
  }

  static Object? _normalize(Object? v) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return {
        for (final e in v.entries)
          '${e.key}': isSensitiveKey('${e.key}') ? '***' : _normalize(e.value),
      };
    }
    if (v is Iterable) return [for (final x in v) _normalize(x)];
    return v.toString();
  }
}

abstract final class AuditDiff {
  /// Only the keys whose values differ; a key missing on one side is null.
  static (Map<String, Object?>, Map<String, Object?>) changed(
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) {
    final b = <String, Object?>{};
    final a = <String, Object?>{};
    for (final key in {...before.keys, ...after.keys}) {
      if (jsonEncode(before[key]) != jsonEncode(after[key])) {
        b[key] = before[key];
        a[key] = after[key];
      }
    }
    return (b, a);
  }
}

/// Last known cloud device id, so events written offline still carry it.
abstract final class AuditDeviceId {
  static const _key = 'audit_device_id';
  static String? _cached;
  static String? get current => _cached;

  static Future<void> loadCached() async {
    try {
      _cached = (await SharedPreferences.getInstance()).getString(_key);
    } on Object catch (_) {}
  }

  static Future<void> remember(String? id) async {
    if (id == null || id.isEmpty) return;
    _cached = id;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, id);
    } on Object catch (_) {}
  }

  @visibleForTesting
  static void debugSet(String? id) => _cached = id;
}

/// Derives module / action type from an action code such as
/// 'finance.expense_deleted' when the caller doesn't supply them, so legacy
/// AuditLogger call sites get classified without edits.
abstract final class AuditClassifier {
  static const _securityActions = {
    'user.suspended',
    'user.reactivated',
    'user.removed',
    'business.ownership_transferred',
  };

  static AuditModule moduleFor(String action) {
    if (_securityActions.contains(action)) return AuditModule.security;
    final prefix = action.split('.').first;
    return switch (prefix) {
      'finance' => AuditModule.finance,
      'inventory' => AuditModule.inventory,
      'sales' || 'pos' => AuditModule.sales,
      'people' || 'employee' => AuditModule.people,
      'security' || 'auth' || 'device' => AuditModule.security,
      _ => AuditModule.administration,
    };
  }

  static AuditActionType actionTypeFor(String action) {
    if (_securityActions.contains(action) ||
        action.startsWith('auth.') ||
        action.startsWith('device.') ||
        action.startsWith('security.')) {
      return AuditActionType.security;
    }
    final verb = action.contains('.')
        ? action.substring(action.indexOf('.') + 1)
        : action;
    if (verb == 'role_changed' || action.startsWith('permission.')) {
      return AuditActionType.permission;
    }
    if (verb.contains('void')) return AuditActionType.voided;
    if (verb.contains('refund')) return AuditActionType.refund;
    if (verb.contains('adjust') || verb.contains('restored')) {
      return AuditActionType.adjustment;
    }
    if (verb.contains('export')) return AuditActionType.export;
    for (final w in const [
      'deleted',
      'removed',
      'archived',
      'reversed',
      'revoked',
    ]) {
      if (verb.contains(w)) return AuditActionType.delete;
    }
    for (final w in const ['created', 'invited', 'redeemed', 'recorded']) {
      if (verb.contains(w)) return AuditActionType.create;
    }
    return AuditActionType.update;
  }
}

abstract final class AuditWriter {
  static const _uuid = Uuid();

  /// Inserts one audit row using [db]. Joins the caller's transaction when
  /// there is one, so the business change and its audit row commit or roll
  /// back together. Idempotent on [eventId] (INSERT OR IGNORE).
  static Future<String> write(
    AppDatabase db, {
    required String businessId,
    required String? userId,
    required String action,
    required String entityType,
    String? entityId,
    AuditModule? module,
    AuditActionType? actionType,
    String? entityLabel,
    String? reason,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    Map<String, Object?>? details,
    bool changedFieldsOnly = true,
    String? eventId,
    DateTime? occurredAt,
    String? actorName,
    String? actorRole,
    String? deviceId,
  }) async {
    if (businessId.trim().isEmpty) {
      throw ArgumentError.value(
        businessId,
        'businessId',
        'An audit event must belong to a business.',
      );
    }

    final resolvedActionType =
        actionType ?? AuditClassifier.actionTypeFor(action);
    final cleanReason = reason?.trim();
    if (resolvedActionType.requiresReason &&
        (cleanReason == null || cleanReason.isEmpty)) {
      throw ArgumentError.value(
        reason,
        'reason',
        '${resolvedActionType.id} requires a reason.',
      );
    }

    final explicitActor = userId?.trim();
    final trackedActor = SyncTracker.currentUserId?.trim();
    final actorId = (explicitActor != null && explicitActor.isNotEmpty)
        ? explicitActor
        : trackedActor;
    if (actorId == null || actorId.isEmpty) {
      throw StateError(
        'Cannot record an audit event without a signed-in actor.',
      );
    }

    var name = actorName;
    var role = actorRole;
    if (name == null) {
      final u = await (db.select(
        db.users,
      )..where((t) => t.id.equals(actorId))).getSingleOrNull();
      final dn = u?.displayName.trim() ?? '';
      name = dn.isNotEmpty ? dn : u?.email;
    }
    if (role == null) {
      final m =
          await (db.select(db.businessMembers)..where(
                (t) =>
                    t.businessId.equals(businessId) & t.userId.equals(actorId),
              ))
              .getSingleOrNull();
      role = m?.role;
    }

    var b = AuditRedactor.sanitize(before);
    var a = AuditRedactor.sanitize(after);
    if (changedFieldsOnly && b != null && a != null) {
      (b, a) = AuditDiff.changed(b, a);
    }

    final id = eventId ?? _uuid.v4();
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            id: id,
            businessId: businessId,
            userId: actorId,
            action: action,
            entityType: entityType,
            entityId: Value(entityId),
            details: Value(_encode(AuditRedactor.sanitize(details))),
            createdAt: Value(occurredAt ?? DateTime.now()),
            module: Value((module ?? AuditClassifier.moduleFor(action)).id),
            actionType: Value(resolvedActionType.id),
            entityLabel: Value(entityLabel),
            actorName: Value(name),
            actorRole: Value(role),
            deviceId: Value(deviceId ?? AuditDeviceId.current),
            source: const Value('client_reported'),
            reason: Value(cleanReason?.isEmpty ?? true ? null : cleanReason),
            beforeJson: Value(_encode(b)),
            afterJson: Value(_encode(a)),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return id;
  }

  static String? _encode(Map<String, Object?>? m) =>
      m == null || m.isEmpty ? null : jsonEncode(m);
}
