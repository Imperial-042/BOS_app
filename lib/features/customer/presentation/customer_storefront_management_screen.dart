import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_order_state.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

class CustomerStorefrontManagementScreen extends ConsumerStatefulWidget {
  const CustomerStorefrontManagementScreen({super.key, this.initialTab = 0})
    : assert(initialTab >= 0 && initialTab < 2);

  final int initialTab;

  @override
  ConsumerState<CustomerStorefrontManagementScreen> createState() =>
      _CustomerStorefrontManagementScreenState();
}

class _CustomerStorefrontManagementScreenState
    extends ConsumerState<CustomerStorefrontManagementScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _points = TextEditingController(text: '0');
  final Set<String> _selectedProducts = {};
  final Map<int, StoreHours> _openingHours = {};
  List<Product>? _products;
  String? _currencyCode;
  bool _published = false;
  bool _offline = false;
  bool _loading = true;
  bool _loadError = false;
  bool _saving = false;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _loadLocal();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _points.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = false;
        _error = null;
      });
    }
    try {
      final db = ref.read(databaseProvider);
      final businessId = ref.read(selectedBusinessIdProvider);
      final business = await (db.select(
        db.businesses,
      )..where((b) => b.id.equals(businessId))).getSingleOrNull();
      final managed = await ref
          .read(customerCommerceServiceProvider)
          .loadManagedStorefront(businessId);
      final products =
          await (db.select(db.products)..where(
                (p) =>
                    p.businessId.equals(businessId) &
                    p.isActive.equals(true) &
                    p.isSellable.equals(true),
              ))
              .get();
      if (!mounted) return;
      setState(() {
        _name.text = managed.storefront?.name ?? business?.name ?? '';
        _description.text =
            managed.storefront?.description ?? business?.description ?? '';
        _phone.text = managed.storefront?.phone ?? '';
        _address.text = managed.storefront?.address ?? '';
        _city.text = managed.storefront?.city ?? business?.addressCity ?? '';
        _points.text = '${managed.storefront?.pointsPerCurrencyUnit ?? 0}';
        _currencyCode =
            managed.storefront?.currencyCode ?? business?.currency ?? 'PHP';
        _published = managed.storefront?.isPublished ?? false;
        _offline = managed.storefront?.offlineEnabled ?? false;
        _openingHours
          ..clear()
          ..addAll(
            parseStoreHours(
              managed.storefront == null
                  ? '{}'
                  : storefrontOpeningHoursJson(managed.storefront!),
            ),
          );
        _selectedProducts
          ..clear()
          ..addAll(managed.items.map((item) => item.id));
        _products = products;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = true;
          _error = 'Could not load cloud storefront settings: $error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final businessId = ref.read(selectedBusinessIdProvider);
    final points = int.tryParse(_points.text.trim());
    if (points == null || points < 0 || points > 1000) {
      setState(
        () => _error = 'Points per currency unit must be between 0 and 1000.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      serializeStoreHours(_openingHours);
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.businessSettings, businessId: businessId);
      await ref
          .read(customerCommerceServiceProvider)
          .publishStorefront(
            businessId: businessId,
            name: _name.text,
            description: _description.text,
            phone: _phone.text,
            address: _address.text,
            city: _city.text,
            currencyCode: _currencyCode ?? 'PHP',
            isPublished: _published,
            offlineEnabled: _offline,
            pointsPerCurrencyUnit: points,
            openingHours: Map.of(_openingHours),
            publishedProductIds: _selectedProducts,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _published ? 'Storefront published.' : 'Storefront saved.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessId = ref.watch(selectedBusinessIdProvider);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 2,
      initialIndex: _tab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customer storefront'),
          bottom: TabBar(
            onTap: (index) => setState(() => _tab = index),
            tabs: const [
              Tab(text: 'Publish', icon: Icon(Icons.storefront_outlined)),
              Tab(text: 'Orders', icon: Icon(Icons.receipt_long_outlined)),
            ],
          ),
        ),
        body: _tab == 0
            ? _buildSettings(context, businessId)
            : _StoreOrderInbox(
                businessId: businessId,
                returnToPosOnImport: false,
              ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context, String businessId) {
    final products = _products ?? const <Product>[];
    final isCloudId = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(businessId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!isCloudId)
          const _InfoCard(
            text:
                'This business is local-only. Link it to the cloud before customers can discover the storefront.',
            error: true,
          ),
        if (_error != null) _InfoCard(text: _error!, error: true),
        if (_loadError)
          OutlinedButton.icon(
            onPressed: _loading ? null : _loadLocal,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry loading settings'),
          ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Store name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Public description',
            helperText: 'Shown to customers in the storefront.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          decoration: const InputDecoration(
            labelText: 'Storefront city (optional)',
            helperText: 'Customer matching uses each branch city below.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          decoration: const InputDecoration(
            labelText: 'Public address (optional)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Public store phone (optional)',
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 20),
        Text(
          'Store opening hours',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _openingHours.isEmpty
              ? 'No schedule set. Orders are accepted at any time until you set hours.'
              : 'Days not enabled below are closed. New orders are blocked outside these hours.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ..._openingHoursWidgets(context),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _offline,
          onChanged: (value) => setState(() => _offline = value),
          title: const Text('Allow cached offline catalog'),
          subtitle: const Text(
            'Customers can keep viewing the last loaded catalog while offline.',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _points,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Points per ${_currencyCode ?? 'PHP'} 1 spent',
            helperText:
                'Points are added only after the business marks an order completed. Set 0 to disable.',
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Publish products',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Only selected sellable products are shared. Recipes, stock, costs, '
          'supplies, and internal product codes are not included.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (products.isEmpty)
          const ListTile(title: Text('No active sellable products.'))
        else
          for (final product in products)
            CheckboxListTile(
              value: _selectedProducts.contains(product.id),
              onChanged: (value) => setState(() {
                if (value ?? false) {
                  _selectedProducts.add(product.id);
                } else {
                  _selectedProducts.remove(product.id);
                }
              }),
              title: Text(product.name),
              subtitle: Text(
                product.sellPrice == null
                    ? '${product.unit} • Price needed before customer ordering'
                    : '${product.unit} • ${_formatPrice(product.sellPrice!, _currencyCode ?? 'PHP')}',
              ),
              secondary: const Icon(Icons.inventory_2_outlined),
            ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _published,
          onChanged: (value) => setState(() => _published = value),
          title: const Text('Publish storefront'),
          subtitle: const Text(
            'Published stores are discoverable by signed-in customers.',
          ),
        ),
        if (_published) ...[
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: storefrontInvitePayload(businessId),
                    size: 190,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'Store follow invitation QR code',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Customers scan this QR and choose to follow.'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saving || _loadError || !isCloudId ? null : _save,
          child: _saving
              ? const CircularProgressIndicator()
              : const Text('Save and publish'),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  List<Widget> _openingHoursWidgets(BuildContext context) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return [
      for (var day = 1; day <= 7; day++)
        Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(days[day - 1]),
              value: _openingHours.containsKey(day),
              onChanged: _saving
                  ? null
                  : (enabled) => setState(() {
                      if (enabled) {
                        _openingHours[day] = (open: '09:00', close: '17:00');
                      } else {
                        _openingHours.remove(day);
                      }
                    }),
            ),
            if (_openingHours[day] case final hours?)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _chooseTime(day, opening: true),
                      icon: const Icon(Icons.schedule),
                      label: Text('Opens ${_timeLabel(hours.open, context)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _chooseTime(day, opening: false),
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text('Closes ${_timeLabel(hours.close, context)}'),
                    ),
                  ),
                ],
              ),
          ],
        ),
    ];
  }

  Future<void> _chooseTime(int day, {required bool opening}) async {
    final hours = _openingHours[day];
    if (hours == null) return;
    final value = opening ? hours.open : hours.close;
    final parts = value.split(':');
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (selected == null || !mounted) return;
    final formatted =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    setState(() {
      _openingHours[day] = opening
          ? (open: formatted, close: hours.close)
          : (open: hours.open, close: formatted);
    });
  }

  String _timeLabel(String value, BuildContext context) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    ).format(context);
  }
}

