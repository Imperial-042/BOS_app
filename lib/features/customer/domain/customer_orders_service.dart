// lib/features/customer/domain/customer_orders_service.dart
//
// Customer orders and loyalty points (cloud + local cache).
// Moved out of CustomerCommerceService.

import 'dart:async';

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/location/location_models.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/features/transactions/domain/product_variants.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

class CustomerOrdersService {
  CustomerOrdersService(this.db, {SupabaseClient? client}) : _client = client;

  final AppDatabase db;
  final SupabaseClient? _client;

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
  static String? _nullIfBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();}

final customerOrdersServiceProvider = Provider<CustomerOrdersService>((ref) {
  final available = ref.watch(supabaseAvailableProvider);
  return CustomerOrdersService(
    ref.watch(databaseProvider),
    client: available ? ref.watch(supabaseClientProvider) : null,
  );
});