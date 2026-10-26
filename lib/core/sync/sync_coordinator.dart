// lib/core/sync/sync_coordinator.dart
//
// The offline-first sync coordinator. Drift is the local source of truth;
// the engine pushes pending outbox changes to Supabase and pulls remote
// changes back via the change-feed cursor. All work is per-business,
// mutex-guarded (no overlapping workers), and survives restarts because the
// outbox + checkpoints live in Drift, not memory.
//
// Realtime is deliberately NOT the source of truth — a missed notification
// never loses data because pull reconciles from the durable cursor.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bos_application/core/audit/audit_sync_codec.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide TableUpdate;

import '../device/device_management_service.dart';
import '../device/device_providers.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../supabase/supabase_service.dart';
import 'sync_change_log.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// User-facing sync state for a business.
enum SyncState {
  synced,
  syncing,
  offline,
  pending,
  failed,
  conflict,
  authorizationRequired,
  accountMismatch,
}

class SyncSummary {
  final SyncState state;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSuccessfulSyncAt;

  /// Remote changes applied to this device during the run.
  final int pulledCount;

  const SyncSummary({
    required this.state,
    required this.pendingCount,
    required this.failedCount,
    this.lastSuccessfulSyncAt,
    this.pulledCount = 0,
  });
}

class SyncCoordinator {
  final AppDatabase db;
  final SupabaseClient? _supabase; // null when backend isn't configured
  final DeviceManagementService? _devices;

  static const Map<String, Set<String>> _deviceLocalColumns = {
    'businesses': {'is_current'},
    'supplies': {'current_stock'},
    'products': {'current_stock'},
  };

  SyncCoordinator(this.db, this._supabase, this._devices);

  bool get isOnline => _supabase != null;

  // ---------------------------------------------------------------------------
  // Concurrency: one in-flight sync per business at a time (in-memory lock is
  // enough — Drift serializes the actual DB work, and this stops duplicate
  // workers within a single app process).
  // ---------------------------------------------------------------------------

  static final Set<String> _active = {};

  static const int _pullIdBatchSize = 100;
  static const int _pullFetchConcurrency = 6;
  static const String _pullCursorVersion = '2';

  final Map<String, Future<Map<String, String>>> _localTableColumns = {};
  bool _pullCursorVersionChecked = false;

  /// Businesses that asked for a sync while one was already running; they run
  /// again as soon as the current one ends so no change is left waiting.
  static final Set<String> _rerun = {};

  /// True while any sync is running (used to ignore the table updates the
  /// sync itself causes).
  static bool get anyActive => _active.isNotEmpty;