class _StoreOrderInbox extends ConsumerStatefulWidget {
  const _StoreOrderInbox({
    required this.businessId,
    this.branchId,
    this.returnToPosOnImport = false,
  });

  final String businessId;
  final String? branchId;
  final bool returnToPosOnImport;

  @override
  ConsumerState<_StoreOrderInbox> createState() => _StoreOrderInboxState();
}

class CustomerOrdersInboxScreen extends StatelessWidget {
  const CustomerOrdersInboxScreen({
    required this.businessId,
    required this.branchId,
    super.key,
  });

  final String businessId;
  final String branchId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer orders')),
    body: _StoreOrderInbox(
      businessId: businessId,
      branchId: branchId,
      returnToPosOnImport: true,
    ),
  );
}

class _StoreOrderInboxState extends ConsumerState<_StoreOrderInbox> {
  late Future<List<CustomerOrder>> _orders;
  String? _workingOrderId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _orders = ref
        .read(customerCommerceServiceProvider)
        .loadOrders(businessId: widget.businessId, branchId: widget.branchId);
  }

  Future<void> _setStatus(CustomerOrder order, String status) async {
    setState(() => _workingOrderId = order.id);
    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.salesEdit, businessId: widget.businessId);
      await ref
          .read(customerCommerceServiceProvider)
          .updateOrderStatus(
            orderId: order.id,
            businessId: widget.businessId,
            status: status,
          );
      if (status == 'cancelled') {
        if (ref.read(posOrderDetailsProvider).customerOrderId == order.id) {
          ref.read(posOrderProvider.notifier).clear();
        }
        ref
            .read(heldOrdersProvider.notifier)
            .discardByCustomerOrderId(order.id);
      }
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update order: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _workingOrderId = null);
    }
  }

  Future<void> _addToPos(CustomerOrder order) async {
    if (order.status != 'accepted') return;
    if (!widget.returnToPosOnImport || widget.branchId == null) return;
    if (order.branchId != widget.branchId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select the order’s pickup branch in the POS first.'),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _workingOrderId = order.id);
    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.salesCreate, businessId: widget.businessId);
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.salesEdit, businessId: widget.businessId);
      final service = ref.read(customerCommerceServiceProvider);
      final items = await service.loadOrderItems(order.id);
      if (items.isEmpty) throw StateError('This order has no items.');

      final db = ref.read(databaseProvider);
      final products =
          await (db.select(db.products)..where(
                (product) =>
                    product.businessId.equals(widget.businessId) &
                    product.id.isIn(items.map((item) => item.catalogItemId)) &
                    product.isActive.equals(true) &
                    product.isSellable.equals(true),
              ))
              .get();
      final productsById = {
        for (final product in products) product.id: product,
      };
      final lines = <POSLineItem>[];
      for (final item in items) {
        final product = productsById[item.catalogItemId];
        if (product == null) {
          throw StateError(
            '${item.itemName} is no longer an active POS product.',
          );
        }
        final quantity = item.quantity.round();
        if (quantity <= 0 || (item.quantity - quantity).abs() > 0.000001) {
          throw StateError(
            '${item.itemName} has a fractional quantity that the POS order '
            'cannot represent.',
          );
        }
        lines.add(
          POSLineItem(
            productId: product.id,
            name: item.itemName,
            unit: item.unit,
            unitPriceCents: item.unitPriceCents,
            quantity: quantity,
          ),
        );
      }

      final currentLines = ref.read(posOrderProvider);
      final currentDetails = ref.read(posOrderDetailsProvider);
      final currentOrderType = ref.read(posOrderTypeProvider);
      final heldOrders = ref.read(heldOrdersProvider);
      if (currentDetails.customerOrderId == order.id ||
          heldOrders.any((held) => held.details.customerOrderId == order.id)) {
        throw StateError('This customer order is already in the POS.');
      }
      await service.updateOrderStatus(
        orderId: order.id,
        businessId: widget.businessId,
        status: 'preparing',
      );
      if (currentLines.isNotEmpty) {
        ref
            .read(heldOrdersProvider.notifier)
            .hold(
              currentLines,
              orderType: currentOrderType,
              details: currentDetails,
            );
      }
      ref.read(posOrderProvider.notifier).replaceAll(lines);
      ref
          .read(posOrderDetailsProvider.notifier)
          .replace(
            OrderDetails(
              contactName: order.customerName,
              contactPhone: order.customerPhone,
              customerOrderId: order.id,
            ),
          );

      if (mounted) {
        if (!widget.returnToPosOnImport) setState(_refresh);
        if (widget.returnToPosOnImport) Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              currentLines.isEmpty
                  ? 'Customer order added to the POS and marked as preparing.'
                  : 'Customer order added to the POS and marked as preparing. Previous draft held.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not add order to POS: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _workingOrderId = null);
    }
  }

  Future<void> _confirmCancel(CustomerOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel customer order?'),
        content: Text('Cancel the order from ${order.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _setStatus(order, 'cancelled');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CustomerOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InfoCard(
            text: 'Could not load orders: ${snapshot.error}',
            error: true,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('No customer orders yet.'));
        }
        return RefreshIndicator(
          onRefresh: () async => setState(_refresh),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final order in snapshot.data!)
                Card(
                  child: ExpansionTile(
                    title: Text('${order.customerName} • ${order.branchName}'),
                    subtitle: Text(
                      '${order.status.toUpperCase()} • ${_formatPrice(order.totalCents, order.currencyCode)}',
                    ),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(order.customerPhone),
                        subtitle: const Text('Shared for this order only'),
                      ),
                      if (order.requestsOfficialReceipt)
                        ListTile(
                          leading: const Icon(Icons.receipt_outlined),
                          title: Text(
                            'Official receipt • TIN ${order.customerTin}',
                          ),
                        ),
                      if (order.notes?.isNotEmpty == true)
                        ListTile(title: Text(order.notes!)),
                      FutureBuilder<List<CustomerOrderItem>>(
                        future: ref
                            .read(customerCommerceServiceProvider)
                            .loadOrderItems(order.id),
                        builder: (context, items) {
                          if (items.hasError) {
                            return ListTile(
                              title: Text('Items unavailable: ${items.error}'),
                            );
                          }
                          if (!items.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            );
                          }
                          return Column(
                            children: [
                              for (final item in items.data!)
                                ListTile(
                                  dense: true,
                                  title: Text(item.itemName),
                                  subtitle: Text(
                                    '${item.quantity} ${item.unit}',
                                  ),
                                  trailing: Text(
                                    _formatPrice(
                                      item.totalCents,
                                      order.currencyCode,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        children: _availableTransitions(order.status)
                            .map(
                              (transition) => TextButton(
                                onPressed: () =>
                                    _setStatus(order, transition.$1),
                                child: Text(transition.$2),
                              ),
                            )
                            .toList(),
                      ),
                      if (order.status == 'accepted' &&
                          widget.returnToPosOnImport)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _workingOrderId == null
                                  ? () => _addToPos(order)
                                  : null,
                              icon: const Icon(Icons.point_of_sale_outlined),
                              label: Text(
                                _workingOrderId == order.id
                                    ? 'Adding to POS...'
                                    : 'Add to POS current order',
                              ),
                            ),
                          ),
                        ),
                      if (_canCancelCustomerOrder(order.status))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: OutlinedButton.icon(
                            onPressed: _workingOrderId == null
                                ? () => _confirmCancel(order)
                                : null,
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel order'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

List<(String, String)> _availableTransitions(String status) => switch (status) {
  'pending' => [('accepted', 'Accept'), ('rejected', 'Decline')],
  'accepted' => [('preparing', 'Start preparing')],
  'preparing' => [('ready', 'Ready for pickup')],
  'ready' => [('completed', 'Complete and award points')],
  _ => const [],
};

bool _canCancelCustomerOrder(String status) =>
    status == 'pending' ||
    status == 'accepted' ||
    status == 'preparing' ||
    status == 'ready';

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Card(
    color: error
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
  );
}

String _formatPrice(int cents, String currency) =>
    '${currency.toUpperCase()} ${(cents / 100).toStringAsFixed(2)}';
