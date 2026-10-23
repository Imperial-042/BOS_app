// lib/core/sync/sync_tracker.dart

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'sync_change_log.dart';

const _uuid = Uuid();

abstract final class SyncOp {
  static const create = 'create';
  static const update = 'update';
  static const delete = 'delete';
}

/// Centralized local change tracking.
///
/// IMPORTANT:
/// Call SyncTracker.record() using the SAME AppDatabase instance and
/// INSIDE the SAME Drift transaction that performs the business mutation.
///
/// This guarantees:
///   business row + outbox row = one atomic local transaction.
abstract final class SyncTracker {
  static String? _currentUserId;
  static AppDatabase? _boundDb;

  /// The signed-in account. Mirrored into the database so changes made now
  /// are attributed to it even when they are queued later.
  static String? get currentUserId => _currentUserId;

  static set currentUserId(String? userId) {
    _currentUserId = userId;
    _mirrorOwner();
  }

  /// Connects the tracker to the app database (called once by the provider).
  static void bind(AppDatabase db) {
    _boundDb = db;
    _mirrorOwner();
  }

  static void _mirrorOwner() {
    final db = _boundDb;
    if (db == null) return;
    unawaited(
      SyncChangeLog.setOwner(db, _currentUserId).catchError((Object _) {}),
    );
  }

  static Future<void> record(
    AppDatabase db, {
    required String businessId,
    required String entityType,
    required String entityId,
    required String operation,
    String? ownerUserId,
  }) async {
    final allPending =
        await (db.select(db.syncOutbox)..where(
              (o) =>
                  o.businessId.equals(businessId) &
                  o.entityType.equals(entityType) &
                  o.entityId.equals(entityId) &
                  o.status.equals('pending'),
            ))
            .get();

    // Only fold into rows this account is allowed to upload. A row owned by
    // someone else stays untouched and gets its own sibling row.
    final owner = ownerUserId ?? currentUserId;
    var pending = allPending;
    if (owner != null && allPending.isNotEmpty) {
      final foreign = await db
          .customSelect(
            'SELECT outbox_id FROM sync_outbox_owners WHERE owner_user_id <> ?',
            variables: [Variable.withString(owner)],
          )
          .get();
      final foreignIds = foreign
          .map((r) => r.read<String>('outbox_id'))
          .toSet();
      pending = allPending.where((r) => !foreignIds.contains(r.id)).toList();
    }

    final now = DateTime.now();

    // -------------------------------------------------------------------------
    // CREATE
    // -------------------------------------------------------------------------
    if (operation == SyncOp.create) {
      final existingCreate = pending
          .where((row) => row.operation == SyncOp.create)
          .firstOrNull;

      if (existingCreate != null) {
        // The entity is still a creation. Keep the original mutationId.
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(existingCreate.id))).write(
          SyncOutboxCompanion(
            createdAt: Value(now),
            nextAttemptAt: const Value(null),
            error: const Value(null),
          ),
        );
        return;
      }

      // If a pending delete exists for the same entity, the latest state is
      // effectively a new creation. Remove the old pending delete.
      for (final row in pending.where(
        (row) => row.operation == SyncOp.delete,
      )) {
        await (db.delete(
          db.syncOutbox,
        )..where((o) => o.id.equals(row.id))).go();
      }

