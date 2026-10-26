import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/auth/approval_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class PosReturn {
  const PosReturn({
    required this.id,
    required this.businessId,
    required this.saleId,
    required this.refundAccountId,
    required this.reason,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String saleId;
  final String refundAccountId;
  final String reason;
  final String? createdBy;
  final DateTime createdAt;
}

class PosReturnItem {
  const PosReturnItem({
    required this.id,
    required this.returnId,
    required this.saleItemId,
    required this.quantity,
    required this.refundAmount,
  });

  final String id;
  final String returnId;
  final String saleItemId;
  final double quantity;
  final int refundAmount;
}

DateTime _returnDate(Object value) {
  if (value is int) {
    if (value.abs() < 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is num) return _returnDate(value.round());
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    final epoch = int.tryParse(value);
    if (epoch != null) return _returnDate(epoch);
  }
  throw FormatException('Invalid POS return timestamp: $value');
}

final posReturnsProvider = FutureProvider<List<PosReturn>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final rows = await db
      .customSelect(
        'SELECT * FROM pos_returns WHERE business_id = ? ORDER BY created_at DESC',
        variables: [Variable.withString(businessId)],
      )
      .get();
  return [
    for (final row in rows)
      PosReturn(
        id: row.read<String>('id'),
        businessId: row.read<String>('business_id'),
        saleId: row.read<String>('sale_id'),
        refundAccountId: row.read<String>('refund_account_id'),
        reason: row.read<String>('reason'),
        createdBy: row.readNullable<String>('created_by'),
        createdAt: _returnDate(row.data['created_at']!),
      ),
  ];
});

final posReturnItemsProvider = FutureProvider<List<PosReturnItem>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  final rows = await db.customSelect('SELECT * FROM pos_return_items').get();
  return [
    for (final row in rows)
      PosReturnItem(
        id: row.read<String>('id'),
        returnId: row.read<String>('return_id'),
        saleItemId: row.read<String>('sale_item_id'),
        quantity: row.read<double>('quantity'),
        refundAmount: row.read<int>('refund_amount'),
      ),
  ];
});

final posReturnServiceProvider = Provider<PosReturnService>((ref) {
  return PosReturnService(
    ref.watch(databaseProvider),
    ref.watch(authorizationServiceProvider),
    ref.watch(selectedBranchIdProvider),
  );
});

class PosReturnService {
  PosReturnService(this.db, this.auth, this.viewBranchId);

  final AppDatabase db;
  final AuthorizationService auth;
  final String viewBranchId;
  final _uuid = const Uuid();

