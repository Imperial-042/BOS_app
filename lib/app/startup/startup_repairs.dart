// lib/app/startup/startup_repairs.dart
//
// One-time local data repairs run at startup. Each is guarded by a
// SharedPreferences flag, so it runs once per account / device.

import 'dart:async';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/sync_change_log.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time repair: stamps old sales that have no cashier with the owner.
/// Runs once per account on this device.
Future<void> backfillCashiers(AppDatabase db, String userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'cashier_backfill_v1:$userId';
    if (prefs.getBool(key) ?? false) return;

    final user = await (db.select(
      db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) return;

    final name = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : user.email;

    await db.customStatement(
      'UPDATE pos_sales SET cashier_user_id = ?, cashier_name = ? '
      "WHERE cashier_user_id IS NULL AND (cashier_name IS NULL OR cashier_name = '')",
      [userId, name],
    );

    await prefs.setBool(key, true);
    debugPrint('[backfill] cashier stamped on old sales');
  } catch (e) {
    debugPrint('[backfill] cashier backfill skipped: $e');
  }
}

/// One-time repair: ISO date strings that an earlier pull wrote into
/// INTEGER columns are converted back to Unix seconds.
Future<void> repairTextTimestamps(AppDatabase db) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const flag = 'ts_repair_v1';
    if (prefs.getBool(flag) ?? false) return;

    await SyncChangeLog.suppressed(db, () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'sync_%'",
          )
          .get();

      for (final t in tables) {
        final table = t.read<String>('name');
        final cols = await db
            .customSelect('PRAGMA table_info("$table")')
            .get();
        for (final c in cols) {
          final col = c.read<String>('name');
          if (c.read<String>('type').toUpperCase() != 'INTEGER') continue;
          const test =
              "typeof(\"COL\") = 'text' AND \"COL\" LIKE '____-__-__%'";
          final where = test.replaceAll('COL', col);
          final bad = await db
              .customSelect('SELECT COUNT(*) AS n FROM "$table" WHERE $where')
              .getSingle();
          final n = bad.read<int>('n');
          if (n == 0) continue;
          debugPrint('[repair] $table.$col: $n rows');
          await db.customStatement(
            'UPDATE "$table" SET "$col" = '
            "CAST(strftime('%s', \"$col\") AS INTEGER) WHERE $where",
          );
        }
      }
    });

    await prefs.setBool(flag, true);
  } catch (e) {
    debugPrint('[repair] timestamp repair skipped: $e');
  }
}
