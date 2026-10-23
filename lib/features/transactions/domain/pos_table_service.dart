// Restaurant tables.

import 'dart:math' as math;

import 'package:bos_application/core/auth/authorization_providers.dart'
    show selectedBusinessIdProvider;
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class PosTableService {
  final AppDatabase db;
  PosTableService(this.db);

  Future<List<PosTable>> _all(String businessId) => (db.select(
    db.posTables,
  )..where((t) => t.businessId.equals(businessId))).get();

  int _seats(int v) {
    if (v < 1 || v > 99) throw StateError('Seats must be between 1 and 99.');
    return v;
  }

  int _nextSort(List<PosTable> all) =>
      all.isEmpty ? 0 : all.map((t) => t.sortOrder).reduce(math.max) + 1;

  Future<void> add(
    String businessId, {
    required String name,
    int seats = 4,
    String? section,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw StateError('Enter a table name.');
    final all = await _all(businessId);
    if (all.any((t) => t.name.toLowerCase() == clean.toLowerCase())) {
      throw StateError('"$clean" already exists.');
    }
    final sec = section?.trim();
    await db
        .into(db.posTables)
        .insert(
          PosTablesCompanion.insert(
            id: const Uuid().v4(),
            businessId: businessId,
            name: clean,
            seats: Value(_seats(seats)),
            section: Value((sec == null || sec.isEmpty) ? null : sec),
            sortOrder: Value(_nextSort(all)),
          ),
        );
  }

  /// "Table 1 ... Table N", continuing after the highest existing number.
  Future<int> addSeries(
    String businessId, {
    String prefix = 'Table',
    required int count,
    int seats = 4,
  }) async {
    if (count < 1 || count > 100) {
      throw StateError('Add between 1 and 100 tables at a time.');
    }
    _seats(seats);
    final all = await _all(businessId);
    final re = RegExp(
      '^${RegExp.escape(prefix)} (\\d+)\$',
      caseSensitive: false,
    );
    var n = 0;
    for (final t in all) {
      final m = re.firstMatch(t.name);
      if (m != null) n = math.max(n, int.parse(m.group(1)!));
    }
    var sort = _nextSort(all);
    for (var i = 1; i <= count; i++) {
      await db
          .into(db.posTables)
          .insert(
            PosTablesCompanion.insert(
              id: const Uuid().v4(),
              businessId: businessId,
              name: '$prefix ${n + i}',
              seats: Value(seats),
              sortOrder: Value(sort++),
            ),
          );
    }
    return count;
  }

  Future<void> update(
    PosTable t, {
    required String name,
    required int seats,
    String? section,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw StateError('Enter a table name.');
    final all = await _all(t.businessId);
    if (all.any(
      (x) => x.id != t.id && x.name.toLowerCase() == clean.toLowerCase(),
    )) {
      throw StateError('"$clean" already exists.');
    }
    final sec = section?.trim();
    await (db.update(db.posTables)..where((x) => x.id.equals(t.id))).write(
      PosTablesCompanion(
        name: Value(clean),
        seats: Value(_seats(seats)),
        section: Value((sec == null || sec.isEmpty) ? null : sec),
      ),
    );
  }

  Future<void> setActive(PosTable t, bool active) =>
      (db.update(db.posTables)..where((x) => x.id.equals(t.id))).write(
        PosTablesCompanion(isActive: Value(active)),
      );

  Future<void> delete(PosTable t) =>
      (db.delete(db.posTables)..where((x) => x.id.equals(t.id))).go();
}

final posTableServiceProvider = Provider<PosTableService>(
  (ref) => PosTableService(ref.watch(databaseProvider)),
);

final allPosTablesProvider = StreamProvider<List<PosTable>>((ref) {
  final businessId = ref.watch(selectedBusinessIdProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.posTables)
        ..where((t) => t.businessId.equals(businessId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.name),
        ]))
      .watch();
});
