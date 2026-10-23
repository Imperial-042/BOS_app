// lib/features/transactions/presentation/screens/receivables_page.dart
//
// Finance -> Receivables. Open customer balances (credit sales not yet
// collected) with quick "record payment" that goes through CustomerService.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/database/app_database.dart';
import '../providers/finance_list_providers.dart';
import 'customers_page.dart' show customerServiceProvider, customersProvider;
import 'transaction_page.dart'
    show ledgerVersionProvider, paymentAccountsProvider;

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

class ReceivablesPage extends ConsumerWidget {
  const ReceivablesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCollect = ref.watch(canProvider(BosPermission.receivablesCreate));
    final itemsAsync = ref.watch(openReceivablesProvider);
    final customersAsync = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Receivables')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load receivables.')),
        data: (items) {
          final customerNames = {
            for (final c in customersAsync.value ?? const <Customer>[])
              c.id: c.name,
          };
          final total = items.fold<int>(0, (sum, i) => sum + i.amount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customers owe you',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _peso(total),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const _ReceivablesEmptyState()
              else
                _ReceivableList(
                  items: items,
                  customerNames: customerNames,
                  canCollect: canCollect,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReceivableList extends StatelessWidget {
  const _ReceivableList({
    required this.items,
    required this.customerNames,
    required this.canCollect,
  });

  final List<IncomeTransaction> items;
  final Map<String, String> customerNames;
  final bool canCollect;

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
            _ReceivableTile(
              item: items[i],
              customerName:
                  customerNames[items[i].customerId] ?? 'Unknown customer',
              canCollect: canCollect,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceivableTile extends ConsumerWidget {
  const _ReceivableTile({
    required this.item,
    required this.customerName,
    required this.canCollect,
  });

  final IncomeTransaction item;
  final String customerName;
  final bool canCollect;

  Future<void> _collect(BuildContext context, WidgetRef ref) async {
    final accounts = await ref.read(paymentAccountsProvider.future);
    if (!context.mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No payment account available.')),
      );
      return;
    }

    String? accountId = accounts.first.id;
    final amountController = TextEditingController(
      text: (item.amount / 100).toStringAsFixed(2),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog.adaptive(
          title: Text('Collect from $customerName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Into account'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (value) => setDialogState(() => accountId = value),
              ),
            ],
          ),
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Collect'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final amount = double.tryParse(
      amountController.text.replaceAll(',', '').trim(),
    );
    if (amount == null || amount <= 0 || accountId == null) return;

    try {
      await ref
          .read(customerServiceProvider)
          .recordPayment(
            customerId: item.customerId!,
            amount: (amount * 100).round(),
            paymentAccountId: accountId!,
            date: DateTime.now(),
            notes:
                'Collected against ${DateFormat('MMM d').format(item.txnDate)} sale',
          );
      ref.read(ledgerVersionProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment recorded.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.request_quote_outlined,
          size: 20,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        customerName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Sale on ${DateFormat('MMM d, yyyy').format(item.txnDate)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _peso(item.amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (canCollect) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.payments_outlined, size: 20),
              tooltip: 'Record payment',
              onPressed: () => _collect(context, ref),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceivablesEmptyState extends StatelessWidget {
  const _ReceivablesEmptyState();

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
              Icons.request_quote_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing outstanding',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Credit sales will show here until customers pay.',
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
