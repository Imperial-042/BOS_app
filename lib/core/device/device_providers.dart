import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/authorization_providers.dart';
import '../supabase/supabase_service.dart';
import 'device_identity_service.dart';
import 'device_management_service.dart';

final deviceIdentityServiceProvider = Provider<DeviceIdentityService>(
  (ref) => DeviceIdentityService(),
);

final currentDeviceUuidProvider = FutureProvider<String>(
  (ref) => ref.watch(deviceIdentityServiceProvider).getOrCreateDeviceUuid(),
);

final deviceManagementServiceProvider = Provider<DeviceManagementService>((
  ref,
) {
  return DeviceManagementService(
    client: ref.watch(supabaseClientProvider),
    identity: ref.watch(deviceIdentityServiceProvider),
  );
});

final currentDeviceRegistrationProvider = FutureProvider<DeviceRecord?>((
  ref,
) async {
  final userId = ref.watch(authenticatedUserIdProvider);
  if (userId == null || !ref.watch(supabaseAvailableProvider)) return null;

  final service = ref.watch(deviceManagementServiceProvider);
  if (service.authenticatedUserId != userId) {
    throw const DeviceAuthorizationException(
      'The active BOS account does not match the Supabase session.',
    );
  }
  final registration = await service.registerCurrentDevice();
  return registration;
});

final myDevicesProvider = FutureProvider<List<DeviceRecord>>((ref) {
  final userId = ref.watch(authenticatedUserIdProvider);
  if (userId == null || !ref.watch(supabaseAvailableProvider)) {
    return Future.value(const <DeviceRecord>[]);
  }
  return ref.watch(deviceManagementServiceProvider).listDevices();
});
