import 'package:bos_application/core/location/location_models.dart';
import 'package:bos_application/core/location/location_picker_map.dart';
import 'package:bos_application/core/location/location_permissions.dart';
import 'package:bos_application/core/location/location_repository.dart';
import 'package:bos_application/core/location/location_services.dart';
import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomerAddressesScreen extends ConsumerWidget {
  const CustomerAddressesScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String userId, [
    SavedCustomerAddress? existing,
  ]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AddressEditor(existing: existing),
    );
    if (saved == true) {
      ref.invalidate(customerAddressesProvider(userId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authenticatedUserIdProvider);
    if (userId == null) return const SizedBox.shrink();
    final addresses = ref.watch(customerAddressesProvider(userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Saved addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, userId),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add address'),
      ),
      body: addresses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(friendlyError(error))),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text(
                  'No saved addresses yet.\nAdd one for faster checkout.',
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final address = items[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          address.label == 'home'
                              ? Icons.home_outlined
                              : address.label == 'work'
                              ? Icons.work_outline
                              : Icons.place_outlined,
                        ),
                      ),
                      title: Text(
                        '${address.label[0].toUpperCase()}${address.label.substring(1)}'
                        '${address.isDefault ? ' · Default' : ''}',
                      ),
                      subtitle: Text(
                        address.address.formattedAddress ??
                            address.address.city ??
                            'Address details',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'edit') {
                            await _edit(context, ref, userId, address);
                          } else {
                            try {
                              await ref
                                  .read(customerLocationRepositoryProvider)
                                  .deleteCustomerAddress(
                                    customerUserId: userId,
                                    addressId: address.id,
                                  );
                              ref.invalidate(customerAddressesProvider(userId));
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(friendlyError(error))),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _AddressEditor extends StatefulWidget {
  const _AddressEditor({this.existing});
  final SavedCustomerAddress? existing;

  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<_AddressEditor> {
  int _lookupVersion = 0;
  final _recipient = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _street = TextEditingController();
  final _formatted = TextEditingController();
  String _label = 'home';
  bool _default = false;
  GeoCoordinate? _coordinate;
  bool _saving = false;
  bool _lookingUpPin = false;
  late final _geocoder = CachedGeocodingProvider(
    const NominatimGeocodingProvider(),
  );

  @override
  void initState() {
    super.initState();
    final a = widget.existing?.address;
    _label = widget.existing?.label ?? 'home';
    _default = widget.existing?.isDefault ?? false;
    _recipient.text = a?.recipientName ?? '';
    _phone.text = a?.contactNumber ?? '';
    _city.text = a?.city ?? '';
    _street.text = a?.streetAddress ?? '';
    _formatted.text = a?.formattedAddress ?? '';
    _coordinate = a?.coordinate;
  }

  @override
  void dispose() {
    _recipient.dispose();
    _phone.dispose();
    _city.dispose();
    _street.dispose();
    _formatted.dispose();
    _geocoder.dispose();
    super.dispose();
  }

  Future<void> _selectCoordinate(GeoCoordinate coordinate) async {
    final lookupVersion = ++_lookupVersion;
    setState(() {
      _coordinate = coordinate;
      _lookingUpPin = true;
    });
    try {
      final address = await _geocoder.reverse(coordinate);
      if (!mounted ||
          lookupVersion != _lookupVersion ||
          _coordinate != coordinate) {
        return;
      }
      if (address != null) {
        setState(() {
          _city.text = address.city ?? _city.text;
          _street.text =
              [address.buildingOrUnit, address.streetAddress, address.barangay]
                  .whereType<String>()
                  .where((value) => value.trim().isNotEmpty)
                  .join(', ');
          _formatted.text = address.formattedAddress ?? _formatted.text;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read the pinned address: $error')),
        );
      }
    } finally {
      if (mounted && lookupVersion == _lookupVersion) {
        setState(() => _lookingUpPin = false);
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      final coordinate = await requestCurrentLocation();
      if (mounted) await _selectCoordinate(coordinate);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _save() async {
    if (_recipient.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient name and phone are required.')),
      );
      return;
    }
    final userId = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authenticatedUserIdProvider);
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(customerLocationRepositoryProvider)
          .saveCustomerAddress(
            id: widget.existing?.id,
            customerUserId: userId,
            label: _label,
            isDefault: _default,
            address: LocationAddress(
              recipientName: _recipient.text.trim(),
              contactNumber: _phone.text.trim(),
              city: _city.text.trim(),
              streetAddress: _street.text.trim(),
              formattedAddress: _formatted.text.trim().isEmpty
                  ? [_street.text, _city.text]
                        .map((value) => value.trim())
                        .where((value) => value.isNotEmpty)
                        .join(', ')
                  : _formatted.text.trim(),
              coordinate: _coordinate,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = const OpenStreetMapTileProvider();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Add address' : 'Edit address',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'home', label: Text('Home')),
                ButtonSegment(value: 'work', label: Text('Work')),
                ButtonSegment(value: 'other', label: Text('Other')),
              ],
              selected: {_label},
              onSelectionChanged: (value) =>
                  setState(() => _label = value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _recipient,
              decoration: const InputDecoration(
                labelText: 'Recipient name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _city,
              decoration: const InputDecoration(
                labelText: 'City or municipality',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _street,
              decoration: const InputDecoration(
                labelText: 'Street / building / unit',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _formatted,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Complete address',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _useCurrentLocation,
                    icon: const Icon(Icons.my_location_outlined),
                    label: const Text('Use GPS'),
                  ),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: _default,
                  onChanged: (value) => setState(() => _default = value),
                ),
                const Text('Default'),
              ],
            ),
            const SizedBox(height: 12),
            LocationPickerMap(
              provider: mapProvider,
              selected: _coordinate,
              onSelected: _selectCoordinate,
            ),
            const SizedBox(height: 6),
            Text(
              _lookingUpPin
                  ? 'Reading address from the pin…'
                  : _coordinate == null
                  ? 'Tap the map to select a delivery pin.'
                  : 'Pin accuracy: ${_coordinate!.accuracyMeters?.toStringAsFixed(0) ?? 'manual'} m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Save address'),
            ),
          ],
        ),
      ),
    );
  }
}
