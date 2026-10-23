// lib/core/auth/session_store.dart
//
// Persists which user is signed in across app restarts, so the login
// screen isn't shown every time the app opens. Stores only a user id —
// never credentials.

import 'package:shared_preferences/shared_preferences.dart';

abstract final class SessionStore {
  static const _kUserIdKey = 'auth.session.userId';
  static const _kBiometricEnabledKey = 'auth.session.biometricEnabled';

  static Future<String?> readUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserIdKey);
  }

  static Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserIdKey, userId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserIdKey);
  }

  /// Whether the signed-in user chose to unlock the app with fingerprint /
  /// face / device passcode instead of retyping their password.
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricEnabledKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabledKey, enabled);
  }
}
