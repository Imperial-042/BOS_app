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

const _uuid = Uuid();

String pendingCustomerProfileKey(String email) =>
    'pending_customer_profile:${email.trim().toLowerCase()}';

typedef StoreHours = ({String open, String close});

class CustomerLocationProfile {
  const CustomerLocationProfile({
    required this.id,
    required this.displayName,
    required this.city,
    required this.address,
  });

  final String id;
  final String displayName;
  final String? city;
  final String? address;
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

class CustomerStoreBranchWithCity extends CustomerStoreBranch {
  CustomerStoreBranchWithCity({
    required CustomerStoreBranch branch,
    required this.city,
    required this.storefrontPublished,
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
}

String storefrontOpeningHoursJson(CustomerStorefront store) =>
    store is CustomerStorefrontWithHours ? store.openingHoursJson : '{}';

Map<int, StoreHours> parseStoreHours(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Store hours must be a JSON object.');
  }
  final hours = <int, StoreHours>{};
  for (final entry in decoded.entries) {
    final day = int.tryParse(entry.key);
    final times = entry.value;
    if (day == null || day < 1 || day > 7 || times is! Map<String, dynamic>) {
      throw const FormatException('Store hours contain an invalid day.');
    }
    final open = times['open'];
    final close = times['close'];
    if (open is! String ||
        close is! String ||
        !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(open) ||
        !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(close) ||
        open.compareTo(close) >= 0) {
      throw const FormatException('Store hours contain an invalid time.');
    }
    hours[day] = (open: open, close: close);
  }
  return hours;
}

String serializeStoreHours(Map<int, StoreHours> hours) {
  final value = jsonEncode({
    for (final entry in hours.entries)
      '${entry.key}': {'open': entry.value.open, 'close': entry.value.close},
  });
  parseStoreHours(value);
  return value;
}

bool storefrontIsOpen(CustomerStorefront store, {DateTime? at}) {
  final value = storefrontOpeningHoursJson(store);
  if (value == '{}') return true;
  final hours = parseStoreHours(value);
  final now = at ?? DateTime.now();
  final today = hours[now.weekday];
  if (today == null) return false;
  final time =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  return time.compareTo(today.open) >= 0 && time.compareTo(today.close) < 0;
}

String storefrontHoursToday(CustomerStorefront store, {DateTime? at}) {
  final value = storefrontOpeningHoursJson(store);
  if (value == '{}') {
    return 'No hours set · orders accepted anytime';
  }
  final hours = parseStoreHours(value);
  final today = hours[(at ?? DateTime.now()).weekday];
  return today == null ? 'Closed today' : 'Today: ${today.open}–${today.close}';
}

class CustomerCommerceService {
  CustomerCommerceService(this.db, {SupabaseClient? client}) : _client = client;

  final AppDatabase db;
  final SupabaseClient? _client;

