import 'package:bos_application/features/customer/presentation/customer_common.dart';
import 'package:bos_application/core/location/location_repository.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Order statuses that count as "in progress" (badge + polling).
const customerLiveOrderStatuses = {'pending', 'accepted', 'preparing', 'ready'};

final customerLocationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(ref.watch(databaseProvider));
});

final customerAddressesProvider =
    FutureProvider.family<List<SavedCustomerAddress>, String>((ref, userId) {
      return ref
          .watch(customerLocationRepositoryProvider)
          .loadCustomerAddresses(userId);
    });

final customerHomeProfileProvider =
    FutureProvider.family<CustomerLocationProfile?, String>((ref, userId) {
      return ref
          .watch(customerCommerceServiceProvider)
          .loadCustomerProfile(userId);
    });

final customerHomeStoresProvider =
    FutureProvider.family<List<CustomerStorefront>, String>((ref, city) {
      return ref
          .watch(customerCommerceServiceProvider)
          .discoverStores(city: city);
    });

final customerHomeFollowsProvider =
    StreamProvider.family<List<CustomerStoreFollow>, String>((ref, userId) {
      return ref.watch(customerCommerceServiceProvider).watchFollows(userId);
    });

final customerHomeOrdersProvider =
    FutureProvider.family<List<CustomerOrder>, String>((ref, userId) {
      return ref
          .watch(customerCommerceServiceProvider)
          .loadOrders(userId: userId);
    });

final customerHomePointsProvider =
    FutureProvider.family<int, ({String userId, String businessId})>((
      ref,
      args,
    ) {
      return ref
          .watch(customerCommerceServiceProvider)
          .loyaltyBalance(userId: args.userId, businessId: args.businessId);
    });

/// Each branch has its own cart.
String customerCartKey(String businessId, String branchId) =>
    '$businessId:$branchId';

final customerHomeBranchStoresProvider =
    FutureProvider.family<List<StoreBranchListing>, String>((ref, city) {
      return ref
          .watch(customerCommerceServiceProvider)
          .discoverBranchStores(city: city);
    });
