// lib/features/transactions/presentation/screens/expenses_page.dart
//
// Finance -> Expenses. Business-scoped list of every expense with running
// totals; tapping opens the shared transaction form to edit.

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

class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate = ref.watch(canProvider(BosPermission.financeCreate));
    final canEdit = ref.watch(canProvider(BosPermission.financeEdit));
    final itemsAsync = ref.watch(expenseListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionPage()),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Record expense'),
            )
          : null,
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load expenses.')),
        data: (items) {
          final total = items
              .where((e) => e.status == 'completed')
              .fold<int>(0, (sum, e) => sum + e.amount);
          final pending = items.where((e) => e.status == 'pending').length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _ExpenseSummaryCard(
                total: total,
                count: items.length,
                pending: pending,
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const _ExpenseEmptyState()
              else
                _ExpenseList(items: items, canEdit: canEdit),
            ],
          );
        },
      ),
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  const _ExpenseSummaryCard({
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
                    'Total spent',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _peso(total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.error,
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

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({required this.items, required this.canEdit});

  final List<Expense> items;
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
            _ExpenseTile(item: items[i], canEdit: canEdit),
          ],
        ],
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.item, required this.canEdit});

  final Expense item;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categoryName = ref
        .watch(_categoryNameProvider(item.categoryId))
        .maybeWhen(data: (name) => name, orElse: () => '—');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.trending_down_rounded,
          size: 20,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      title: Text(
        item.description?.isNotEmpty == true ? item.description! : categoryName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${DateFormat('MMM d, yyyy').format(item.expenseDate)}'
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
                  builder: (_) => TransactionPage(existingExpense: item),
                ),
              );
            }
          : null,
    );
  }
}

class _ExpenseEmptyState extends StatelessWidget {
  const _ExpenseEmptyState();

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
              Icons.trending_down_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No expenses recorded yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Record expense" to add your first one.',
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

final _categoryNameProvider = FutureProvider.family<String, String>((
  ref,
  categoryId,
) async {
  final db = ref.watch(databaseProvider);
  final category = await (db.select(
    db.categories,
  )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
  return category?.name ?? 'Uncategorized';
});
