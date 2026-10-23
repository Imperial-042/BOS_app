// lib/features/transactions/presentation/screens/transfers_page.dart
//
// Finance -> Transfers. Business-scoped list of every inter-account transfer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../providers/finance_list_providers.dart';
import 'transaction_page.dart' show paymentAccountsProvider;

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

class TransfersPage extends ConsumerWidget {
  const TransfersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfersAsync = ref.watch(accountTransferListProvider);
    final accountsAsync = ref.watch(paymentAccountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transfers')),
      body: transfersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load transfers.')),
        data: (transfers) {
          final accountNames = {
            for (final b in accountsAsync.value ?? const <Account>[])
              b.id: b.name,
          };
          final total = transfers.fold<int>(0, (sum, t) => sum + t.amount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total moved',
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
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${transfers.length} transfer${transfers.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (transfers.isEmpty)
                const _TransfersEmptyState()
              else
                _TransferList(transfers: transfers, accountNames: accountNames),
            ],
          );
        },
      ),
    );
  }
}

class _TransferList extends StatelessWidget {
  const _TransferList({required this.transfers, required this.accountNames});

  final List<AccountTransfer> transfers;
  final Map<String, String> accountNames;

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
          for (var i = 0; i < transfers.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16),
            _TransferTile(
              transfer: transfers[i],
              fromName: accountNames[transfers[i].fromAccountId] ?? '?',
              toName: accountNames[transfers[i].toAccountId] ?? '?',
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.transfer,
    required this.fromName,
    required this.toName,
  });

  final AccountTransfer transfer;
  final String fromName;
  final String toName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.tertiaryContainer,
        child: Icon(
          Icons.swap_horiz_rounded,
          size: 20,
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
      title: Text(
        '$fromName → $toName',
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        DateFormat('MMM d, yyyy').format(transfer.transferDate),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        _peso(transfer.amount),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _TransfersEmptyState extends StatelessWidget {
  const _TransfersEmptyState();

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
              Icons.swap_horiz_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No transfers yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Move money between accounts from the Cashflow page.',
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
