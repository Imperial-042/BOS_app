// lib/features/transactions/presentation/screens/income_page.dart
//
// Finance -> Income. Business-scoped list of every income transaction with
// running totals; tapping opens the shared transaction form to edit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../providers/finance_list_providers.dart';
import 'transaction_page.dart';

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

class IncomePage extends ConsumerWidget {
  const IncomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate = ref.watch(canProvider(BosPermission.financeCreate));
    final canEdit = ref.watch(canProvider(BosPermission.financeEdit));
    final itemsAsync = ref.watch(incomeListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Income')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context, isIncome: true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Record income'),
            )
          : null,
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load income.')),
        data: (items) {
          final total = items
              .where((i) => i.status == 'completed')
              .fold<int>(0, (sum, i) => sum + i.amount);
          final pending = items.where((i) => i.status == 'pending').length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _IncomeSummaryCard(
                total: total,
                count: items.length,
                pending: pending,
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const _IncomeEmptyState()
              else
                _IncomeList(items: items, canEdit: canEdit),
            ],
          );
        },
      ),
    );
  }

  void _openForm(
    BuildContext context, {
    required bool isIncome,
    IncomeTransaction? existing,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionPage(existingIncome: existing),
      ),
    );
  }
}

class _IncomeSummaryCard extends StatelessWidget {
  const _IncomeSummaryCard({
    required this.total,
    required this.count,
    required this.pending,
  });

  final int total;
  final int count;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total earned',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _peso(total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$count transaction${count == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
                if (pending > 0)
                  Text(
                    '$pending pending',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeList extends StatelessWidget {
  const _IncomeList({required this.items, required this.canEdit});

  final List<IncomeTransaction> items;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16),
            _IncomeTile(item: items[i], canEdit: canEdit),
          ],
        ],
      ),
    );
  }
}

class _IncomeTile extends ConsumerWidget {
  const _IncomeTile({required this.item, required this.canEdit});

  final IncomeTransaction item;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categoryName = ref
        .watch(categoryNameProvider(item.categoryId))
        .maybeWhen(data: (name) => name, orElse: () => '—');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.trending_up_rounded,
          size: 20,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        item.description?.isNotEmpty == true ? item.description! : categoryName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${DateFormat('MMM d, yyyy').format(item.txnDate)}'
        '${item.status == 'pending' ? ' · pending' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        _peso(item.amount),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      onTap: canEdit
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionPage(existingIncome: item),
                ),
              );
            }
          : null,
    );
  }
}

class _IncomeEmptyState extends StatelessWidget {
  const _IncomeEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.trending_up_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No income recorded yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Record income" to add your first one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category name lookup for a transaction row.
final categoryNameProvider = FutureProvider.family<String, String>((
  ref,
  categoryId,
) async {
  final db = ref.watch(databaseProvider);
  final category = await (db.select(
    db.categories,
  )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
  return category?.name ?? 'Uncategorized';
});
