// lib/core/audit/audit_repository.dart
//
// Read side of the audit trail. Permission-gated with the existing
// AuthorizationService.require, scoped to the SELECTED business only.
// Reuses BosPermission.securityManage (bos_access.dart was not provided, so
// no new permission was invented); swap to a dedicated auditView permission
// if you add one.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/authorization_providers.dart';
import '../auth/authorization_service.dart';
import '../auth/bos_access.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'audit_enums.dart';

class AuditFilter {
  const AuditFilter({
    this.from,
    this.toExclusive,
    this.userId,
    this.module,
    this.actionType,
    this.query = '',
    this.limit = 300,
  });

  final DateTime? from;
  final DateTime? toExclusive;
  final String? userId;
  final AuditModule? module;
  final AuditActionType? actionType;

  /// Matches the affected record's type, id or label.
  final String query;
  final int limit;

  AuditFilter copyWith({
    DateTime? Function()? from,
    DateTime? Function()? toExclusive,
    String? Function()? userId,
    AuditModule? Function()? module,
    AuditActionType? Function()? actionType,
    String? query,
  }) => AuditFilter(
    from: from != null ? from() : this.from,
    toExclusive: toExclusive != null ? toExclusive() : this.toExclusive,
    userId: userId != null ? userId() : this.userId,
    module: module != null ? module() : this.module,
    actionType: actionType != null ? actionType() : this.actionType,
    query: query ?? this.query,
    limit: limit,
  );

  @override
  bool operator ==(Object other) =>
      other is AuditFilter &&
      other.from == from &&
      other.toExclusive == toExclusive &&
      other.userId == userId &&
      other.module == module &&
      other.actionType == actionType &&
      other.query == query &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(from, toExclusive, userId, module, actionType, query, limit);
}

class AuditActor {
  const AuditActor(this.userId, this.name);
  final String userId;
  final String name;
}

class AuditRepository {
  AuditRepository(this._db, this._auth);

  final AppDatabase _db;
  final AuthorizationService _auth;

  static const viewPermission = BosPermission.securityManage;

  /// Throws [PermissionDeniedException] unless the member may view the trail.
  String _scope() {
    _auth.require(viewPermission);
    return _auth.currentBusinessId!;
  }

  Stream<List<AuditLog>> watch(AuditFilter f) {
    final businessId = _scope();
    final q = _db.select(_db.auditLogs)
      ..where((t) {
        final p = <Expression<bool>>[t.businessId.equals(businessId)];
        if (f.from != null) p.add(t.createdAt.isBiggerOrEqualValue(f.from!));
        if (f.toExclusive != null) {
          p.add(t.createdAt.isSmallerThanValue(f.toExclusive!));
        }
        if (f.userId != null) p.add(t.userId.equals(f.userId!));
        if (f.module != null) p.add(t.module.equals(f.module!.id));
        if (f.actionType != null) {
          p.add(t.actionType.equals(f.actionType!.id));
        }
        final text = f.query.trim();
        if (text.isNotEmpty) {
          final like = '%$text%';
          p.add(
            t.entityType.like(like) |
                t.entityId.like(like) |
                t.entityLabel.like(like),
          );
        }
        return p.reduce((a, b) => a & b);
      })
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(f.limit);
    return q.watch();
  }

  Future<List<AuditActor>> actors() async {
    final businessId = _scope();
    final rows = await _db
        .customSelect(
          'SELECT user_id, MAX(actor_name) AS name FROM audit_logs '
          'WHERE business_id = ? GROUP BY user_id ORDER BY name',
          variables: [Variable.withString(businessId)],
        )
        .get();
    return [
      for (final r in rows)
        AuditActor(
          r.read<String>('user_id'),
          r.readNullable<String>('name') ?? r.read<String>('user_id'),
        ),
    ];
  }
}

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
  );
});

final auditEventsProvider = StreamProvider.autoDispose
    .family<List<AuditLog>, AuditFilter>(
      (ref, filter) => ref.watch(auditRepositoryProvider).watch(filter),
    );

final auditActorsProvider = FutureProvider.autoDispose<List<AuditActor>>(
  (ref) => ref.watch(auditRepositoryProvider).actors(),
);
