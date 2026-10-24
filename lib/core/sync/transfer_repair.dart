// One-time repair for stock transfers created before branch attribution:
//  1. stamps the correct branch on transfer movements,
//  2. puts failed/conflict transfer uploads back in the queue,
//  3. re-queues every transfer row so the server and other devices get it.

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _flag = 'transfer_repair_v1';

Future<void> repairBranchTransfers(AppDatabase db) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_flag) ?? false) return;

  await db.transaction(() async {
    // 1. Correct branch on transfer movements (out/cancel = sender, in = receiver).
    const branchExpr =
        "(SELECT CASE {t}.movement_type WHEN 'transfer_in' "
        'THEN st.to_branch_id ELSE st.from_branch_id END '
        'FROM stock_transfers st WHERE st.id = {t}.reference_id)';

    for (final t in const ['inventory_movements', 'product_stock_movements']) {
      final expr = branchExpr.replaceAll('{t}', t);
      await db.customStatement(
        'UPDATE $t SET branch_id = $expr '
        "WHERE reference_type = 'stock_transfer' "
        "AND movement_type IN ('transfer_out','transfer_in','transfer_cancel') "
        'AND reference_id IN (SELECT id FROM stock_transfers) '
        'AND branch_id IS NOT $expr',
      );
    }

    // 2. Failed / conflicting uploads go back in the queue.
    await db.customStatement(
      "UPDATE sync_outbox SET status = 'pending', attempt_count = 0, "
      'next_attempt_at = NULL, error = NULL '
      "WHERE status IN ('failed','conflict') AND entity_type IN "
      "('stock_transfers','stock_transfer_items','inventory_movements',"
      "'product_stock_movements')",
    );

    // 3. Re-queue every transfer row (upsert is idempotent on the server).
    Future<void> requeue(String type, String sql) async {
      final rows = await db.customSelect(sql).get();
      for (final r in rows) {
        await SyncTracker.record(
          db,
          businessId: r.read<String>('business_id'),
          entityType: type,
          entityId: r.read<String>('id'),
          operation: SyncOp.update,
        );
      }
    }

    await requeue(
      'stock_transfers',
      'SELECT id, business_id FROM stock_transfers',
    );
    await requeue(
      'stock_transfer_items',
      'SELECT id, business_id FROM stock_transfer_items',
    );
    await requeue(
      'inventory_movements',
      'SELECT m.id AS id, s.business_id AS business_id '
          'FROM inventory_movements m JOIN supplies s ON s.id = m.supply_id '
          "WHERE m.reference_type = 'stock_transfer'",
    );
    await requeue(
      'product_stock_movements',
      'SELECT id, business_id FROM product_stock_movements '
          "WHERE reference_type = 'stock_transfer'",
    );
  });

  await prefs.setBool(_flag, true);
}
