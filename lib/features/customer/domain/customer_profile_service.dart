// lib/features/customer/domain/customer_profile_service.dart
//
// The signed-in customer's own profile and location (cloud + local cache).
// Moved out of CustomerCommerceService.

import 'dart:async';
import 'dart:io';

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/location/location_models.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/features/customer/domain/storefront_models.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

class CustomerProfileService {
  CustomerProfileService(this.db, {SupabaseClient? client}) : _client = client;

  final AppDatabase db;
  final SupabaseClient? _client;

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

  static String? _nullIfBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();}

final customerProfileServiceProvider = Provider<CustomerProfileService>((ref) {
  final available = ref.watch(supabaseAvailableProvider);
  return CustomerProfileService(
    ref.watch(databaseProvider),
    client: available ? ref.watch(supabaseClientProvider) : null,
  );
});