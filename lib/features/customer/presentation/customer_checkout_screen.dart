import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_design.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:bos_application/features/customer/presentation/customer_addresses_screen.dart';
import 'package:bos_application/core/location/location_picker_map.dart';
import 'package:bos_application/core/location/location_repository.dart';
import 'package:bos_application/core/location/location_services.dart';
import 'package:bos_application/features/transactions/domain/product_variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CustomerCheckoutScreen extends ConsumerStatefulWidget {
  const CustomerCheckoutScreen({
    required this.store,
    required this.items,
    required this.branchId,
    this.catalog,
    super.key,
  });

  final CustomerStorefront store;
  final List<CustomerCartLine> items;
  final String branchId;

  /// Optional: lets the screen show an order summary and estimated total.
  final List<CustomerCatalogItem>? catalog;

  @override
  ConsumerState<CustomerCheckoutScreen> createState() =>
      _CustomerCheckoutScreenState();
}

class _CustomerCheckoutScreenState
    extends ConsumerState<CustomerCheckoutScreen> {
  final _phone = TextEditingController();
  final _tin = TextEditingController();
  final _notes = TextEditingController();
  late Future<List<CustomerStoreBranchWithCity>> _branchesFuture;
  late Future<List<SavedCustomerAddress>> _addressesFuture;
  String? _branchId;
  String? _addressId;
  bool _delivery = false;
  bool _officialReceipt = false;
  String _paymentMethod = 'cash';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _branchesFuture = _loadBranches(ref.read(customerCommerceServiceProvider));
    _addressesFuture = _loadAddresses();
  }

  Future<List<SavedCustomerAddress>> _loadAddresses() async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return const [];
    return ref
        .read(customerLocationRepositoryProvider)
        .loadCustomerAddresses(userId);
  }

  @override
  void dispose() {
    _phone.dispose();
    _tin.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<List<CustomerStoreBranchWithCity>> _loadBranches(
    CustomerCommerceService service,
  ) async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return const [];
    final profile = await service.loadCustomerProfile(userId);
    final branches = await service.loadStoreBranches(
      widget.store.businessId,
      city: profile?.city ?? '',
    );
    return branches.where((b) => b.id == widget.branchId).toList();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  Future<void> _submit(List<CustomerStoreBranchWithCity> branches) async {
    if (_branchId == null || branches.every((b) => b.id != _branchId)) {
      _showMessage('Select an active pickup branch.');
      return;
    }
    final selected = branches.firstWhere((b) => b.id == _branchId);
    if (!branchIsOpen(selected)) {
      _showMessage('${selected.name} is closed right now.');
      return;
    }
    if (_phone.text.trim().length < 5) {
      _showMessage('Enter a valid contact phone number.');
      return;
    }
    if (_officialReceipt && _tin.text.trim().isEmpty) {
      _showMessage('Enter your TIN to request an official receipt.');
      return;
    }
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    final addresses = _delivery
        ? await _addressesFuture
        : const <SavedCustomerAddress>[];
    final selectedAddress = addresses
        .where((address) => address.id == _addressId)
        .firstOrNull;
    if (_delivery && selectedAddress == null) {
      _showMessage('Select a saved delivery address.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(customerCommerceServiceProvider)
          .submitOrder(
            userId: userId,
            businessId: widget.store.businessId,
            branchId: _branchId!,
            phone: _phone.text,
            requestsOfficialReceipt: _officialReceipt,
            tin: _tin.text,
            notes: _notes.text,
            items: [
              for (final line in widget.items)
                (
                  itemId: line.itemId,
                  quantity: line.quantity,
                  options: line.options,
                ),
            ],
            fulfillmentType: _delivery ? 'delivery' : 'pickup',
            deliveryAddressId: selectedAddress?.id,
            deliveryAddress: selectedAddress?.address,
            paymentMethod: _paymentMethod,
          );
      // `ref` must not be used after this screen is disposed.
      if (!mounted) return;
      ref.invalidate(customerHomeOrdersProvider(userId));
      ref
              .read(
                customerCartProvider(
                  customerCartKey(widget.store.businessId, widget.branchId),
                ).notifier,
              )
              .state =
          <CustomerCartLine>[];
      _showMessage('Order sent to the store.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      _showMessage('Could not submit order: ${friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _section({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final catalogById = {
      for (final i in widget.catalog ?? const <CustomerCatalogItem>[]) i.id: i,
    };
    var estimated = 0.0;
    for (final line in widget.items) {
      final price = catalogById[line.itemId]?.priceCents;
      if (price != null) {
        estimated +=
            (price +
                line.options.fold<int>(
                  0,
                  (sum, option) => sum + option.priceDeltaCents,
                )) *
            line.quantity;
      }
    }
    final currency = widget.store.currencyCode;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Checkout',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              widget.store.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<CustomerStoreBranchWithCity>>(
        future: _branchesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return CustomerStateMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load pickup branches',
              message: friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = snapshot.data!;
          if (branches.isEmpty) {
            return const CustomerStateMessage(
              icon: Icons.location_off_outlined,
              title: 'No pickup branches',
              message: 'This store has not published an active pickup branch.',
            );
          }
          if (branches.every((branch) => branch.id != _branchId)) {
            final firstOpen = branches.where((b) => branchIsOpen(b));
            _branchId =
                (firstOpen.isNotEmpty ? firstOpen.first : branches.first).id;
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    if (widget.catalog != null) ...[
                      _section(
                        icon: Icons.shopping_bag_outlined,
                        title: 'Your order',
                        subtitle:
                            '${widget.items.length} item'
                            '${widget.items.length == 1 ? '' : 's'}',
                        child: Column(
                          children: [
                            for (final line in widget.items)
                              if (catalogById[line.itemId] case final item?)
                                _SummaryRow(
                                  name: item.name,
                                  quantity: line.quantity,
                                  options: line.options,
                                  totalLabel: item.priceCents == null
                                      ? '—'
                                      : formatCustomerPrice(
                                          ((item.priceCents! +
                                                      line.options.fold<int>(
                                                        0,
                                                        (sum, option) =>
                                                            sum +
                                                            option
                                                                .priceDeltaCents,
                                                      )) *
                                                  line.quantity)
                                              .round(),
                                          currency,
                                        ),
                                ),
                            const Divider(height: 22),
                            Row(
                              children: [
                                Text(
                                  'Estimated total',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  formatCustomerPrice(
                                    estimated.round(),
                                    currency,
                                  ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _section(
                      icon: Icons.location_on_outlined,
                      title: 'Fulfilment',
                      subtitle: 'Choose pickup or delivery.',
                      child: Column(
                        children: [
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.store_outlined),
                                label: Text('Pickup'),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.delivery_dining_outlined),
                                label: Text('Delivery'),
                              ),
                            ],
                            selected: {_delivery},
                            onSelectionChanged: _submitting
                                ? null
                                : (value) =>
                                      setState(() => _delivery = value.first),
                          ),
                          const SizedBox(height: 12),
                          for (final branch in branches)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _BranchTile(
                                branch: branch,
                                selected: branch.id == _branchId,
                                onTap: (_submitting || !branchIsOpen(branch))
                                    ? null
                                    : () =>
                                          setState(() => _branchId = branch.id),
                              ),
                            ),
                          if (_delivery)
                            FutureBuilder<List<SavedCustomerAddress>>(
                              future: _addressesFuture,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: LinearProgressIndicator(),
                                  );
                                }
                                final addresses = snapshot.data!;
                                if (addresses.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const CustomerAddressesScreen(),
                                          ),
                                        );
                                        if (mounted) {
                                          setState(
                                            () => _addressesFuture =
                                                _loadAddresses(),
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.add_location_alt_outlined,
                                      ),
                                      label: const Text(
                                        'Add a delivery address',
                                      ),
                                    ),
                                  );
                                }
                                _addressId ??= addresses
                                    .firstWhere(
                                      (address) => address.isDefault,
                                      orElse: () => addresses.first,
                                    )
                                    .id;
                                final selected = addresses
                                    .where((a) => a.id == _addressId)
                                    .firstOrNull;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: _addressId,
                                      decoration: const InputDecoration(
                                        labelText: 'Delivery address',
                                        prefixIcon: Icon(Icons.home_outlined),
                                      ),
                                      items: [
                                        for (final address in addresses)
                                          DropdownMenuItem(
                                            value: address.id,
                                            child: Text(
                                              '${address.label} · '
                                              '${address.address.formattedAddress ?? address.address.city ?? ''}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) => setState(() {
                                        _addressId = value;
                                        final address = addresses
                                            .where((a) => a.id == value)
                                            .firstOrNull;
                                        if (address?.address.contactNumber
                                                ?.trim()
                                                .isNotEmpty ==
                                            true) {
                                          _phone.text =
                                              address!.address.contactNumber!;
                                        }
                                      }),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  const CustomerAddressesScreen(),
                                            ),
                                          );
                                          if (mounted) {
                                            setState(
                                              () => _addressesFuture =
                                                  _loadAddresses(),
                                            );
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.add_location_alt_outlined,
                                        ),
                                        label: const Text(
                                          'Add another delivery address',
                                        ),
                                      ),
                                    ),
                                    if (selected?.address.coordinate !=
                                        null) ...[
                                      const SizedBox(height: 10),
                                      LocationPickerMap(
                                        provider:
                                            const OpenStreetMapTileProvider(),
                                        selected: selected!.address.coordinate,
                                        height: 190,
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.phone_outlined,
                      title: 'Contact',
                      subtitle: 'Shared with this store for fulfilment.',
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact phone',
                          prefixIcon: Icon(Icons.call_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.payments_outlined,
                      title: 'Payment method',
                      subtitle: 'Tell the store how you will pay.',
                      child: DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Payment method',
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                          DropdownMenuItem(
                            value: 'gcash',
                            child: Text('GCash'),
                          ),
                          DropdownMenuItem(value: 'maya', child: Text('Maya')),
                          DropdownMenuItem(value: 'card', child: Text('Card')),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) => setState(
                                () => _paymentMethod = value ?? 'cash',
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.receipt_outlined,
                      title: 'Receipt',
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _officialReceipt,
                            onChanged: _submitting
                                ? null
                                : (value) =>
                                      setState(() => _officialReceipt = value),
                            title: const Text(
                              'Request an official receipt',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Your TIN is shared with this store for the receipt.',
                            ),
                          ),
                          if (_officialReceipt) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _tin,
                              decoration: const InputDecoration(
                                labelText: 'TIN',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.edit_note_rounded,
                      title: 'Notes',
                      subtitle: 'Optional message to the store.',
                      child: TextField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Please pack separately',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'The store will confirm availability and pickup details. '
                              'Payment is handled with the store.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        if (widget.catalog != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Total',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  formatCustomerPrice(
                                    estimated.round(),
                                    currency,
                                  ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : () => _submit(branches),
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(
                                _submitting ? 'Sending…' : 'Send order',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.name,
    required this.quantity,
    required this.options,
    required this.totalLabel,
  });

  final String name;
  final double quantity;
  final List<ProductOptionSelection> options;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${NumberFormat('0.###').format(quantity)}×',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (options.isNotEmpty)
                  Text(
                    options.map((option) => option.choiceName).join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(totalLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.selected,
    required this.onTap,
  });

  final CustomerStoreBranchWithCity branch;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = branchIsOpen(branch);
    final detail = [
      if (branch.address?.isNotEmpty == true) branch.address!,
    ].join(' • ');

    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.6)
          : scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      open
                          ? branchHoursToday(branch)
                          : 'Closed · ${branchHoursToday(branch)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: open ? scheme.onSurfaceVariant : scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
