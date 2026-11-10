import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'location_models.dart';

class SavedCustomerAddress {
  const SavedCustomerAddress({
    required this.id,
    required this.customerUserId,
    required this.label,
    required this.address,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String customerUserId;
  final String label;
  final LocationAddress address;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class LocationRepository {
  LocationRepository(this.db);

  static const _uuid = Uuid();
  final AppDatabase db;

  Future<List<SavedCustomerAddress>> loadCustomerAddresses(
    String customerUserId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM customer_addresses WHERE customer_user_id = ? '
          'ORDER BY is_default DESC, updated_at DESC',
          variables: [Variable<String>(customerUserId)],
        )
        .get();
    return rows.map(_addressFromRow).toList();
  }

  Future<SavedCustomerAddress> saveCustomerAddress({
    String? id,
    required String customerUserId,
    required String label,
    required LocationAddress address,
    required bool isDefault,
  }) async {
    final cleanLabel = label.trim().toLowerCase();
    if (!{'home', 'work', 'other'}.contains(cleanLabel)) {
      throw ArgumentError.value(label, 'label', 'Use home, work, or other.');
    }
    if (address.recipientName?.trim().isEmpty ?? true) {
      throw StateError('Recipient name is required.');
    }
    if (address.contactNumber?.trim().isEmpty ?? true) {
      throw StateError('Recipient contact number is required.');
    }
    final addressId = id ?? _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.transaction(() async {
      if (isDefault) {
        await db.customStatement(
          'UPDATE customer_addresses SET is_default = 0, updated_at = ? '
          'WHERE customer_user_id = ?',
          [now, customerUserId],
        );
      }
      await db.customStatement(
        '''
        INSERT INTO customer_addresses (
          id, customer_user_id, label, recipient_name, contact_number,
          country, region, province, city, barangay, street_address,
          building_or_unit, postal_code, landmark, formatted_address,
          latitude, longitude, location_accuracy_meters, is_default,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          label = excluded.label,
          recipient_name = excluded.recipient_name,
          contact_number = excluded.contact_number,
          country = excluded.country,
          region = excluded.region,
          province = excluded.province,
          city = excluded.city,
          barangay = excluded.barangay,
          street_address = excluded.street_address,
          building_or_unit = excluded.building_or_unit,
          postal_code = excluded.postal_code,
          landmark = excluded.landmark,
          formatted_address = excluded.formatted_address,
          latitude = excluded.latitude,
          longitude = excluded.longitude,
          location_accuracy_meters = excluded.location_accuracy_meters,
          is_default = excluded.is_default,
          updated_at = excluded.updated_at
        ''',
        [
          addressId,
          customerUserId,
          cleanLabel,
          address.recipientName!.trim(),
          address.contactNumber!.trim(),
          address.country,
          address.region,
          address.province,
          address.city,
          address.barangay,
          address.streetAddress,
          address.buildingOrUnit,
          address.postalCode,
          address.landmark,
          address.formattedAddress,
          address.coordinate?.latitude,
          address.coordinate?.longitude,
          address.coordinate?.accuracyMeters,
          isDefault ? 1 : 0,
          now,
          now,
        ],
      );
    });
    final row = await db
        .customSelect(
          'SELECT * FROM customer_addresses WHERE id = ?',
          variables: [Variable<String>(addressId)],
        )
        .getSingle();
    return _addressFromRow(row);
  }

  Future<void> deleteCustomerAddress({
    required String customerUserId,
    required String addressId,
  }) async {
    final deleted = await db.customUpdate(
      'DELETE FROM customer_addresses WHERE id = ? AND customer_user_id = ?',
      variables: [
        Variable<String>(addressId),
        Variable<String>(customerUserId),
      ],
    );
    if (deleted == 0) throw StateError('Address not found.');
  }

  SavedCustomerAddress _addressFromRow(QueryRow row) {
    final json = <String, dynamic>{
      'recipient_name': row.read<String>('recipient_name'),
      'contact_number': row.read<String>('contact_number'),
      'country': row.read<String?>('country'),
      'region': row.read<String?>('region'),
      'province': row.read<String?>('province'),
      'city': row.read<String?>('city'),
      'barangay': row.read<String?>('barangay'),
      'street_address': row.read<String?>('street_address'),
      'building_or_unit': row.read<String?>('building_or_unit'),
      'postal_code': row.read<String?>('postal_code'),
      'landmark': row.read<String?>('landmark'),
      'formatted_address': row.read<String?>('formatted_address'),
      'latitude': row.read<double?>('latitude'),
      'longitude': row.read<double?>('longitude'),
      'accuracy_meters': row.read<double?>('location_accuracy_meters'),
    };
    return SavedCustomerAddress(
      id: row.read<String>('id'),
      customerUserId: row.read<String>('customer_user_id'),
      label: row.read<String>('label'),
      address: LocationAddress.fromJson(json),
      isDefault: row.read<bool>('is_default'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at') * 1000,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at') * 1000,
      ),
    );
  }

  Future<void> saveOrderAddressSnapshot({
    required String orderId,
    required String fulfillmentType,
    required String? addressId,
    required LocationAddress? address,
  }) async {
    if (fulfillmentType != 'pickup' && fulfillmentType != 'delivery') {
      throw ArgumentError.value(
        fulfillmentType,
        'fulfillmentType',
        'Use pickup or delivery.',
      );
    }
    if (fulfillmentType == 'delivery' && address == null) {
      throw StateError('A delivery address is required.');
    }
    await db.customStatement(
      '''
      UPDATE customer_orders
      SET fulfillment_type = ?,
          delivery_address_snapshot = ?,
          delivery_latitude = ?,
          delivery_longitude = ?,
          delivery_accuracy_meters = ?
      WHERE id = ?
      ''',
      [
        fulfillmentType,
        address == null
            ? null
            : jsonEncode({...address.toJson(), 'address_id': addressId}),
        address?.coordinate?.latitude,
        address?.coordinate?.longitude,
        address?.coordinate?.accuracyMeters,
        orderId,
      ],
    );
  }
}
