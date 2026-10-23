// lib/core/sync/sync_change_log.dart
//
// Captures every local write to a synced table, whichever code path made it.
//
// Hand-written SyncTracker.record() calls only cover the screens and services
// that remember to make them (supplies, products, POS, recipes... did not).
// SQLite triggers record each insert/update/delete in `sync_change_log`, and
// [SyncChangeLog.drain] turns those rows into outbox entries through
// SyncTracker.record, so the existing folding rules still apply (an update
// after a pending create stays one create, create + delete cancels out).
//
// Writes that arrive FROM the cloud (pull) or that merely seed defaults on a
// new device are not local edits: they run inside [SyncChangeLog.suppressed]
// so they are never echoed back to the server.

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'sync_tracker.dart';

class _Synced {
  const _Synced(this.table, this.businessIdOf);

  final String table;

  /// SQL expression for the owning business, given the row alias
  /// (NEW or OLD).
  final String Function(String row) businessIdOf;
}

String _direct(String row) => '$row.business_id';

String _via(String parent, String fk, String row) =>
    '(SELECT business_id FROM $parent WHERE id = $row.$fk)';

final List<_Synced> _syncedTables = [
  _Synced('businesses', (r) => '$r.id'),
  _Synced('accounts', _direct),
  _Synced('categories', _direct),
  _Synced('customers', _direct),
  _Synced('suppliers', _direct),
  _Synced('journal_entries', _direct),
  _Synced(
    'ledger_lines',
    (r) => _via('journal_entries', 'journal_entry_id', r),
  ),
  _Synced('income_transactions', _direct),
  _Synced('expenses', _direct),
  _Synced('receivable_payments', _direct),
  _Synced('payable_payments', _direct),
  _Synced('supplier_purchases', _direct),
  _Synced('account_transfers', _direct),
  _Synced('supplies', _direct),
  _Synced('inventory_movements', (r) => _via('supplies', 'supply_id', r)),
  _Synced('product_categories', _direct),
  _Synced('products', _direct),
  _Synced('supply_price_history', (r) => _via('supplies', 'supply_id', r)),
  _Synced('shopping_carts', _direct),
  _Synced('shopping_cart_items', (r) => _via('shopping_carts', 'cart_id', r)),
  _Synced('recipes', (r) => _via('products', 'product_id', r)),
  _Synced(
    'recipe_components',
    (r) =>
        '(SELECT p.business_id FROM recipes rc JOIN products p '
        'ON p.id = rc.product_id WHERE rc.id = $r.recipe_id)',
  ),
  _Synced('payment_providers', _direct),
  _Synced('pos_sessions', _direct),
  _Synced('pos_sales', _direct),
  _Synced('pos_sale_items', (r) => _via('pos_sales', 'sale_id', r)),
  _Synced('pos_sale_payments', (r) => _via('pos_sales', 'sale_id', r)),
  _Synced('pos_sale_tenders', (r) => _via('pos_sales', 'sale_id', r)),
  _Synced('pos_order_types', _direct),
  _Synced('pos_tables', _direct),
  _Synced('role_permission_overrides', _direct),
  _Synced('business_module_configs', _direct),
  _Synced('audit_logs', _direct),
  _Synced('schedule_shifts', _direct),
  _Synced('attendance_records', _direct),
  _Synced('leave_requests', _direct),
  _Synced('payroll_profiles', _direct),
  _Synced('payroll_runs', _direct),
  _Synced('payroll_items', (r) => _via('payroll_runs', 'run_id', r)),
  _Synced('role_labels', _direct),
  _Synced('custom_roles', _direct),

  _Synced('branches', _direct),
  _Synced('branch_members', _direct),
  _Synced('product_stock_movements', _direct),
  _Synced('stock_transfers', _direct),
  _Synced('stock_transfer_items', _direct),
];

/// Entity types the change log records. Exposed for the sync order and tests.
List<String> get syncedEntityTypes => [for (final t in _syncedTables) t.table];

abstract final class SyncChangeLog {
  /// Creates the log tables and triggers. Idempotent; runs on every open.
  static Future<void> install(AppDatabase db) async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_context (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        owner_user_id TEXT,
        suppress INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.customStatement(
      'INSERT OR IGNORE INTO sync_context (id, owner_user_id, suppress) '
      'VALUES (1, NULL, 0)',
    );
    // A crash mid-pull must not leave logging switched off.
    await db.customStatement('UPDATE sync_context SET suppress = 0');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_change_log (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id TEXT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        owner_user_id TEXT
      )
    ''');

    for (final t in _syncedTables) {
      for (final (suffix, event, op, row) in const [
        ('ins', 'INSERT', 'create', 'NEW'),
        ('upd', 'UPDATE', 'update', 'NEW'),
        ('del', 'DELETE', 'delete', 'OLD'),
      ]) {
        await db.customStatement('''
          CREATE TRIGGER IF NOT EXISTS sync_log_${t.table}_$suffix
          AFTER $event ON ${t.table}
          WHEN (SELECT suppress FROM sync_context WHERE id = 1) = 0
          BEGIN
            INSERT INTO sync_change_log
              (business_id, entity_type, entity_id, operation, owner_user_id)
            VALUES (
              ${t.businessIdOf(row)},
              '${t.table}',
              $row.id,
              '$op',
              (SELECT owner_user_id FROM sync_context WHERE id = 1)
            );
          END
        ''');
      }
    }
  }

  /// Records which account is signed in, so changes made now are attributed
  /// to that account even if they are drained later.
  static Future<void> setOwner(AppDatabase db, String? userId) {
    return db.customStatement(
      'UPDATE sync_context SET owner_user_id = ? WHERE id = 1',
      [userId],
    );
  }

  /// Runs [body] with change logging off. Use for writes that are not local
  /// edits: applying cloud changes, seeding defaults on adoption.
  static Future<T> suppressed<T>(
    AppDatabase db,
    Future<T> Function() body,
  ) async {
    await db.customStatement('UPDATE sync_context SET suppress = 1');
    try {
      return await body();
    } finally {
      await db.customStatement('UPDATE sync_context SET suppress = 0');
    }
  }

  /// Moves logged changes into the outbox. Returns how many were processed.
  static Future<int> drain(AppDatabase db, {String? fallbackOwner}) async {
    return db.transaction(() async {
      final rows = await db
          .customSelect('SELECT * FROM sync_change_log ORDER BY seq')
          .get();
      if (rows.isEmpty) return 0;

      for (final row in rows) {
        final businessId = row.readNullable<String>('business_id');
        if (businessId != null && businessId.isNotEmpty) {
          final type = row.read<String>('entity_type');
          final id = row.read<String>('entity_id');
          if (type == 'shopping_carts' && id.startsWith('draft-')) continue;
          if (type == 'shopping_cart_items') {
            final parent = await db
                .customSelect(
                  'SELECT cart_id FROM shopping_cart_items WHERE id = ?',
                  variables: [Variable.withString(id)],
                )
                .getSingleOrNull();
            if (parent != null &&
                parent.read<String>('cart_id').startsWith('draft-')) {
              continue;
            }
          }
          await SyncTracker.record(
            db,
            businessId: businessId,
            entityType: row.read<String>('entity_type'),
            entityId: row.read<String>('entity_id'),
            operation: row.read<String>('operation'),
            ownerUserId:
                row.readNullable<String>('owner_user_id') ?? fallbackOwner,
          );
        }
      }
      await db.customStatement('DELETE FROM sync_change_log WHERE seq <= ?', [
        rows.last.read<int>('seq'),
      ]);
      return rows.length;
    });
  }
}
