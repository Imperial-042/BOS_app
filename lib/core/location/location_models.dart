import 'dart:math' as math;

class GeoCoordinate {
  GeoCoordinate({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  }) {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'Must be between -90 and 90.',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Must be between -180 and 180.',
      );
    }
    if (accuracyMeters != null && accuracyMeters! < 0) {
      throw ArgumentError.value(
        accuracyMeters,
        'accuracyMeters',
        'Must not be negative.',
      );
    }
  }

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  double distanceTo(GeoCoordinate other) {
    const earthRadiusMeters = 6371008.8;
    final latitudeDelta = _radians(other.latitude - latitude);
    final longitudeDelta = _radians(other.longitude - longitude);
    final a =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_radians(latitude)) *
            math.cos(_radians(other.latitude)) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
  };

  factory GeoCoordinate.fromJson(Map<String, dynamic> json) => GeoCoordinate(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
  );
}

double _radians(double degrees) => degrees * math.pi / 180;

class LocationAddress {
  const LocationAddress({
    this.recipientName,
    this.contactNumber,
    this.country,
    this.region,
    this.province,
    this.city,
    this.barangay,
    this.streetAddress,
    this.buildingOrUnit,
    this.postalCode,
    this.landmark,
    this.formattedAddress,
    this.coordinate,
  });

  final String? recipientName;
  final String? contactNumber;
  final String? country;
  final String? region;
  final String? province;
  final String? city;
  final String? barangay;
  final String? streetAddress;
  final String? buildingOrUnit;
  final String? postalCode;
  final String? landmark;
  final String? formattedAddress;
  final GeoCoordinate? coordinate;

  bool get hasCoordinates => coordinate != null;

  Map<String, dynamic> toJson() => {
    'recipient_name': recipientName,
    'contact_number': contactNumber,
    'country': country,
    'region': region,
    'province': province,
    'city': city,
    'barangay': barangay,
    'street_address': streetAddress,
    'building_or_unit': buildingOrUnit,
    'postal_code': postalCode,
    'landmark': landmark,
    'formatted_address': formattedAddress,
    if (coordinate != null) ...coordinate!.toJson(),
  };

  factory LocationAddress.fromJson(Map<String, dynamic> json) =>
      LocationAddress(
        recipientName: json['recipient_name'] as String?,
        contactNumber: json['contact_number'] as String?,
        country: json['country'] as String?,
        region: json['region'] as String?,
        province: json['province'] as String?,
        city: json['city'] as String?,
        barangay: json['barangay'] as String?,
        streetAddress: json['street_address'] as String?,
        buildingOrUnit: json['building_or_unit'] as String?,
        postalCode: json['postal_code'] as String?,
        landmark: json['landmark'] as String?,
        formattedAddress: json['formatted_address'] as String?,
        coordinate: json['latitude'] == null || json['longitude'] == null
            ? null
            : GeoCoordinate.fromJson(json),
      );
}

enum LocationVerificationStatus { unverified, confirmed, updated }

String locationVerificationStatusValue(LocationVerificationStatus status) =>
    status.name;

LocationVerificationStatus locationVerificationStatusFromValue(String? value) =>
    LocationVerificationStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => LocationVerificationStatus.unverified,
    );
