import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;

import '../navigation/app_navigator.dart';
import '../supabase/supabase_auth_service.dart';
import '../supabase/supabase_service.dart';
import '../sync/sync_tracker.dart';
import 'authorization_providers.dart';
import 'session_store.dart';

/// Shown on the login screen after the server ended this session.
final sessionEndedNoticeProvider = StateProvider<String?>((ref) => null);

bool _ending = false;

/// Signs this device out locally and brings the person to the login screen.
/// Safe to call more than once.
Future<void> endSessionLocally(Ref ref, {String? notice}) async {
  if (_ending) return;
  _ending = true;
  try {
    if (notice != null) {
      ref.read(sessionEndedNoticeProvider.notifier).state = notice;
    }

    // 1. Close every pushed page, sheet and dialog first.
    resetNavigationToRoot();

    // 2. End the cloud + local session.
    if (ref.read(supabaseAvailableProvider)) {
      try {
        await ref
            .read(cloudAuthServiceProvider)
            .signOutWithScope(SignOutScope.local)
            .timeout(const Duration(seconds: 6));
      } on Object {
        // The client drops its local session first; a failed server call
        // (offline, already revoked) must not block signing out here.
      }
    }
    await SessionStore.clear();
    SyncTracker.currentUserId = null;
    ref.read(authenticatedUserIdProvider.notifier).state = null;

    // 3. Tell the person why, once the login screen is on screen.
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(showSignedOutDialog(notice));
      });
    }
  } finally {
    _ending = false;
  }
}
