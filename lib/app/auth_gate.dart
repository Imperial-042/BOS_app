// lib/app/auth_gate.dart
//
// Shows the login screen until someone is signed in; restores persisted sessions.

import 'dart:async';
import 'package:bos_application/core/navigation/app_navigator.dart';
import 'package:bos_application/features/customer/presentation/customer_mode_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/auth_providers.dart';
import 'package:bos_application/features/auth/presentation/screens/biometric_unlock_screen.dart';
import 'package:bos_application/features/auth/presentation/screens/login_screen.dart';
import 'package:bos_application/core/auth/session_store.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthState, SignOutScope;
import 'package:bos_application/app/startup/startup_gate.dart';
import 'package:bos_application/app/startup/startup_screens.dart';

/// Restores a persisted session on first launch. If the user opted into
/// biometric/passcode unlock, [BiometricUnlockScreen] must confirm it's
/// them before the session resumes; otherwise it resumes right away, same
/// as before biometrics existed. Signing in and out both flow through
/// [authenticatedUserIdProvider], so most of this widget just watches it.
class BosAuthGate extends ConsumerStatefulWidget {
  const BosAuthGate({super.key});

  @override
  ConsumerState<BosAuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<BosAuthGate> {
  bool _forcePasswordLogin = false;
  StreamSubscription<AuthState>? _cloudAuthSub;

  /// Whether the device-level biometric/passcode lock is enabled. Loaded
  /// once per cold start; drives whether a restored session must confirm
  /// identity first. Only consulted when Supabase is configured.
  bool _biometricChecked = false;
  bool _biometricLockEnabled = false;

  @override
  void initState() {
    super.initState();
    if (SupabaseService.isAvailable) {
      // Expired sessions and sign-outs from another device arrive here:
      // drop the local session so no stale account data stays on screen.
      _cloudAuthSub = ref
          .read(cloudAuthServiceProvider)
          .onAuthStateChange
          .listen(_onCloudAuthChange);
    }
  }

  @override
  void dispose() {
    _cloudAuthSub?.cancel();
    super.dispose();
  }

  void _onCloudAuthChange(AuthState authState) {
    // Covers local sign-out, expired refresh tokens, and sessions revoked
    // from another device (gotrue emits signedOut for all of them).
    if (authState.event == AuthChangeEvent.signedOut) {
      SessionStore.clear();
      SyncTracker.currentUserId = null;
      ref.read(authenticatedUserIdProvider.notifier).state = null;
      resetNavigationToRoot();
      return;
    }
    final cloudUserId = authState.session?.user.id;
    if (cloudUserId != null) SyncTracker.currentUserId = cloudUserId;
  }

  void _resume(String userId) {
    SyncTracker.currentUserId = userId;
    ref.read(authenticatedUserIdProvider.notifier).state = userId;
  }

  /// Reads the device-level biometric/passcode lock flag once, then either
  /// gates the cloud session behind it or resumes right away.
  Future<void> _checkBiometricLock(String cloudUid) async {
    final enabled = await SessionStore.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricChecked = true;
      _biometricLockEnabled = enabled;
    });
  }

  /// "Use password instead" from the biometric gate for a cloud session:
  /// drop the persisted Supabase session and show the login form.
  Future<void> _forgetCloudSession() async {
    try {
      await ref
          .read(cloudAuthServiceProvider)
          .signOutWithScope(SignOutScope.local);
    } on Object catch (error) {
      // Best-effort; the local session flag is cleared regardless.
      debugPrint('[auth] local sign-out failed (${error.runtimeType})');
    }
    await SessionStore.clear();
    if (!mounted) return;
    setState(() {
      _forcePasswordLogin = true;
      _biometricChecked = false;
      _biometricLockEnabled = false;
    });
  }

  /// Resuming a persisted Supabase session: create the local identity shell
  /// (idempotent) BEFORE flipping authenticatedUserIdProvider, so profile /
  /// membership lookups keyed on the Users table never observe a missing
  /// row for the cloud UUID.
  Future<void> _resumeCloud(String cloudUid) async {
    final cloudAuth = ref.read(cloudAuthServiceProvider);
    var displayName = cloudAuth.currentDisplayName ?? '';
    try {
      final profile = await ref
          .read(cloudBusinessServiceProvider)
          .getMyProfile();
      if (profile != null && profile.displayName.trim().isNotEmpty) {
        displayName = profile.displayName;
      }
    } catch (_) {
      // Profile lookup is best-effort; auth metadata is enough to resume.
    }
    await ref
        .read(authServiceProvider)
        .ensureLocalUser(
          id: cloudUid,
          email: cloudAuth.currentEmail ?? '',
          displayName: displayName,
        );
    if (mounted) _resume(cloudUid);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authenticatedUserIdProvider);
    if (userId != null) {
      return CustomerModeGate(businessBuilder: (_) => const BosStartupGate());
    }

    if (_forcePasswordLogin) return const LoginScreen();

    // When the cloud backend is configured, its session is the source of
    // truth: restore it (Supabase persists the session on-device) before
    // falling back to the local pending-session/biometric flow.
    if (ref.watch(supabaseAvailableProvider)) {
      final cloudAuth = ref.watch(cloudAuthServiceProvider);
      final cloudUid = cloudAuth.currentUserId;
      if (cloudUid != null) {
        // Honor the biometric/passcode lock for cloud sessions too — the
        // flag is stored on-device, independent of the auth backend.
        if (_biometricLockEnabled) {
          return BiometricUnlockScreen(
            session: PendingSession(
              userId: cloudUid,
              email: cloudAuth.currentEmail ?? '',
              displayName: cloudAuth.currentDisplayName ?? '',
              biometricEnabled: true,
            ),
            onUnlocked: () => unawaited(_resumeCloud(cloudUid)),
            onUsePassword: _forgetCloudSession,
          );
        }
        if (!_biometricChecked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _checkBiometricLock(cloudUid);
          });
          return const BosStartupLoading();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_resumeCloud(cloudUid));
        });
        return const BosStartupLoading();
      }
      return const LoginScreen();
    }

    final pending = ref.watch(pendingSessionProvider);
    return pending.when(
      loading: () => const BosStartupLoading(),
      error: (_, _) => const LoginScreen(),
      data: (session) {
        if (session == null) return const LoginScreen();

        if (!session.biometricEnabled) {
          // No lock configured: resume the session right away, as before.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resume(session.userId);
          });
          return const BosStartupLoading();
        }

        return BiometricUnlockScreen(
          session: session,
          onUnlocked: () => _resume(session.userId),
          onUsePassword: () => setState(() => _forcePasswordLogin = true),
        );
      },
    );
  }
}
