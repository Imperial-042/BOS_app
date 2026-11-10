import 'package:bos_application/core/location/location_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates coordinates and calculates distance', () {
    final manila = GeoCoordinate(latitude: 14.5995, longitude: 120.9842);
    final quezonCity = GeoCoordinate(latitude: 14.6760, longitude: 121.0437);

    expect(manila.distanceTo(quezonCity), closeTo(10100, 1200));
    expect(
      () => GeoCoordinate(latitude: 91, longitude: 120),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: 14, longitude: 181),
      throwsArgumentError,
    );
  });

  test('round trips address coordinates', () {
    final address = LocationAddress(
      recipientName: 'Alex',
      contactNumber: '09170000000',
      city: 'Manila',
      formattedAddress: '1 Example Street, Manila',
      coordinate: GeoCoordinate(
        latitude: 14.5995,
        longitude: 120.9842,
        accuracyMeters: 8,
      ),
    );

    final decoded = LocationAddress.fromJson(address.toJson());
    expect(decoded.recipientName, 'Alex');
    expect(decoded.coordinate?.latitude, 14.5995);
    expect(decoded.coordinate?.accuracyMeters, 8);
  });
}
