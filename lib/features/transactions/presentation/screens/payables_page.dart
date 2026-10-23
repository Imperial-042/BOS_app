// lib/features/transactions/presentation/screens/payables_page.dart
//
// Finance -> Payables. Open supplier balances (credit purchases not yet
// paid) with quick "record payment" that goes through SupplierService.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/database/app_database.dart';
import '../providers/finance_list_providers.dart';
import 'suppliers_page.dart' show supplierServiceProvider, suppliersProvider;
import 'transaction_page.dart'
    show ledgerVersionProvider, paymentAccountsProvider;

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

class PayablesPage extends ConsumerWidget {
  const PayablesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canPay = ref.watch(canProvider(BosPermission.payablesCreate));
    final itemsAsync = ref.watch(openPayablesProvider);
    final suppliersAsync = ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Payables')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load payables.')),
        data: (items) {
          final supplierNames = {
            for (final s in suppliersAsync.value ?? const <Supplier>[])
              s.id: s.name,
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
                        'You owe suppliers',
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
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const _PayablesEmptyState()
              else
                _PayableList(
                  items: items,
                  supplierNames: supplierNames,
                  canPay: canPay,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PayableList extends StatelessWidget {
  const _PayableList({
    required this.items,
    required this.supplierNames,
    required this.canPay,
  });

  final List<SupplierPurchase> items;
  final Map<String, String> supplierNames;
  final bool canPay;

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
            _PayableTile(
              item: items[i],
              supplierName:
                  supplierNames[items[i].supplierId] ?? 'Unknown supplier',
              canPay: canPay,
            ),
          ],
        ],
      ),
    );
  }
}

class _PayableTile extends ConsumerWidget {
  const _PayableTile({
    required this.item,
    required this.supplierName,
    required this.canPay,
  });

  final SupplierPurchase item;
  final String supplierName;
  final bool canPay;

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
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
          title: Text('Pay $supplierName'),
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
                decoration: const InputDecoration(labelText: 'From account'),
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
              child: const Text('Pay'),
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
          .read(supplierServiceProvider)
          .recordPayment(
            supplierId: item.supplierId,
            amount: (amount * 100).round(),
            paymentAccountId: accountId!,
            date: DateTime.now(),
            notes:
                'Payment for ${DateFormat('MMM d').format(item.purchaseDate)} purchase',
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
        backgroundColor: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.payments_outlined,
          size: 20,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      title: Text(
        supplierName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Purchase on ${DateFormat('MMM d, yyyy').format(item.purchaseDate)}',
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
          if (canPay) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.payments_outlined, size: 20),
              tooltip: 'Record payment',
              onPressed: () => _pay(context, ref),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayablesEmptyState extends StatelessWidget {
  const _PayablesEmptyState();

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
              Icons.payments_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing to pay',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Credit purchases will show here until you pay suppliers.',
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
