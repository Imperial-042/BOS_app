import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'location_models.dart';
import 'location_services.dart';

class LocationPickerMap extends StatelessWidget {
  const LocationPickerMap({
    super.key,
    required this.provider,
    this.selected,
    this.markers = const [],
    this.onSelected,
    this.height = 280,
  });

  final MapTileProvider provider;
  final GeoCoordinate? selected;
  final List<Marker> markers;
  final ValueChanged<GeoCoordinate>? onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final center = selected == null
        ? const LatLng(14.5995, 120.9842)
        : LatLng(selected!.latitude, selected!.longitude);
    final selectedMarker = selected == null
        ? const <Marker>[]
        : [
            Marker(
              point: center,
              width: 48,
              height: 48,
              child: const Icon(
                Icons.location_pin,
                color: Colors.red,
                size: 44,
              ),
            ),
          ];
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: selected == null ? 11 : 15,
                onTap: onSelected == null
                    ? null
                    : (_, point) => onSelected!(
                        GeoCoordinate(
                          latitude: point.latitude,
                          longitude: point.longitude,
                        ),
                      ),
              ),
              children: [
                TileLayer(
                  urlTemplate: provider.tileUrlTemplate,
                  userAgentPackageName: 'com.bos.application',
                ),
                MarkerLayer(markers: [...markers, ...selectedMarker]),
                RichAttributionWidget(
                  attributions: [TextSourceAttribution(provider.attribution)],
                ),
              ],
            ),
            if (onSelected != null)
              Positioned(
                top: 12,
                left: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text('Tap the map to place the pin'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
