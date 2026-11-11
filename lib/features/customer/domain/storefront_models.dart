// lib/features/customer/domain/storefront_models.dart
//
// Storefront value types and the pure store-hours helpers (no I/O).

import 'dart:convert';

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/location/location_models.dart';

typedef StoreHours = ({String open, String close});

class CustomerLocationProfile {
  const CustomerLocationProfile({
    required this.id,
    required this.displayName,
    required this.phone,
    required this.city,
    required this.address,
    this.coordinate,
  });

  final String id;
  final String displayName;
  final String? phone;
  final String? city;
  final String? address;
  final GeoCoordinate? coordinate;
}

class CustomerStorefrontWithHours extends CustomerStorefront {
  CustomerStorefrontWithHours({
    required CustomerStorefront storefront,
    required this.openingHoursJson,
  }) : super(
         businessId: storefront.businessId,
         name: storefront.name,
         description: storefront.description,
         phone: storefront.phone,
         address: storefront.address,
         city: storefront.city,
         currencyCode: storefront.currencyCode,
         isPublished: storefront.isPublished,
         offlineEnabled: storefront.offlineEnabled,
         pointsPerCurrencyUnit: storefront.pointsPerCurrencyUnit,
         updatedAt: storefront.updatedAt,
       );

  final String openingHoursJson;
}

String storefrontOpeningHoursJson(CustomerStorefront store) =>
    store is CustomerStorefrontWithHours ? store.openingHoursJson : '{}';

Map<int, StoreHours> parseStoreHours(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('Store hours must be a JSON object.');
  }
  final hours = <int, StoreHours>{};
  for (final entry in decoded.entries) {
    final day = int.tryParse(entry.key);
    final times = entry.value;
    if (day == null || day < 1 || day > 7 || times is! Map) {
      throw const FormatException('Store hours contain an invalid day.');
    }
    final open = times['open'];
    final close = times['close'];
    final normalizedOpen = _normalizeStoreTime(open);
    final normalizedClose = _normalizeStoreTime(close);
    if (normalizedOpen == null || normalizedClose == null) {
      throw const FormatException('Store hours contain an invalid time.');
    }
    hours[day] = (open: normalizedOpen, close: normalizedClose);
  }
  return hours;
}

String? _normalizeStoreTime(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim().toUpperCase();
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$',
  ).firstMatch(trimmed);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final meridiem = match.group(3);
  if (minute > 59) return null;
  if (meridiem != null) {
    if (hour < 1 || hour > 12) return null;
    if (meridiem == 'AM') {
      hour = hour == 12 ? 0 : hour;
    } else {
      hour = hour == 12 ? 12 : hour + 12;
    }
  } else if (hour > 23) {
    return null;
  }
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

