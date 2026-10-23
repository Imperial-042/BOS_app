// lib/core/supabase/supabase_service.dart
//
// Centralized Supabase access. Widgets and services go through the
// providers here; nobody calls Supabase.instance directly from UI code.
//
// When Supabase isn't configured (no --dart-define), [isAvailable] is false
// and BOS runs entirely on the local Drift database — the app must never
// crash just because the cloud backend is absent (offline-first).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class SupabaseService {
  SupabaseService._();

  static bool _initialized = false;

  /// Initialize the client once at app startup. Safe to call when not
  /// configured (no-op) or when the network is unavailable — the client
  /// object is created locally and only fails on actual requests.
  static Future<void> initialize() async {
    if (_initialized || !SupabaseConfig.isConfigured) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    _initialized = true;
  }

  static bool get isAvailable => _initialized && SupabaseConfig.isConfigured;

  static SupabaseClient get client => Supabase.instance.client;
}

final supabaseAvailableProvider = Provider<bool>(
  (ref) => SupabaseService.isAvailable,
);

/// The shared client. Only read this when [supabaseAvailableProvider] is
/// true; otherwise there is no backend to talk to.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!SupabaseService.isAvailable) {
    throw StateError(
      'Supabase is not configured. Check supabaseAvailableProvider first.',
    );
  }
  return SupabaseService.client;
});
