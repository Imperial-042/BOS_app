import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_identity_service.dart';

class DeviceAuthorizationException implements Exception {
  const DeviceAuthorizationException(
    this.message, {
    this.status,
    this.requiresFreshLogin = false,
  });

  final String message;
  final String? status;
  final bool requiresFreshLogin;

  @override
  String toString() => message;
}

class DeviceManagementException implements Exception {
  const DeviceManagementException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.deviceUuid,
    required this.deviceName,
    required this.deviceModel,
    required this.platform,
    required this.clientType,
    required this.status,
    this.requiresFreshLogin = false,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.activeSessionCount,
    this.appVersion,
    this.lastSyncAt,
  });

  final String id;
  final String deviceUuid;
  final String deviceName;
  final String? deviceModel;
  final String platform;
  final String clientType;
  final String status;
  final bool requiresFreshLogin;
  final String? appVersion;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final DateTime? lastSyncAt;
  final int activeSessionCount;

  factory DeviceRecord.fromMap(
    Map<String, dynamic> map, {
    int activeSessionCount = 0,
  }) {
    return DeviceRecord(
      id: map['id'] as String,
      deviceUuid: map['device_uuid'] as String,
      deviceName: map['device_name'] as String,
      deviceModel: map['device_model'] as String?,
      platform: map['platform'] as String,
      clientType: map['client_type'] as String,
      status: map['status'] as String,
      requiresFreshLogin: map['reauthentication_required'] as bool? ?? false,
      appVersion: map['app_version'] as String?,
      firstSeenAt: DateTime.parse(map['first_seen_at'] as String),
      lastSeenAt: DateTime.parse(map['last_seen_at'] as String),
      lastSyncAt: _parseOptionalDate(map['last_sync_at']),
      activeSessionCount: activeSessionCount,
    );
  }
}

DateTime? _parseOptionalDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

class DeviceManagementService {
  DeviceManagementService({
    required SupabaseClient client,
    required DeviceIdentityService identity,
  }) : _client = client,
       _identity = identity;

