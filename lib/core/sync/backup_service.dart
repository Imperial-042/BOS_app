// lib/core/sync/backup_service.dart
//
// Backup / restore. Backup reuses the deterministic BusinessExportService to
// write the full business dataset as JSON to a shareable file. Restore reads
// such a file back into Drift inside one transaction, keyed by stable UUIDs
// (insert-or-ignore per row), so restoring never duplicates existing rows
// and can be re-run safely.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'business_export_service.dart'
    show BusinessExportService, businessExportTables;

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => message;
}

class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  /// Export the business to a timestamped JSON file and share it.
  Future<void> backupBusiness(String businessId) async {
    final data = await BusinessExportService(db).exportBusiness(businessId);
    final json = const JsonEncoder.withIndent('  ').convert({
      'format': 'bos-backup',
      'version': 1,
      'businessId': businessId,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': data,
    });

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bos_backup_$businessId.json');
    await file.writeAsString(json);

    await Share.shareXFiles([
      XFile(file.path, mimeType: 'application/json'),
    ], subject: 'BOS backup');
  }

  /// Restore a backup file into the CURRENT business context. Validates the
  /// format and only restores rows whose businessId matches this business —
  /// a backup can never inject another business's data.
  Future<int> restoreBusiness(String businessId, String jsonText) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic> || decoded['format'] != 'bos-backup') {
      throw const BackupException('That file is not a valid BOS backup.');
    }
    if (decoded['businessId'] != businessId) {
      throw const BackupException(
        'This backup belongs to a different business.',
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const BackupException('The backup has no data.');
    }
    final unknownTables = data.keys
        .where((table) => !businessExportTables.contains(table))
        .toList();
    if (unknownTables.isNotEmpty) {
      throw const BackupException(
        'The backup contains unsupported data tables.',
      );
    }

    var restored = 0;
    await db.transaction(() async {
      for (final table in businessExportTables) {
        final rows = data[table];
        if (rows == null) continue;
        if (rows is! List) {
          throw BackupException('Invalid rows for table "$table".');
        }
        // Sync operations belong to this installation, not the restored data.
        if (table == 'sync_outbox') continue;

        final info = await db.customSelect('PRAGMA table_info("$table")').get();
        final tableColumns = info
            .map((row) => row.read<String>('name'))
            .toSet();

        for (final rawRow in rows) {
          if (rawRow is! Map || rawRow.keys.any((key) => key is! String)) {
            throw BackupException('Invalid row in table "$table".');
          }
          final row = Map<String, Object?>.from(rawRow);
          final primaryKeys = _primaryKeyColumns(table);
          if (primaryKeys.any((key) => row[key] == null)) {
            throw BackupException('A row in "$table" is missing its key.');
          }
          if (row.keys.any((column) => !tableColumns.contains(column))) {
            throw BackupException('A row in "$table" has unknown columns.');
          }
          if (!await _belongsToBusiness(db, table, row, businessId)) {
            throw const BackupException(
              'The backup contains records outside the current business.',
            );
          }

          // Restoring is idempotent; existing rows are left unchanged.
          final columns = row.keys.toList();
          final placeholders = List.filled(columns.length, '?').join(', ');
          final quotedColumns = columns.map(_quoteIdentifier).join(', ');
          final values = [
            for (final column in columns) _toDbValue(row[column]),
          ];
          await db.customStatement(
            'INSERT OR IGNORE INTO ${_quoteIdentifier(table)} '
            '($quotedColumns) VALUES ($placeholders)',
            values,
          );
          final changes = await db
              .customSelect('SELECT changes() AS count')
              .getSingle();
          restored += changes.read<int>('count');
        }
      }
    });
    return restored;
  }

  Future<bool> _belongsToBusiness(
    AppDatabase db,
    String table,
    Map<String, Object?> row,
    String businessId,
  ) async {
    if (table == 'businesses') return row['id'] == businessId;
    if (row.containsKey('business_id')) {
      return row['business_id'] == businessId;
    }

    final parent = switch (table) {
      'supply_price_history' ||
      'supply_unit_conversions' ||
      'inventory_movements' => (
        'SELECT 1 FROM supplies WHERE id = ? AND business_id = ?',
        'supply_id',
      ),
      'shopping_cart_items' => (
        'SELECT 1 FROM shopping_carts WHERE id = ? AND business_id = ?',
        'cart_id',
      ),
      'recipes' => (
        'SELECT 1 FROM products WHERE id = ? AND business_id = ?',
        'product_id',
      ),
      'recipe_components' => (
        'SELECT 1 FROM recipes r '
            'JOIN products p ON p.id = r.product_id '
            'WHERE r.id = ? AND p.business_id = ?',
        'recipe_id',
      ),
      'pos_sale_items' || 'pos_sale_payments' || 'pos_sale_tenders' => (
        'SELECT 1 FROM pos_sales WHERE id = ? AND business_id = ?',
        'sale_id',
      ),
      'pos_return_items' => (
        'SELECT 1 FROM pos_returns WHERE id = ? AND business_id = ?',
        'return_id',
      ),
      'payroll_items' => (
        'SELECT 1 FROM payroll_runs WHERE id = ? AND business_id = ?',
        'run_id',
      ),
      'stock_transfer_items' => (
        'SELECT 1 FROM stock_transfers WHERE id = ? AND business_id = ?',
        'transfer_id',
      ),
      'ledger_lines' => (
        'SELECT 1 FROM journal_entries WHERE id = ? AND business_id = ?',
        'journal_entry_id',
      ),
      _ => null,
    };
    if (parent == null) {
      throw BackupException('Cannot validate ownership for table "$table".');
    }
    final parentId = row[parent.$2];
    if (parentId == null) return false;
    final result = await db
        .customSelect(
          parent.$1,
          variables: [
            Variable.withString(parentId.toString()),
            Variable.withString(businessId),
          ],
        )
        .getSingleOrNull();
    return result != null;
  }

  List<String> _primaryKeyColumns(String table) => switch (table) {
    'supply_unit_conversions' => ['supply_id', 'unit_name'],
    _ => ['id'],
  };

  String _quoteIdentifier(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';

  /// Drift stores booleans as 0/1 and DateTimes as ISO strings; the export
  /// produces raw column maps, so values pass through unchanged. This only
  /// normalizes any nested non-scalar just in case.
  Object? _toDbValue(Object? value) {
    if (value == null || value is num || value is String) return value;
    if (value is bool) return value ? 1 : 0;
    return value.toString();
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
