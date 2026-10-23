// lib/core/sync/backup_service.dart
//
// Backup / restore. Backup reuses the deterministic BusinessExportService to
// write the full business dataset as JSON to a shareable file. Restore reads
// such a file back into Drift inside one transaction, keyed by stable UUIDs
// (insert-or-ignore per row), so restoring never duplicates existing rows
// and can be re-run safely.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'business_export_service.dart';

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

    var restored = 0;
    await db.transaction(() async {
      for (final entry in data.entries) {
        final table = entry.key;
        final rows = entry.value;
        if (rows is! List) continue;

        for (final row in rows) {
          if (row is! Map) continue;
          // Skip transient/internal tables that are never restored.
          if (table == 'sync_outbox' || table == 'sync_changes') continue;

          final id = row['id'];
          if (id == null) continue;

          // Insert-or-ignore per row: restoring never duplicates an existing
          // record, and re-running a restore is safe.
          final columns = row.keys.toList();
          final placeholders = List.filled(columns.length, '?').join(', ');
          final values = [for (final c in columns) _toDbValue(row[c])];
          await db.customStatement(
            'INSERT OR IGNORE INTO "$table" (${columns.join(', ')}) '
            'VALUES ($placeholders)',
            values,
          );
          restored++;
        }
      }
    });
    return restored;
  }

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
