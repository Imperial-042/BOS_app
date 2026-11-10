// lib/app/startup/device_authorization_screen.dart

import 'dart:async';
import 'package:bos_application/features/transactions/presentation/screens/startup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/session_store.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:bos_application/core/device/device_management_service.dart';
import 'package:bos_application/core/device/device_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;

class BosDeviceAuthorizationScreen extends ConsumerStatefulWidget {
  const BosDeviceAuthorizationScreen({super.key, 
    required this.error,
    required this.onRetry,
  });

  final DeviceAuthorizationException error;
  final VoidCallback onRetry;

  @override
  ConsumerState<BosDeviceAuthorizationScreen> createState() =>
      _DeviceAuthorizationScreenState();
}

class _DeviceAuthorizationScreenState
    extends ConsumerState<BosDeviceAuthorizationScreen> {
  bool _working = false;

  Future<void> _reactivate() async {
    setState(() => _working = true);
    try {
      await ref.read(deviceManagementServiceProvider).reactivateCurrentDevice();
      if (!mounted) return;
      ref.invalidate(currentDeviceRegistrationProvider);
      widget.onRetry();
    } on DeviceManagementException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not reactivate this device (${error.runtimeType}).',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _working = true);
    try {
      await ref
          .read(cloudAuthServiceProvider)
          .signOutWithScope(SignOutScope.local);
      await SessionStore.clear();
      SyncTracker.currentUserId = null;
      ref.read(authenticatedUserIdProvider.notifier).state = null;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sign out: ${error.runtimeType}.')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DeviceAuthorizationView(
      message: widget.error.message,
      canReactivate:
          widget.error.status == 'revoked' && !widget.error.requiresFreshLogin,
      working: _working,
      onReactivate: _reactivate,
      onSignOut: _signOut,
    );
  }
}
