// lib/core/sync/business_export_service.dart
//
// Deterministic, service-level export of one business's full dataset as
// JSON. Preserves stable UUIDs, relationships, timestamps, and business
// ownership, in a fixed parent-before-child order. This is the migration /
// backup / support foundation — later Supabase import can replay it.
//
// Deliberately NOT tied to the CSV Import/Export screen, which stays a
// human-readable spreadsheet surface. This export is machine-grade.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';

/// Parent-before-child: inserting in this order satisfies every foreign
/// key. Businesses lead, then account/category masters, then parties, then
/// the transactional/ledger records that reference them.
const _exportOrder = <String>[
  'businesses',
  'accounts',
  'categories',
  'product_categories',
  'customers',
  'suppliers',
  'payment_providers',
  'supplies',
  'supply_unit_conversions',
  'products',
  'recipes',
  'recipe_components',
  'income_transactions',
  'expenses',
  'receivable_payments',
  'payable_payments',
  'supplier_purchases',
  'account_transfers',
  'shopping_carts',
  'shopping_cart_items',
  'supply_price_history',
  'inventory_movements',
  'pos_sessions',
  'pos_sales',
  'pos_sale_items',
  'pos_sale_payments',
  'pos_sale_tenders',
  'journal_entries',
  'ledger_lines',
  'business_members',
  'business_invites',
  'business_module_configs',
  'role_permission_overrides',
  'audit_logs',
  'sync_outbox',
];

class BusinessExportService {
  final AppDatabase db;
  BusinessExportService(this.db);

  /// One business's rows, keyed by table name, in [_exportOrder]. Every row
  /// is the raw column map, so IDs and FKs survive intact. Deterministic:
  /// rows are ordered by primary key inside each table.
  Future<Map<String, List<Map<String, Object?>>>> exportBusiness(
    String businessId,
  ) async {
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in _exportOrder) {
      result[table] = await _exportTable(table, businessId);
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _exportTable(
    String table,
    String businessId,
  ) async {
    // Businesses row itself: just the one row, no business_id filter.
    if (table == 'businesses') {
      final rows = await db
          .customSelect(
            'SELECT * FROM businesses WHERE id = ?',
            variables: [Variable.withString(businessId)],
          )
          .get();
      return [for (final r in rows) r.data];
    }

    // Child tables without a business_id column are pulled through their
    // business-owned parent via a parameterized subquery.
    final parentSql = _childParentSql(table);
    final sql = parentSql != null
        ? 'SELECT * FROM $table WHERE $parentSql ORDER BY ${_primaryKeyOf(table)}'
        : 'SELECT * FROM $table WHERE business_id = ? ORDER BY ${_primaryKeyOf(table)}';

    final rows = await db
        .customSelect(sql, variables: [Variable.withString(businessId)])
        .get();
    return [for (final r in rows) r.data];
  }

  /// Parameterized subquery for child tables that don't carry their own
  /// business_id. Always takes exactly one `?` bound to the business id.
  String? _childParentSql(String table) {
    switch (table) {
      case 'supply_price_history':
      case 'supply_unit_conversions':
      case 'inventory_movements':
        return 'supply_id IN (SELECT id FROM supplies WHERE business_id = ?)';
      case 'shopping_cart_items':
        return 'cart_id IN (SELECT id FROM shopping_carts WHERE business_id = ?)';
      case 'recipes':
        return 'product_id IN (SELECT id FROM products WHERE business_id = ?)';
      case 'recipe_components':
        return 'recipe_id IN (SELECT id FROM recipes WHERE product_id IN '
            '(SELECT id FROM products WHERE business_id = ?))';
      case 'pos_sale_items':
      case 'pos_sale_payments':
      case 'pos_sale_tenders':
        return 'sale_id IN (SELECT id FROM pos_sales WHERE business_id = ?)';
      case 'ledger_lines':
        return 'journal_entry_id IN (SELECT id FROM journal_entries WHERE business_id = ?)';
      default:
        return null;
    }
  }

  String _primaryKeyOf(String table) {
    switch (table) {
      case 'supply_unit_conversions':
        return 'supply_id, unit_name';
      default:
        return 'id';
    }
  }
}

final businessExportServiceProvider = Provider<BusinessExportService>(
  (ref) => BusinessExportService(ref.watch(databaseProvider)),
);
