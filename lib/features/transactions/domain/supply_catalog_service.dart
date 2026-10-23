// lib/features/transactions/domain/supply_catalog_service.dart
//
// SKU / barcode / category handling for SUPPLIES — the raw materials
// and stocked items in the price catalog. Mirrors
// ProductCatalogService so both halves of the catalog behave the same.

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Thrown when a SKU or barcode already belongs to another supply in
/// the same business. Carries the conflicting row so the UI can name it.
class DuplicateSupplyCodeException implements Exception {
  final String field; // 'SKU' | 'Barcode'
  final String value;
  final Supply existing;

  DuplicateSupplyCodeException({
    required this.field,
    required this.value,
    required this.existing,
  });

  @override
  String toString() => '$field "$value" is already used by ${existing.name}.';
}

class SupplyCatalogService {
  final AppDatabase db;
  final String businessId;

  SupplyCatalogService(this.db, {required this.businessId});

  // ---------- normalisation ----------

  /// One canonical form: trimmed, upper-cased, inner whitespace to dash.
  static String? normalizeSku(String? raw) {
    final v = (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '-');
    return v.isEmpty ? null : v;
  }

  /// Scanners sometimes append control characters — strip those and
  /// any whitespace, but otherwise keep the payload verbatim.
  static String? normalizeBarcode(String? raw) {
    final v = (raw ?? '').trim().replaceAll(RegExp(r'[\s\u0000-\u001f]'), '');
    return v.isEmpty ? null : v;
  }

  // ---------- uniqueness ----------

  Future<Supply?> findBySku(String? sku, {String? excludeId}) async {
    final value = normalizeSku(sku);
    if (value == null) return null;

    final q = db.select(db.supplies)
      ..where((s) => s.businessId.equals(businessId) & s.sku.equals(value));
    if (excludeId != null) {
      q.where((s) => s.id.equals(excludeId).not());
    }
    return q.getSingleOrNull();
  }

  Future<Supply?> findByBarcode(String? barcode, {String? excludeId}) async {
    final value = normalizeBarcode(barcode);
    if (value == null) return null;

    final q = db.select(db.supplies)
      ..where((s) => s.businessId.equals(businessId) & s.barcode.equals(value));
    if (excludeId != null) {
      q.where((s) => s.id.equals(excludeId).not());
    }
    return q.getSingleOrNull();
  }

  Future<bool> isSkuAvailable(String? sku, {String? excludeId}) async =>
      await findBySku(sku, excludeId: excludeId) == null;

  Future<bool> isBarcodeAvailable(String? code, {String? excludeId}) async =>
      await findByBarcode(code, excludeId: excludeId) == null;

  /// Throws [DuplicateSupplyCodeException] when either code collides.
  /// Call this before any insert or update that sets a code.
  Future<void> assertCodesFree({
    String? sku,
    String? barcode,
    String? excludeId,
  }) async {
    final skuClash = await findBySku(sku, excludeId: excludeId);
    if (skuClash != null) {
      throw DuplicateSupplyCodeException(
        field: 'SKU',
        value: normalizeSku(sku)!,
        existing: skuClash,
      );
    }

    final barcodeClash = await findByBarcode(barcode, excludeId: excludeId);
    if (barcodeClash != null) {
      throw DuplicateSupplyCodeException(
        field: 'Barcode',
        value: normalizeBarcode(barcode)!,
        existing: barcodeClash,
      );
    }
  }

  /// Suggests the next free SKU for a prefix, e.g. "FLR" → "FLR-004".
  Future<String> suggestSku(String prefix) async {
    final clean = normalizeSku(prefix) ?? 'SKU';
    final rows =
        await (db.select(db.supplies)..where(
              (s) => s.businessId.equals(businessId) & s.sku.like('$clean-%'),
            ))
            .get();

    var highest = 0;
    for (final row in rows) {
      final n = int.tryParse(row.sku!.split('-').last);
      if (n != null && n > highest) highest = n;
    }

    return '$clean-${(highest + 1).toString().padLeft(3, '0')}';
  }

  // ---------- lookup ----------

  /// Scanner path: exact barcode (index-backed), then exact SKU, then a
  /// unique name match. Null when nothing — or more than one thing — hits.
  Future<Supply?> lookupForPos(String scanned) async {
    final code = scanned.trim();
    if (code.isEmpty) return null;

    final byBarcode = await findByBarcode(code);
    if (byBarcode != null) return byBarcode;

    final bySku = await findBySku(code);
    if (bySku != null) return bySku;

    final byName =
        await (db.select(db.supplies)..where(
              (s) =>
                  s.businessId.equals(businessId) &
                  s.isActive.equals(true) &
                  s.name.lower().equals(code.toLowerCase()),
            ))
            .get();

    return byName.length == 1 ? byName.first : null;
  }

  Future<void> assignCategory(String supplyId, String? categoryId) {
    return (db.update(db.supplies)..where((s) => s.id.equals(supplyId))).write(
      SuppliesCompanion(
        categoryId: Value(categoryId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// How many active supplies sit in each category (key '' = uncategorized).
  Future<Map<String, int>> categoryCounts() async {
    final count = db.supplies.id.count();
    final rows =
        await (db.selectOnly(db.supplies)
              ..addColumns([db.supplies.categoryId, count])
              ..where(
                db.supplies.businessId.equals(businessId) &
                    db.supplies.isActive.equals(true),
              )
              ..groupBy([db.supplies.categoryId]))
            .get();

    return {
      for (final row in rows)
        row.read(db.supplies.categoryId) ?? '': row.read(count) ?? 0,
    };
  }
}