  Future<void> ensureCustomerProfile({
    required String userId,
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) throw StateError('Enter your name.');

    if (_client != null) {
      await _client.from('customer_profiles').upsert({
        'id': userId,
        'display_name': name,
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
  }

  Future<bool> hasCustomerProfile(String userId) async {
    final local = await (db.select(
      db.customerProfiles,
    )..where((profile) => profile.id.equals(userId))).getSingleOrNull();
    if (local != null) return true;
    if (_client == null) return false;

    final row = await _client
        .from('customer_profiles')
        .select('id, display_name, city, address')
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
    );
    return true;
  }

  Future<CustomerLocationProfile?> loadCustomerProfile(String userId) async {
    Map<String, dynamic>? remote;
    if (_client != null) {
      try {
        remote = await _client
            .from('customer_profiles')
            .select('id, display_name, city, address')
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
        city: remote['city'] as String?,
        address: remote['address'] as String?,
      );
    }
    final profile = await (db.select(
      db.customerProfiles,
    )..where((profile) => profile.id.equals(userId))).getSingleOrNull();
    if (profile == null) return null;
    final location = await db
        .customSelect(
          'SELECT city, address FROM customer_profiles WHERE id = ?',
          variables: [Variable<String>(userId)],
        )
        .getSingleOrNull();
    return CustomerLocationProfile(
      id: userId,
      displayName: profile.displayName,
      city: location?.read<String?>('city'),
      address: location?.read<String?>('address'),
    );
  }

  Future<void> updateCustomerLocation({
    required String userId,
    required String city,
    required String address,
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
          .update({'city': cleanCity, 'address': cleanAddress})
          .eq('id', userId)
          .select('id');
      if (rows.isEmpty) throw StateError('Customer profile not found.');
    }
    await _writeLocalCustomerLocation(userId, cleanCity, cleanAddress);
  }

  Future<void> _writeLocalCustomerLocation(
    String userId,
    String? city,
    String? address,
  ) async {
    await db.customStatement(
      'UPDATE customer_profiles SET city = ?, address = ?, updated_at = ? '
      'WHERE id = ?',
      [city, address, DateTime.now().millisecondsSinceEpoch ~/ 1000, userId],
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
          .eq('is_active', true);
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
  }) async {
    final storefront = await loadStorefrontForCity(businessId, city: city);
    if (storefront == null) return const [];

    if (_client != null) {
      try {
        final rows = await _client
            .from('customer_catalog_items')
            .select(
              'id, business_id, name, description, category, unit, '
              'price_cents, image_url, is_available, updated_at',
            )
            .eq('business_id', businessId)
            .eq('is_available', true)
            .order('name');
        final items = rows.map(_catalogItemFromCloud).toList();
        await _cacheCatalog(businessId, items);
        return items;
      } on SocketException {
        return _offlineCatalog(storefront);
      } on HttpException {
        return _offlineCatalog(storefront);
      } on TimeoutException {
        return _offlineCatalog(storefront);
      }
    }
    return _offlineCatalog(storefront);
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
              'id, business_id, name, address, city, storefront_published, '
              'is_active, updated_at',
            )
            .eq('business_id', businessId)
            .eq('is_active', true)
            .order('name');
        final branches = rows
            .map(_branchFromCloud)
            .where(
              (branch) =>
                  normalizeStoreCity(branch.city ?? '') == normalizedCity,
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

  Future<void> publishStorefront({
    required String businessId,
    required String name,
    required String description,
    required String phone,
    required String address,
    required String city,
    required String currencyCode,
    required bool isPublished,
    required bool offlineEnabled,
    required int pointsPerCurrencyUnit,
    required Map<int, StoreHours> openingHours,
    required Set<String> publishedProductIds,
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
    if (isPublished && name.trim().isEmpty) {
      throw StateError('Enter a storefront name before publishing.');
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
    final activeBranches = branches.where((branch) => branch.isActive).toList();
    if (isPublished &&
        (activeBranches.isEmpty ||
            activeBranches.any(
              (branch) =>
                  normalizeStoreCity(branchCities[branch.id] ?? '').isEmpty,
            ))) {
      throw StateError(
        'Add a city to every active branch before publishing the storefront.',
      );
    }

    await client.from('customer_storefronts').upsert({
      'business_id': businessId,
      'name': name.trim(),
      'description': _nullIfBlank(description),
      'phone': _nullIfBlank(phone),
      'address': _nullIfBlank(address),
      'city': _nullIfBlank(city),
      'currency_code': currencyCode,
      'is_published': isPublished,
      'offline_enabled': offlineEnabled,
      'points_per_currency_unit': pointsPerCurrencyUnit,
      'opening_hours': jsonDecode(serializeStoreHours(openingHours)),
    });

    if (branches.isNotEmpty) {
      await client
          .from('customer_store_branches')
          .upsert(
            branches
                .map(
                  (branch) => {
                    'id': branch.id,
                    'business_id': businessId,
                    'name': branch.name,
                    'address': _nullIfBlank(branch.address),
                    'city': _nullIfBlank(branchCities[branch.id]),
                    'storefront_published': isPublished,
                    'is_active': branch.isActive,
                  },
                )
                .toList(),
          );
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
          storefrontPublished: isPublished,
        ),
    ]);

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

    final cached = CustomerStorefrontWithHours(
      storefront: CustomerStorefront(
        businessId: businessId,
        name: name.trim(),
        description: _nullIfBlank(description),
        phone: _nullIfBlank(phone),
        address: _nullIfBlank(address),
        city: _nullIfBlank(city),
        currencyCode: currencyCode,
        isPublished: isPublished,
        offlineEnabled: offlineEnabled,
        pointsPerCurrencyUnit: pointsPerCurrencyUnit,
        updatedAt: DateTime.now(),
      ),
      openingHoursJson: serializeStoreHours(openingHours),
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

  Future<String> submitOrder({
    required String userId,
    required String businessId,
    required String branchId,
    required String phone,
    required bool requestsOfficialReceipt,
    required String tin,
    required String notes,
    required List<({String itemId, double quantity})> items,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Connect to the internet to submit your order.');
    }
    if (items.isEmpty) throw StateError('Add at least one item to the order.');
    final result = await client.rpc(
      'submit_customer_order',
      params: {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_phone': phone.trim(),
        'p_requests_official_receipt': requestsOfficialReceipt,
        'p_tin': requestsOfficialReceipt ? tin.trim() : null,
        'p_notes': _nullIfBlank(notes),
        'p_items': [
          for (final item in items)
            {'catalog_item_id': item.itemId, 'quantity': item.quantity},
        ],
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
  ) async {
    if (!store.offlineEnabled) return const [];
    return (db.select(db.customerCatalogItems)
          ..where(
            (item) =>
                item.businessId.equals(store.businessId) &
                item.isAvailable.equals(true),
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
          'SELECT city, storefront_published '
          'FROM customer_store_branches WHERE id = ?',
          variables: [Variable<String>(branch.id)],
        )
        .getSingleOrNull();
    return CustomerStoreBranchWithCity(
      branch: branch,
      city: row?.read<String?>('city'),
      storefrontPublished: row?.read<bool>('storefront_published') ?? false,
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
        'UPDATE customer_store_branches '
        'SET city = ?, storefront_published = ? WHERE id = ?',
        [branch.city, branch.storefrontPublished ? 1 : 0, branch.id],
      );
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
    Map<String, dynamic> row,
  ) => CustomerStoreBranchWithCity(
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

String storefrontInvitePayload(String businessId) =>
    'bosapp://store/$businessId';

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
