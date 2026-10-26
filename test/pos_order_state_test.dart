import 'package:bos_application/features/transactions/presentation/screens/pos_order_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'customer order linkage survives holding and can be removed on cancel',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const orderId = 'customer-order-1';
      const details = OrderDetails(
        contactName: 'Customer',
        customerOrderId: orderId,
      );

      container.read(heldOrdersProvider.notifier).hold(const [
        POSLineItem(
          productId: 'product-1',
          name: 'Product',
          unit: 'each',
          unitPriceCents: 100,
          quantity: 1,
        ),
      ], details: details);

      expect(
        container.read(heldOrdersProvider).single.details.customerOrderId,
        orderId,
      );

      container
          .read(heldOrdersProvider.notifier)
          .discardByCustomerOrderId(orderId);

      expect(container.read(heldOrdersProvider), isEmpty);
    },
  );
}