  /// Entry point for "sync this business now" (startup, foreground, manual,
  /// network-restored, or a Realtime nudge). No-op if a sync for this
  /// business is already running or the backend isn't configured.
  Future<SyncSummary> syncNow(
    String businessId, {
    required String userId,
  }) async {
    if (_supabase == null) {
      return _summary(businessId, SyncState.offline);
    }

    if (!_active.add(businessId)) {
      _rerun.add(businessId);
      return _summary(businessId, SyncState.syncing);
    }

    var pulled = 0;
    try {
      final devices = _devices;
      if (devices == null) {
        throw const DeviceAuthorizationException(
          'Device authorization is unavailable. Pending local changes are preserved.',
        );
      }
      if (devices.authenticatedUserId != userId) {
        throw const DeviceAuthorizationException(
          'The active BOS account does not match the Supabase session.',
        );
      }
      await devices.assertCurrentDeviceAuthorized();
      await SyncChangeLog.drain(db, fallbackOwner: userId);
      await _push(businessId, userId);
      pulled = await _pull(businessId, userId);
      await devices.recordSuccessfulSync();

      final pending = await _pendingCount(businessId);
      final failed = await _failedCount(businessId);
      final accountMismatch = await _accountMismatchCount(businessId, userId);

      final state = failed > 0
          ? SyncState.failed
          : accountMismatch > 0
          ? SyncState.accountMismatch
          : pending > 0
          ? SyncState.pending
          : SyncState.synced;

      return await _summary(businessId, state, pulledCount: pulled);
    } on DeviceAuthorizationException catch (error) {
      // The outbox remains intact so an authorized session can resume it.
      // ignore: avoid_print
      print('[sync] authorization required: ${error.message}');
      return _summary(businessId, SyncState.authorizationRequired);
    } on PostgrestException catch (error) {
      if (error.code == '42501' || error.code == 'PGRST301') {
        return _summary(businessId, SyncState.authorizationRequired);
      }
      // ignore: avoid_print
      print('[sync] syncNow failed: ${error.code}: ${error.message}');
      return _summary(businessId, SyncState.failed);
    } on SocketException {
      // No internet / DNS failure. Local changes stay queued and retry later.
      return _summary(businessId, SyncState.offline);
    } on ClientException {
      // The http package wraps SocketException in this.
      return _summary(businessId, SyncState.offline);
    } catch (e, st) {
      // ignore: avoid_print
      print('[sync] syncNow failed: $e\n$st');

      return _summary(businessId, SyncState.failed);
    } finally {
      _active.remove(businessId);
      if (_rerun.remove(businessId)) {
        unawaited(syncNow(businessId, userId: userId));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PUSH: process pending outbox rows oldest-first, respecting backoff.
  // ---------------------------------------------------------------------------

  Future<void> _push(String businessId, String userId) async {
    final client = _supabase!;
    final now = DateTime.now();

    // This business holds the sync lock, so anything still 'syncing' is left
    // over from an interrupted run. Put it back in the queue.
    await db.customStatement(
      "UPDATE sync_outbox SET status = 'pending' "
      "WHERE business_id = ? AND status = 'syncing'",
      [businessId],
    );

    final pending =
        await (db.select(db.syncOutbox)..where(
              (o) =>
                  o.businessId.equals(businessId) &
                  o.status.equals('pending') &
                  (o.nextAttemptAt.isNull() |
                      o.nextAttemptAt.isSmallerOrEqualValue(now)),
            ))
            .get();

    // ignore: avoid_print
    final ownedIds = await db
        .customSelect(
          'SELECT outbox_id FROM sync_outbox_owners WHERE owner_user_id = ?',
          variables: [Variable.withString(userId)],
        )
        .get();
    final ownedOutboxIds = ownedIds
        .map((row) => row.read<String>('outbox_id'))
        .toSet();

    const order = [
      'businesses',
      'branches',
      'branch_members',
      'accounts',
      'categories',
      'product_categories',
      'customers',
      'suppliers',
      'supplies',
      'products',
      'journal_entries',
      'income_transactions',
      'expenses',
      'ledger_lines',
      'supplier_purchases',
      'receivable_payments',
      'payable_payments',
      'account_transfers',
      'shopping_carts',
      'shopping_cart_items',
      'supply_price_history',
      'recipes',
      'recipe_components',
      'payment_providers',
      'pos_order_types',
      'pos_tables',
      'pos_sessions',
      'pos_sales',
      'pos_sale_items',
      'pos_sale_payments',
      'pos_sale_tenders',
      'pos_returns',
      'pos_return_items',
      'inventory_movements',
      'role_permission_overrides',
      'business_module_configs',
      'custom_roles',
      'role_labels',
      'schedule_shifts',
      'attendance_records',
      'leave_requests',
      'payroll_profiles',
      'payroll_runs',
      'payroll_items',
      'audit_logs',
      'product_stock_movements',
      'stock_transfers',
      'stock_transfer_items',
    ];
    int rank(String t) {
      final i = order.indexOf(t);
      return i < 0 ? 999 : i;
    }

    final sorted =
        pending.where((row) => ownedOutboxIds.contains(row.id)).toList()
          ..sort((a, b) {
            final ad = a.operation == 'delete';
            final bd = b.operation == 'delete';
            if (ad != bd) return ad ? 1 : -1; // creates/updates before deletes
            final r = rank(a.entityType).compareTo(rank(b.entityType));
            return ad ? -r : r; // deletes go children-first
          });

    // ignore: avoid_print
    print('[outbox] ${sorted.length} groups owned by the active account');

    for (final row in sorted) {
      await _pushOne(client, row, userId);
    }
  }

  Future<void> _pushOne(
    SupabaseClient client,
    SyncOutboxData op,
    String userId,
  ) async {
    // Mark syncing so a crash mid-upload resumes from a known state.
    await _setStatus(op.id, 'syncing');

    try {
      final ownBranchAssignment =
          op.entityType == 'branch_members' &&
          (await _readEntity('branch_members', op.entityId))?['user_id'] ==
              userId;
      final result = await _dispatch(client, op);

      // Duplicate is a SUCCESS — the server already has this mutation.
      await db.transaction(() async {
        await (db.delete(db.syncOutbox)..where((o) => o.id.equals(op.id))).go();
        if (ownBranchAssignment) {
          await db.customStatement(
            'UPDATE sync_checkpoints SET last_server_cursor = 0 '
            'WHERE business_id = ?',
            [op.businessId],
          );
        }

        await _bumpCheckpoint(op.businessId);
      });

      _log(
        op,
        result == 'duplicate'
            ? 'pushed (duplicate)'
            : result == 'obsolete'
            ? 'skipped (row deleted locally)'
            : 'pushed',
      );
    } on _TransientSyncException {
      await _scheduleRetry(op);
    } on _ConflictSyncException catch (e) {
      await _setStatus(op.id, 'conflict', error: e.message);
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == 'PGRST301') {
        if (e.code == '42501' && op.entityType == 'ledger_lines') {
          await _scheduleRetry(op);
          return;
        }
        // Re-check the device. Only a real device/session problem aborts the
        // whole sync; an ordinary permission denial fails just this one row.
        try {
          await _devices?.assertCurrentDeviceAuthorized();
        } on DeviceAuthorizationException {
          await _setStatus(
            op.id,
            'pending',
            error:
                'Cloud authorization is required before this change can sync.',
          );
          rethrow;
        }

        if (op.entityType == 'leave_requests' ||
            op.entityType == 'custom_roles') {
          try {
            await _adoptServerCopy(op);
          } catch (_) {
            await _scheduleRetry(op); // network hiccup: try again later
          }
          return;
        }
        // ignore: avoid_print
        print('[outbox] denied ${op.entityType}/${op.entityId} (${e.code})');
        await _setStatus(
          op.id,
          'failed',
          error: 'Not permitted by cloud policy (${e.code}).',
        );
        return;
      }
      final parentNotYetThere =
          (e.code == '42501' && op.entityType == 'ledger_lines') ||
          e.code == '23503';
      if (parentNotYetThere) {
        await _scheduleRetry(op);
      } else {
        await _setStatus(op.id, 'failed', error: '${e.code}: ${e.message}');
      }
    } on SocketException {
      await _setStatus(op.id, 'pending');
      rethrow; // stops this sync run; syncNow reports "offline"
    } on ClientException {
      await _setStatus(op.id, 'pending');
      rethrow;
    } catch (e) {
      // Permanent validation/business-rule failure: stop retrying forever.
      await _setStatus(op.id, 'failed', error: '$e');
    }
  }

  /// The server refused our version of this row (for example the request was
  /// already decided on another device). Drop the queued change and take the
  /// server's copy so this device stops disagreeing with it.
  Future<void> _adoptServerCopy(SyncOutboxData op) async {
    final row = await _supabase!
        .from(op.entityType)
        .select()
        .eq('id', op.entityId)
        .maybeSingle();

    await db.transaction(() async {
      await (db.delete(db.syncOutbox)..where((o) => o.id.equals(op.id))).go();
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      await db.customStatement('UPDATE sync_context SET suppress = 1');
      try {
        if (row == null) {
          await db.customStatement(
            'DELETE FROM "${op.entityType}" WHERE id = ?',
            [op.entityId],
          );
        } else {
          await _applyRemote({
            'entity_type': op.entityType,
            'entity_id': op.entityId,
            'operation': 'update',
          }, row);
        }
      } finally {
        await db.customStatement('UPDATE sync_context SET suppress = 0');
      }
    });
    db.notifyUpdates({TableUpdate(op.entityType)});
    // ignore: avoid_print
    print(
      '[sync] ${op.entityType}/${op.entityId} refused; server copy adopted',
    );
  }

  /// Route the outbox op to the right server command.
  ///
  /// Returns 'duplicate' when the server already processed this mutation id.
  Future<String> _dispatch(SupabaseClient client, SyncOutboxData op) async {
    switch (op.entityType) {
      case 'payable_payments':
        return _pushComposite(
          client,
          op,
          rpc: 'record_supplier_payment',
          table: 'payable_payments',
        );

      case 'receivable_payments':
        return _pushComposite(
          client,
          op,
          rpc: 'record_customer_payment',
          table: 'receivable_payments',
        );
      case 'audit_logs':
        return _pushAuditEvent(client, op);
      case 'pos_returns':
      case 'pos_return_items':
        return _pushAppendOnlyReturn(client, op);

      default:
        return _pushRow(client, op);
    }
  }

  /// Composite financial ops go through their atomic server command, which
  /// re-validates membership/ownership/balance/idempotency server-side.
  Future<String> _pushComposite(
    SupabaseClient client,
    SyncOutboxData op, {
    required String rpc,
    required String table,
  }) async {
    if (op.operation == 'delete') {
      // Deleting a posted payment voids it server-side via the same command
      // family; for now delete the record row (managers+ per RLS).
      await client.from(table).delete().eq('id', op.entityId);

      return 'ok';
    }

    final row = await _readEntity(table, op.entityId);

    if (row == null) {
      throw _PermanentSyncException('Local $table row ${op.entityId} is gone.');
    }

    final params = _compositeParams(table, row, op);

    final response = await client.rpc(rpc, params: params);

    final map = response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);

    return map['duplicate'] == true ? 'duplicate' : 'ok';
  }

  /// Client reports sync for visibility, but the database accepts them only
  /// with the `client_reported` source. Database audit rows use the pull feed.
  Future<String> _pushAuditEvent(
    SupabaseClient client,
    SyncOutboxData op,
  ) async {
    if (op.operation != 'create') return 'ok';
    final row = await _readEntity('audit_logs', op.entityId);
    if (row == null) {
      throw _PermanentSyncException(
        'Local audit_logs row ${op.entityId} is gone.',
      );
    }
    if (row['source'] != 'client_reported') {
      throw _PermanentSyncException(
        'Only client-reported audit rows may be uploaded.',
      );
    }
    final payload = AuditSyncCodec.toCloud(
      _toSupabaseRow('audit_logs', row, businessId: op.businessId),
    );
    await client
        .from('audit_logs')
        .upsert(payload, onConflict: 'id', ignoreDuplicates: true);
    return 'ok';
  }

  Future<String> _pushAppendOnlyReturn(
    SupabaseClient client,
    SyncOutboxData op,
  ) async {
    if (op.operation != 'create') {
      throw _PermanentSyncException(
        'POS return records are append-only and cannot be changed.',
      );
    }
    final row = await _readEntity(op.entityType, op.entityId);
    if (row == null) {
      throw _PermanentSyncException(
        'Local ${op.entityType} row ${op.entityId} is gone.',
      );
    }
    final payload = _toSupabaseRow(
      op.entityType,
      row,
      businessId: op.businessId,
    );
    await client
        .from(op.entityType)
        .upsert(payload, onConflict: 'id', ignoreDuplicates: true);
    return 'ok';
  }

  Map<String, dynamic> _compositeParams(
    String table,
    Map<String, dynamic> row,
    SyncOutboxData op,
  ) {
    final base = <String, dynamic>{
      'p_mutation_id': op.mutationId,
      'p_payment_id': op.entityId,
      'p_business_id': op.businessId,
      'p_amount': row['amount'],
      'p_payment_account_id': row['payment_account_id'],
      'p_payment_date': _timestampForSupabase(row['payment_date']),
      'p_notes': row['notes'],
    };

    if (table == 'payable_payments') {
      base['p_supplier_id'] = row['supplier_id'];
    } else {
      base['p_customer_id'] = row['customer_id'];
    }

    return base;
  }

  /// Master-data + simple rows push straight to their table.
  /// Idempotency is the stable primary key: upsert on the same id is a
  /// no-op server-side.
  Future<String> _pushRow(SupabaseClient client, SyncOutboxData op) async {
    try {
      // DELETE
      if (op.operation == 'delete') {
        await client.from(op.entityType).delete().eq('id', op.entityId);

        if (kDebugMode) {
          // ignore: avoid_print
          print('[outbox] deleted ${op.entityType}/${op.entityId}');
        }

        return 'ok';
      }

      // READ LOCAL ROW
      final row = await _readEntity(op.entityType, op.entityId);

      if (row == null) {
        // The row was deleted locally after this change was queued, so there
        // is nothing left to upload. Any queued delete handles the server.
        return 'obsolete';
      }

      // BUILD SUPABASE PAYLOAD
      final payload = _toSupabaseRow(
        op.entityType,
        row,
        businessId: op.businessId,
      );

      // SUPABASE WRITE (the response body isn't needed, so no .select())
      await client.from(op.entityType).upsert(payload, onConflict: 'id');

      if (kDebugMode) {
        // ignore: avoid_print
        print('[outbox] ${op.entityType} uploaded id=${op.entityId}');
      }

      return 'ok';
    } catch (e, st) {
      // Failures stay visible in every build, but without payloads. The
      // stack trace is debug-only.
      // ignore: avoid_print
      print(
        '[outbox] write failed ${op.entityType}/${op.entityId} '
        'operation=${op.operation} error=$e',
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[outbox] STACKTRACE $st');
      }

      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _readEntity(String table, String id) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM "$table" WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  // ---------------------------------------------------------------------------
  // SUPABASE SERIALIZATION
  // ---------------------------------------------------------------------------

  /// Converts local Drift/SQLite row values into values accepted by
  /// Supabase/PostgreSQL.
  ///
  /// Important:
  /// Drift dateTime() values are currently represented locally as INTEGER
  /// Unix seconds in SQLite. PostgreSQL timestamptz columns must receive an
  /// ISO-8601 timestamp string.
  ///
  /// Example:
  ///
  ///   1791011696
  ///
  /// becomes:
  ///
  ///   2026-10-03T07:14:56.000Z
  ///
  /// This conversion happens only at the sync boundary. The local database
  /// representation does not change.
  Map<String, dynamic> _toSupabaseRow(
    String table,
    Map<String, dynamic> row, {
    String? businessId,
  }) {
    final result = <String, dynamic>{};

    for (final entry in row.entries) {
      final column = entry.key;
      final value = entry.value;

      result[column] = _serializeSupabaseColumn(
        table: table,
        column: column,
        value: value,
      );
    }

    // is_current records which business THIS device has open. It is
    // per-device state and must never overwrite another device's choice.
    final deviceLocalColumns = _deviceLocalColumns[table] ?? const <String>{};

    for (final column in deviceLocalColumns) {
      result.remove(column);
    }
    // ledger_lines has business_id in Supabase but not in the
    // local Drift row. Derive it from the outbox operation.
    if (table == 'ledger_lines' &&
        !result.containsKey('business_id') &&
        businessId != null &&
        businessId.isNotEmpty) {
      result['business_id'] = businessId;
    }

    return result;
  }

  Object? _serializeSupabaseColumn({
    required String table,
    required String column,
    required Object? value,
  }) {
    if (value == null) {
      return null;
    }

    // Journal entries:
    // entry_date and created_at are PostgreSQL timestamptz columns.
    if (table == 'journal_entries') {
      switch (column) {
        case 'entry_date':
        case 'created_at':
          return _timestampForSupabase(value);
      }
    }

    // Other known timestamp columns.
    if (_dateOnlyColumns.contains(column)) {
      return _dateOnlyForSupabase(value);
    }
    if (_isDateTimeColumn(column)) {
      return _timestampForSupabase(value);
    }

    if (value is Map) {
      return value.map((key, nestedValue) => MapEntry(key, nestedValue));
    }

    if (value is List) {
      return value.toList();
    }

    return value;
  }

  bool _isDateTimeColumn(String column) {
    switch (column) {
      case 'entry_date':
      case 'txn_date':
      case 'expense_date':
      case 'purchase_date':
      case 'payment_date':
      case 'transfer_date':
      case 'recorded_date':
      case 'cart_date':
      case 'movement_date':
      case 'sale_date':
      case 'created_at':
      case 'updated_at':
      case 'last_attempt_at':
      case 'next_attempt_at':
      case 'last_successful_sync_at':
      case 'opened_at':
      case 'closed_at':
      case 'paid_at':
      case 'voided_at':
      case 'started_at':
      case 'ended_at':
      case 'shift_date':
      case 'work_date':
      case 'clock_in':
      case 'clock_out':
      case 'start_date':
      case 'end_date':
      case 'decided_at':
      case 'period_start':
      case 'period_end':
      case 'finalized_at':
      case 'shipped_at':
      case 'received_at':
        return true;

      default:
        return false;
    }
  }

  static const _dateOnlyColumns = {
    'shift_date',
    'work_date',
    'start_date',
    'end_date',
    'period_start',
    'period_end',
  };

  /// Local calendar day -> "yyyy-MM-dd" (no UTC shift).
  String _dateOnlyForSupabase(Object value) {
    DateTime? dt;
    if (value is DateTime) {
      dt = value;
    } else if (value is num) {
      dt = _epochToDateTime(value.round());
    } else if (value is String) {
      dt =
          DateTime.tryParse(value) ??
          (int.tryParse(value) != null
              ? _epochToDateTime(int.parse(value))
              : null);
    }
    if (dt == null) {
      throw FormatException('Cannot convert to date: $value');
    }
    final l = dt.toLocal(); // the local calendar day the user picked
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}';
  }

  String _timestampForSupabase(Object value) {
    DateTime? dt;

    if (value is DateTime) {
      dt = value;
    } else if (value is int) {
      dt = _epochToDateTime(value);
    } else if (value is num) {
      dt = _epochToDateTime(value.round());
    } else if (value is String) {
      dt = DateTime.tryParse(value);

      if (dt == null) {
        final number = int.tryParse(value);

        if (number != null) {
          dt = _epochToDateTime(number);
        }
      }
    }

    if (dt == null) {
      throw FormatException(
        'Cannot convert timestamp to Supabase timestamptz: $value',
      );
    }

    return dt.toUtc().toIso8601String();
  }

  DateTime _epochToDateTime(int value) {
    final absolute = value.abs();

    if (absolute < 100000000000) {
      // Unix seconds.
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }

    if (absolute < 100000000000000) {
      // Unix milliseconds.
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    // Unix microseconds.
    return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
  }

  // ---------------------------------------------------------------------------
  // PULL: fetch change-feed rows after the durable cursor, apply atomically.
  // ---------------------------------------------------------------------------

  /// Returns how many remote changes were applied to this device.
  Future<int> _pull(String businessId, String userId) async {
    final client = _supabase!;
    await _ensurePullCursorVersion();
    final checkpoint = await _checkpoint(businessId);

    var cursor = checkpoint?.lastServerCursor ?? 0;

    const pageSize = 500;
    var applied = 0;
    final touchedTables = <String>{};

    while (true) {
      final changes = await client
          .from('sync_changes')
          .select()
          .eq('business_id', businessId)
          .gt('seq', cursor)
          .order('seq', ascending: true)
          .limit(pageSize);

      final list = List<Map<String, dynamic>>.from(changes);
      // ignore: avoid_print
      print('[pull] fetched ${list.length} changes after cursor=$cursor');

      if (list.isEmpty) {
        break;
      }

      // Fetch the authoritative rows BEFORE opening the local transaction so
      // no network wait happens while the database is locked. Fetch ids in
      // batches per table rather than issuing one request per changed row.
      final fetched = <String, Map<String, dynamic>?>{};
      final idsByTable = <String, Set<String>>{};
      for (final change in list) {
        if (change['operation'] == 'delete') continue;
        final table = change['entity_type'] as String;
        idsByTable
            .putIfAbsent(table, () => <String>{})
            .add(change['entity_id'] as String);
      }

      final tables = idsByTable.keys.toList();
      final available = await Future.wait(tables.map(_hasLocalTable));
      final requests = <({String table, List<String> ids})>[];
      for (var i = 0; i < tables.length; i++) {
        if (!available[i]) continue;
        final ids = idsByTable[tables[i]]!.toList();
        for (var offset = 0; offset < ids.length; offset += _pullIdBatchSize) {
          final end = (offset + _pullIdBatchSize).clamp(0, ids.length).toInt();
          requests.add((table: tables[i], ids: ids.sublist(offset, end)));
        }
      }

      var nextRequest = 0;
      await Future.wait(
        List.generate(_pullFetchConcurrency.clamp(0, requests.length).toInt(), (
          _,
        ) async {
          while (nextRequest < requests.length) {
            final request = requests[nextRequest++];
            final rows = await client
                .from(request.table)
                .select()
                .inFilter('id', request.ids);
            for (final row in rows) {
              final data = Map<String, dynamic>.from(row);
              fetched['${request.table}/${data['id']}'] = data;
            }
          }
        }),
      );

      // Preserve explicit null entries for missing tables/rows so apply logic
      // can distinguish them from ids that were never present in this page.
      for (final entry in idsByTable.entries) {
        for (final id in entry.value) {
          fetched.putIfAbsent('${entry.key}/$id', () => null);
        }
      }

      final newCursor = await db.transaction(() async {
        // Rows can arrive before the rows they reference; check references
        // at commit instead of per statement.
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        // Cloud changes are not local edits and must not be queued for upload.
        await db.customStatement('UPDATE sync_context SET suppress = 1');

        var maxSeq = cursor;
        var ownBranchAssignmentChanged = false;

        for (final change in list) {
          final key = '${change['entity_type']}/${change['entity_id']}';
          final row = fetched[key];
          final isOwnBranchAssignment = await _isOwnBranchAssignmentChange(
            change,
            row,
            userId,
          );
          final changed = await _applyRemote(change, row);
          if (changed) {
            applied++;
            touchedTables.add(change['entity_type'] as String);
            ownBranchAssignmentChanged |= isOwnBranchAssignment;
          }

          maxSeq = (change['seq'] as int) > maxSeq
              ? change['seq'] as int
              : maxSeq;
        }

        await db.customStatement('UPDATE sync_context SET suppress = 0');

        // Advance the durable cursor only after every change in this batch
        // applied locally — an interrupted pull resumes from the last safe
        // point, never skipping unapplied rows.
        await _setCursor(businessId, ownBranchAssignmentChanged ? 0 : maxSeq);

        return ownBranchAssignmentChanged ? 0 : maxSeq;
      });

      cursor = newCursor;

      if (cursor == 0) continue;
      if (list.length < pageSize) {
        break; // last page
      }
    }

    await _touchLastSuccess(businessId);

    // customStatement writes are invisible to Drift's reactive queries; tell
    // them what changed so open screens refresh immediately.
    if (touchedTables.isNotEmpty) {
      db.notifyUpdates({for (final table in touchedTables) TableUpdate(table)});
    }
    // ignore: avoid_print
    print(
      '[pull] business=$businessId cursor=$cursor applied=$applied tables=$touchedTables',
    );

    return applied;
  }

  Future<bool> _isOwnBranchAssignmentChange(
    Map<String, dynamic> change,
    Map<String, dynamic>? row,
    String userId,
  ) async {
    if (change['entity_type'] != 'branch_members') return false;
    if (row != null) return row['user_id'] == userId;

    final local =
        await (db.select(db.branchMembers)..where(
              (member) => member.id.equals(change['entity_id'] as String),
            ))
            .getSingleOrNull();
    return local?.userId == userId;
  }

  Future<void> _ensurePullCursorVersion() async {
    if (_pullCursorVersionChecked) return;
    await SyncChangeLog.ensurePullCursorVersion(
      db,
      version: _pullCursorVersion,
    );
    _pullCursorVersionChecked = true;
  }

  Future<bool> _hasLocalTable(String table) async {
    return (await _columnsForTable(table)).isNotEmpty;
  }

  Future<Map<String, String>> _columnsForTable(String table) {
    return _localTableColumns.putIfAbsent(table, () async {
      final info = await db.customSelect('PRAGMA table_info("$table")').get();
      return {
        for (final column in info)
          column.read<String>('name'): column
              .read<String>('type')
              .toUpperCase(),
      };
    });
  }

  /// Apply one remote change to Drift inside the pull batch's transaction.
  /// Returns whether anything was written.
  ///
  /// The change feed carries ids only; the row itself is the authoritative
  /// one fetched from the entity table (RLS-scoped).
  Future<bool> _applyRemote(
    Map<String, dynamic> change,
    Map<String, dynamic>? row,
  ) async {
    final entityType = change['entity_type'] as String;
    final entityId = change['entity_id'] as String;

    final types = await _columnsForTable(entityType);
    if (types.isEmpty) return false;
    // History is never deleted locally because of a feed entry.
    if (entityType == 'audit_logs' && change['operation'] == 'delete') {
      return false;
    }
    final isDelete = change['operation'] == 'delete';
    if (!isDelete && row == null) {
      return false;
    }

    // A local edit that has not reached the server yet wins; it uploads on
    // the next push and the server copy catches up.
    final unsent = await db
        .customSelect(
          'SELECT 1 FROM sync_outbox WHERE entity_type = ? AND entity_id = ? '
          "AND status IN ('pending', 'syncing') LIMIT 1",
          variables: [
            Variable.withString(entityType),
            Variable.withString(entityId),
          ],
        )
        .get();
    if (unsent.isNotEmpty) {
      return false;
    }

    if (isDelete) {
      await db.customStatement('DELETE FROM "$entityType" WHERE id = ?', [
        entityId,
      ]);
      return true;
    }
    final cloudRow = row;
    if (cloudRow == null) return false;

    // Per-device state; the cloud value is meaningless locally.
    final deviceLocalColumns =
        _deviceLocalColumns[entityType] ?? const <String>{};
    final cols = types.keys
        .where(
          (c) => cloudRow.containsKey(c) && !deviceLocalColumns.contains(c),
        )
        .toList();

    if (!cols.contains('id')) {
      return false;
    }

    final values = [for (final c in cols) _toLocal(cloudRow[c], types[c]!, c)];

    // Echo guard: skip the write when local already holds these exact values.
    final existing = await db
        .customSelect(
          'SELECT * FROM "$entityType" WHERE id = ?',
          variables: [Variable.withString(entityId)],
        )
        .get();
    if (existing.isNotEmpty) {
      final local = existing.first.data;
      var identical = true;
      for (var i = 0; i < cols.length; i++) {
        if (!_sameValue(local[cols[i]], values[i])) {
          identical = false;
          break;
        }
      }
      if (identical) return false;
    }

    final quoted = cols.map((c) => '"$c"').join(', ');

    final setCols = cols
        .where((c) => c != 'id')
        .map((c) => '"$c" = excluded."$c"')
        .join(', ');

    await db.customStatement(
      'INSERT INTO "$entityType" ($quoted) '
      'VALUES (${List.filled(values.length, '?').join(', ')}) '
      'ON CONFLICT(id) DO UPDATE SET $setCols',
      values,
    );

    return true;
  }

  bool _sameValue(Object? a, Object? b) {
    if (a == b) return true;
    if (a == null || b == null) return false;
    if (a is num && b is num) return a == b;
    return a.toString() == b.toString();
  }

  /// Supabase JSON -> what Drift stores.
  ///
  /// Local Drift dateTime() columns are stored as Unix seconds in INTEGER
  /// columns, so timestamp strings from Supabase are converted back to Unix
  /// seconds only when the local SQLite column is actually INTEGER and the
  /// column is known to be a timestamp.
  static final _isoLike = RegExp(r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}.*)?$');

  Object? _toLocal(Object? value, String sqlType, String column) {
    if (sqlType == 'INTEGER' &&
        value is String &&
        _dateOnlyColumns.contains(column) &&
        value.length >= 10) {
      // Take the calendar day literally, whatever time/offset follows it.
      final y = int.tryParse(value.substring(0, 4));
      final m = int.tryParse(value.substring(5, 7));
      final d = int.tryParse(value.substring(8, 10));
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d).millisecondsSinceEpoch ~/ 1000;
      }
    }
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;

    // Any INTEGER column that receives an ISO date string is a Drift
    // dateTime column. Store it as Unix seconds, whatever its name.
    if (sqlType == 'INTEGER' && value is String && _isoLike.hasMatch(value)) {
      final dt = DateTime.tryParse(value);
      if (dt != null) return dt.millisecondsSinceEpoch ~/ 1000;
    }

    if (value is Map || value is List) return jsonEncode(value);
    return value;
  }