  Future<String> createReturn({
    required String saleId,
    required String refundAccountId,
    required String reason,
    required Map<String, double> quantitiesBySaleItemId,
    String? approvedByUserId,
    String? approvedByName,
  }) async {
    final businessId = auth.currentBusinessId;
    if (businessId == null) {
      throw const PermissionDeniedException(
        'Select an active business before recording a return.',
      );
    }
    auth.require(BosPermission.salesVoid, businessId: businessId);
    if (approvedByUserId == null &&
        await ApprovalService.anyPinSet(db, businessId)) {
      throw StateError('Manager approval is required for this return.');
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw StateError('A reason is required to record a return.');
    }
    if (cleanReason.length > 500) {
      throw StateError('The return reason must be 500 characters or fewer.');
    }
    if (quantitiesBySaleItemId.isEmpty) {
      throw StateError('Select at least one item to return.');
    }
    for (final entry in quantitiesBySaleItemId.entries) {
      if (!entry.value.isFinite || entry.value <= 0) {
        throw StateError('Enter a valid return quantity for every item.');
      }
    }

    final returnId = _uuid.v4();
    final stock = StockService(db, viewBranchId: viewBranchId);

    await db.transaction(() async {
      final sale =
          await (db.select(db.posSales)..where(
                (s) => s.id.equals(saleId) & s.businessId.equals(businessId),
              ))
              .getSingleOrNull();
      if (sale == null) throw StateError('The sale could not be found.');
      if (sale.isVoided || sale.isStockOnly) {
        throw StateError('Voided and stock-only receipts cannot be returned.');
      }

      final account =
          await (db.select(db.accounts)..where(
                (a) =>
                    a.id.equals(refundAccountId) &
                    a.businessId.equals(businessId) &
                    a.isActive.equals(true) &
                    a.isPaymentAccount.equals(true),
              ))
              .getSingleOrNull();
      if (account == null) {
        throw StateError('Choose an active payment account for the refund.');
      }

      final saleItems =
          await (db.select(db.posSaleItems)
                ..where((i) => i.saleId.equals(saleId))
                ..orderBy([(i) => OrderingTerm.asc(i.id)]))
              .get();
      if (saleItems.isEmpty) throw StateError('This receipt has no items.');
      final byId = {for (final item in saleItems) item.id: item};
      if (!byId.keys.toSet().containsAll(quantitiesBySaleItemId.keys)) {
        throw StateError(
          'One or more selected items do not belong to this sale.',
        );
      }
      final invalidQuantity = quantitiesBySaleItemId.entries.any(
        (entry) => entry.value - byId[entry.key]!.quantity > 1e-9,
      );
      if (invalidQuantity) {
        throw StateError('A return quantity cannot exceed the quantity sold.');
      }

      final previousReturnRows = await db
          .customSelect(
            'SELECT id FROM pos_returns WHERE sale_id = ?',
            variables: [Variable.withString(saleId)],
          )
          .get();
      final previousReturnIds = [
        for (final row in previousReturnRows) row.read<String>('id'),
      ];
      final previousLines = previousReturnIds.isEmpty
          ? <PosReturnItem>[]
          : [
              for (final row
                  in await db
                      .customSelect(
                        'SELECT * FROM pos_return_items WHERE return_id IN '
                        '(${List.filled(previousReturnIds.length, '?').join(',')})',
                        variables: [
                          for (final id in previousReturnIds)
                            Variable.withString(id),
                        ],
                      )
                      .get())
                PosReturnItem(
                  id: row.read<String>('id'),
                  returnId: row.read<String>('return_id'),
                  saleItemId: row.read<String>('sale_item_id'),
                  quantity: row.read<double>('quantity'),
                  refundAmount: row.read<int>('refund_amount'),
                ),
            ];
      final returnedQty = <String, double>{};
      final returnedCents = <String, int>{};
      for (final line in previousLines) {
        returnedQty.update(
          line.saleItemId,
          (value) => value + line.quantity,
          ifAbsent: () => line.quantity,
        );
        returnedCents.update(
          line.saleItemId,
          (value) => value + line.refundAmount,
          ifAbsent: () => line.refundAmount,
        );
      }
      for (final entry in quantitiesBySaleItemId.entries) {
        final totalReturned = (returnedQty[entry.key] ?? 0) + entry.value;
        if (totalReturned - byId[entry.key]!.quantity > 1e-9) {
          throw StateError('Some of these items have already been returned.');
        }
      }

      final gross = saleItems.fold<int>(0, (sum, item) => sum + item.lineTotal);
      if (gross <= 0 || sale.totalAmount < 0) {
        throw StateError('This receipt does not have a refundable total.');
      }
      final allocatedNet = <String, int>{};
      var assignedCents = 0;
      for (var i = 0; i < saleItems.length; i++) {
        final item = saleItems[i];
        final allocation = i == saleItems.length - 1
            ? sale.totalAmount - assignedCents
            : (item.lineTotal * sale.totalAmount / gross).round();
        allocatedNet[item.id] = allocation;
        assignedCents += allocation;
      }

      final refundAmounts = <String, int>{};
      for (final entry in quantitiesBySaleItemId.entries) {
        final item = byId[entry.key]!;
        final oldQuantity = returnedQty[item.id] ?? 0;
        final newQuantity = oldQuantity + entry.value;
        final cumulativeRefund =
            (allocatedNet[item.id]! * newQuantity / item.quantity).round();
        refundAmounts[item.id] =
            cumulativeRefund - (returnedCents[item.id] ?? 0);
      }

      await db.customStatement(
        'INSERT INTO pos_returns '
        '(id, business_id, sale_id, refund_account_id, reason, created_by, created_at) '
        'VALUES (?, ?, ?, ?, ?, nullif(?, \'\'), ?)',
        [
          returnId,
          businessId,
          saleId,
          refundAccountId,
          cleanReason,
          auth.userId ?? '',
          DateTime.now().millisecondsSinceEpoch,
        ],
      );

      for (final entry in quantitiesBySaleItemId.entries) {
        await db.customStatement(
          'INSERT INTO pos_return_items '
          '(id, return_id, sale_item_id, quantity, refund_amount) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            _uuid.v4(),
            returnId,
            entry.key,
            entry.value,
            refundAmounts[entry.key]!,
          ],
        );

        final saleItem = byId[entry.key]!;
        final productId = saleItem.productId;
        if (productId == null) continue;
        final product = await (db.select(
          db.products,
        )..where((p) => p.id.equals(productId))).getSingleOrNull();
        if (product == null) continue;
        if (product.trackingType == 'stocked') {
          await stock.moveProduct(
            branchId: sale.branchId ?? AppDatabase.mainBranchId(businessId),
            productId: product.id,
            businessId: businessId,
            type: 'pos_return',
            quantity: entry.value,
            referenceType: 'pos_return',
            referenceId: returnId,
            notes: cleanReason,
          );
        }
      }

      final completesSale = saleItems.every((item) {
        final quantity =
            (returnedQty[item.id] ?? 0) +
            (quantitiesBySaleItemId[item.id] ?? 0);
        return quantity + 1e-9 >= item.quantity;
      });
      if (completesSale) {
        final recipeMovements =
            await (db.select(db.inventoryMovements)..where(
                  (m) =>
                      m.referenceId.equals(saleId) &
                      m.movementType.equals('production_consumption'),
                ))
                .get();
        for (final movement in recipeMovements) {
          await stock.moveSupply(
            branchId:
                movement.branchId ??
                sale.branchId ??
                AppDatabase.mainBranchId(businessId),
            supplyId: movement.supplyId,
            type: 'pos_return',
            unit: movement.unit,
            quantity: -movement.quantity,
            referenceType: 'pos_return',
            referenceId: returnId,
            notes: cleanReason,
          );
        }
      }

      final refundCents = refundAmounts.values.fold<int>(0, (a, b) => a + b);
      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: auth.userId,
        action: 'sales.return_recorded',
        module: AuditModule.sales,
        actionType: AuditActionType.refund,
        entityType: 'pos_returns',
        entityId: returnId,
        entityLabel: 'Return ${sale.receiptNo ?? saleId.substring(0, 8)}',
        reason: cleanReason,
        after: {
          'saleId': saleId,
          'refundAccountId': refundAccountId,
          'refundAmount': refundCents,
          'items': quantitiesBySaleItemId,
        },
        details: {
          'approvedByUserId': approvedByUserId,
          'approvedByName': approvedByName,
        },
      );
    });

    return returnId;
  }
}
