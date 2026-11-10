import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/location/location_models.dart';
import '../../transactions/domain/product_variants.dart';

const _uuid = Uuid();

String pendingCustomerProfileKey(String email) =>
    'pending_customer_profile:${email.trim().toLowerCase()}';

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

StoreAvailabilityOverride? _availabilityFromValue(Object? value) {
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

class CustomerCommerceService {
  CustomerCommerceService(this.db, {SupabaseClient? client}) : _client = client;

  final AppDatabase db;
  final SupabaseClient? _client;

  Future<List<ManagedBranchStorefront>> loadManagedBranches(
    String businessId, {
    Set<String>? allowedBranchIds,
  }) async {
    final scopedBranchIds = allowedBranchIds;
    final local = await db
        .customSelect(
          'SELECT id, name, address, phone, city, is_active FROM branches '
          'WHERE business_id = ? ORDER BY is_headquarters DESC, name',
          variables: [Variable<String>(businessId)],
        )
        .get();
    final scopedLocal = scopedBranchIds == null
        ? local
        : local
              .where((row) => scopedBranchIds.contains(row.read<String>('id')))
              .toList();

    var cloud = <String, Map<String, dynamic>>{};
    final links = <String, Set<String>>{};
    final client = _client;
    if (client != null) {
      try {
        final branchQuery = client
            .from('customer_store_branches')
            .select(
              'id, storefront_published, phone, opening_hours, '
              'availability_override',
            )
            .eq('business_id', businessId);
        final rows = scopedBranchIds == null
            ? await branchQuery
            : await branchQuery.inFilter('id', scopedBranchIds.toList());
        cloud = {for (final r in rows) r['id'] as String: r};
        final linkRows = await client
            .from('customer_branch_catalog_items')
            .select('branch_id, catalog_item_id')
            .eq('business_id', businessId);
        for (final r in linkRows) {
          (links[r['branch_id'] as String] ??= <String>{}).add(
            r['catalog_item_id'] as String,
          );
        }
      } on SocketException {
        // fall through with local data only
      } on HttpException {
        // fall through with local data only
      } on TimeoutException {
        // fall through with local data only
      }
    }

    return [
      for (final row in scopedLocal)
        () {
          final id = row.read<String>('id');
          final remote = cloud[id];
          return ManagedBranchStorefront(
            id: id,
            name: row.read<String>('name'),
            address: row.read<String?>('address'),
            city: row.read<String?>('city'),
            isActive: row.read<bool>('is_active'),
            published: (remote?['storefront_published'] as bool?) ?? false,
            phone:
                (remote?['phone'] as String?) ??
                row.read<String?>('phone') ??
                '',
            openingHours: parseStoreHours(
              _openingHoursJson(remote?['opening_hours']),
            ),
            productIds: links[id] ?? <String>{},
            availabilityOverride: _availabilityFromValue(
              remote?['availability_override'],
            ),
          );
        }(),
    ];
  }

  Future<void> ensureCustomerProfile({
    required String userId,
    required String displayName,
    String? phone,
    String? city,
    String? address,
    GeoCoordinate? coordinate,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) throw StateError('Enter your name.');

    if (_client != null) {
      await _client.from('customer_profiles').upsert({
        'id': userId,
        'display_name': name,
        'phone': _nullIfBlank(phone),
        'city': _nullIfBlank(city),
        'address': _nullIfBlank(address),
        'latitude': coordinate?.latitude,
        'longitude': coordinate?.longitude,
        'location_accuracy_meters': coordinate?.accuracyMeters,
      });
    }

    await db
        .into(db.customerProfiles)
        .insertOnConflictUpdate(
          CustomerProfilesCompanion.insert(
            id: userId,
            displayName: name,
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (_nullIfBlank(phone) != null) {
      await db.customStatement(
        'UPDATE customer_profiles SET phone = ? WHERE id = ?',
        [_nullIfBlank(phone), userId],
      );
    }
    await _writeLocalCustomerLocation(
      userId,
      _nullIfBlank(city),
      _nullIfBlank(address),
      _nullIfBlank(phone),
      coordinate,
    );
  }

  Future<bool> hasCustomerProfile(String userId) async {
    final local = await (db.select(
      db.customerProfiles,
    )..where((profile) => profile.id.equals(userId))).getSingleOrNull();
    if (local != null) return true;
    if (_client == null) return false;

    final row = await _client
        .from('customer_profiles')
        .select(
          'id, display_name, phone, city, address, latitude, longitude, '
          'location_accuracy_meters',
        )
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return false;
    await db
        .into(db.customerProfiles)
        .insertOnConflictUpdate(
          CustomerProfilesCompanion.insert(
            id: userId,
            displayName: row['display_name'] as String,
          ),
        );
    await _writeLocalCustomerLocation(
      userId,
      row['city'] as String?,
      row['address'] as String?,
      row['phone'] as String?,
      _coordinateFromMap(row),
    );
    return true;
  }

  Future<CustomerLocationProfile?> loadCustomerProfile(String userId) async {
    Map<String, dynamic>? remote;
    if (_client != null) {
      try {
        remote = await _client
            .from('customer_profiles')
            .select(
              'id, display_name, phone, city, address, latitude, longitude, '
              'location_accuracy_meters',
            )
            .eq('id', userId)
            .maybeSingle();
        if (remote != null) {
          await db
              .into(db.customerProfiles)
              .insertOnConflictUpdate(
                CustomerProfilesCompanion.insert(
                  id: userId,
                  displayName: remote['display_name'] as String,
                ),
              );
          await _writeLocalCustomerLocation(
            userId,
            remote['city'] as String?,
            remote['address'] as String?,
            remote['phone'] as String?,
            _coordinateFromMap(remote),
          );
        }
      } on SocketException {
        // Use the cached profile while offline.
      } on HttpException {
        // Use the cached profile while offline.
      } on TimeoutException {
        // Use the cached profile while offline.
      }
    }
    if (remote != null) {
      return CustomerLocationProfile(
        id: userId,
        displayName: remote['display_name'] as String,
        phone: remote['phone'] as String?,
        city: remote['city'] as String?,
        address: remote['address'] as String?,
        coordinate: _coordinateFromMap(remote),
      );
    }
    final profile = await (db.select(
      db.customerProfiles,
    )..where((profile) => profile.id.equals(userId))).getSingleOrNull();
    if (profile == null) return null;
    final location = await db
        .customSelect(
          'SELECT phone, city, address, latitude, longitude, '
          'location_accuracy_meters FROM customer_profiles WHERE id = ?',
          variables: [Variable<String>(userId)],
        )
        .getSingleOrNull();
    return CustomerLocationProfile(
      id: userId,
      displayName: profile.displayName,
      phone: location?.read<String?>('phone'),
      city: location?.read<String?>('city'),
      address: location?.read<String?>('address'),
      coordinate: _coordinateFromRow(location),
    );
  }

  Future<void> updateCustomerProfile({
    required String userId,
    required String displayName,
    required String phone,
    required String city,
    required String address,
    GeoCoordinate? coordinate,
  }) async {
    final cleanName = displayName.trim();
    final cleanCity = _nullIfBlank(city);
    if (cleanName.isEmpty) throw StateError('Enter your name.');
    if (cleanCity == null) throw StateError('Enter your city or area.');
    final cleanPhone = _nullIfBlank(phone);
    final cleanAddress = _nullIfBlank(address);
    final profile = await (db.select(
      db.customerProfiles,
    )..where((value) => value.id.equals(userId))).getSingleOrNull();
    if (profile == null) throw StateError('Customer profile not found.');

    final client = _client;
    if (client != null) {
      final rows = await client
          .from('customer_profiles')
          .update({
            'display_name': cleanName,
            'phone': cleanPhone,
            'city': cleanCity,
            'address': cleanAddress,
            'latitude': coordinate?.latitude,
            'longitude': coordinate?.longitude,
            'location_accuracy_meters': coordinate?.accuracyMeters,
          })
          .eq('id', userId)
          .select('id');
      if (rows.isEmpty) throw StateError('Customer profile not found.');
    }
    await db.transaction(() async {
      await (db.update(
        db.customerProfiles,
      )..where((value) => value.id.equals(userId))).write(
        CustomerProfilesCompanion(
          displayName: Value(cleanName),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await db.customStatement(
        'UPDATE customer_profiles SET phone = ?, city = ?, address = ?, '
        'updated_at = ? WHERE id = ?',
        [
          cleanPhone,
          cleanCity,
          cleanAddress,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          userId,
        ],
      );
    });
  }

  Future<void> updateCustomerLocation({
    required String userId,
    required String city,
    required String address,
    GeoCoordinate? coordinate,
  }) async {
    final cleanCity = _nullIfBlank(city);
    final cleanAddress = _nullIfBlank(address);
    if (cleanCity == null) throw StateError('Enter your city or area.');
    final profile = await (db.select(
      db.customerProfiles,
    )..where((value) => value.id.equals(userId))).getSingleOrNull();
    if (profile == null) throw StateError('Customer profile not found.');

    final client = _client;
    if (client != null) {
      final rows = await client
          .from('customer_profiles')
          .update({
            'city': cleanCity,
            'address': cleanAddress,
            'latitude': coordinate?.latitude,
            'longitude': coordinate?.longitude,
            'location_accuracy_meters': coordinate?.accuracyMeters,
          })
          .eq('id', userId)
          .select('id');
      if (rows.isEmpty) throw StateError('Customer profile not found.');
    }
    await _writeLocalCustomerLocation(
      userId,
      cleanCity,
      cleanAddress,
      null,
      coordinate,
    );
  }

  Future<void> _writeLocalCustomerLocation(
    String userId,
    String? city,
    String? address, [
    String? phone,
    GeoCoordinate? coordinate,
  ]) async {
    await db.customStatement(
      'UPDATE customer_profiles SET phone = COALESCE(?, phone), city = ?, '
      'address = ?, latitude = ?, longitude = ?, '
      'location_accuracy_meters = ?, updated_at = ? '
      'WHERE id = ?',
      [
        phone,
        city,
        address,
        coordinate?.latitude,
        coordinate?.longitude,
        coordinate?.accuracyMeters,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        userId,
      ],
    );
  }

  Future<bool> hasBusinessMembership(String userId) async {
    final local =
        await (db.select(db.businessMembers)..where(
              (member) =>
                  member.userId.equals(userId) & member.status.equals('active'),
            ))
            .get();
    if (local.isNotEmpty) return true;
    final owned = await (db.select(
      db.businesses,
    )..where((business) => business.ownerUserId.equals(userId))).get();
    if (owned.isNotEmpty) return true;
    if (_client == null) return false;

    final memberships = await _client
        .from('business_memberships')
        .select('business_id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .limit(1);
    return memberships.isNotEmpty;
  }

  Future<bool> hasOwnerBusinessMembership(String userId) async {
    final owned = await (db.select(
      db.businesses,
    )..where((business) => business.ownerUserId.equals(userId))).get();
    if (owned.isNotEmpty) return true;

    final localOwner =
        await (db.select(db.businessMembers)..where(
              (member) =>
                  member.userId.equals(userId) &
                  member.role.equals('owner') &
                  member.status.equals('active'),
            ))
            .getSingleOrNull();
    if (localOwner != null) return true;
    if (_client == null) return false;

    final memberships = await _client
        .from('business_memberships')
        .select('business_id')
        .eq('user_id', userId)
        .eq('role', 'owner')
        .eq('status', 'active')
        .limit(1);
    return memberships.isNotEmpty;
  }

  Future<bool> hasTeamBusinessMembership(String userId) async {
    if (!await hasBusinessMembership(userId)) return false;
    if (await hasOwnerBusinessMembership(userId)) return false;
    return true;
  }

  Future<List<CustomerStorefront>> discoverStores({
    required String city,
  }) async {
    final normalizedCity = normalizeStoreCity(city);
    if (normalizedCity.isEmpty) return const [];
    if (_client == null) {
      return _offlineStores(normalizedCity);
    }
    try {
      final branchRows = await _client
          .from('customer_store_branches')
          .select('business_id, city')
          .eq('is_active', true)
          .eq('storefront_published', true);
      final businessIds = branchRows
          .where(
            (branch) =>
                normalizeStoreCity(branch['city'] as String? ?? '') ==
                normalizedCity,
          )
          .map((branch) => branch['business_id'] as String)
          .toSet();
      if (businessIds.isEmpty) return const [];
      final rows = await _client
          .from('customer_storefronts')
          .select(
            'business_id, name, description, phone, address, city, '
            'currency_code, is_published, offline_enabled, points_per_currency_unit, opening_hours, updated_at',
          )
          .eq('is_published', true)
          .order('name');
      final stores = rows
          .map(_storefrontFromCloud)
          .where((store) => businessIds.contains(store.businessId))
          .toList();
      await _cacheStorefronts(stores);
      return stores;
    } on SocketException {
      return _offlineStores(normalizedCity);
    } on HttpException {
      return _offlineStores(normalizedCity);
    } on TimeoutException {
      return _offlineStores(normalizedCity);
    }
  }

  Future<CustomerStorefront?> loadStorefrontForCity(
    String businessId, {
    required String city,
  }) async {
    final normalizedCity = normalizeStoreCity(city);
    if (normalizedCity.isEmpty) return null;
    if (_client != null) {
      try {
        final row = await _client
            .from('customer_storefronts')
            .select(
              'business_id, name, description, phone, address, city, '
              'currency_code, is_published, offline_enabled, points_per_currency_unit, opening_hours, updated_at',
            )
            .eq('business_id', businessId)
            .eq('is_published', true)
            .maybeSingle();
        if (row == null) return null;
        final storefront = _storefrontFromCloud(row);
        final branches = await loadStoreBranches(
          businessId,
          city: normalizedCity,
        );
        if (branches.isEmpty) {
          return null;
        }
        await _cacheStorefronts([storefront]);
        return storefront;
      } on SocketException {
        return _cachedOfflineStorefront(businessId, normalizedCity);
      } on HttpException {
        return _cachedOfflineStorefront(businessId, normalizedCity);
      } on TimeoutException {
        return _cachedOfflineStorefront(businessId, normalizedCity);
      }
    }
    return _cachedOfflineStorefront(businessId, normalizedCity);
  }

  Future<({CustomerStorefront? storefront, List<CustomerCatalogItem> items})>
  loadManagedStorefront(String businessId) async {
    Future<({CustomerStorefront? storefront, List<CustomerCatalogItem> items})>
    localSettings() async {
      final storefront =
          await (db.select(db.customerStorefronts)
                ..where((store) => store.businessId.equals(businessId)))
              .getSingleOrNull();
      return (
        storefront: storefront == null
            ? null
            : await _withOpeningHours(storefront),
        items: await (db.select(
          db.customerCatalogItems,
        )..where((item) => item.businessId.equals(businessId))).get(),
      );
    }

    final client = _client;
    if (client == null) return localSettings();
    final row = await client
        .from('customer_storefronts')
        .select(
          'business_id, name, description, phone, address, city, '
          'currency_code, is_published, offline_enabled, points_per_currency_unit, opening_hours, updated_at',
        )
        .eq('business_id', businessId)
        .maybeSingle();
    if (row == null) {
      await (db.delete(
        db.customerStorefronts,
      )..where((store) => store.businessId.equals(businessId))).go();
      await (db.delete(
        db.customerCatalogItems,
      )..where((item) => item.businessId.equals(businessId))).go();
      return (storefront: null, items: const <CustomerCatalogItem>[]);
    }
    final storefront = _storefrontFromCloud(row);
    final rows = await client
        .from('customer_catalog_items')
        .select(
          'id, business_id, name, description, category, unit, '
          'price_cents, image_url, is_available, updated_at',
        )
        .eq('business_id', businessId)
        .order('name');
    final items = rows.map(_catalogItemFromCloud).toList();
    await _cacheStorefronts([storefront]);
    await _cacheCatalog(businessId, items);
    return (storefront: storefront, items: items);
  }

  Future<List<CustomerCatalogItem>> loadCatalog(
    String businessId, {
    required String city,
    required String branchId,
  }) async {
    final storefront = await loadStorefrontForCity(businessId, city: city);
    if (storefront == null) return const [];

    if (_client != null) {
      try {
        final links = await _client
            .from('customer_branch_catalog_items')
            .select('catalog_item_id')
            .eq('business_id', businessId)
            .eq('branch_id', branchId);
        final ids = links.map((r) => r['catalog_item_id'] as String).toList();
        if (ids.isEmpty) {
          await _cacheBranchCatalog(businessId, branchId, const []);
          return const [];
        }
        final rows = await _client
            .from('customer_catalog_items')
            .select(
              'id, business_id, name, description, category, unit, '
              'price_cents, image_url, is_available, updated_at',
            )
            .eq('business_id', businessId)
            .eq('is_available', true)
            .inFilter('id', ids)
            .order('name');
        final items = rows.map(_catalogItemFromCloud).toList();
        await _cacheBranchCatalog(businessId, branchId, items);
        return items;
      } on SocketException {
        return _offlineCatalog(storefront, branchId);
      } on HttpException {
        return _offlineCatalog(storefront, branchId);
      } on TimeoutException {
        return _offlineCatalog(storefront, branchId);
      }
    }
    return _offlineCatalog(storefront, branchId);
  }

  Future<List<ProductOptionGroup>> loadCustomerProductOptions(
    String productId,
  ) async {
    final client = _client;
    if (client != null) {
      final groups = await client
          .from('product_option_groups')
          .select(
            'id, product_id, business_id, name, is_required, allow_multiple, '
            'min_selections, max_selections, is_add_on, sort_order, is_active',
          )
          .eq('product_id', productId)
          .eq('is_active', true)
          .order('sort_order');
      final choices = await client
          .from('product_option_choices')
          .select(
            'id, product_id, group_id, name, price_delta_cents, '
            'inventory_product_id, inventory_supply_id, inventory_quantity, '
            'sort_order, is_active',
          )
          .eq('product_id', productId)
          .eq('is_active', true)
          .order('sort_order');
      return [
        for (final group in groups)
          ProductOptionGroup(
            id: group['id'] as String,
            productId: productId,
            businessId: group['business_id'] as String,
            name: group['name'] as String,
            required: group['is_required'] as bool,
            multiple: group['allow_multiple'] as bool,
            minSelections: (group['min_selections'] as num).toInt(),
            maxSelections: (group['max_selections'] as num?)?.toInt(),
            isAddOn: group['is_add_on'] as bool,
            sortOrder: (group['sort_order'] as num).toInt(),
            isActive: group['is_active'] as bool,
            choices: [
              for (final choice in choices)
                if ((choice['group_id'] as String) == group['id'])
                  ProductOptionChoice(
                    id: choice['id'] as String,
                    groupId: group['id'] as String,
                    name: choice['name'] as String,
                    priceDeltaCents: (choice['price_delta_cents'] as num)
                        .toInt(),
                    inventoryProductId:
                        choice['inventory_product_id'] as String?,
                    inventorySupplyId: choice['inventory_supply_id'] as String?,
                    inventoryQuantity: (choice['inventory_quantity'] as num)
                        .toDouble(),
                    sortOrder: (choice['sort_order'] as num).toInt(),
                    isActive: choice['is_active'] as bool,
                  ),
            ],
          ),
      ];
    }
    return ProductVariantService(db).loadGroups(productId, activeOnly: true);
  }

  /// One entry per (store, branch) so Discover can show each branch as its
  /// own storefront.
  Future<List<StoreBranchListing>> discoverBranchStores({
    required String city,
  }) async {
    final stores = await discoverStores(city: city);
    final perStore = await Future.wait(
      stores.map((store) async {
        final branches = await loadStoreBranches(store.businessId, city: city);
        return [for (final b in branches) (storefront: store, branch: b)];
      }),
    );
    return [for (final list in perStore) ...list];
  }

  Stream<List<CustomerStoreFollow>> watchFollows(String userId) async* {
    final localQuery = db.select(db.customerStoreFollows)
      ..where((follow) => follow.customerUserId.equals(userId))
      ..orderBy([(follow) => OrderingTerm.desc(follow.createdAt)]);
    if (_client != null) {
      try {
        final rows = await _client
            .from('customer_store_follows')
            .select('business_id, created_at')
            .eq('customer_user_id', userId)
            .order('created_at', ascending: false);
        final follows = rows
            .map(
              (row) => CustomerStoreFollowsCompanion.insert(
                id: '$userId:${row['business_id']}',
                customerUserId: userId,
                businessId: row['business_id'] as String,
                createdAt: Value(_date(row['created_at'])),
              ),
            )
            .toList();
        await db.transaction(() async {
          await (db.delete(
            db.customerStoreFollows,
          )..where((follow) => follow.customerUserId.equals(userId))).go();
          if (follows.isNotEmpty) {
            await db.batch((batch) {
              batch.insertAll(
                db.customerStoreFollows,
                follows,
                mode: InsertMode.insertOrReplace,
              );
            });
          }
        });
      } on SocketException {
        yield* localQuery.watch();
        return;
      } on HttpException {
        yield* localQuery.watch();
        return;
      } on TimeoutException {
        yield* localQuery.watch();
        return;
      }
    }
    yield* localQuery.watch();
  }

  Future<bool> isFollowing(String userId, String businessId) async {
    if (_client != null) {
      try {
        final row = await _client
            .from('customer_store_follows')
            .select('business_id')
            .eq('customer_user_id', userId)
            .eq('business_id', businessId)
            .maybeSingle();
        if (row == null) {
          await (db.delete(db.customerStoreFollows)..where(
                (follow) =>
                    follow.customerUserId.equals(userId) &
                    follow.businessId.equals(businessId),
              ))
              .go();
          return false;
        }
        await db
            .into(db.customerStoreFollows)
            .insertOnConflictUpdate(
              CustomerStoreFollowsCompanion.insert(
                id: '$userId:$businessId',
                customerUserId: userId,
                businessId: businessId,
              ),
            );
        return true;
      } on SocketException {
        return _isFollowingLocally(userId, businessId);
      } on HttpException {
        return _isFollowingLocally(userId, businessId);
      } on TimeoutException {
        return _isFollowingLocally(userId, businessId);
      }
    }
    return _isFollowingLocally(userId, businessId);
  }

  Future<bool> _isFollowingLocally(String userId, String businessId) async =>
      await (db.select(db.customerStoreFollows)..where(
            (follow) =>
                follow.customerUserId.equals(userId) &
                follow.businessId.equals(businessId),
          ))
          .getSingleOrNull() !=
      null;

  Future<void> followStore({
    required String userId,
    required String businessId,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Connect to the internet to follow a store.');
    }
    final profile = await loadCustomerProfile(userId);
    final city = normalizeStoreCity(profile?.city ?? '');
    if (city.isEmpty) {
      throw StateError('Add your city before following a store.');
    }
    final store = await loadStorefrontForCity(businessId, city: city);
    if (store == null || !store.isPublished) {
      throw StateError('This store is not accepting customers right now.');
    }
    await client.from('customer_store_follows').upsert({
      'customer_user_id': userId,
      'business_id': businessId,
    });
    await db
        .into(db.customerStoreFollows)
        .insertOnConflictUpdate(
          CustomerStoreFollowsCompanion.insert(
            id: '$userId:$businessId',
            customerUserId: userId,
            businessId: businessId,
          ),
        );
  }

  Future<void> unfollowStore({
    required String userId,
    required String businessId,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Connect to the internet to unfollow a store.');
    }
    await client
        .from('customer_store_follows')
        .delete()
        .eq('customer_user_id', userId)
        .eq('business_id', businessId);
    await (db.delete(db.customerStoreFollows)..where(
          (f) =>
              f.customerUserId.equals(userId) & f.businessId.equals(businessId),
        ))
        .go();
  }

  Future<List<CustomerStoreBranchWithCity>> loadStoreBranches(
    String businessId, {
    required String city,
  }) async {
    final normalizedCity = normalizeStoreCity(city);
    if (normalizedCity.isEmpty) return const [];
    if (_client != null) {
      try {
        final rows = await _client
            .from('customer_store_branches')
            .select(
              'id, business_id, name, address, city, phone, opening_hours, '
              'storefront_published, is_active, availability_override, updated_at',
            )
            .eq('business_id', businessId)
            .eq('is_active', true)
            .order('name');
        final locationRows = await _client
            .from('branch_locations')
            .select('branch_id, latitude, longitude, location_accuracy_meters')
            .inFilter(
              'branch_id',
              rows.map((row) => row['id'] as String).toList(),
            );
        final coordinates = {
          for (final row in locationRows)
            row['branch_id'] as String: GeoCoordinate(
              latitude: (row['latitude'] as num).toDouble(),
              longitude: (row['longitude'] as num).toDouble(),
              accuracyMeters: (row['location_accuracy_meters'] as num?)
                  ?.toDouble(),
            ),
        };
        final branches = rows
            .map((row) => _branchFromCloud(row, coordinates[row['id']]))
            .where(
              (b) =>
                  b.storefrontPublished &&
                  normalizeStoreCity(b.city ?? '') == normalizedCity,
            )
            .toList();
        await _cacheStoreBranches(branches);
        return branches;
      } on SocketException {
        return _offlineBranches(businessId, normalizedCity);
      } on HttpException {
        return _offlineBranches(businessId, normalizedCity);
      } on TimeoutException {
        return _offlineBranches(businessId, normalizedCity);
      }
    }
    return _offlineBranches(businessId, normalizedCity);
  }

  Future<void> updateBranchStorefrontAddress({
    required String businessId,
    required String branchId,
    required String address,
    required String city,
  }) async {
    final cleanAddress = _nullIfBlank(address);
    final cleanCity = _nullIfBlank(city);
    await db.customStatement(
      'UPDATE customer_store_branches SET address = ?, city = ?, '
      'updated_at = ? WHERE id = ? AND business_id = ?',
      [
        cleanAddress,
        cleanCity,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        branchId,
        businessId,
      ],
    );
    final client = _client;
    if (client == null) return;
    await client
        .from('customer_store_branches')
        .update({'address': cleanAddress, 'city': cleanCity})
        .eq('id', branchId)
        .eq('business_id', businessId);
  }

  Future<void> publishStorefront({
    required String businessId,
    required String name,
    required String description,
    required String currencyCode,
    required bool offlineEnabled,
    required int pointsPerCurrencyUnit,
    required Map<String, BranchStorefrontSettings> branchSettings,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Connect to the cloud to publish a storefront.');
    }
    final publishedProductIds = <String>{
      for (final s in branchSettings.values) ...s.productIds,
    };
    if (pointsPerCurrencyUnit < 0 || pointsPerCurrencyUnit > 1000) {
      throw ArgumentError.value(
        pointsPerCurrencyUnit,
        'pointsPerCurrencyUnit',
        'Must be between 0 and 1000.',
      );
    }
    final business = await (db.select(
      db.businesses,
    )..where((b) => b.id.equals(businessId))).getSingleOrNull();
    if (business == null) throw StateError('Business not found.');

    final branches = await (db.select(
      db.branches,
    )..where((b) => b.businessId.equals(businessId))).get();
    final cityRows = await db
        .customSelect(
          'SELECT id, city FROM branches WHERE business_id = ?',
          variables: [Variable<String>(businessId)],
        )
        .get();
    final branchCities = {
      for (final row in cityRows)
        row.read<String>('id'): row.read<String?>('city'),
    };

    bool isLive(Branch b) =>
        b.isActive && (branchSettings[b.id]?.published ?? false);
    final isPublished = branches.any(isLive);

    if (isPublished && name.trim().isEmpty) {
      throw StateError('Enter a storefront name before publishing.');
    }
    final missingCity = branches
        .where(isLive)
        .where((b) => normalizeStoreCity(branchCities[b.id] ?? '').isEmpty)
        .map((b) => b.name)
        .toList();
    if (missingCity.isNotEmpty) {
      throw StateError(
        'Add a city to ${missingCity.join(', ')} before publishing it.',
      );
    }

    // Business-level fields only. Phone, address, city and hours are
    // per-branch now, so they are intentionally not sent here.
    await client.from('customer_storefronts').upsert({
      'business_id': businessId,
      'name': name.trim(),
      'description': _nullIfBlank(description),
      'currency_code': currencyCode,
      'is_published': isPublished,
      'offline_enabled': offlineEnabled,
      'points_per_currency_unit': pointsPerCurrencyUnit,
    });

    final branchRows = [
      for (final branch in branches)
        {
          'id': branch.id,
          'business_id': businessId,
          'name': branch.name,
          'address': _nullIfBlank(branch.address),
          'city': _nullIfBlank(branchCities[branch.id]),
          'phone': _nullIfBlank(branchSettings[branch.id]?.phone),
          'opening_hours': jsonDecode(
            serializeStoreHours(
              branchSettings[branch.id]?.openingHours ?? const {},
            ),
          ),
          'availability_override': branchSettings[branch.id]
              ?.availabilityOverride
              ?.toJson(),
          'storefront_published': isLive(branch),
          'is_active': branch.isActive,
        },
    ];
    if (branchRows.isNotEmpty) {
      await client.from('customer_store_branches').upsert(branchRows);
    }
    await _cacheStoreBranches([
      for (final branch in branches)
        CustomerStoreBranchWithCity(
          branch: CustomerStoreBranch(
            id: branch.id,
            businessId: businessId,
            name: branch.name,
            address: branch.address,
            isActive: branch.isActive,
            updatedAt: branch.updatedAt,
          ),
          city: branchCities[branch.id],
          storefrontPublished: isLive(branch),
          phone: _nullIfBlank(branchSettings[branch.id]?.phone),
          openingHoursJson: serializeStoreHours(
            branchSettings[branch.id]?.openingHours ?? const {},
          ),
          availabilityOverride: branchSettings[branch.id]?.availabilityOverride,
        ),
    ]);

    // ... selectedProducts / catalog upsert code stays exactly as it is ...
    final selectedProducts = publishedProductIds.isEmpty
        ? const <Product>[]
        : await (db.select(db.products)..where(
                (p) =>
                    p.businessId.equals(businessId) &
                    p.id.isIn(publishedProductIds) &
                    p.isActive.equals(true) &
                    p.isSellable.equals(true),
              ))
              .get();
    final selectedProductIds = selectedProducts
        .map((product) => product.id)
        .toSet();
    final categories = await (db.select(
      db.productCategories,
    )..where((category) => category.businessId.equals(businessId))).get();
    final categoryNames = {for (final c in categories) c.id: c.name};
    final rows = selectedProducts
        .map(
          (product) => {
            'id': product.id,
            'business_id': businessId,
            'name': product.name,
            'description': _nullIfBlank(product.description),
            'category': categoryNames[product.categoryId],
            'unit': product.unit,
            'price_cents': product.sellPrice,
            'image_url': null,
            'is_available': true,
          },
        )
        .toList();

    if (rows.isNotEmpty) {
      await client.from('customer_catalog_items').upsert(rows);
    }
    final existing = await client
        .from('customer_catalog_items')
        .select('id')
        .eq('business_id', businessId);
    final staleIds = existing
        .map((row) => row['id'] as String)
        .where((id) => !selectedProductIds.contains(id))
        .toList();
    if (staleIds.isNotEmpty) {
      await client
          .from('customer_catalog_items')
          .delete()
          .eq('business_id', businessId)
          .inFilter('id', staleIds);
    }
    // Per-branch catalog: exactly the products each branch sells.
    final desired = <String, Set<String>>{
      for (final branch in branches)
        branch.id: <String>{
          for (final id
              in branchSettings[branch.id]?.productIds ?? const <String>{})
            if (selectedProductIds.contains(id)) id,
        },
    };
    final linkRows = [
      for (final e in desired.entries)
        for (final id in e.value)
          {
            'branch_id': e.key,
            'catalog_item_id': id,
            'business_id': businessId,
          },
    ];
    if (linkRows.isNotEmpty) {
      await client
          .from('customer_branch_catalog_items')
          .upsert(linkRows, onConflict: 'branch_id,catalog_item_id');
    }
    final existingLinks = await client
        .from('customer_branch_catalog_items')
        .select('branch_id, catalog_item_id')
        .eq('business_id', businessId);
    final staleByBranch = <String, List<String>>{};
    for (final row in existingLinks) {
      final b = row['branch_id'] as String;
      final i = row['catalog_item_id'] as String;
      if (!(desired[b]?.contains(i) ?? false)) {
        (staleByBranch[b] ??= []).add(i);
      }
    }
    for (final e in staleByBranch.entries) {
      await client
          .from('customer_branch_catalog_items')
          .delete()
          .eq('business_id', businessId)
          .eq('branch_id', e.key)
          .inFilter('catalog_item_id', e.value);
    }

    final cached = CustomerStorefrontWithHours(
      storefront: CustomerStorefront(
        businessId: businessId,
        name: name.trim(),
        description: _nullIfBlank(description),
        phone: _nullIfBlank(null),
        address: _nullIfBlank(null),
        city: _nullIfBlank(null),
        currencyCode: currencyCode,
        isPublished: isPublished,
        offlineEnabled: offlineEnabled,
        pointsPerCurrencyUnit: pointsPerCurrencyUnit,
        updatedAt: DateTime.now(),
      ),
      openingHoursJson: '{}',
    );
    await _cacheStorefronts([cached]);
    await _cacheCatalog(
      businessId,
      selectedProducts
          .map(
            (product) => CustomerCatalogItem(
              id: product.id,
              businessId: businessId,
              name: product.name,
              description: product.description,
              category: categoryNames[product.categoryId],
              unit: product.unit,
              priceCents: product.sellPrice,
              imageUrl: null,
              isAvailable: true,
              updatedAt: DateTime.now(),
            ),
          )
          .toList(),
    );
  }

  /// Publishes ONE branch: its switch, hours, phone and product list.
  /// Other branches are never touched.
  Future<void> publishBranchStorefront({
    required String businessId,
    required String branchId,
    required String name,
    required String description,
    required String currencyCode,
    required bool offlineEnabled,
    required int pointsPerCurrencyUnit,
    required BranchStorefrontSettings settings,
    required Set<String> allowedBranchIds,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Connect to the cloud to publish a storefront.');
    }
    if (pointsPerCurrencyUnit < 0 || pointsPerCurrencyUnit > 1000) {
      throw ArgumentError.value(
        pointsPerCurrencyUnit,
        'pointsPerCurrencyUnit',
        'Must be between 0 and 1000.',
      );
    }
    final branch =
        await (db.select(db.branches)..where(
              (b) => b.id.equals(branchId) & b.businessId.equals(businessId),
            ))
            .getSingleOrNull();
    if (branch == null) throw StateError('Branch not found.');
    if (!allowedBranchIds.contains(branchId)) {
      throw StateError('You are not assigned to this branch.');
    }
    final cityRow = await db
        .customSelect(
          'SELECT city FROM branches WHERE id = ?',
          variables: [Variable<String>(branchId)],
        )
        .getSingleOrNull();
    final city = cityRow?.read<String?>('city');

    final live = branch.isActive && settings.published;
    if (live && name.trim().isEmpty) {
      throw StateError('Enter a storefront name before publishing.');
    }
    if (live && normalizeStoreCity(city ?? '').isEmpty) {
      throw StateError('Add a city to ${branch.name} before publishing it.');
    }
    final hoursJson = serializeStoreHours(settings.openingHours);

    // The business storefront stays published while ANY branch is live.
    final others = await client
        .from('customer_store_branches')
        .select('id, storefront_published, is_active')
        .eq('business_id', businessId)
        .neq('id', branchId);
    final isPublished =
        live ||
        others.any(
          (r) => r['storefront_published'] == true && r['is_active'] == true,
        );

    await client.from('customer_storefronts').upsert({
      'business_id': businessId,
      'name': name.trim(),
      'description': _nullIfBlank(description),
      'currency_code': currencyCode,
      'is_published': isPublished,
      'offline_enabled': offlineEnabled,
      'points_per_currency_unit': pointsPerCurrencyUnit,
    });

    await client.from('customer_store_branches').upsert({
      'id': branch.id,
      'business_id': businessId,
      'name': branch.name,
      'address': _nullIfBlank(branch.address),
      'city': _nullIfBlank(city),
      'phone': _nullIfBlank(settings.phone),
      'opening_hours': jsonDecode(hoursJson),
      'availability_override': settings.availabilityOverride?.toJson(),
      'storefront_published': live,
      'is_active': branch.isActive,
    });

    // Products for THIS branch only.
    final selected = settings.productIds.isEmpty
        ? const <Product>[]
        : await (db.select(db.products)..where(
                (p) =>
                    p.businessId.equals(businessId) &
                    p.id.isIn(settings.productIds) &
                    p.isActive.equals(true) &
                    p.isSellable.equals(true),
              ))
              .get();
    final categories = await (db.select(
      db.productCategories,
    )..where((c) => c.businessId.equals(businessId))).get();
    final categoryNames = {for (final c in categories) c.id: c.name};

    if (selected.isNotEmpty) {
      await client.from('customer_catalog_items').upsert([
        for (final product in selected)
          {
            'id': product.id,
            'business_id': businessId,
            'name': product.name,
            'description': _nullIfBlank(product.description),
            'category': categoryNames[product.categoryId],
            'unit': product.unit,
            'price_cents': product.sellPrice,
            'image_url': null,
            'is_available': true,
          },
      ]);
    }

    final desired = selected.map((p) => p.id).toSet();
    final existingLinks = await client
        .from('customer_branch_catalog_items')
        .select('catalog_item_id')
        .eq('business_id', businessId)
        .eq('branch_id', branchId);
    final staleLinks = existingLinks
        .map((r) => r['catalog_item_id'] as String)
        .where((id) => !desired.contains(id))
        .toList();
    if (staleLinks.isNotEmpty) {
      await client
          .from('customer_branch_catalog_items')
          .delete()
          .eq('business_id', businessId)
          .eq('branch_id', branchId)
          .inFilter('catalog_item_id', staleLinks);
    }
    if (desired.isNotEmpty) {
      await client.from('customer_branch_catalog_items').upsert([
        for (final id in desired)
          {
            'branch_id': branchId,
            'catalog_item_id': id,
            'business_id': businessId,
          },
      ], onConflict: 'branch_id,catalog_item_id');
    }

    // Server-side cleanup that can see every branch's links.
    try {
      await client.rpc(
        'cleanup_orphan_catalog_items',
        params: {'p_business_id': businessId},
      );
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains('schema cache') ||
          error.message.toLowerCase().contains(
            'cleanup_orphan_catalog_items',
          )) {
        throw StateError(
          'Branch saved, but publishing needs the latest Supabase migration. '
          'Apply 20261101080000_cleanup_orphan_catalog_items.sql, then retry.',
        );
      }
      rethrow;
    }

    // Local cache
    await _cacheStoreBranches([
      CustomerStoreBranchWithCity(
        branch: CustomerStoreBranch(
          id: branch.id,
          businessId: businessId,
          name: branch.name,
          address: branch.address,
          isActive: branch.isActive,
          updatedAt: branch.updatedAt,
        ),
        city: city,
        storefrontPublished: live,
        phone: _nullIfBlank(settings.phone),
        openingHoursJson: hoursJson,
      ),
    ]);
    await _cacheStorefronts([
      CustomerStorefrontWithHours(
        storefront: CustomerStorefront(
          businessId: businessId,
          name: name.trim(),
          description: _nullIfBlank(description),
          phone: null,
          address: null,
          city: null,
          currencyCode: currencyCode,
          isPublished: isPublished,
          offlineEnabled: offlineEnabled,
          pointsPerCurrencyUnit: pointsPerCurrencyUnit,
          updatedAt: DateTime.now(),
        ),
        openingHoursJson: '{}',
      ),
    ]);
    await _cacheBranchCatalog(businessId, branchId, [
      for (final product in selected)
        CustomerCatalogItem(
          id: product.id,
          businessId: businessId,
          name: product.name,
          description: product.description,
          category: categoryNames[product.categoryId],
          unit: product.unit,
          priceCents: product.sellPrice,
          imageUrl: null,
          isAvailable: true,
          updatedAt: DateTime.now(),
        ),
    ]);
  }

  Future<String> submitOrder({
    required String userId,
    required String businessId,
    required String branchId,
    required String phone,
    required bool requestsOfficialReceipt,
    required String tin,
    required String notes,
    required List<
      ({String itemId, double quantity, List<ProductOptionSelection> options})
    >
    items,
    String fulfillmentType = 'pickup',
    String? deliveryAddressId,
    LocationAddress? deliveryAddress,
    String paymentMethod = 'cash',
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Connect to the internet to submit your order.');
    }
    if (items.isEmpty) throw StateError('Add at least one item to the order.');
    if (fulfillmentType != 'pickup' && fulfillmentType != 'delivery') {
      throw ArgumentError.value(
        fulfillmentType,
        'fulfillmentType',
        'Use pickup or delivery.',
      );
    }
    if (fulfillmentType == 'delivery' && deliveryAddress == null) {
      throw StateError('Select a delivery address.');
    }
    final result = await client.rpc(
      fulfillmentType == 'delivery'
          ? 'submit_customer_delivery_order'
          : 'submit_customer_order',
      params: {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_phone': phone.trim(),
        'p_requests_official_receipt': requestsOfficialReceipt,
        'p_tin': requestsOfficialReceipt ? tin.trim() : null,
        'p_notes': _nullIfBlank(notes),
        'p_payment_method': paymentMethod,
        'p_items': [
          for (final item in items)
            {
              'catalog_item_id': item.itemId,
              'quantity': item.quantity,
              'options': item.options.map((option) => option.toJson()).toList(),
            },
        ],
        if (fulfillmentType == 'delivery') ...{
          'p_address_snapshot': {
            'address_id': deliveryAddressId,
            ...deliveryAddress!.toJson(),
          },
          'p_delivery_latitude': deliveryAddress.coordinate?.latitude,
          'p_delivery_longitude': deliveryAddress.coordinate?.longitude,
          'p_delivery_accuracy_meters':
              deliveryAddress.coordinate?.accuracyMeters,
        },
      },
    );
    final orderId = result as String;
    await loadOrders(userId: userId);
    return orderId;
  }

  Future<List<CustomerOrder>> loadOrders({
    String? userId,
    String? businessId,
    String? branchId,
  }) async {
    if (_client == null) {
      return (db.select(db.customerOrders)
            ..where((order) {
              if (userId != null) {
                return order.customerUserId.equals(userId);
              }
              return order.businessId.equals(businessId!) &
                  (branchId == null
                      ? const Constant(true)
                      : order.branchId.equals(branchId));
            })
            ..orderBy([(order) => OrderingTerm.desc(order.createdAt)]))
          .get();
    }

    final query = _client
        .from('customer_orders')
        .select(
          'id, business_id, customer_user_id, branch_id, branch_name, currency_code, status, '
          'customer_name, customer_phone, requests_official_receipt, customer_tin, '
          'notes, total_cents, created_at, updated_at',
        );
    final rows = userId != null
        ? await query
              .eq('customer_user_id', userId)
              .order('created_at', ascending: false)
        : await (branchId == null
                  ? query.eq('business_id', businessId!)
                  : query
                        .eq('business_id', businessId!)
                        .eq('branch_id', branchId))
              .order('created_at', ascending: false);
    final orders = rows.map(_orderFromCloud).toList();
    await db.batch((batch) {
      batch.insertAll(
        db.customerOrders,
        orders.map(_orderCompanion).toList(),
        mode: InsertMode.insertOrReplace,
      );
    });
    return orders;
  }

  Future<List<CustomerOrderItem>> loadOrderItems(String orderId) async {
    if (_client != null) {
      final rows = await _client
          .from('customer_order_items')
          .select(
            'id, order_id, catalog_item_id, item_name, unit, quantity, '
            'unit_price_cents, total_cents',
          )
          .eq('order_id', orderId);
      final items = rows.map(_orderItemFromCloud).toList();
      await db.batch((batch) {
        batch.insertAll(
          db.customerOrderItems,
          items.map(_orderItemCompanion).toList(),
          mode: InsertMode.insertOrReplace,
        );
      });
      return items;
    }
    return (db.select(
      db.customerOrderItems,
    )..where((item) => item.orderId.equals(orderId))).get();
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String businessId,
    required String status,
  }) async {
    const allowed = {
      'accepted',
      'rejected',
      'preparing',
      'ready',
      'completed',
      'cancelled',
    };
    if (!allowed.contains(status)) throw ArgumentError.value(status, 'status');
    final client = _client;
    if (client == null) {
      throw StateError('Connect to the cloud to update customer orders.');
    }
    await client
        .from('customer_orders')
        .update({'status': status})
        .eq('id', orderId)
        .eq('business_id', businessId);
    await loadOrders(businessId: businessId);
  }

  Future<int> loyaltyBalance({
    required String userId,
    required String businessId,
  }) async {
    if (_client != null) {
      final rows = await _client
          .from('customer_loyalty_entries')
          .select('points')
          .eq('customer_user_id', userId)
          .eq('business_id', businessId);
      return rows.fold<int>(
        0,
        (sum, row) => sum + (row['points'] as num).toInt(),
      );
    }
    final rows =
        await (db.select(db.customerLoyaltyEntries)..where(
              (entry) =>
                  entry.customerUserId.equals(userId) &
                  entry.businessId.equals(businessId),
            ))
            .get();
    return rows.fold<int>(0, (sum, entry) => sum + entry.points);
  }

  Future<List<CustomerStorefront>> _offlineStores(String city) async {
    final branchRows = await (db.select(
      db.customerStoreBranches,
    )..where((branch) => branch.isActive.equals(true))).get();
    final branches = await Future.wait(
      branchRows.map((branch) => _branchWithCity(branch)),
    );
    final businessIds = branches
        .where(
          (branch) =>
              branch.storefrontPublished &&
              normalizeStoreCity(branch.city ?? '') == city,
        )
        .map((branch) => branch.businessId)
        .toSet();
    if (businessIds.isEmpty) return const [];
    final cached =
        await (db.select(db.customerStorefronts)
              ..where(
                (store) =>
                    store.isPublished.equals(true) &
                    store.offlineEnabled.equals(true) &
                    store.businessId.isIn(businessIds),
              )
              ..orderBy([(store) => OrderingTerm.asc(store.name)]))
            .get();
    final stores = await Future.wait(cached.map(_withOpeningHours));
    return stores;
  }

  Future<CustomerStorefront?> _cachedOfflineStorefront(
    String businessId,
    String city,
  ) async {
    final cached =
        await (db.select(db.customerStorefronts)..where(
              (store) =>
                  store.businessId.equals(businessId) &
                  store.isPublished.equals(true) &
                  store.offlineEnabled.equals(true),
            ))
            .getSingleOrNull();
    final branches = await _offlineBranches(businessId, city);
    if (cached == null || branches.isEmpty) {
      return null;
    }
    return _withOpeningHours(cached);
  }

  Future<CustomerStorefrontWithHours> _withOpeningHours(
    CustomerStorefront store,
  ) async {
    final row = await db
        .customSelect(
          'SELECT opening_hours FROM customer_storefronts WHERE business_id = ?',
          variables: [Variable<String>(store.businessId)],
        )
        .getSingleOrNull();
    return CustomerStorefrontWithHours(
      storefront: store,
      openingHoursJson: row?.read<String>('opening_hours') ?? '{}',
    );
  }

  Future<List<CustomerCatalogItem>> _offlineCatalog(
    CustomerStorefront store,
    String branchId,
  ) async {
    if (!store.offlineEnabled) return const [];
    final links = await db
        .customSelect(
          'SELECT catalog_item_id FROM customer_branch_catalog '
          'WHERE branch_id = ?',
          variables: [Variable<String>(branchId)],
        )
        .get();
    final ids = links.map((r) => r.read<String>('catalog_item_id')).toList();
    if (ids.isEmpty) return const [];
    return (db.select(db.customerCatalogItems)
          ..where(
            (item) =>
                item.businessId.equals(store.businessId) &
                item.isAvailable.equals(true) &
                item.id.isIn(ids),
          )
          ..orderBy([(item) => OrderingTerm.asc(item.name)]))
        .get();
  }

  Future<List<CustomerStoreBranchWithCity>> _offlineBranches(
    String businessId,
    String city,
  ) async {
    final branches =
        await (db.select(db.customerStoreBranches)..where(
              (branch) =>
                  branch.businessId.equals(businessId) &
                  branch.isActive.equals(true),
            ))
            .get();
    final withCities = await Future.wait(
      branches.map((branch) => _branchWithCity(branch)),
    );
    return withCities
        .where(
          (branch) =>
              branch.storefrontPublished &&
              normalizeStoreCity(branch.city ?? '') == city,
        )
        .toList();
  }

  Future<CustomerStoreBranchWithCity> _branchWithCity(
    CustomerStoreBranch branch,
  ) async {
    final row = await db
        .customSelect(
          'SELECT city, storefront_published, phone, opening_hours '
          'FROM customer_store_branches WHERE id = ?',
          variables: [Variable<String>(branch.id)],
        )
        .getSingleOrNull();
    return CustomerStoreBranchWithCity(
      branch: branch,
      city: row?.read<String?>('city'),
      storefrontPublished: row?.read<bool>('storefront_published') ?? false,
      phone: row?.read<String?>('phone'),
      openingHoursJson: row?.read<String>('opening_hours') ?? '{}',
      coordinate: row == null ? null : await _localBranchCoordinate(branch.id),
    );
  }

  Future<GeoCoordinate?> _localBranchCoordinate(String branchId) async {
    final row = await db
        .customSelect(
          'SELECT latitude, longitude, location_accuracy_meters '
          'FROM branch_locations WHERE branch_id = ?',
          variables: [Variable<String>(branchId)],
        )
        .getSingleOrNull();
    if (row == null ||
        row.read<double?>('latitude') == null ||
        row.read<double?>('longitude') == null) {
      return null;
    }
    return GeoCoordinate(
      latitude: row.read<double>('latitude'),
      longitude: row.read<double>('longitude'),
      accuracyMeters: row.read<double?>('location_accuracy_meters'),
    );
  }

  Future<void> _cacheStoreBranches(
    List<CustomerStoreBranchWithCity> branches,
  ) async {
    await db.batch((batch) {
      batch.insertAll(
        db.customerStoreBranches,
        branches.map(_branchCompanion).toList(),
        mode: InsertMode.insertOrReplace,
      );
    });
    for (final branch in branches) {
      await db.customStatement(
        'UPDATE customer_store_branches SET city = ?, storefront_published = ?, '
        'phone = ?, opening_hours = ? WHERE id = ?',
        [
          branch.city,
          branch.storefrontPublished ? 1 : 0,
          branch.phone,
          branch.openingHoursJson,
          branch.id,
        ],
      );
      if (branch.coordinate != null) {
        await db.customStatement(
          '''
          INSERT INTO branch_locations (
            branch_id, business_id, latitude, longitude,
            location_accuracy_meters, location_verified
          ) VALUES (?, ?, ?, ?, ?, 'confirmed')
          ON CONFLICT(branch_id) DO UPDATE SET
            latitude = excluded.latitude,
            longitude = excluded.longitude,
            location_accuracy_meters = excluded.location_accuracy_meters
          ''',
          [
            branch.id,
            branch.businessId,
            branch.coordinate!.latitude,
            branch.coordinate!.longitude,
            branch.coordinate!.accuracyMeters,
          ],
        );
      }
    }
  }

  Future<void> _cacheStorefronts(List<CustomerStorefront> stores) async {
    await db.transaction(() async {
      await db.batch((batch) {
        batch.insertAll(
          db.customerStorefronts,
          stores.map(_storefrontCompanion).toList(),
          mode: InsertMode.insertOrReplace,
        );
      });
      for (final store in stores) {
        await db.customStatement(
          'UPDATE customer_storefronts SET opening_hours = ? '
          'WHERE business_id = ?',
          [storefrontOpeningHoursJson(store), store.businessId],
        );
      }
    });
  }

  Future<void> _cacheCatalog(
    String businessId,
    List<CustomerCatalogItem> items,
  ) async {
    await db.transaction(() async {
      await (db.delete(
        db.customerCatalogItems,
      )..where((item) => item.businessId.equals(businessId))).go();
      if (items.isNotEmpty) {
        await db.batch((batch) {
          batch.insertAll(
            db.customerCatalogItems,
            items.map(_catalogCompanion).toList(),
            mode: InsertMode.insertOrReplace,
          );
        });
      }
    });
  }

  Future<void> _cacheBranchCatalog(
    String businessId,
    String branchId,
    List<CustomerCatalogItem> items,
  ) async {
    await db.transaction(() async {
      if (items.isNotEmpty) {
        await db.batch((batch) {
          batch.insertAll(
            db.customerCatalogItems,
            items.map(_catalogCompanion).toList(),
            mode: InsertMode.insertOrReplace,
          );
        });
      }
      await db.customStatement(
        'DELETE FROM customer_branch_catalog WHERE branch_id = ?',
        [branchId],
      );
      for (final item in items) {
        await db.customStatement(
          'INSERT OR REPLACE INTO customer_branch_catalog '
          '(branch_id, catalog_item_id, business_id) VALUES (?, ?, ?)',
          [branchId, item.id, businessId],
        );
      }
    });
  }

  static CustomerStorefront _storefrontFromCloud(Map<String, dynamic> row) =>
      CustomerStorefrontWithHours(
        storefront: CustomerStorefront(
          businessId: row['business_id'] as String,
          name: row['name'] as String,
          description: row['description'] as String?,
          phone: row['phone'] as String?,
          address: row['address'] as String?,
          city: row['city'] as String?,
          currencyCode: row['currency_code'] as String,
          isPublished: row['is_published'] as bool,
          offlineEnabled: row['offline_enabled'] as bool,
          pointsPerCurrencyUnit: (row['points_per_currency_unit'] as num)
              .toInt(),
          updatedAt: _date(row['updated_at']),
        ),
        openingHoursJson: _openingHoursJson(row['opening_hours']),
      );

  static CustomerCatalogItem _catalogItemFromCloud(Map<String, dynamic> row) =>
      CustomerCatalogItem(
        id: row['id'] as String,
        businessId: row['business_id'] as String,
        name: row['name'] as String,
        description: row['description'] as String?,
        category: row['category'] as String?,
        unit: row['unit'] as String,
        priceCents: (row['price_cents'] as num?)?.toInt(),
        imageUrl: row['image_url'] as String?,
        isAvailable: row['is_available'] as bool,
        updatedAt: _date(row['updated_at']),
      );

  static CustomerStoreBranchWithCity _branchFromCloud(
    Map<String, dynamic> row, [
    GeoCoordinate? coordinate,
  ]) => CustomerStoreBranchWithCity(
    branch: CustomerStoreBranch(
      id: row['id'] as String,
      businessId: row['business_id'] as String,
      name: row['name'] as String,
      address: row['address'] as String?,
      isActive: row['is_active'] as bool,
      updatedAt: _date(row['updated_at']),
    ),
    city: row['city'] as String?,
    storefrontPublished: row['storefront_published'] as bool,
    phone: row['phone'] as String?,
    openingHoursJson: _openingHoursJson(row['opening_hours']),
    coordinate: coordinate,
  );

  static CustomerOrder _orderFromCloud(Map<String, dynamic> row) =>
      CustomerOrder(
        id: row['id'] as String,
        businessId: row['business_id'] as String,
        customerUserId: row['customer_user_id'] as String,
        branchId: row['branch_id'] as String,
        branchName: row['branch_name'] as String,
        currencyCode: row['currency_code'] as String,
        status: row['status'] as String,
        customerName: row['customer_name'] as String,
        customerPhone: row['customer_phone'] as String,
        requestsOfficialReceipt: row['requests_official_receipt'] as bool,
        customerTin: row['customer_tin'] as String?,
        notes: row['notes'] as String?,
        totalCents: (row['total_cents'] as num).toInt(),
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
      );

  static CustomerOrderItem _orderItemFromCloud(Map<String, dynamic> row) =>
      CustomerOrderItem(
        id: row['id'] as String,
        orderId: row['order_id'] as String,
        catalogItemId: row['catalog_item_id'] as String,
        itemName: row['item_name'] as String,
        unit: row['unit'] as String,
        quantity: (row['quantity'] as num).toDouble(),
        unitPriceCents: (row['unit_price_cents'] as num).toInt(),
        totalCents: (row['total_cents'] as num).toInt(),
      );

  static CustomerStorefrontsCompanion _storefrontCompanion(
    CustomerStorefront store,
  ) => CustomerStorefrontsCompanion.insert(
    businessId: store.businessId,
    name: store.name,
    description: Value(store.description),
    phone: Value(store.phone),
    address: Value(store.address),
    city: Value(store.city),
    currencyCode: Value(store.currencyCode),
    isPublished: Value(store.isPublished),
    offlineEnabled: Value(store.offlineEnabled),
    pointsPerCurrencyUnit: Value(store.pointsPerCurrencyUnit),
    updatedAt: Value(store.updatedAt),
  );

  static CustomerCatalogItemsCompanion _catalogCompanion(
    CustomerCatalogItem item,
  ) => CustomerCatalogItemsCompanion.insert(
    id: item.id,
    businessId: item.businessId,
    name: item.name,
    description: Value(item.description),
    category: Value(item.category),
    unit: item.unit,
    priceCents: Value(item.priceCents),
    imageUrl: Value(item.imageUrl),
    isAvailable: Value(item.isAvailable),
    updatedAt: Value(item.updatedAt),
  );

  static CustomerStoreBranchesCompanion _branchCompanion(
    CustomerStoreBranch branch,
  ) => CustomerStoreBranchesCompanion.insert(
    id: branch.id,
    businessId: branch.businessId,
    name: branch.name,
    address: Value(branch.address),
    isActive: Value(branch.isActive),
    updatedAt: Value(branch.updatedAt),
  );

  static CustomerOrdersCompanion _orderCompanion(CustomerOrder order) =>
      CustomerOrdersCompanion.insert(
        id: order.id,
        businessId: order.businessId,
        customerUserId: order.customerUserId,
        branchId: order.branchId,
        branchName: order.branchName,
        currencyCode: Value(order.currencyCode),
        status: order.status,
        customerName: order.customerName,
        customerPhone: order.customerPhone,
        requestsOfficialReceipt: Value(order.requestsOfficialReceipt),
        customerTin: Value(order.customerTin),
        notes: Value(order.notes),
        totalCents: order.totalCents,
        createdAt: Value(order.createdAt),
        updatedAt: Value(order.updatedAt),
      );

  static CustomerOrderItemsCompanion _orderItemCompanion(
    CustomerOrderItem item,
  ) => CustomerOrderItemsCompanion.insert(
    id: item.id,
    orderId: item.orderId,
    catalogItemId: item.catalogItemId,
    itemName: item.itemName,
    unit: item.unit,
    quantity: item.quantity,
    unitPriceCents: item.unitPriceCents,
    totalCents: item.totalCents,
  );

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now().toUtc();

  static String _openingHoursJson(Object? value) {
    if (value == null) return '{}';
    if (value is String) return value;
    if (value is Map<String, dynamic>) return jsonEncode(value);
    throw FormatException('Invalid storefront hours value: $value');
  }

  static String? _nullIfBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static GeoCoordinate? _coordinateFromMap(Map<String, dynamic> row) {
    final latitude = (row['latitude'] as num?)?.toDouble();
    final longitude = (row['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    return GeoCoordinate(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: (row['location_accuracy_meters'] as num?)?.toDouble(),
    );
  }

  static GeoCoordinate? _coordinateFromRow(QueryRow? row) {
    if (row == null) return null;
    final latitude = row.read<double?>('latitude');
    final longitude = row.read<double?>('longitude');
    if (latitude == null || longitude == null) return null;
    return GeoCoordinate(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: row.read<double?>('location_accuracy_meters'),
    );
  }
}

String normalizeStoreCity(String city) =>
    city.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

final customerCommerceServiceProvider = Provider<CustomerCommerceService>((
  ref,
) {
  final available = ref.watch(supabaseAvailableProvider);
  return CustomerCommerceService(
    ref.watch(databaseProvider),
    client: available ? ref.watch(supabaseClientProvider) : null,
  );
});

String storefrontInvitePayload(String businessId, {String? branchId}) =>
    branchId == null
    ? 'bosapp://store/$businessId'
    : 'bosapp://store/$businessId?branch=$branchId';

String? branchIdFromStorefrontInvite(String payload) {
  final id = Uri.tryParse(payload.trim())?.queryParameters['branch'];
  if (id == null ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(id)) {
    return null;
  }
  return id;
}

String? businessIdFromStorefrontInvite(String payload) {
  final uri = Uri.tryParse(payload.trim());
  if (uri == null || uri.scheme != 'bosapp' || uri.host != 'store') return null;
  final businessId = uri.pathSegments.length == 1
      ? uri.pathSegments.single
      : '';
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(businessId)) {
    return null;
  }
  return businessId;
}

String newCustomerOrderId() => _uuid.v4();
