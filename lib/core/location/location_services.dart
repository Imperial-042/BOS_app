import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'location_models.dart';

class GeocodingResult {
  const GeocodingResult({
    required this.address,
    required this.coordinate,
    this.label,
  });

  final LocationAddress address;
  final GeoCoordinate coordinate;
  final String? label;
}

abstract interface class GeocodingProvider {
  Future<List<GeocodingResult>> search(String query);
  Future<LocationAddress?> reverse(GeoCoordinate coordinate);
}

abstract interface class MapTileProvider {
  String get tileUrlTemplate;
  String get attribution;
}

class NominatimGeocodingProvider implements GeocodingProvider {
  const NominatimGeocodingProvider({
    this.endpoint = 'https://nominatim.openstreetmap.org',
    this.userAgent = 'BOS_app/1.0',
  });

  final String endpoint;
  final String userAgent;

  @override
  Future<List<GeocodingResult>> search(String query) async {
    final response = await http.get(
      Uri.parse('$endpoint/search').replace(
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'addressdetails': '1',
          'limit': '5',
        },
      ),
      headers: {'User-Agent': userAgent},
    );
    if (response.statusCode != 200) {
      throw StateError('Address search is temporarily unavailable.');
    }
    final rows = jsonDecode(response.body);
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) _resultFromNominatim(row),
    ];
  }

  @override
  Future<LocationAddress?> reverse(GeoCoordinate coordinate) async {
    final response = await http.get(
      Uri.parse('$endpoint/reverse').replace(
        queryParameters: {
          'lat': '${coordinate.latitude}',
          'lon': '${coordinate.longitude}',
          'format': 'jsonv2',
          'addressdetails': '1',
        },
      ),
      headers: {'User-Agent': userAgent},
    );
    if (response.statusCode != 200) {
      throw StateError('Address lookup is temporarily unavailable.');
    }
    final row = jsonDecode(response.body);
    if (row is! Map<String, dynamic>) return null;
    return _addressFromNominatim(row, coordinate);
  }

  static GeocodingResult _resultFromNominatim(Map<String, dynamic> row) {
    final coordinate = GeoCoordinate(
      latitude: double.parse(row['lat'] as String),
      longitude: double.parse(row['lon'] as String),
    );
    return GeocodingResult(
      coordinate: coordinate,
      address: _addressFromNominatim(row, coordinate),
      label: row['display_name'] as String?,
    );
  }

  static LocationAddress _addressFromNominatim(
    Map<String, dynamic> row,
    GeoCoordinate coordinate,
  ) {
    final address = row['address'];
    final fields = address is Map<String, dynamic> ? address : const {};
    final city =
        fields['city'] ??
        fields['town'] ??
        fields['municipality'] ??
        fields['village'];
    final street = fields['road'] ?? fields['pedestrian'];
    return LocationAddress(
      country: fields['country'] as String?,
      region: fields['state'] as String?,
      province: fields['state_district'] as String?,
      city: city as String?,
      barangay: fields['suburb'] as String? ?? fields['quarter'] as String?,
      streetAddress: street as String?,
      buildingOrUnit: fields['house_number'] as String?,
      postalCode: fields['postcode'] as String?,
      formattedAddress: row['display_name'] as String?,
      coordinate: coordinate,
    );
  }
}

class CachedGeocodingProvider implements GeocodingProvider {
  CachedGeocodingProvider(
    this.delegate, {
    this.debounce = const Duration(milliseconds: 350),
    this.maxEntries = 100,
  });

  final GeocodingProvider delegate;
  final Duration debounce;
  final int maxEntries;
  final _searchCache = <String, List<GeocodingResult>>{};
  final _reverseCache = <String, LocationAddress?>{};
  Timer? _timer;

  @override
  Future<List<GeocodingResult>> search(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final cached = _searchCache[key];
    if (cached != null) return cached;
    _timer?.cancel();
    final completer = Completer<List<GeocodingResult>>();
    _timer = Timer(debounce, () async {
      try {
        final results = await delegate.search(key);
        _put(_searchCache, key, results);
        completer.complete(results);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<LocationAddress?> reverse(GeoCoordinate coordinate) async {
    final key =
        '${coordinate.latitude.toStringAsFixed(6)},${coordinate.longitude.toStringAsFixed(6)}';
    if (_reverseCache.containsKey(key)) return _reverseCache[key];
    final result = await delegate.reverse(coordinate);
    _put(_reverseCache, key, result);
    return result;
  }

  void _put<T>(Map<String, T> cache, String key, T value) {
    cache[key] = value;
    while (cache.length > maxEntries) {
      cache.remove(cache.keys.first);
    }
  }

  void dispose() => _timer?.cancel();
}

class OpenStreetMapTileProvider implements MapTileProvider {
  const OpenStreetMapTileProvider({
    this.userAgent = 'BOS_app/1.0',
    this.tileHost = 'tile.openstreetmap.org',
  });

  final String userAgent;
  final String tileHost;

  @override
  String get tileUrlTemplate => 'https://$tileHost/{z}/{x}/{y}.png';

  @override
  String get attribution => '© OpenStreetMap contributors';
}
