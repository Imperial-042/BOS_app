import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/approval_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/domain/pos_return_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_history_page.dart'
    show posSaleItemsProvider, posSalesHistoryProvider;
import 'package:bos_application/features/transactions/presentation/widgets/manager_approval_dialog.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';

final _refundAccountsProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  return (db.select(db.accounts)
        ..where(
          (a) =>
              a.businessId.equals(businessId) &
              a.isActive.equals(true) &
              a.isPaymentAccount.equals(true),
        )
        ..orderBy([(a) => OrderingTerm.asc(a.name)]))
      .watch();
});

class ReturnsPage extends ConsumerWidget {
  const ReturnsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final canReturn = ref.watch(canProvider(BosPermission.salesVoid));
    final returnsAsync = ref.watch(posReturnsProvider);
    final returnItems = ref.watch(posReturnItemsProvider).value ?? const [];
    final sales = ref.watch(posSalesHistoryProvider).value ?? const [];
    final accounts = ref.watch(_refundAccountsProvider).value ?? const [];
    final salesById = {for (final sale in sales) sale.id: sale};
    final accountsById = {for (final account in accounts) account.id: account};
    final returnTotalById = <String, int>{};
    final returnCountById = <String, int>{};
    for (final item in returnItems) {
      returnTotalById.update(
        item.returnId,
        (value) => value + item.refundAmount,
        ifAbsent: () => item.refundAmount,
      );
      returnCountById.update(
        item.returnId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Returns'),
        actions: [
          if (canReturn)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => _openReturnForm(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Record return'),
              ),
            ),
        ],
      ),
      body: returnsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Unable to load returns: $error')),
        data: (returns) {
          if (returns.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_return_outlined,
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No returns recorded',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      canReturn
                          ? 'Record a full or partial return against a completed POS sale.'
                          : 'Returns will appear here when recorded by an authorized user.',
                      textAlign: TextAlign.center,
                    ),
                    if (canReturn) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _openReturnForm(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Record return'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          final total = returns.fold<int>(
            0,
            (sum, row) => sum + (returnTotalById[row.id] ?? 0),
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        color: scheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${returns.length} return${returns.length == 1 ? '' : 's'} recorded',
                              style: TextStyle(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Refunds recorded · no finance entries posted',
                              style: TextStyle(
                                color: scheme.onTertiaryContainer,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatPeso(total),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: scheme.onTertiaryContainer,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: returns.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final row = returns[index];
                    final sale = salesById[row.saleId];
                    final count = returnCountById[row.id] ?? 0;
                    return Card(
                      elevation: 0,
                      color: scheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: .45),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: scheme.tertiaryContainer,
                          foregroundColor: scheme.onTertiaryContainer,
                          child: const Icon(Icons.assignment_return_rounded),
                        ),
                        title: Text(
                          'Receipt ${sale?.receiptNo ?? row.saleId.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${DateFormat('MMM d, yyyy · h:mm a').format(row.createdAt)} · '
                                '$count item${count == 1 ? '' : 's'}',
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Refund via ${accountsById[row.refundAccountId]?.name ?? 'payment account'}'
                                '${row.reason.trim().isEmpty ? '' : ' · ${row.reason}'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        trailing: Text(
                          formatPeso(returnTotalById[row.id] ?? 0),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openReturnForm(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewReturnSheet(),
    );
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Return recorded.')));
  }
}

class _NewReturnSheet extends ConsumerStatefulWidget {
  const _NewReturnSheet();

  @override
  ConsumerState<_NewReturnSheet> createState() => _NewReturnSheetState();
}

class _NewReturnSheetState extends ConsumerState<_NewReturnSheet> {
  final _reason = TextEditingController();
  final _quantities = <String, double>{};
  String? _saleId;
  String? _accountId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sales =
        (ref.watch(posSalesHistoryProvider).value ?? const <PosSale>[])
            .where((sale) => !sale.isVoided && !sale.isStockOnly)
            .toList();
    final accounts = ref.watch(_refundAccountsProvider).value ?? const [];
    final returns = ref.watch(posReturnsProvider).value ?? const <PosReturn>[];
    final returnItems =
        ref.watch(posReturnItemsProvider).value ?? const <PosReturnItem>[];
    final sale = sales.where((s) => s.id == _saleId).firstOrNull;
    final returnIds = returns
        .where((r) => r.saleId == _saleId)
        .map((r) => r.id)
        .toSet();
    final alreadyReturned = <String, double>{};
    final alreadyRefunded = <String, int>{};
    for (final item in returnItems.where((i) => returnIds.contains(i.returnId))) {
      alreadyReturned.update(
        item.saleItemId,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
      alreadyRefunded.update(
        item.saleItemId,
        (value) => value + item.refundAmount,
        ifAbsent: () => item.refundAmount,
      );
    }

    final itemsAsync = sale == null
        ? null
        : ref.watch(posSaleItemsProvider(sale.id));
    final items = itemsAsync?.value ?? const <PosSaleItem>[];
    final orderedItems = [...items]
      ..sort((a, b) => a.id.compareTo(b.id));
    final gross = orderedItems.fold<int>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final allocatedNet = <String, int>{};
    var allocated = 0;
    for (var i = 0; i < orderedItems.length; i++) {
      final item = orderedItems[i];
      final net = sale == null || gross <= 0
          ? 0
          : i == orderedItems.length - 1
          ? sale.totalAmount - allocated
          : (item.lineTotal * sale.totalAmount / gross).round();
      allocatedNet[item.id] = net;
      allocated += net;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        top: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
          maxWidth: 620,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Record return',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _saleId,
              decoration: const InputDecoration(
                labelText: 'Original POS receipt',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in sales)
                  DropdownMenuItem(
                    value: entry.id,
                    child: Text(
                      '${entry.receiptNo ?? entry.id.substring(0, 8).toUpperCase()} · '
                      '${DateFormat('MMM d').format(entry.saleDate)} · '
                      '${formatPeso(entry.totalAmount)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _saleId = value;
                      _quantities.clear();
                      _error = null;
                    }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: 'Refund through',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              enabled: !_saving,
              maxLength: 500,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for return',
                prefixIcon: Icon(Icons.notes_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Return quantities',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            if (sale == null)
              Expanded(
                child: Center(
                  child: Text(
                    sales.isEmpty
                        ? 'There are no completed POS sales to return.'
                        : 'Choose the original receipt to see its items.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (itemsAsync?.isLoading == true)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (itemsAsync?.hasError == true)
              Expanded(
                child: Center(
                  child: Text('Unable to load receipt items: ${itemsAsync!.error}'),
                ),
              )
            else if (items.isEmpty)
              const Expanded(child: Center(child: Text('This receipt has no items.')))
            else
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final returned = alreadyReturned[item.id] ?? 0;
                    final remaining = (item.quantity - returned).clamp(
                      0.0,
                      item.quantity,
                    );
                    final quantity = _quantities[item.id] ?? 0;
                    final lineRefund = item.quantity <= 0
                        ? 0
                        : (allocatedNet[item.id]! *
                                      (returned + quantity) /
                                      item.quantity)
                                  .round() -
                              (alreadyRefunded[item.id] ?? 0);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${item.quantity} ${item.unit} sold · '
                        '${remaining.toStringAsFixed(remaining % 1 == 0 ? 0 : 2)} remaining · '
                        'Refund estimate ${formatPeso(lineRefund)}',
                      ),
                      trailing: SizedBox(
                        width: 94,
                        child: TextFormField(
                          key: ValueKey('${sale.id}:${item.id}:$remaining'),
                          initialValue: quantity == 0 ? '' : '$quantity',
                          enabled: !_saving && remaining > 0,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            hintText: '0',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (raw) => setState(() {
                            final value = double.tryParse(raw.trim()) ?? 0;
                            _quantities[item.id] =
                                value.clamp(0.0, remaining).toDouble();
                            _error = null;
                          }),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Recording…' : 'Record refund'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final saleId = _saleId;
    final accountId = _accountId;
    if (saleId == null || accountId == null) {
      setState(() => _error = 'Choose a receipt and refund account.');
      return;
    }
    final quantities = Map.fromEntries(
      _quantities.entries.where((entry) => entry.value > 0),
    );
    if (quantities.isEmpty) {
      setState(() => _error = 'Enter a return quantity for at least one item.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sale = (ref.read(posSalesHistoryProvider).value ?? const <PosSale>[])
          .where((entry) => entry.id == saleId)
          .firstOrNull;
      if (sale == null) throw StateError('The selected receipt is unavailable.');
      Approver? approver;
      if (await ApprovalService.anyPinSet(
        ref.read(databaseProvider),
        sale.businessId,
      )) {
        if (!mounted) return;
        approver = await requestManagerApproval(
          context,
          title: 'Manager approval',
          message: 'Enter an owner or manager PIN to approve this refund.',
          permission: BosPermission.salesVoid,
        );
        if (approver == null || !mounted) {
          setState(() => _saving = false);
          return;
        }
      }
      final id = await ref
          .read(posReturnServiceProvider)
          .createReturn(
            saleId: saleId,
            refundAccountId: accountId,
            reason: _reason.text,
            quantitiesBySaleItemId: quantities,
            approvedByUserId: approver?.userId,
            approvedByName: approver?.name,
          );
      ref.invalidate(posReturnsProvider);
      ref.invalidate(posReturnItemsProvider);
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message
              : error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }
}
