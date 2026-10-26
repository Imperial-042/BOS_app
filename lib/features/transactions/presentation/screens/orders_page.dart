import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/domain/pos_return_service.dart';
import 'package:bos_application/features/transactions/domain/sales_analytics.dart'
    show allPosSaleItemsProvider;
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart'
    show customersProvider;
import 'package:bos_application/features/transactions/presentation/screens/pos_history_page.dart'
    show POSSaleDetailPage, posSalesHistoryProvider;
import 'package:bos_application/features/transactions/presentation/screens/returns_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';

enum _OrderFilter { all, active, returned, voided }

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  final _search = TextEditingController();
  String _query = '';
  _OrderFilter _filter = _OrderFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final salesAsync = ref.watch(posSalesHistoryProvider);
    final allSaleItems =
        ref.watch(allPosSaleItemsProvider).value ?? const <PosSaleItem>[];
    final itemsBySale = <String, List<PosSaleItem>>{};
    for (final item in allSaleItems) {
      (itemsBySale[item.saleId] ??= []).add(item);
    }
    final returns = ref.watch(posReturnsProvider).value ?? const <PosReturn>[];
    final returnItems =
        ref.watch(posReturnItemsProvider).value ?? const <PosReturnItem>[];
    final customers =
        ref.watch(customersProvider).value ?? const <Customer>[];
    final saleIdsByReturn = {for (final r in returns) r.id: r.saleId};
    final returnedQuantityByItem = <String, double>{};
    for (final item in returnItems) {
      if (!saleIdsByReturn.containsKey(item.returnId)) continue;
      returnedQuantityByItem.update(
        item.saleItemId,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Orders'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ReturnsPage(),
              ),
            ),
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('Returns'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search receipt, customer, or order reference',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final filter in _OrderFilter.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(switch (filter) {
                        _OrderFilter.all => 'All orders',
                        _OrderFilter.active => 'Active',
                        _OrderFilter.returned => 'Returned',
                        _OrderFilter.voided => 'Voided',
                      }),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: salesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text('Unable to load orders: $error'),
              ),
              data: (sales) {
                final filtered = sales.where((sale) {
                  if (sale.isStockOnly) return false;
                  final name = customers
                      .where((customer) => customer.id == sale.customerId)
                      .map((customer) => customer.name)
                      .firstOrNull;
                  final itemIds = returns
                      .where((r) => r.saleId == sale.id)
                      .map((r) => r.id)
                      .toSet();
                  final hasReturn = itemIds.isNotEmpty;
                  final isFullyReturned = hasReturn &&
                      _isFullyReturned(
                        itemsBySale[sale.id] ?? const [],
                        returnedQuantityByItem,
                      );

                  if (_filter == _OrderFilter.active &&
                      (sale.isVoided || isFullyReturned)) {
                    return false;
                  }
                  if (_filter == _OrderFilter.returned && !hasReturn) {
                    return false;
                  }
                  if (_filter == _OrderFilter.voided && !sale.isVoided) {
                    return false;
                  }
                  if (_query.isEmpty) return true;
                  final haystack = [
                    sale.receiptNo,
                    sale.orderRef,
                    sale.orderType,
                    sale.contactName,
                    sale.contactPhone,
                    sale.deliveryAddress,
                    sale.notes,
                    sale.cashierName,
                    name,
                  ].whereType<String>().join(' ').toLowerCase();
                  return haystack.contains(_query.toLowerCase());
                }).toList();

                if (filtered.isEmpty) {
                  return _OrdersEmpty(
                    searching: _query.isNotEmpty || _filter != _OrderFilter.all,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final sale = filtered[index];
                    final customer = customers
                        .where((c) => c.id == sale.customerId)
                        .map((c) => c.name)
                        .firstOrNull;
                    final orderReturns =
                        returns.where((r) => r.saleId == sale.id).toList();
                    final orderReturnIds =
                        orderReturns.map((r) => r.id).toSet();
                    final orderReturnLines = returnItems
                        .where((r) => orderReturnIds.contains(r.returnId))
                        .toList();
                    final isFullyReturned = orderReturnLines.isNotEmpty &&
                        _isFullyReturned(
                          itemsBySale[sale.id] ?? const [],
                          returnedQuantityByItem,
                        );
                    return _OrderCard(
                      sale: sale,
                      customerName: customer,
                      returned: orderReturns.isNotEmpty,
                      fullyReturned: isFullyReturned,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => POSSaleDetailPage(sale: sale),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isFullyReturned(
    List<PosSaleItem> items,
    Map<String, double> returnedQuantityByItem,
  ) {
    if (items.isEmpty) return false;
    return items.every(
      (item) =>
          (returnedQuantityByItem[item.id] ?? 0) + 1e-9 >= item.quantity,
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.sale,
    required this.customerName,
    required this.returned,
    required this.fullyReturned,
    required this.onTap,
  });

  final PosSale sale;
  final String? customerName;
  final bool returned;
  final bool fullyReturned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = sale.isVoided
        ? ('Voided', scheme.error, Icons.block_rounded)
        : fullyReturned
        ? ('Returned', scheme.tertiary, Icons.assignment_return_rounded)
        : returned
        ? ('Partially returned', scheme.tertiary, Icons.assignment_return_outlined)
        : ('Paid', scheme.primary, Icons.check_circle_outline_rounded);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sale.receiptNo?.trim().isNotEmpty == true
                          ? sale.receiptNo!
                          : 'Order ${sale.id.substring(0, 8).toUpperCase()}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _OrderStatus(label: status.$1, color: status.$2, icon: status.$3),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _OrderMeta(
                    icon: Icons.schedule_rounded,
                    label: DateFormat('MMM d, yyyy · h:mm a').format(sale.saleDate),
                  ),
                  if ((sale.orderType ?? '').trim().isNotEmpty)
                    _OrderMeta(
                      icon: Icons.category_outlined,
                      label: sale.orderType!,
                    ),
                  if ((customerName ?? sale.contactName)?.trim().isNotEmpty ==
                      true)
                    _OrderMeta(
                      icon: Icons.person_outline_rounded,
                      label: customerName ?? sale.contactName!,
                    ),
                  if ((sale.orderRef ?? '').trim().isNotEmpty)
                    _OrderMeta(
                      icon: Icons.confirmation_number_outlined,
                      label: sale.orderRef!,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sale.cashierName?.trim().isNotEmpty == true
                          ? 'Cashier: ${sale.cashierName}'
                          : 'POS order',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    formatPeso(sale.totalAmount),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: sale.isVoided ? scheme.onSurfaceVariant : null,
                      decoration:
                          sale.isVoided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderStatus extends StatelessWidget {
  const _OrderStatus({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _OrderMeta extends StatelessWidget {
  const _OrderMeta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}

class _OrdersEmpty extends StatelessWidget {
  const _OrdersEmpty({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.receipt_long_rounded,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            searching ? 'No matching orders' : 'No orders yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            searching
                ? 'Try another search or filter.'
                : 'Completed POS sales will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
