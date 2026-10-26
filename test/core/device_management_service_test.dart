import 'package:bos_application/core/device/device_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> deviceResponse({bool? requiresReauthentication}) => {
    'id': 'device-id',
    'device_uuid': '123e4567-e89b-42d3-a456-426614174000',
    'device_name': 'Test device',
    'platform': 'android',
    'client_type': 'mobile',
    'app_version': '1.0.0',
    'status': 'revoked',
    if (requiresReauthentication != null)
      'reauthentication_required': requiresReauthentication,
    'first_seen_at': '2026-01-01T00:00:00Z',
    'last_seen_at': '2026-01-02T00:00:00Z',
    'last_sync_at': null,
  };

  test('parses revoked registration metadata and reauthentication state', () {
    final device = DeviceRecord.fromMap(
      deviceResponse(requiresReauthentication: true),
    );

    expect(device.status, 'revoked');
    expect(device.platform, 'android');
    expect(device.clientType, 'mobile');
    expect(device.requiresFreshLogin, isTrue);
  });

  test('defaults absent reauthentication state to false', () {
    final device = DeviceRecord.fromMap(deviceResponse());

    expect(device.requiresFreshLogin, isFalse);
  });
}