      await _insertOutbox(
        db,
        businessId: businessId,
        entityType: entityType,
        entityId: entityId,
        operation: SyncOp.create,
        ownerUserId: ownerUserId,
      );
      return;
    }

    // -------------------------------------------------------------------------
    // UPDATE
    // -------------------------------------------------------------------------
    if (operation == SyncOp.update) {
      // A not-yet-uploaded create already contains the latest local state.
      // Keep it as CREATE instead of generating CREATE + UPDATE.
      final existingCreate = pending
          .where((row) => row.operation == SyncOp.create)
          .firstOrNull;

      if (existingCreate != null) {
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(existingCreate.id))).write(
          SyncOutboxCompanion(
            createdAt: Value(now),
            nextAttemptAt: const Value(null),
            error: const Value(null),
          ),
        );
        return;
      }

      final existingUpdate = pending
          .where((row) => row.operation == SyncOp.update)
          .firstOrNull;

      if (existingUpdate != null) {
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(existingUpdate.id))).write(
          SyncOutboxCompanion(
            createdAt: Value(now),
            nextAttemptAt: const Value(null),
            error: const Value(null),
          ),
        );
        return;
      }

      // Replace a pending delete with an update only when an entity has been
      // recreated/modified before the delete was uploaded.
      final existingDelete = pending
          .where((row) => row.operation == SyncOp.delete)
          .firstOrNull;

      if (existingDelete != null) {
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(existingDelete.id))).write(
          SyncOutboxCompanion(
            operation: const Value(SyncOp.update),
            createdAt: Value(now),
            nextAttemptAt: const Value(null),
            error: const Value(null),
          ),
        );
        return;
      }

      await _insertOutbox(
        db,
        businessId: businessId,
        entityType: entityType,
        entityId: entityId,
        operation: SyncOp.update,
        ownerUserId: ownerUserId,
      );
      return;
    }

    // -------------------------------------------------------------------------
    // DELETE
    // -------------------------------------------------------------------------
    if (operation == SyncOp.delete) {
      // If CREATE has never reached Supabase, there is nothing to delete
      // remotely. Remove the pending CREATE instead.
      final existingCreate = pending
          .where((row) => row.operation == SyncOp.create)
          .firstOrNull;

      if (existingCreate != null) {
        await (db.delete(
          db.syncOutbox,
        )..where((o) => o.id.equals(existingCreate.id))).go();

        // Remove any redundant pending updates for this same entity too.
        for (final row in pending.where(
          (row) => row.operation == SyncOp.update,
        )) {
          await (db.delete(
            db.syncOutbox,
          )..where((o) => o.id.equals(row.id))).go();
        }

        return;
      }

      final existingDelete = pending
          .where((row) => row.operation == SyncOp.delete)
          .firstOrNull;

      if (existingDelete != null) {
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(existingDelete.id))).write(
          SyncOutboxCompanion(
            createdAt: Value(now),
            nextAttemptAt: const Value(null),
            error: const Value(null),
          ),
        );
        return;
      }

      // An update followed by delete collapses to DELETE.
      final existingUpdate = pending
          .where((row) => row.operation == SyncOp.update)
          .firstOrNull;

      if (existingUpdate != null) {
        await (db.update(
          db.syncOutbox,
        )..where((o) => o.id.equals(existingUpdate.id))).write(
          SyncOutboxCompanion(
            operation: const Value(SyncOp.delete),
            createdAt: Value(now),
            nextAttemptAt: const Value(null),
            error: const Value(null),
          ),
        );
        return;
      }

      await _insertOutbox(
        db,
        businessId: businessId,
        entityType: entityType,
        entityId: entityId,
        operation: SyncOp.delete,
        ownerUserId: ownerUserId,
      );
      return;
    }

    throw ArgumentError('Unknown sync operation: $operation');
  }

  static Future<void> _insertOutbox(
    AppDatabase db, {
    required String businessId,
    required String entityType,
    required String entityId,
    required String operation,
    String? ownerUserId,
  }) async {
    final outboxId = _uuid.v4();
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: outboxId,
            businessId: businessId,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            mutationId: _uuid.v4(),
          ),
        );
    final userId = ownerUserId ?? currentUserId;
    if (userId != null) {
      await db.customStatement(
        'INSERT INTO sync_outbox_owners (outbox_id, owner_user_id) VALUES (?, ?)',
        [outboxId, userId],
      );
    }
  }
}

class SyncStatusService {
  final AppDatabase db;

  SyncStatusService(this.db);

  Stream<List<SyncOutboxData>> watchPending(String businessId) {
    return (db.select(db.syncOutbox)
          ..where(
            (o) => o.businessId.equals(businessId) & o.status.equals('pending'),
          )
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
        .watch();
  }

  Stream<List<SyncOutboxData>> watchFailed(String businessId) {
    return (db.select(db.syncOutbox)
          ..where(
            (o) => o.businessId.equals(businessId) & o.status.equals('failed'),
          )
          ..orderBy([(o) => OrderingTerm.desc(o.lastAttemptAt)]))
        .watch();
  }

  Future<int> pendingCount(String businessId) async {
    final row = await db
        .customSelect(
          '''
          SELECT COUNT(*) AS c
          FROM sync_outbox
          WHERE business_id = ?
            AND status = 'pending'
          ''',
          variables: [Variable.withString(businessId)],
        )
        .getSingle();

    return row.read<int>('c');
  }

  Future<void> markStatus(
    String outboxId,
    String status, {
    String? error,
  }) async {
    await (db.update(db.syncOutbox)..where((o) => o.id.equals(outboxId))).write(
      SyncOutboxCompanion(
        status: Value(status),
        lastAttemptAt: Value(DateTime.now()),
        error: Value(error),
      ),
    );
  }

  /// Puts failed changes back in the queue (e.g. after a server-side fix).
  Future<int> requeueFailed(String businessId) {
    return (db.update(db.syncOutbox)..where(
          (o) => o.businessId.equals(businessId) & o.status.equals('failed'),
        ))
        .write(
          const SyncOutboxCompanion(
            status: Value('pending'),
            attemptCount: Value(0),
            nextAttemptAt: Value(null),
            error: Value(null),
          ),
        );
  }
}

final syncStatusServiceProvider = Provider<SyncStatusService>((ref) {
  return SyncStatusService(ref.watch(databaseProvider));
});
