// lib/features/transactions/presentation/screens/pos_sync_status.dart
//
// Shows whether each POS receipt has reached the cloud.
//
// HOW IT KNOWS
//   Every local change waits in two places until it is uploaded:
//     * sync_change_log : just written, not yet queued
//     * sync_outbox     : queued (pending / syncing / failed / conflict)
//   A receipt is "synced" when neither place holds anything for it (the
//   sale row, its items, its payment proofs or its tenders). After a
//   successful upload the sync engine deletes the outbox row, so an empty
//   queue means the cloud has it.
//
//   If cloud sync is not configured on this build, receipts show
//   "This device only" instead of a misleading "Synced".

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/supabase/supabase_service.dart'
    show supabaseAvailableProvider;
import 'package:bos_application/core/sync/sync_tracker.dart'
    show syncStatusServiceProvider;
import 'package:bos_application/core/sync/sync_trigger_service.dart'
    show syncTriggerServiceProvider;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import 'transaction_page.dart' show kCurrentBusinessId;

// ============================================================================
// MODEL
// ============================================================================

enum SaleSyncState { synced, syncing, pending, failed, localOnly }

class SaleSyncInfo {
  final SaleSyncState state;
  final String? error;
  const SaleSyncInfo(this.state, {this.error});

  /// Waiting for, or in the middle of, an upload (or failed to upload).
  bool get isUnsynced =>
      state == SaleSyncState.pending ||
      state == SaleSyncState.syncing ||
      state == SaleSyncState.failed;
}

class SaleSyncSnapshot {
  final bool cloudEnabled;
  final Map<String, SaleSyncInfo> _byId;

  const SaleSyncSnapshot(this.cloudEnabled, this._byId);

  /// Receipts still waiting to upload (or failed).
  int get unsyncedCount => _byId.values.where((i) => i.isUnsynced).length;

  SaleSyncInfo of(String saleId) {
    if (!cloudEnabled) return const SaleSyncInfo(SaleSyncState.localOnly);
    return _byId[saleId] ?? const SaleSyncInfo(SaleSyncState.synced);
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

const _kSql = '''
SELECT sale_id, status, error FROM (
  SELECT entity_id AS sale_id, status AS status, error AS error
    FROM sync_outbox WHERE entity_type = 'pos_sales'
  UNION ALL
  SELECT i.sale_id, o.status, o.error
    FROM sync_outbox o JOIN pos_sale_items i ON i.id = o.entity_id
    WHERE o.entity_type = 'pos_sale_items'
  UNION ALL
  SELECT p.sale_id, o.status, o.error
    FROM sync_outbox o JOIN pos_sale_payments p ON p.id = o.entity_id
    WHERE o.entity_type = 'pos_sale_payments'
  UNION ALL
  SELECT t.sale_id, o.status, o.error
    FROM sync_outbox o JOIN pos_sale_tenders t ON t.id = o.entity_id
    WHERE o.entity_type = 'pos_sale_tenders'
  UNION ALL
  SELECT entity_id, 'pending', NULL
    FROM sync_change_log WHERE entity_type = 'pos_sales'
  UNION ALL
  SELECT i.sale_id, 'pending', NULL
    FROM sync_change_log c JOIN pos_sale_items i ON i.id = c.entity_id
    WHERE c.entity_type = 'pos_sale_items'
  UNION ALL
  SELECT p.sale_id, 'pending', NULL
    FROM sync_change_log c JOIN pos_sale_payments p ON p.id = c.entity_id
    WHERE c.entity_type = 'pos_sale_payments'
  UNION ALL
  SELECT t.sale_id, 'pending', NULL
    FROM sync_change_log c JOIN pos_sale_tenders t ON t.id = c.entity_id
    WHERE c.entity_type = 'pos_sale_tenders'
)
''';

/// Live sync state of every receipt that still has something waiting.
/// Receipts that are not in the map are fully synced.
final posSaleSyncProvider = StreamProvider<SaleSyncSnapshot>((ref) {
  final db = ref.watch(databaseProvider);
  final cloud = ref.watch(supabaseAvailableProvider);
  final branchId = ref.watch(selectedBranchIdProvider);
  final mainId = AppDatabase.mainBranchId(
    ref.watch(selectedBusinessIdProvider),
  );

  return db
      .customSelect(
        '$_kSql WHERE sale_id IN '
        '(SELECT id FROM pos_sales WHERE COALESCE(branch_id, ?) = ?)',
        variables: [Variable.withString(mainId), Variable.withString(branchId)],
        readsFrom: {
          db.syncOutbox,
          db.posSales,
          db.posSaleItems,
          db.posSalePayments,
          db.posSaleTenders,
        },
      )
      .watch()
      .map((rows) {
        int rank(String s) => switch (s) {
          'failed' || 'conflict' => 3,
          'syncing' => 2,
          _ => 1,
        };

        final worst = <String, int>{};
        final errors = <String, String>{};
        for (final r in rows) {
          final id = r.read<String>('sale_id');
          final status = r.read<String>('status');
          if (status == 'synced') continue;
          final k = rank(status);
          if (k > (worst[id] ?? 0)) worst[id] = k;
          final err = r.readNullable<String>('error');
          if (k == 3 && err != null && err.isNotEmpty) errors[id] = err;
        }

        return SaleSyncSnapshot(cloud, {
          for (final e in worst.entries)
            e.key: SaleSyncInfo(switch (e.value) {
              3 => SaleSyncState.failed,
              2 => SaleSyncState.syncing,
              _ => SaleSyncState.pending,
            }, error: errors[e.key]),
        });
      });
});

/// True when the phone has any network connection. (A connection is not a
/// guarantee the server is reachable, but it explains most "waiting" states.)
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});

