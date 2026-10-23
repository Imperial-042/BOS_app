// lib/core/auth/biometric_auth_service.dart
//
// Thin wrapper around `local_auth` so the rest of the app doesn't touch the
// plugin directly. `biometricOnly: false` lets the OS fall back to the
// device's PIN/pattern/passcode when no fingerprint/face is enrolled.

import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  final _auth = LocalAuthentication();

  /// Whether this device can do biometric/passcode unlock at all.
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
