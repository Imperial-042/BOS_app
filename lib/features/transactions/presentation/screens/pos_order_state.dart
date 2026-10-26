// lib/features/production/presentation/screens/pos_order_state.dart
//
// Order state for the POS (moved out of pos_page.dart so the page and the
// checkout sheet can both use it without importing each other).
//
// STOCK RULE: addOrIncrement / updateQuantity take the item's current
// maximum producible units. If the requested quantity would exceed it, the
// change is refused and `false` is returned so the UI can explain why.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';

class POSLineItem {
  final String productId;
  final String name;
  final String unit;
  final int unitPriceCents;
  final int quantity;

  const POSLineItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.unitPriceCents,
    required this.quantity,
  });

  int get lineTotal => unitPriceCents * quantity;

  POSLineItem copyWith({int? quantity}) {
    return POSLineItem(
      productId: productId,
      name: name,
      unit: unit,
      unitPriceCents: unitPriceCents,
      quantity: quantity ?? this.quantity,
    );
  }
}

class POSOrderNotifier extends StateNotifier<List<POSLineItem>> {
  POSOrderNotifier() : super([]);

  /// Returns false (and changes nothing) if adding one more would exceed
  /// [maxUnits].
  bool addOrIncrement(Product product, {int? maxUnits}) {
    final index = state.indexWhere((line) => line.productId == product.id);
    final current = index >= 0 ? state[index].quantity : 0;

    if (maxUnits != null && current + 1 > maxUnits) return false;

    if (index >= 0) {
      final existing = state[index];
      state = [
        ...state.sublist(0, index),
        existing.copyWith(quantity: existing.quantity + 1),
        ...state.sublist(index + 1),
      ];
      return true;
    }

    state = [
      ...state,
      POSLineItem(
        productId: product.id,
        name: product.name,
        unit: product.unit,
        unitPriceCents: product.sellPrice ?? 0,
        quantity: 1,
      ),
    ];
    return true;
  }

  /// Returns false (and changes nothing) if [quantity] exceeds [maxUnits].
  /// Lowering a quantity is always allowed.
  bool updateQuantity(String productId, int quantity, {int? maxUnits}) {
    if (quantity <= 0) {
      removeItem(productId);
      return true;
    }
    final index = state.indexWhere((l) => l.productId == productId);
    if (index < 0) return false;

    final isIncrease = quantity > state[index].quantity;
    if (isIncrease && maxUnits != null && quantity > maxUnits) return false;

    state = [
      for (final line in state)
        if (line.productId == productId)
          line.copyWith(quantity: quantity)
        else
          line,
    ];
    return true;
  }

  void removeItem(String productId) {
    state = state.where((line) => line.productId != productId).toList();
  }

  void removeItems(Iterable<String> productIds) {
    final ids = productIds.toSet();
    state = state.where((line) => !ids.contains(line.productId)).toList();
  }

  /// Replaces the whole order (used when resuming a held order).
  void replaceAll(List<POSLineItem> lines) => state = List.of(lines);

  void clear() => state = [];
}

final posOrderProvider =
    StateNotifierProvider<POSOrderNotifier, List<POSLineItem>>(
      (ref) => POSOrderNotifier(),
    );
// ---------------------------------------------------------------------------
// HELD ORDERS (in memory)
// ---------------------------------------------------------------------------

class HeldOrder {
  final String id;
  final DateTime heldAt;
  final List<POSLineItem> lines;

  /// Order type and details (table, customer...) held together with the items.
  final String? orderType;
  final OrderDetails details;

  const HeldOrder({
    required this.id,
    required this.heldAt,
    required this.lines,
    this.orderType,
    this.details = const OrderDetails(),
  });

  int get total => lines.fold<int>(0, (s, l) => s + l.lineTotal);
  int get count => lines.fold<int>(0, (s, l) => s + l.quantity);
}

class HeldOrdersNotifier extends StateNotifier<List<HeldOrder>> {
  HeldOrdersNotifier(this._ref) : super([]);
  final Ref _ref;

  void hold(
    List<POSLineItem> lines, {
    String? orderType,
    OrderDetails details = const OrderDetails(),
  }) {
    if (lines.isEmpty) return;
    final now = DateTime.now();
    state = [
      ...state,
      HeldOrder(
        id: now.microsecondsSinceEpoch.toString(),
        heldAt: now,
        lines: List.of(lines),
        orderType: orderType,
        details: details,
      ),
    ];
  }

