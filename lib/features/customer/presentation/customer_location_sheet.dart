import 'dart:async';

import 'package:bos_application/core/location/location_models.dart';
import 'package:bos_application/core/location/location_permissions.dart';
import 'package:bos_application/core/location/location_picker_map.dart';
import 'package:bos_application/core/location/location_services.dart';
import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/features/customer/presentation/customer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the "discovery area" sheet and saves the result.
Future<void> editCustomerLocation(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required CustomerLocationProfile? profile,
}) async {
  final result =
      await showModalBottomSheet<
        ({String city, String address, GeoCoordinate? coordinate})
      >(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _LocationSheet(
          city: profile?.city ?? '',
          address: profile?.address ?? '',
          coordinate: profile?.coordinate,
        ),
      );
  if (result == null) return;
  try {
    await ref
        .read(customerCommerceServiceProvider)
        .updateCustomerLocation(
          userId: userId,
          city: result.city,
          address: result.address,
          coordinate: result.coordinate,
        );
    ref.invalidate(customerHomeProfileProvider(userId));
    ref.invalidate(customerHomeStoresProvider(result.city));
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not save location: ${friendlyError(error)}'),
        ),
      );
    }
  }
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({
    required this.city,
    required this.address,
    this.coordinate,
  });
  final String city;
  final String address;
  final GeoCoordinate? coordinate;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  late final _city = TextEditingController(text: widget.city);
  late final _address = TextEditingController(text: widget.address);
  late final _geocoder = CachedGeocodingProvider(
    const NominatimGeocodingProvider(),
  );
  GeoCoordinate? _coordinate;
  bool _lookingUpAddress = false;

  @override
  void initState() {
    super.initState();
    _coordinate = widget.coordinate;
  }

  String? _cityError;

  @override
  void dispose() {
    _geocoder.dispose();
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _selectCoordinate(GeoCoordinate coordinate) async {
    setState(() {
      _coordinate = coordinate;
      _lookingUpAddress = true;
    });
    try {
      final result = await _geocoder.reverse(coordinate);
      if (!mounted || result == null) return;
      if (result.city?.trim().isNotEmpty == true) {
        _city.text = result.city!.trim();
      }
      if (result.formattedAddress?.trim().isNotEmpty == true) {
        _address.text = result.formattedAddress!.trim();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pin saved: $error')));
      }
    } finally {
      if (mounted) setState(() => _lookingUpAddress = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      await _selectCoordinate(await requestCurrentLocation());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _save() {
    final city = _city.text.trim();
    if (city.isEmpty) {
      setState(() => _cityError = 'Enter your city or area');
      return;
    }
    Navigator.pop(context, (
      city: city,
      address: _address.text.trim(),
      coordinate: _coordinate,
    ));
  }

  InputDecoration _dec(
    ColorScheme scheme,
    String label,
    IconData icon, {
    String? helper,
    String? error,
  }) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      errorText: error,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: b(Colors.transparent),
      enabledBorder: b(Colors.transparent),
      focusedBorder: b(scheme.primary, 1.8),
      errorBorder: b(scheme.error, 1.2),
      focusedErrorBorder: b(scheme.error, 1.8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your discovery area',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'We use your city to show nearby stores.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _city,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _dec(
                scheme,
                'City or area',
                Icons.location_city_rounded,
                helper: 'Used to show stores in your city.',
                error: _cityError,
              ),
              onChanged: (_) {
                if (_cityError != null) setState(() => _cityError = null);
              },
            ),
            const SizedBox(height: 14),
            LocationPickerMap(
              provider: const OpenStreetMapTileProvider(),
              selected: _coordinate,
              onSelected: (coordinate) =>
                  unawaited(_selectCoordinate(coordinate)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _useCurrentLocation,
                    icon: const Icon(Icons.my_location_outlined),
                    label: const Text('Use current location'),
                  ),
                ),
                if (_lookingUpAddress) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: _dec(
                scheme,
                'Street address (optional)',
                Icons.home_outlined,
                helper: 'Private to your profile; it is not sent to stores.',
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _save,
                    child: const Text('Save location'),
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
