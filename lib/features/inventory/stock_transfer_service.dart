// lib/features/inventory/stock_transfer_service.dart  (NEW FILE)
//
// Move stock between branches of the SAME business.
//
//   ship    : sender creates the transfer; stock leaves the source branch
//             immediately (transfer_out movements). Status: in_transit.
//   receive : receiving branch confirms what arrived (transfer_in movements).
//   cancel  : sender takes it back while still in transit (transfer_cancel).
//
// Every movement id is DETERMINISTIC (derived from the transfer item id), so a
// retry, a double tap or two devices doing the same step never duplicates
// stock: the second insert of the same id is ignored.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart'
    show AuditLogger;
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';

const _uuid = Uuid();

class TransferLine {
  const TransferLine({
    required this.itemType, // 'supply' | 'product'
    required this.itemId,
    required this.name,
    required this.unit,
    required this.quantity,
  });
  final String itemType;
  final String itemId;
  final String name;
  final String unit;
  final double quantity;
}

String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class StockTransferService {
  StockTransferService(this.db, this.auth, this.stock, this.allowedBranchIds);

  final AppDatabase db;
  final AuthorizationService auth;
  final StockService stock;
  final Set<String> allowedBranchIds;

  String _mid(String kind, String itemId, bool supply) =>
      AppDatabase.cloudCompatibleDefaultId(
        supply ? 'inventory_movements' : 'product_stock_movements',
        '${kind}_$itemId',
      );

  Future<void> _move({
    required StockTransferItem item,
    required String branchId,
    required String kind, // tout | tin | tcancel
    required String type, // transfer_out | transfer_in | transfer_cancel
    required double quantity,
    required String transferId,
  }) {
    final isSupply = item.itemType == 'supply';
    final id = _mid(kind, item.id, isSupply);
    return isSupply
        ? stock.moveSupply(
            branchId: branchId,
            supplyId: item.itemId,
            type: type,
            unit: item.unit,
            quantity: quantity,
            referenceType: 'stock_transfer',
            referenceId: transferId,
            id: id,
          )
        : stock.moveProduct(
            branchId: branchId,
            productId: item.itemId,
            businessId: item.businessId,
            type: type,
            quantity: quantity,
            referenceType: 'stock_transfer',
            referenceId: transferId,
            id: id,
          );
  }

  // ------------------------------------------------------------------ ship --

  Future<String> createAndShip({
    required String businessId,
    required String fromBranchId,
    required String toBranchId,
    required List<TransferLine> lines,
    String? notes,
  }) async {
    auth.require(BosPermission.stockTransferCreate, businessId: businessId);
    if (!allowedBranchIds.contains(fromBranchId)) {
      throw const PermissionDeniedException(
        'You are not assigned to this branch.',
      );
    }
    if (fromBranchId == toBranchId) {
      throw StateError('Choose a different destination branch.');
    }
    if (lines.isEmpty) throw StateError('Add at least one item.');
    final seen = <String>{};
    for (final l in lines) {
      if (!l.quantity.isFinite || l.quantity <= 0) {
        throw StateError('Enter a valid quantity for ${l.name}.');
      }
      if (l.itemType != 'supply' && l.itemType != 'product') {
        throw StateError('Unsupported item type for ${l.name}.');
      }
      if (!seen.add('${l.itemType}:${l.itemId}')) {
        throw StateError('${l.name} is listed twice.');
      }
    }

    final transferId = _uuid.v4();
    await db.transaction(() async {
      final from =
          await (db.select(db.branches)..where(
                (b) =>
                    b.id.equals(fromBranchId) &
                    b.businessId.equals(businessId) &
                    b.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (from == null) {
        throw StateError('That source branch is not available.');
      }
      final to =
          await (db.select(db.branches)..where(
                (b) =>
                    b.id.equals(toBranchId) &
                    b.businessId.equals(businessId) &
                    b.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (to == null) {
        throw StateError('That destination branch is not available.');
      }

      for (final l in lines) {
        if (l.itemType == 'supply') {
          final item =
              await (db.select(db.supplies)..where(
                    (s) =>
                        s.id.equals(l.itemId) &
                        s.businessId.equals(businessId) &
                        s.isActive.equals(true),
                  ))
                  .getSingleOrNull();
          if (item == null) {
            throw StateError('${l.name} is not an active supply here.');
          }
        } else {
          final item =
              await (db.select(db.products)..where(
                    (p) =>
                        p.id.equals(l.itemId) &
                        p.businessId.equals(businessId) &
                        p.isActive.equals(true) &
                        p.trackingType.equals('stocked'),
                  ))
                  .getSingleOrNull();
          if (item == null) {
            throw StateError(
              '${l.name} is not an active stocked product here.',
            );
          }
        }

        final onHand = l.itemType == 'supply'
            ? await stock.supplyQty(fromBranchId, l.itemId)
            : await stock.productQty(fromBranchId, l.itemId);
        if (onHand + 1e-9 < l.quantity) {
          throw StateError(
            'Not enough ${l.name} here: have ${_n(onHand)} ${l.unit}, '
            'sending ${_n(l.quantity)}.',
          );
        }
      }

      final now = DateTime.now();
      await db
          .into(db.stockTransfers)
          .insert(
            StockTransfersCompanion.insert(
              id: transferId,
              businessId: businessId,
              fromBranchId: fromBranchId,
              toBranchId: toBranchId,
              notes: Value((notes ?? '').trim().isEmpty ? null : notes!.trim()),
              createdBy: Value(auth.userId),
              shippedAt: Value(now),
            ),
          );

      for (final l in lines) {
        final itemId = _uuid.v4();
        await db
            .into(db.stockTransferItems)
            .insert(
              StockTransferItemsCompanion.insert(
                id: itemId,
                businessId: businessId,
                transferId: transferId,
                itemType: l.itemType,
                itemId: l.itemId,
                itemName: l.name,
                unit: Value(l.unit),
                quantity: l.quantity,
              ),
            );
        final item = await (db.select(
          db.stockTransferItems,
        )..where((i) => i.id.equals(itemId))).getSingle();
        await _move(
          item: item,
          branchId: fromBranchId,
          kind: 'tout',
          type: 'transfer_out',
          quantity: -l.quantity,
          transferId: transferId,
        );
      }

      await AuditLogger.record(
        db,
        businessId: businessId,
        userId: auth.userId,
        action: 'inventory.stock_transfer_shipped',
        module: AuditModule.inventory,
        actionType: AuditActionType.create,
        entityType: 'stock_transfers',
        entityId: transferId,
        entityLabel: 'Transfer to ${to.name}',
        details: {
          'from': fromBranchId,
          'fromName': from.name,
          'to': toBranchId,
          'toName': to.name,
          'items': [
            for (final l in lines)
              {
                'itemId': l.itemId,
                'itemType': l.itemType,
                'name': l.name,
                'unit': l.unit,
                'shipped': l.quantity,
              },
          ],
        },
      );
    });
    return transferId;
  }

  // --------------------------------------------------------------- receive --

  /// [receivedByItemId] maps transfer-item id -> quantity that actually
  /// arrived (default: everything). Less than shipped = shortage.
  Future<void> receive(
    String transferId,
    Map<String, double> receivedByItemId,
  ) async {
    await db.transaction(() async {
      final t = await (db.select(
        db.stockTransfers,
      )..where((x) => x.id.equals(transferId))).getSingle();
      auth.require(
        BosPermission.stockTransferReceive,
        businessId: t.businessId,
      );
      if (!allowedBranchIds.contains(t.toBranchId)) {
        throw const PermissionDeniedException(
          'Only the receiving branch can receive this transfer.',
        );
      }
      if (t.status != 'in_transit') {
        throw StateError('This transfer is already ${t.status}.');
      }
      final items = await (db.select(
        db.stockTransferItems,
      )..where((i) => i.transferId.equals(transferId))).get();

      final receivedItems = <Map<String, Object?>>[];
      final shortages = <Map<String, Object?>>[];
      for (final it in items) {
        final got = receivedByItemId[it.id] ?? it.quantity;
        if (!got.isFinite || got < 0 || got > it.quantity + 1e-9) {
          throw StateError(
            'Received quantity for ${it.itemName} must be between 0 and '
            '${_n(it.quantity)}.',
          );
        }
        if (got > 0) {
          await _move(
            item: it,
            branchId: t.toBranchId,
            kind: 'tin',
            type: 'transfer_in',
            quantity: got,
            transferId: transferId,
          );
        }
        if (got + 1e-9 < it.quantity) {
          shortages.add({
            'itemId': it.itemId,
            'itemType': it.itemType,
            'name': it.itemName,
            'unit': it.unit,
            'shipped': it.quantity,
            'received': got,
          });
        }
        receivedItems.add({
          'itemId': it.itemId,
          'itemType': it.itemType,
          'name': it.itemName,
          'unit': it.unit,
          'shipped': it.quantity,
          'received': got,
        });
        await (db.update(db.stockTransferItems)
              ..where((i) => i.id.equals(it.id)))
            .write(StockTransferItemsCompanion(receivedQuantity: Value(got)));
      }

      final now = DateTime.now();
      await (db.update(
        db.stockTransfers,
      )..where((x) => x.id.equals(transferId))).write(
        StockTransfersCompanion(
          status: const Value('received'),
          receivedAt: Value(now),
          receivedBy: Value(auth.userId),
          updatedAt: Value(now),
        ),
      );
      await AuditLogger.record(
        db,
        businessId: t.businessId,
        userId: auth.userId,
        action: 'inventory.stock_transfer_received',
        module: AuditModule.inventory,
        actionType: AuditActionType.update,
        entityType: 'stock_transfers',
        entityId: transferId,
        details: {'items': receivedItems, 'shortages': shortages},
      );
    });
  }

  // ---------------------------------------------------------------- cancel --

  Future<void> cancel(String transferId) async {
    await db.transaction(() async {
      final t = await (db.select(
        db.stockTransfers,
      )..where((x) => x.id.equals(transferId))).getSingle();
      auth.require(BosPermission.stockTransferCreate, businessId: t.businessId);
      if (!allowedBranchIds.contains(t.fromBranchId)) {
        throw const PermissionDeniedException(
          'Only the sending branch can cancel this transfer.',
        );
      }
      if (t.status != 'in_transit') {
        throw StateError('This transfer is already ${t.status}.');
      }
      final items = await (db.select(
        db.stockTransferItems,
      )..where((i) => i.transferId.equals(transferId))).get();
      for (final it in items) {
        await _move(
          item: it,
          branchId: t.fromBranchId,
          kind: 'tcancel',
          type: 'transfer_cancel',
          quantity: it.quantity,
          transferId: transferId,
        );
      }
      await (db.update(
        db.stockTransfers,
      )..where((x) => x.id.equals(transferId))).write(
        StockTransfersCompanion(
          status: const Value('cancelled'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await AuditLogger.record(
        db,
        businessId: t.businessId,
        userId: auth.userId,
        action: 'inventory.stock_transfer_cancelled',
        module: AuditModule.inventory,
        actionType: AuditActionType.update,
        entityType: 'stock_transfers',
        entityId: transferId,
        details: {
          'from': t.fromBranchId,
          'to': t.toBranchId,
          'items': [
            for (final it in items)
              {
                'itemId': it.itemId,
                'itemType': it.itemType,
                'name': it.itemName,
                'unit': it.unit,
                'restored': it.quantity,
              },
          ],
        },
      );
    });
  }
}

// ============================================================ providers ====

final stockTransferServiceProvider = Provider<StockTransferService>((ref) {
  return StockTransferService(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
    ref.watch(stockServiceProvider),
    {for (final b in ref.watch(allowedBranchesProvider)) b.id},
  );
});

final stockTransfersProvider = StreamProvider<List<StockTransfer>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final allowed = ref.watch(allowedBranchesProvider).map((b) => b.id).toList();
  return (db.select(db.stockTransfers)
        ..where(
          (t) =>
              t.businessId.equals(businessId) &
              (t.fromBranchId.isIn(allowed) | t.toBranchId.isIn(allowed)),
        )
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(300))
      .watch();
});

final stockTransferItemsProvider =
    StreamProvider.family<List<StockTransferItem>, String>((ref, transferId) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.stockTransferItems,
      )..where((i) => i.transferId.equals(transferId))).watch();
    });