/// Re-queues anything that failed, then runs a sync now.
Future<void> syncReceiptsNow(WidgetRef ref) async {
  await ref.read(syncStatusServiceProvider).requeueFailed(kCurrentBusinessId);
  await ref.read(syncTriggerServiceProvider).syncNow();
}

// ============================================================================
// SMALL CHIP (receipt cards)
// ============================================================================

class SyncChip extends ConsumerWidget {
  final SaleSyncInfo info;
  const SyncChip({super.key, required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final online = ref.watch(isOnlineProvider).value ?? true;

    final (IconData icon, String label, Color color) = switch (info.state) {
      SaleSyncState.synced => (
        Icons.cloud_done_outlined,
        'Synced',
        Colors.green.shade700,
      ),
      SaleSyncState.syncing => (Icons.sync_rounded, 'Syncing', scheme.primary),
      SaleSyncState.pending =>
        online
            ? (
                Icons.cloud_upload_outlined,
                'Waiting to sync',
                Colors.orange.shade800,
              )
            : (
                Icons.cloud_off_outlined,
                'Saved offline',
                Colors.orange.shade800,
              ),
      SaleSyncState.failed => (
        Icons.error_outline_rounded,
        'Sync failed',
        scheme.error,
      ),
      SaleSyncState.localOnly => (
        Icons.phone_android_rounded,
        'This device only',
        scheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BANNER (top of the history page)
// ============================================================================

class SyncSummaryBanner extends ConsumerStatefulWidget {
  /// The receipts currently listed (so the counts match what is on screen).
  final List<String> saleIds;
  const SyncSummaryBanner({super.key, required this.saleIds});

  @override
  ConsumerState<SyncSummaryBanner> createState() => _SyncSummaryBannerState();
}

class _SyncSummaryBannerState extends ConsumerState<SyncSummaryBanner> {
  bool _busy = false;

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      await syncReceiptsNow(ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snap = ref.watch(posSaleSyncProvider).value;
    final online = ref.watch(isOnlineProvider).value ?? true;

    if (snap == null || !snap.cloudEnabled) return const SizedBox.shrink();

    var waiting = 0;
    var failed = 0;
    for (final id in widget.saleIds) {
      switch (snap.of(id).state) {
        case SaleSyncState.pending:
        case SaleSyncState.syncing:
          waiting++;
        case SaleSyncState.failed:
          failed++;
        case SaleSyncState.synced:
        case SaleSyncState.localOnly:
          break;
      }
    }

    final unsynced = waiting + failed;
    final Color color;
    final IconData icon;
    final String text;

    if (failed > 0) {
      color = scheme.error;
      icon = Icons.cloud_off_rounded;
      text =
          '$failed receipt${failed == 1 ? '' : 's'} failed to sync. '
          'Tap Retry.';
    } else if (waiting > 0) {
      color = Colors.orange.shade800;
      icon = Icons.cloud_upload_outlined;
      text = online
          ? '$waiting receipt${waiting == 1 ? '' : 's'} waiting to upload.'
          : '$waiting receipt${waiting == 1 ? ' is' : 's are'} saved on this '
                'phone and will upload when you are back online.';
    } else if (!online) {
      color = scheme.onSurfaceVariant;
      icon = Icons.wifi_off_rounded;
      text = 'Offline. New sales are saved on this phone.';
    } else {
      color = Colors.green.shade700;
      icon = Icons.cloud_done_outlined;
      text = 'All receipts are synced.';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (unsynced > 0)
              TextButton(
                onPressed: (!online || _busy) ? null : _sync,
                child: Text(
                  failed > 0 ? 'Retry' : 'Sync now',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DETAIL CARD (receipt page)
// ============================================================================

class SyncDetailCard extends ConsumerStatefulWidget {
  final String saleId;
  const SyncDetailCard({super.key, required this.saleId});

  @override
  ConsumerState<SyncDetailCard> createState() => _SyncDetailCardState();
}

class _SyncDetailCardState extends ConsumerState<SyncDetailCard> {
  bool _busy = false;

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      await syncReceiptsNow(ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snap = ref.watch(posSaleSyncProvider).value;
    final online = ref.watch(isOnlineProvider).value ?? true;
    if (snap == null) return const SizedBox.shrink();

    final info = snap.of(widget.saleId);

    final (
      IconData icon,
      String title,
      String body,
      Color color,
    ) = switch (info.state) {
      SaleSyncState.synced => (
        Icons.cloud_done_outlined,
        'Synced',
        'This receipt is saved in the cloud and visible on your other '
            'devices.',
        Colors.green.shade700,
      ),
      SaleSyncState.syncing => (
        Icons.sync_rounded,
        'Syncing',
        'Uploading this receipt now.',
        scheme.primary,
      ),
      SaleSyncState.pending => (
        Icons.cloud_upload_outlined,
        'Waiting to sync',
        online
            ? 'Saved on this phone. It uploads automatically in a moment.'
            : 'Saved on this phone. It uploads automatically when you are '
                  'back online.',
        Colors.orange.shade800,
      ),
      SaleSyncState.failed => (
        Icons.cloud_off_rounded,
        'Sync failed',
        'This receipt could not be uploaded. It is safe on this phone. '
            'Tap Retry, and if it keeps failing, tell your administrator.',
        scheme.error,
      ),
      SaleSyncState.localOnly => (
        Icons.phone_android_rounded,
        'This device only',
        'Cloud sync is not turned on, so this receipt exists only on '
            'this phone.',
        scheme.onSurfaceVariant,
      ),
    };

    final canAct =
        info.state == SaleSyncState.pending ||
        info.state == SaleSyncState.failed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
                if (info.error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    info.error!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canAct)
            TextButton(
              onPressed: (!online || _busy) ? null : _sync,
              child: Text(
                info.state == SaleSyncState.failed ? 'Retry' : 'Sync now',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
