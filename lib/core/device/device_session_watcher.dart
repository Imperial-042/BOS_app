import 'dart:async';
import 'dart:convert';

import 'package:bos_application/core/auth/session_end.dart';
import 'package:bos_application/core/device/device_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Watches this device's own session row and calls [onRevoked] as soon as the
/// server revokes or ends it. Falls back to a check on app resume in case the
/// realtime connection was asleep.
class DeviceSessionWatcher with WidgetsBindingObserver {
  DeviceSessionWatcher({
    required SupabaseClient client,
    required this.onRevoked,
  }) : _client = client {
    WidgetsBinding.instance.addObserver(this);
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) start();
      if (state.event == AuthChangeEvent.signedOut) _unsubscribe();
    });
  }

  final SupabaseClient _client;
  final Future<void> Function() onRevoked;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  bool _fired = false;
  Timer? _poll;

  void start() {
    _unsubscribe();
    final sessionId = _sessionIdOf(_client.auth.currentSession);
    if (sessionId == null) return;
    _fired = false;

    _channel = _client
        .channel('device-session-$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'device_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            final status = payload.newRecord['status'];
            if (status == 'revoked' || status == 'ended') _fire();
          },
        )
        .subscribe();
    // Realtime can be asleep or unpublished. A light check guarantees a
    // remote sign-out is noticed within seconds either way.
    _poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(check()),
    );
  }

  /// Fallback check, e.g. after the app returns to the foreground.
  Future<void> check() async {
    if (_client.auth.currentSession == null || _fired) return;
    try {
      final active = await _client.rpc('is_current_device_session_active');
      if (active == false) _fire();
    } catch (_) {
      // Offline or transient error: stay quiet, try again next time.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  void _fire() {
    if (_fired) return;
    _fired = true;
    onRevoked();
  }

  void _unsubscribe() {
    _poll?.cancel();
    _poll = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) _client.removeChannel(channel);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _unsubscribe();
  }

  static String? _sessionIdOf(Session? session) {
    final token = session?.accessToken;
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      return payload['session_id'] as String?;
    } catch (_) {
      return null;
    }
  }
}

final deviceSessionWatcherProvider = Provider<DeviceSessionWatcher>((ref) {
  final watcher = DeviceSessionWatcher(
    client: Supabase.instance.client,
    onRevoked: () async {
      await ref
          .read(deviceManagementServiceProvider)
          .markCurrentSessionRevoked();
      await endSessionLocally(
        ref,
        notice:
            'You were signed out because this device\'s access was removed '
            'from another device. Sign in again to continue.',
      );
    },
  );
  ref.onDispose(watcher.dispose);
  watcher.start();
  return watcher;
});
