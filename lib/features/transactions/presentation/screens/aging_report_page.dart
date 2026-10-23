// lib/features/transactions/presentation/screens/aging_report_page.dart
//
// Finance -> Aging report. Groups outstanding receivables and payables into
// 0–30 / 31–60 / 61–90 / 90+ day buckets by days outstanding — the standard
// credit-management view.

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/database_provider.dart';
import 'transaction_page.dart' show kCurrentBusinessId, ledgerVersionProvider;

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

/// One bucket: current (0-30), 31-60, 61-90, 90+ days outstanding.
class _AgingBucket {
  int current = 0;
  int days31to60 = 0;
  int days61to90 = 0;
  int over90 = 0;

  int get total => current + days31to60 + days61to90 + over90;
}

class _AgingData {
  final _AgingBucket receivables;
  final _AgingBucket payables;
  const _AgingData({required this.receivables, required this.payables});
}

final _agingProvider = FutureProvider<_AgingData>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();

  int bucketFor(DateTime date, int amount, _AgingBucket bucket) {
    final days = now.difference(date).inDays;
    if (days <= 30) {
      bucket.current += amount;
    } else if (days <= 60) {
      bucket.days31to60 += amount;
    } else if (days <= 90) {
      bucket.days61to90 += amount;
    } else {
      bucket.over90 += amount;
    }
    return bucket.total;
  }

  final receivables = _AgingBucket();
  final openReceivables =
      await (db.select(db.incomeTransactions)..where(
            (i) =>
                i.businessId.equals(kCurrentBusinessId) &
                i.paymentAccountId.isNull() &
                i.customerId.isNotNull(),
          ))
          .get();
  for (final r in openReceivables) {
    bucketFor(r.txnDate, r.amount, receivables);
  }

  final payables = _AgingBucket();
  final openPayables =
      await (db.select(db.supplierPurchases)..where(
            (p) =>
                p.businessId.equals(kCurrentBusinessId) &
                p.isOnCredit.equals(true),
          ))
          .get();
  for (final p in openPayables) {
    bucketFor(p.purchaseDate, p.amount, payables);
  }

  return _AgingData(receivables: receivables, payables: payables);
});

class AgingReportPage extends ConsumerWidget {
  const AgingReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingAsync = ref.watch(_agingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Aging report')),
      body: agingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load the aging report.')),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _AgingCard(
              title: 'Receivables',
              subtitle: 'What customers owe you',
              bucket: data.receivables,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            _AgingCard(
              title: 'Payables',
              subtitle: 'What you owe suppliers',
              bucket: data.payables,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgingCard extends StatelessWidget {
  const _AgingCard({
    required this.title,
    required this.subtitle,
    required this.bucket,
    required this.color,
  });

  final String title;
  final String subtitle;
  final _AgingBucket bucket;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = bucket.total;
    final rows = [
      ('Current (0–30 days)', bucket.current, theme.colorScheme.primary),
      ('31–60 days', bucket.days31to60, const Color(0xFFF2A93B)),
      ('61–90 days', bucket.days61to90, const Color(0xFFE07A2B)),
      ('90+ days', bucket.over90, theme.colorScheme.error),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _peso(total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final (label, amount, barColor) in rows) ...[
              _AgingRow(
                label: label,
                amount: amount,
                share: total == 0 ? 0 : amount / total,
                color: barColor,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgingRow extends StatelessWidget {
  const _AgingRow({
    required this.label,
    required this.amount,
    required this.share,
    required this.color,
  });

  final String label;
  final int amount;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              _peso(amount),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: share.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
