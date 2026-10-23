// import 'package:bos_application/core/device/device_identity_service.dart';
// import 'package:test/test.dart';

// class _MemoryDeviceIdStore implements DeviceIdStore {
//   String? value;

//   @override
//   Future<String?> read(String key) async => value;

//   @override
//   Future<void> write(String key, String value) async {
//     this.value = value;
//   }

//   @override
//   Future<void> delete(String key) {
//     // TODO: implement delete
//     throw UnimplementedError();
//   }
// }

// void main() {
//   group('DeviceIdentityService', () {
//     test('persists and reuses an installation UUID', () async {
//       final store = _MemoryDeviceIdStore();
//       final firstInstall = DeviceIdentityService(store: store);
//       final firstId = await firstInstall.getOrCreateDeviceUuid();

//       final afterRestart = DeviceIdentityService(store: store);

//       expect(firstId, matches(RegExp(r'^[0-9a-f-]{36}$')));
//       expect(await afterRestart.getOrCreateDeviceUuid(), firstId);
//     });

//     test('replaces malformed stored identifiers with a UUID', () async {
//       final store = _MemoryDeviceIdStore()..value = 'physical-device-id';
//       final service = DeviceIdentityService(store: store);

//       final id = await service.getOrCreateDeviceUuid();

//       expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
//       expect(id, isNot('physical-device-id'));
//       expect(store.value, id);
//     });
//   });
// }
