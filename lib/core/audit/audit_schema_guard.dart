// lib/core/audit/audit_schema_guard.dart
//
// Local append-only protection + lookup indexes for audit_logs.
// Install from AppDatabase.beforeOpen AFTER SyncChangeLog.install (it reads
// sync_context). App code cannot UPDATE/DELETE audit rows; the sync pull
// runs with sync_context.suppress = 1 and is therefore the only writer that
// may touch an existing row (to apply the cloud copy).
//
// Note: this protects against app-level bugs/misuse, not against someone
// with direct file access to the SQLite database. The authoritative
// tamper-resistant copy is the server (see the Supabase migration).

import '../database/app_database.dart';

abstract final class AuditSchemaGuard {
  static Future<void> install(AppDatabase db) async {
    const indexes = [
      'CREATE INDEX IF NOT EXISTS ix_audit_logs_business_module '
          'ON audit_logs (business_id, module, created_at)',
      'CREATE INDEX IF NOT EXISTS ix_audit_logs_business_user '
          'ON audit_logs (business_id, user_id, created_at)',
      'CREATE INDEX IF NOT EXISTS ix_audit_logs_entity '
          'ON audit_logs (business_id, entity_type, entity_id)',
    ];
    for (final sql in indexes) {
      await db.customStatement(sql);
    }

    for (final (suffix, event) in const [
      ('update', 'UPDATE'),
      ('delete', 'DELETE'),
    ]) {
      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS audit_logs_no_$suffix
        BEFORE $event ON audit_logs
        WHEN (SELECT suppress FROM sync_context WHERE id = 1) = 0
        BEGIN
          SELECT RAISE(ABORT, 'audit_logs is append-only');
        END
      ''');
    }
  }
}