int _storeTimeMinutes(String value) {
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String? _cleanText(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

StoreAvailabilityOverride? availabilityFromValue(Object? value) {
  if (value is! Map) return null;
  final start = DateTime.tryParse(value['start_date']?.toString() ?? '');
  final end = DateTime.tryParse(value['end_date']?.toString() ?? '');
  final mode = value['mode']?.toString();
  if (start == null ||
      end == null ||
      end.isBefore(start) ||
      (mode != StoreAvailabilityMode.open.name &&
          mode != StoreAvailabilityMode.closed.name)) {
    return null;
  }
  return StoreAvailabilityOverride(
    mode: mode == StoreAvailabilityMode.open.name
        ? StoreAvailabilityMode.open
        : StoreAvailabilityMode.closed,
    startDate: start,
    endDate: end,
    reason: value['reason']?.toString(),
  );
}

String serializeStoreHours(Map<int, StoreHours> hours) {
  final value = jsonEncode({
    for (final entry in hours.entries)
      '${entry.key}': {'open': entry.value.open, 'close': entry.value.close},
  });
  parseStoreHours(value);
  return value;
}

bool hoursJsonIsOpen(String value, {DateTime? at}) {
  if (value == '{}') return true;
  final hours = parseStoreHours(value);
  final now = at ?? DateTime.now();
  final time = now.hour * 60 + now.minute;
  final today = hours[now.weekday];
  if (today != null && _isStoreTimeInWindow(today, time)) return true;

  final previousDay = now.weekday == DateTime.monday
      ? DateTime.sunday
      : now.weekday - 1;
  final previous = hours[previousDay];
  return previous != null &&
      _storeTimeMinutes(previous.open) > _storeTimeMinutes(previous.close) &&
      time < _storeTimeMinutes(previous.close);
}

bool _isStoreTimeInWindow(StoreHours hours, int time) {
  final open = _storeTimeMinutes(hours.open);
  final close = _storeTimeMinutes(hours.close);
  if (open == close) return true;
  if (open < close) return time >= open && time < close;
  return time >= open || time < close;
}

String hoursJsonToday(String value, {DateTime? at}) {
  if (value == '{}') return 'No hours set · orders accepted anytime';
  final today = parseStoreHours(value)[(at ?? DateTime.now()).weekday];
  return today == null ? 'Closed today' : 'Today: ${today.open}–${today.close}';
}

bool storefrontIsOpen(CustomerStorefront store, {DateTime? at}) =>
    hoursJsonIsOpen(storefrontOpeningHoursJson(store), at: at);

String storefrontHoursToday(CustomerStorefront store, {DateTime? at}) =>
    hoursJsonToday(storefrontOpeningHoursJson(store), at: at);

bool branchIsOpen(CustomerStoreBranchWithCity b, {DateTime? at}) =>
    b.availabilityOverride?.isActive(at ?? DateTime.now()) == true
    ? b.availabilityOverride!.mode == StoreAvailabilityMode.open
    : hoursJsonIsOpen(b.openingHoursJson, at: at);

String branchHoursToday(CustomerStoreBranchWithCity b, {DateTime? at}) =>
    hoursJsonToday(b.openingHoursJson, at: at);

class CustomerStoreBranchWithCity extends CustomerStoreBranch {
  CustomerStoreBranchWithCity({
    required CustomerStoreBranch branch,
    required this.city,
    required this.storefrontPublished,
    this.phone,
    this.openingHoursJson = '{}',
    this.availabilityOverride,
    this.coordinate,
  }) : super(
         id: branch.id,
         businessId: branch.businessId,
         name: branch.name,
         address: branch.address,
         isActive: branch.isActive,
         updatedAt: branch.updatedAt,
       );

  final String? city;
  final bool storefrontPublished;
  final String? phone;
  final String openingHoursJson;
  final StoreAvailabilityOverride? availabilityOverride;
  final GeoCoordinate? coordinate;
}

enum StoreAvailabilityMode { open, closed }

class StoreAvailabilityOverride {
  const StoreAvailabilityOverride({
    required this.mode,
    required this.startDate,
    required this.endDate,
    this.reason,
  });

  final StoreAvailabilityMode mode;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;

  bool isActive(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'start_date': _dateOnly(startDate),
    'end_date': _dateOnly(endDate),
    'reason': _cleanText(reason),
  };
}

class BranchStorefrontSettings {
  const BranchStorefrontSettings({
    required this.published,
    required this.phone,
    required this.openingHours,
    this.productIds = const <String>{},
    this.availabilityOverride,
  });
  final bool published;
  final String phone;
  final Map<int, StoreHours> openingHours;

  /// Products this branch sells on its storefront.
  final Set<String> productIds;
  final StoreAvailabilityOverride? availabilityOverride;
}

class ManagedBranchStorefront {
  const ManagedBranchStorefront({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.isActive,
    required this.published,
    required this.phone,
    required this.openingHours,
    required this.productIds,
    this.availabilityOverride,
  });
  final String id;
  final String name;
  final String? address;
  final String? city;
  final bool isActive;
  final bool published;
  final String phone;
  final Map<int, StoreHours> openingHours;
  final Set<String> productIds;
  final StoreAvailabilityOverride? availabilityOverride;
}

typedef StoreBranchListing = ({
  CustomerStorefront storefront,
  CustomerStoreBranchWithCity branch,
});


String normalizeStoreCity(String city) =>
    city.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
