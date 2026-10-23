import 'dart:convert';

import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';

final legacyCloudBootstrapServiceProvider =
    Provider<LegacyDataBootstrapService>((ref) {
      final db = ref.watch(databaseProvider);
      final client = ref.watch(supabaseClientProvider);

      return LegacyDataBootstrapService(db: db, client: client);
    });

class LegacyDataBootstrapService {
  final AppDatabase db;
  final SupabaseClient client;

  LegacyDataBootstrapService({required this.db, required this.client});

  static const int _batchSize = 100;

  /// Runs the legacy bootstrap only when:
  ///
  /// 1. The local business has existing accounts/data.
  /// 2. Supabase has no accounts for that business yet.
  ///
  /// Device 2 has zero local accounts, while the cloud already has
  /// accounts, so Device 2 will never upload an empty local database.
  ///
  ///

  Future<bool> bootstrapIfNeeded(String businessId) async {
    for (final t in [
      'product_categories',
      'products',
      'supply_price_history',
      'shopping_carts',
      'shopping_cart_items',
      'recipes',
      'recipe_components',
      'inventory_movements',
      'payment_providers',
      'pos_sessions',
      'pos_sales',
      'pos_sale_items',
      'pos_sale_payments',
      'pos_sale_tenders',
    ]) {
      final cols = await db.customSelect('PRAGMA table_info("$t")').get();
      print(
        '[schema] $t: ${cols.map((r) => "${r.read<String>('name')}:${r.read<String>('type')}").join(", ")}',
      );
    }

    final localAccountCount = await _countLocalBusinessRows(
      table: 'accounts',
      businessId: businessId,
    );

    if (localAccountCount == 0) {
      print(
        '[bootstrap] local business $businessId has no accounts; '
        'nothing to migrate',
      );
      return false;
    }

    final cloudAccountCount = await _countCloudRows(
      table: 'accounts',
      businessId: businessId,
    );

    print(
      '[bootstrap] accounts local=$localAccountCount '
      'cloud=$cloudAccountCount',
    );

    if (cloudAccountCount > 0) {
      print(
        '[bootstrap] cloud already contains business data; '
        'legacy bootstrap skipped',
      );
      return false;
    }

    print('[bootstrap] starting legacy migration for business $businessId');

    await _uploadTableWithBusinessId(
      table: 'businesses',
      businessId: businessId,
    );

    // Parent records first.
    await _uploadTableWithBusinessId(table: 'accounts', businessId: businessId);

    await _uploadTableWithBusinessId(
      table: 'categories',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'customers',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'suppliers',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'journal_entries',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'ledger_lines',
      sql: '''
        SELECT ll.*
        FROM ledger_lines ll
        INNER JOIN journal_entries je
          ON je.id = ll.journal_entry_id
        WHERE je.business_id = ?
      ''',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(table: 'expenses', businessId: businessId);

    await _uploadTableWithBusinessId(
      table: 'income_transactions',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'receivable_payments',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'supplier_purchases',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'payable_payments',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(table: 'supplies', businessId: businessId);

    await _uploadTableWithBusinessId(
      table: 'product_categories',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(table: 'products', businessId: businessId);

    await _uploadChildTable(
      table: 'supply_price_history',
      sql: '''
        SELECT sph.*
        FROM supply_price_history sph
        INNER JOIN supplies s
          ON s.id = sph.supply_id
        WHERE s.business_id = ?
      ''',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'shopping_carts',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'shopping_cart_items',
      sql: '''
        SELECT sci.*
        FROM shopping_cart_items sci
        INNER JOIN shopping_carts sc
          ON sc.id = sci.cart_id
        WHERE sc.business_id = ?
      ''',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'account_transfers',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'recipes',
      sql: '''
        SELECT r.*
        FROM recipes r
        INNER JOIN products p
          ON p.id = r.product_id
        WHERE p.business_id = ?
      ''',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'recipe_components',
      sql: '''
        SELECT rc.*
        FROM recipe_components rc
        INNER JOIN recipes r
          ON r.id = rc.recipe_id
        INNER JOIN products p
          ON p.id = r.product_id
        WHERE p.business_id = ?
      ''',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'inventory_movements',
      sql: '''
        SELECT im.*
        FROM inventory_movements im
        INNER JOIN supplies s
          ON s.id = im.supply_id
        WHERE s.business_id = ?
      ''',
      businessId: businessId,
    );

    // POS / payment infrastructure.
    await _uploadTableWithBusinessId(
      table: 'payment_providers',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'pos_sessions',
      businessId: businessId,
    );

    await _uploadTableWithBusinessId(
      table: 'pos_sales',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'pos_sale_items',
      sql: '''
        SELECT psi.*
        FROM pos_sale_items psi
        INNER JOIN pos_sales ps
          ON ps.id = psi.sale_id
        WHERE ps.business_id = ?
      ''',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'pos_sale_payments',
      sql: '''
        SELECT psp.*
        FROM pos_sale_payments psp
        INNER JOIN pos_sales ps
          ON ps.id = psp.sale_id
        WHERE ps.business_id = ?
      ''',
      businessId: businessId,
    );

    await _uploadChildTable(
      table: 'pos_sale_tenders',
      sql: '''
        SELECT pst.*
        FROM pos_sale_tenders pst
        INNER JOIN pos_sales ps
          ON ps.id = pst.sale_id
        WHERE ps.business_id = ?
      ''',
      businessId: businessId,
    );

    final finalCloudAccounts = await _countCloudRows(
      table: 'accounts',
      businessId: businessId,
    );

    if (finalCloudAccounts == 0) {
      throw StateError(
        'Legacy cloud bootstrap completed without creating cloud accounts.',
      );
    }

    print('[bootstrap] migration completed successfully for $businessId');

    return true;
  }

  // --------------------------------------------------------------------------
  // LOCAL DATA
  // --------------------------------------------------------------------------

  Future<int> _countLocalBusinessRows({
    required String table,
    required String businessId,
  }) async {
    final row = await db
        .customSelect(
          '''
      SELECT COUNT(*) AS c
      FROM "$table"
      WHERE business_id = ?
      ''',
          variables: [Variable.withString(businessId)],
        )
        .getSingle();

    return row.read<int>('c');
  }

  Future<List<Map<String, dynamic>>> _readLocalBusinessRows({
    required String table,
    required String businessId,
  }) async {
    // The businesses table identifies the business by its own
    // primary key (`id`), so it does NOT have a `business_id` column.
    if (table == 'businesses') {
      final rows = await db
          .customSelect(
            '''
          SELECT *
          FROM businesses
          WHERE id = ?
          ''',
            variables: [Variable.withString(businessId)],
          )
          .get();

      return rows
          .map((row) => _serializeRow(table, row.data))
          .toList(growable: false);
    }

    // All other parent tables passed through this method are
    // business-scoped using their `business_id` column.
    final rows = await db
        .customSelect(
          '''
        SELECT *
        FROM "$table"
        WHERE business_id = ?
        ORDER BY id
        ''',
          variables: [Variable.withString(businessId)],
        )
        .get();

    return rows
        .map((row) => _serializeRow(table, row.data))
        .toList(growable: false);
  }

  // --------------------------------------------------------------------------
  // CLOUD COUNTS
  // --------------------------------------------------------------------------

  Future<int> _countCloudRows({
    required String table,
    required String businessId,
  }) async {
    final response = await client
        .from(table)
        .select('id')
        .eq('business_id', businessId);

    return response.length;
  }

  // --------------------------------------------------------------------------
  // UPLOAD
  // --------------------------------------------------------------------------

  Future<void> _uploadTableWithBusinessId({
    required String table,
    required String businessId,
  }) async {
    final rows = await _readLocalBusinessRows(
      table: table,
      businessId: businessId,
    );

    if (rows.isEmpty) {
      print('[bootstrap] $table = 0 rows');
      return;
    }

    print('[bootstrap] uploading $table = ${rows.length} rows');

    await _upsertInBatches(table: table, rows: rows);
  }

  Future<void> _uploadChildTable({
    required String table,
    required String sql,
    required String businessId,
  }) async {
    final rows = await db
        .customSelect(sql, variables: [Variable.withString(businessId)])
        .get();

    final serialized = rows
        .map((row) => _serializeRow(table, row.data))
        .toList(growable: false);

    if (serialized.isEmpty) {
      print('[bootstrap] $table = 0 rows');
      return;
    }

    print('[bootstrap] uploading $table = ${serialized.length} rows');

    await _upsertInBatches(table: table, rows: serialized);
  }

  Future<void> _upsertInBatches({
    required String table,
    required List<Map<String, dynamic>> rows,
  }) async {
    for (var start = 0; start < rows.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, rows.length);
      final batch = rows.sublist(start, end);

      await client.from(table).upsert(batch, onConflict: 'id');

      print(
        '[bootstrap] $table uploaded '
        '$end/${rows.length}',
      );
    }
  }

  // --------------------------------------------------------------------------
  // SQLITE -> POSTGRES JSON NORMALIZATION
  // --------------------------------------------------------------------------

  Map<String, dynamic> _serializeRow(String table, Map<String, dynamic> row) {
    final result = <String, dynamic>{};

    for (final entry in row.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value == null) {
        result[key] = null;
        continue;
      }

      // Drift DateTime values.
      if (value is DateTime) {
        result[key] = value.toUtc().toIso8601String();
        continue;
      }

      // SQLite stores Drift booleans as INTEGER 0/1.
      if (_booleanColumns.contains(key)) {
        if (value is bool) {
          result[key] = value;
        } else if (value is num) {
          result[key] = value != 0;
        } else {
          result[key] = value;
        }
        continue;
      }

      // If an older/local implementation stored JSON as a Dart
      // Map/List, turn it into JSON text only for columns that are
      // represented as text in the application.
      if (value is Map || value is List) {
        result[key] = jsonEncode(value);
        continue;
      }

      result[key] = value;
    }

    // DateTime values may arrive through customSelect as INTEGER rather
    // than Dart DateTime. Convert known timestamp columns.
    for (final key in _dateTimeColumns) {
      final value = result[key];

      if (value is int && value > 0) {
        result[key] = DateTime.fromMillisecondsSinceEpoch(
          value * 1000,
          isUtc: true,
        ).toIso8601String();
      } else if (value is num && value > 0) {
        result[key] = DateTime.fromMillisecondsSinceEpoch(
          value.toInt() * 1000,
          isUtc: true,
        ).toIso8601String();
      }
    }

    return result;
  }

  static const Set<String> _booleanColumns = {
    'is_active',
    'is_custom',
    'is_payment_account',
    'is_on_credit',
    'is_sellable',
    'is_stock_only',
    'is_voided',
    'is_weighted',
    'is_sold_by_weight',
  };

  static const Set<String> _dateTimeColumns = {
    'created_at',
    'updated_at',
    'entry_date',
    'txn_date',
    'payment_date',
    'purchase_date',
    'expense_date',
    'recorded_date',
    'cart_date',
    'movement_date',
    'sale_date',
    'paid_at',
    'opened_at',
    'closed_at',
    'voided_at',
  };
}
