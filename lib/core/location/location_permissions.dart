import 'package:geolocator/geolocator.dart';

import 'location_models.dart';

class LocationPermissionException implements Exception {
  const LocationPermissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<GeoCoordinate> requestCurrentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationPermissionException(
      'Device location services are disabled.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const LocationPermissionException('Location permission was denied.');
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationPermissionException(
      'Location permission is permanently denied. Enable it in device settings.',
    );
  }
  final position = await Geolocator.getCurrentPosition();
  return GeoCoordinate(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
  );
}