  /// Removes and returns the held order (null if it no longer exists).
  /// Also puts its order type and details (table...) back on the screen.
  HeldOrder? take(String id) {
    final index = state.indexWhere((h) => h.id == id);
    if (index < 0) return null;
    final found = state[index];
    state = [...state.sublist(0, index), ...state.sublist(index + 1)];
    _ref.read(posOrderTypeProvider.notifier).set(found.orderType);
    _ref.read(posOrderDetailsProvider.notifier).replace(found.details);
    return found;
  }

  void discard(String id) => state = state.where((h) => h.id != id).toList();
}

final heldOrdersProvider =
    StateNotifierProvider<HeldOrdersNotifier, List<HeldOrder>>(
      (ref) => HeldOrdersNotifier(ref),
    );

// ---------------------------------------------------------------------------
// ORDER TYPE (Dine in / Take out / GrabFood ...) of the current order
// ---------------------------------------------------------------------------

class PosOrderTypeNotifier extends StateNotifier<String?> {
  PosOrderTypeNotifier() : super(null);

  void set(String? value) => state = value;
}

/// Resets itself whenever the order becomes empty (sale done, cleared or
/// held), so the next order starts with no type chosen.
final posOrderTypeProvider =
    StateNotifierProvider<PosOrderTypeNotifier, String?>((ref) {
      final notifier = PosOrderTypeNotifier();
      ref.listen<List<POSLineItem>>(posOrderProvider, (_, next) {
        if (next.isEmpty) notifier.set(null);
      });
      return notifier;
    });
// ---------------------------------------------------------------------------
// ORDER DETAILS (table, guests, customer, address, platform order no.)
// ---------------------------------------------------------------------------

const Object _keep = Object();

class OrderDetails {
  final String? tableId;
  final String? tableLabel;
  final int? guests;
  final String? contactName;
  final String? contactPhone;
  final String? address;
  final String? orderRef;

  const OrderDetails({
    this.tableId,
    this.tableLabel,
    this.guests,
    this.contactName,
    this.contactPhone,
    this.address,
    this.orderRef,
  });

  OrderDetails copyWith({
    Object? tableId = _keep,
    Object? tableLabel = _keep,
    Object? guests = _keep,
    Object? contactName = _keep,
    Object? contactPhone = _keep,
    Object? address = _keep,
    Object? orderRef = _keep,
  }) {
    return OrderDetails(
      tableId: identical(tableId, _keep) ? this.tableId : tableId as String?,
      tableLabel: identical(tableLabel, _keep)
          ? this.tableLabel
          : tableLabel as String?,
      guests: identical(guests, _keep) ? this.guests : guests as int?,
      contactName: identical(contactName, _keep)
          ? this.contactName
          : contactName as String?,
      contactPhone: identical(contactPhone, _keep)
          ? this.contactPhone
          : contactPhone as String?,
      address: identical(address, _keep) ? this.address : address as String?,
      orderRef: identical(orderRef, _keep)
          ? this.orderRef
          : orderRef as String?,
    );
  }
}

class OrderDetailsNotifier extends StateNotifier<OrderDetails> {
  OrderDetailsNotifier() : super(const OrderDetails());

  void setTable(String? id, String? label) =>
      state = state.copyWith(tableId: id, tableLabel: label);
  void setGuests(int? v) => state = state.copyWith(guests: v);
  void setName(String v) => state = state.copyWith(contactName: v);
  void setPhone(String v) => state = state.copyWith(contactPhone: v);
  void setAddress(String v) => state = state.copyWith(address: v);
  void setRef(String v) => state = state.copyWith(orderRef: v);
  void replace(OrderDetails d) => state = d;
  void clear() => state = const OrderDetails();
}

/// Clears itself whenever the order becomes empty (sale done, cleared or held).
final posOrderDetailsProvider =
    StateNotifierProvider<OrderDetailsNotifier, OrderDetails>((ref) {
      final notifier = OrderDetailsNotifier();
      ref.listen<List<POSLineItem>>(posOrderProvider, (_, next) {
        if (next.isEmpty) notifier.clear();
      });
      return notifier;
    });
