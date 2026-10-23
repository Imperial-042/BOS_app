import '../database/app_database.dart';
import '../sync/sync_change_log.dart';

class BusinessPurgeException implements Exception {
  final String message;
  const BusinessPurgeException(this.message);
  @override
  String toString() => message;
}

/// Removes a business and everything it owns from the local database.
/// Not a local edit, so change logging is suppressed.
Future<void> purgeLocalBusiness(AppDatabase db, String businessId) {
  return SyncChangeLog.suppressed(
    db,
    () => db.transaction(() async {
      await db.customStatement('PRAGMA defer_foreign_keys = ON');

      const childDeletes = [
        'DELETE FROM ledger_lines WHERE journal_entry_id IN '
            '(SELECT id FROM journal_entries WHERE business_id = ?)',
        'DELETE FROM supply_price_history WHERE supply_id IN '
            '(SELECT id FROM supplies WHERE business_id = ?)',
        'DELETE FROM supply_unit_conversions WHERE supply_id IN '
            '(SELECT id FROM supplies WHERE business_id = ?)',
        'DELETE FROM shopping_cart_items WHERE cart_id IN '
            '(SELECT id FROM shopping_carts WHERE business_id = ?)',
        'DELETE FROM inventory_movements WHERE supply_id IN '
            '(SELECT id FROM supplies WHERE business_id = ?)',
        'DELETE FROM recipe_components WHERE recipe_id IN '
            '(SELECT id FROM recipes WHERE product_id IN '
            '(SELECT id FROM products WHERE business_id = ?))',
        'DELETE FROM recipes WHERE product_id IN '
            '(SELECT id FROM products WHERE business_id = ?)',
        'DELETE FROM pos_sale_tenders WHERE sale_id IN '
            '(SELECT id FROM pos_sales WHERE business_id = ?)',
        'DELETE FROM pos_sale_payments WHERE sale_id IN '
            '(SELECT id FROM pos_sales WHERE business_id = ?)',
        'DELETE FROM pos_sale_items WHERE sale_id IN '
            '(SELECT id FROM pos_sales WHERE business_id = ?)',
      ];
      for (final sql in childDeletes) {
        await db.customStatement(sql, [businessId]);
      }

      const tables = [
        'stock_transfer_items',
        'stock_transfers',
        'product_stock_movements',
        'branch_members',
        'branches',
        'pos_sales',
        'pos_sessions',
        'shopping_carts',
        'receivable_payments',
        'payable_payments',
        'income_transactions',
        'expenses',
        'supplier_purchases',
        'account_transfers',
        'products',
        'supplies',
        'product_categories',
        'payment_providers',
        'suppliers',
        'customers',
        'role_permission_overrides',
        'business_invites',
        'business_module_configs',
        'audit_logs',
        'business_members',
        'journal_entries',
        'categories',
        'accounts',
        'sync_outbox',
        'sync_checkpoints',
      ];
      for (final t in tables) {
        await db.customStatement('DELETE FROM $t WHERE business_id = ?', [
          businessId,
        ]);
      }

      await db.customStatement('DELETE FROM businesses WHERE id = ?', [
        businessId,
      ]);
      await db.customStatement(
        'DELETE FROM sync_change_log WHERE business_id = ?',
        [businessId],
      );

      // Sweep orphaned sync bookkeeping so the check reports real problems.
      await db.customStatement(
        'DELETE FROM sync_outbox WHERE business_id NOT IN (SELECT id FROM businesses)',
      );
      await db.customStatement(
        'DELETE FROM sync_checkpoints WHERE business_id NOT IN (SELECT id FROM businesses)',
      );
      await db.customStatement(
        'DELETE FROM sync_outbox_owners WHERE outbox_id NOT IN (SELECT id FROM sync_outbox)',
      );

      final bad = await db.customSelect('PRAGMA foreign_key_check').get();
      if (bad.isNotEmpty) {
        final details = bad
            .map(
              (r) => '${r.read<String>('table')}→${r.read<String>('parent')}',
            )
            .toSet()
            .join(', ');
        throw BusinessPurgeException(
          'Could not delete: dangling references ($details).',
        );
      }
    }),
  );
}
