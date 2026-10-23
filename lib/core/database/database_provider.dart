// lib/core/database/database_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../sync/sync_tracker.dart';
import 'app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  SyncTracker.bind(db);
  ref.onDispose(() => db.close());
  return db;
});