  // ---------------------------------------------------------------------------
  // Retry / backoff / status
  // ---------------------------------------------------------------------------

  Future<void> _scheduleRetry(SyncOutboxData op) async {
    final attempts = op.attemptCount + 1;

    // Exponential backoff: 2^n seconds, capped at ~5 minutes.
    final delaySeconds = (1 << attempts).clamp(1, 300);

    await (db.update(db.syncOutbox)..where((o) => o.id.equals(op.id))).write(
      SyncOutboxCompanion(
        status: const Value('pending'),
        attemptCount: Value(attempts),
        lastAttemptAt: Value(DateTime.now()),
        nextAttemptAt: Value(
          DateTime.now().add(Duration(seconds: delaySeconds)),
        ),
      ),
    );
  }

  Future<void> _setStatus(String id, String status, {String? error}) async {
    await (db.update(db.syncOutbox)..where((o) => o.id.equals(id))).write(
      SyncOutboxCompanion(
        status: Value(status),
        lastAttemptAt: Value(DateTime.now()),
        error: Value(error),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Checkpoints / summary
  // ---------------------------------------------------------------------------

  Future<SyncCheckpoint?> _checkpoint(String businessId) {
    return (db.select(
      db.syncCheckpoints,
    )..where((c) => c.businessId.equals(businessId))).getSingleOrNull();
  }

  Future<void> _setCursor(String businessId, int cursor) async {
    await db
        .into(db.syncCheckpoints)
        .insertOnConflictUpdate(
          SyncCheckpointsCompanion(
            businessId: Value(businessId),
            lastServerCursor: Value(cursor),
            lastSuccessfulSyncAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _touchLastSuccess(String businessId) async {
    final existing = await _checkpoint(businessId);

    if (existing != null) {
      await (db.update(
        db.syncCheckpoints,
      )..where((c) => c.businessId.equals(businessId))).write(
        SyncCheckpointsCompanion(lastSuccessfulSyncAt: Value(DateTime.now())),
      );
    }
  }

  Future<void> _bumpCheckpoint(String businessId) async {
    await _touchLastSuccess(businessId);
  }

  Future<int> _pendingCount(String businessId) {
    return _count(businessId, 'pending');
  }

  Future<int> _failedCount(String businessId) {
    return _count(businessId, 'failed');
  }

  Future<int> _accountMismatchCount(String businessId, String userId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sync_outbox o '
          "WHERE o.business_id = ? AND o.status <> 'synced' "
          'AND NOT EXISTS ('
          '  SELECT 1 FROM sync_outbox_owners own '
          '  WHERE own.outbox_id = o.id AND own.owner_user_id = ?'
          ')',
          variables: [
            Variable.withString(businessId),
            Variable.withString(userId),
          ],
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> _count(String businessId, String status) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sync_outbox '
          'WHERE business_id = ? AND status = ?',
          variables: [
            Variable.withString(businessId),
            Variable.withString(status),
          ],
        )
        .getSingle();

    return row.read<int>('c');
  }

  Future<SyncSummary> _summary(
    String businessId,
    SyncState state, {
    int pulledCount = 0,
  }) async {
    final checkpoint = await _checkpoint(businessId);

    return SyncSummary(
      state: state,
      pendingCount: await _pendingCount(businessId),
      failedCount: await _failedCount(businessId),
      lastSuccessfulSyncAt: checkpoint?.lastSuccessfulSyncAt,
      pulledCount: pulledCount,
    );
  }

  void _log(SyncOutboxData op, String result) {
    // Structured local log for diagnostics. Never logs secrets or PII.
    // ignore: avoid_print
    print(
      '[sync] ${op.operation} '
      '${op.entityType}/${op.entityId} '
      'mutation=${op.mutationId} '
      'result=$result',
    );
  }
}

class _TransientSyncException implements Exception {}

class _PermanentSyncException implements Exception {
  final String message;

  const _PermanentSyncException(this.message);

  @override
  String toString() => message;
}

class _ConflictSyncException implements Exception {
  final String message;

  const _ConflictSyncException(this.message);

  @override
  String toString() => message;
}

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final available = ref.watch(supabaseAvailableProvider);
  final supabase = available ? ref.watch(supabaseClientProvider) : null;
  final devices = available ? ref.watch(deviceManagementServiceProvider) : null;

  return SyncCoordinator(ref.watch(databaseProvider), supabase, devices);
});