  final SupabaseClient _client;
  final DeviceIdentityService _identity;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const DeviceAuthorizationException(
        'Sign in to manage BOS devices.',
      );
    }
    return id;
  }

  /// Called when the server revokes this session. Keeps local data, but the
  /// cached decision now says a fresh login is needed.
  Future<void> markCurrentSessionRevoked() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return;
    await _identity.writeCachedAuthorization(
      userId: id,
      authorized: false,
      status: 'revoked',
      requiresFreshLogin: true,
    );
  }

  Future<String> get currentDeviceUuid => _identity.getOrCreateDeviceUuid();

  /// Offline-readable authorization decision for this installation.
  ///
  /// Returns null when no decision has been cached yet (e.g. legacy installs
  /// that pre-date the cache). Callers treat null as "allow local business
  /// access; reconcile online when possible".
  Future<CachedDeviceAuthorization?> getCachedAuthorization({
    required String userId,
  }) {
    return _identity.readCachedAuthorization(userId);
  }

  Future<DeviceRecord> registerCurrentDevice() async {
    final deviceUuid = await _identity.getOrCreateDeviceUuid();
    final metadata = await _identity.getMetadata();
    try {
      final response = await _client.rpc(
        'register_current_device',
        params: {
          'p_device_uuid': deviceUuid,
          'p_device_name': metadata.deviceName,
          'p_platform': metadata.platform,
          'p_client_type': metadata.clientType,
          'p_app_version': metadata.appVersion,
          'p_device_model': metadata.model.isEmpty ? null : metadata.model,
        },
      );
      final record = DeviceRecord.fromMap(_asMap(response));
      await _identity.writeCachedAuthorization(
        userId: _userId,
        authorized: record.status == 'active',
        status: record.status,
        requiresFreshLogin: record.requiresFreshLogin,
      );
      return record;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') {
        throw const DeviceManagementException(
          'The BOS device registry is not installed or is out of date on the '
          'server. Apply the Supabase migrations '
          '20261003151947_user_device_registry and '
          '20261013000000_user_device_model to this project, then try again.',
          code: 'PGRST202',
        );
      }
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Future<List<DeviceRecord>> listDevices() async {
    final userId = _userId;
    try {
      final rows = await _client
          .from('user_devices')
          .select(
            'id, device_uuid, device_name, device_model, platform, client_type, '
            'app_version, status, first_seen_at, last_seen_at, last_sync_at',
          )
          .eq('user_id', userId)
          .order('last_seen_at', ascending: false);
      final sessions = await _client
          .from('device_sessions')
          .select('user_device_id, status')
          .eq('user_id', userId)
          .eq('status', 'active');

      final activeByDevice = <String, int>{};
      for (final row in sessions) {
        final deviceId = row['user_device_id'] as String;
        activeByDevice.update(
          deviceId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      return [
        for (final row in rows)
          DeviceRecord.fromMap(
            Map<String, dynamic>.from(row),
            activeSessionCount: activeByDevice[row['id']] ?? 0,
          ),
      ];
    } on PostgrestException catch (error) {
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Future<void> renameDevice({
    required String deviceUuid,
    required String name,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 80) {
      throw const DeviceManagementException(
        'Device name must be between 1 and 80 characters.',
      );
    }
    try {
      await _client.rpc(
        'rename_current_user_device',
        params: {'p_device_uuid': deviceUuid, 'p_device_name': normalized},
      );
    } on PostgrestException catch (error) {
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Future<void> revokeDevice(String deviceUuid) async {
    try {
      await _client.rpc(
        'revoke_current_user_device',
        params: {'p_device_uuid': deviceUuid},
      );
    } on PostgrestException catch (error) {
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  /// Ends the sessions on ONE other device. The device is not blocked and
  /// can sign in again straight away.
  Future<void> signOutDevice(String deviceUuid) async {
    try {
      await _client.rpc(
        'sign_out_user_device',
        params: {'p_device_uuid': deviceUuid},
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') {
        throw const DeviceManagementException(
          'Signing out a single device needs a database update. Apply the '
          'sign_out_user_device migration, then try again.',
          code: 'PGRST202',
        );
      }
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Future<DeviceRecord> reactivateCurrentDevice() async {
    final deviceUuid = await _identity.getOrCreateDeviceUuid();
    try {
      final response = await _client.rpc(
        'reactivate_current_user_device',
        params: {'p_device_uuid': deviceUuid},
      );
      final record = DeviceRecord.fromMap(_asMap(response));
      await _identity.writeCachedAuthorization(
        userId: _userId,
        authorized: record.status == 'active',
        status: record.status,
        requiresFreshLogin: record.requiresFreshLogin,
      );
      return record;
    } on PostgrestException catch (error) {
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Future<void> signOutOtherSessions() async {
    try {
      await _client.rpc('revoke_other_device_sessions');
      await _client.auth.signOut(scope: SignOutScope.others);
    } on PostgrestException catch (error) {
      throw DeviceManagementException(error.message, code: error.code);
    } on AuthException catch (error) {
      throw DeviceManagementException(error.message, code: error.statusCode);
    }
  }

  Future<void> endCurrentSession() async {
    try {
      await _client.rpc('end_current_device_session');
    } on PostgrestException catch (error) {
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Future<void> assertCurrentDeviceAuthorized() async {
    try {
      final authorized = await _client.rpc('is_current_device_session_active');
      if (authorized != true) {
        throw const DeviceAuthorizationException(
          'This device is no longer authorized. Pending local changes are preserved.',
        );
      }
    } on PostgrestException catch (error) {
      if (error.code == '42501' || error.code == 'PGRST301') {
        throw const DeviceAuthorizationException(
          'This device is no longer authorized. Pending local changes are preserved.',
        );
      }
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Future<void> recordSuccessfulSync() async {
    await assertCurrentDeviceAuthorized();
    try {
      await _client.rpc('touch_current_device_sync');
    } on PostgrestException catch (error) {
      if (error.code == '42501' || error.code == 'PGRST301') {
        throw const DeviceAuthorizationException(
          'This device is no longer authorized. Pending local changes are preserved.',
        );
      }
      throw DeviceManagementException(error.message, code: error.code);
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const DeviceManagementException(
      'The device service returned an invalid response.',
    );
  }

  String get authenticatedUserId => _userId;
}
