// lib/app/startup/startup_gate.dart
//
// Widget half of startup: runs StartupService and shows the right screen for
// the outcome (loading, error, device blocked, join-or-create, onboarding,
// employee profile, or the app itself).

import 'dart:async';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/transactions/presentation/screens/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/device/device_management_service.dart';
import 'package:bos_application/app/startup/startup_service.dart';
import 'package:bos_application/app/startup/startup_screens.dart';
import 'package:bos_application/app/startup/join_or_create_screen.dart';
import 'package:bos_application/app/startup/device_authorization_screen.dart';
import 'package:bos_application/app/startup/employee_profile_gate.dart';
import 'package:bos_application/app/access_gate.dart';

/// Lets screens outside this flow restart it (for example after the user's
/// last business is deleted).
VoidCallback? restartStartupFlow;

class BosStartupGate extends ConsumerStatefulWidget {
  const BosStartupGate({super.key});

  @override
  ConsumerState<BosStartupGate> createState() => _BosStartupGateState();
}

class _BosStartupGateState extends ConsumerState<BosStartupGate> {
  late Future<BusinessesData> _initFuture;
  bool _allowCreateFirstBusiness = false;

  @override
  void initState() {
    super.initState();
    restartStartupFlow = _reloadStartup;
    _initFuture = _load();
  }

  @override
  void dispose() {
    if (restartStartupFlow == _reloadStartup) restartStartupFlow = null;
    super.dispose();
  }

  Future<BusinessesData> _load() {
    return ref
        .read(startupServiceProvider)
        .ensureBusinessExists(
          allowCreateFirstBusiness: _allowCreateFirstBusiness,
          hooks: StartupHooks(isActive: () => mounted, restart: _reloadStartup),
        );
  }

  void _reloadStartup() {
    if (!mounted) return;

    setState(() {
      _initFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BusinessesData>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const BosStartupLoading();
        }

        if (snapshot.hasError) {
          if (snapshot.error is DeviceAuthorizationException) {
            return BosDeviceAuthorizationScreen(
              error: snapshot.error as DeviceAuthorizationException,
              onRetry: _reloadStartup,
            );
          }

          if (snapshot.error is NoBusinessYet) {
            return BosJoinOrCreateScreen(
              onCreate: () {
                _allowCreateFirstBusiness = true;
                _reloadStartup();
              },
              onJoined: _reloadStartup,
            );
          }

          return BosStartupError(
            error: snapshot.error,
            onRetry: _reloadStartup,
          );
        }

        final business = snapshot.data!;

        final isOwner =
            business.ownerUserId == ref.read(authenticatedUserIdProvider);

        if (isOwner &&
            (business.ownerName == null || business.businessCategory == null)) {
          return OnboardingScreen(onFinished: _reloadStartup);
        }

        if (!isOwner && ref.read(supabaseAvailableProvider)) {
          return BosEmployeeProfileGate(
            key: ValueKey('emp-profile-${business.id}'),
            business: business,
          );
        }

        return const BosAccessGate();
      },
    );
  }
}
