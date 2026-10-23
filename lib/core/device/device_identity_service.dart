import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

abstract interface class DeviceIdStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureDeviceIdStore implements DeviceIdStore {
  SecureDeviceIdStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class DeviceMetadata {
  const DeviceMetadata({
    required this.deviceName,
    required this.platform,
    required this.clientType,
    required this.appVersion,
    required this.model,
  });

  final String deviceName;
  final String platform;
  final String clientType;
  final String appVersion;

  /// Hardware model, e.g. "samsung SM-S918B" or "MacBookPro18,3".
  /// Empty if it could not be determined.
  final String model;

  static Future<DeviceMetadata> load() async {
    final platform = _platformName();
    final packageInfo = await PackageInfo.fromPlatform();
    final model = await _loadModel();

    return DeviceMetadata(
      deviceName: model.isNotEmpty
          ? (model.length > 80 ? model.substring(0, 80) : model)
          : _defaultDeviceName(platform), // user-editable // user-editable
      platform: platform,
      clientType: _clientType(platform),
      appVersion: packageInfo.version,
      model: model,
    );
  }

  static Future<String> _loadModel() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        final w = await plugin.webBrowserInfo;
        return 'Web browser (${w.browserName.name})';
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final a = await plugin.androidInfo;
          final maker = a.manufacturer.trim();
          final model = a.model.trim();
          final pretty =
              maker.isEmpty ||
                  model.toLowerCase().startsWith(maker.toLowerCase())
              ? model
              : '${maker[0].toUpperCase()}${maker.substring(1)} $model';
          return pretty.trim();
        case TargetPlatform.iOS:
          final i = await plugin.iosInfo;
          return '${i.model} (${i.utsname.machine})';
        case TargetPlatform.windows:
          final w = await plugin.windowsInfo;
          return w.computerName;
        case TargetPlatform.macOS:
          final m = await plugin.macOsInfo;
          return m.model;
        case TargetPlatform.linux:
          final l = await plugin.linuxInfo;
          return l.prettyName;
        case TargetPlatform.fuchsia:
          return '';
      }
    } catch (_) {
      // Never block registration because the model lookup failed.
      return '';
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static String _clientType(String platform) => switch (platform) {
    'android' || 'ios' => 'mobile',
    'web' => 'web',
    'windows' || 'macos' || 'linux' => 'desktop',
    _ => 'desktop',
  };

  static String _defaultDeviceName(String platform) => switch (platform) {
    'android' => 'Android phone',
    'ios' => 'iPhone or iPad',
    'windows' => 'Windows PC',
    'macos' => 'Mac',
    'linux' => 'Linux PC',
    'web' => 'BOS web client',
    _ => 'BOS device',
  };
}

/// Last known server-side authorization for this installation.
///
/// This is deliberately cached locally so BOS can start while completely
/// offline. The cache is NOT a replacement for server authorization:
/// whenever connectivity returns, BOS reconciles this state with Supabase.
class CachedDeviceAuthorization {
  const CachedDeviceAuthorization({
    required this.userId,
    required this.authorized,
    required this.status,
    required this.requiresFreshLogin,
    required this.verifiedAt,
  });

  final String userId;
  final bool authorized;
  final String status;
  final bool requiresFreshLogin;
  final DateTime verifiedAt;

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'authorized': authorized,
      'status': status,
      'requiresFreshLogin': requiresFreshLogin,
      'verifiedAt': verifiedAt.toUtc().toIso8601String(),
    };
  }

  factory CachedDeviceAuthorization.fromJson(Map<String, dynamic> json) {
    return CachedDeviceAuthorization(
      userId: json['userId'] as String,
      authorized: json['authorized'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      requiresFreshLogin: json['requiresFreshLogin'] as bool? ?? false,
      verifiedAt: DateTime.parse(json['verifiedAt'] as String),
    );
  }
}

class DeviceIdentityService {
  DeviceIdentityService({DeviceIdStore? store, Uuid uuid = const Uuid()})
    : _store = store ?? SecureDeviceIdStore(),
      _uuid = uuid;

  final DeviceIdStore _store;
  final Uuid _uuid;

  static const _deviceIdKey = 'bos.installation.deviceUuid';

  static const _authorizationKeyPrefix = 'bos.installation.authorization.v1.';

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[1-8][0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-'
    r'[0-9a-fA-F]{12}$',
  );

  Future<String> getOrCreateDeviceUuid() async {
    final stored = await _store.read(_deviceIdKey);

    if (stored != null && _uuidPattern.hasMatch(stored)) {
      return stored.toLowerCase();
    }

    final generated = _uuid.v4();

    await _store.write(_deviceIdKey, generated);

    return generated;
  }

  Future<DeviceMetadata> getMetadata() => DeviceMetadata.load();

  String _authorizationKey(String userId) {
    return '$_authorizationKeyPrefix$userId';
  }

  Future<CachedDeviceAuthorization?> readCachedAuthorization(
    String userId,
  ) async {
    final key = _authorizationKey(userId);
    final raw = await _store.read(key);

    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        await _store.delete(key);
        return null;
      }

      return CachedDeviceAuthorization.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      // Corrupt cache must never prevent the user from recovering.
      await _store.delete(key);
      return null;
    }
  }

  Future<void> writeCachedAuthorization({
    required String userId,
    required bool authorized,
    required String status,
    required bool requiresFreshLogin,
  }) async {
    final entry = CachedDeviceAuthorization(
      userId: userId,
      authorized: authorized,
      status: status,
      requiresFreshLogin: requiresFreshLogin,
      verifiedAt: DateTime.now().toUtc(),
    );

    await _store.write(_authorizationKey(userId), jsonEncode(entry.toJson()));
  }

  Future<void> clearCachedAuthorization(String userId) async {
    await _store.delete(_authorizationKey(userId));
  }
}
