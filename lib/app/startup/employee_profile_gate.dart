// lib/app/startup/employee_profile_gate.dart
//
// Shows the employee profile form once (per business) before the app opens.

import 'dart:async';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/employee_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/app/access_gate.dart';
import 'package:bos_application/app/startup/startup_screens.dart';

/// Shows the employee profile form once (per business) before the app opens.
class BosEmployeeProfileGate extends ConsumerStatefulWidget {
  const BosEmployeeProfileGate({super.key, required this.business});

  final BusinessesData business;

  @override
  ConsumerState<BosEmployeeProfileGate> createState() =>
      _EmployeeProfileGateState();
}

class _EmployeeProfileGateState extends ConsumerState<BosEmployeeProfileGate> {
  late final Future<bool> _needsProfile;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _needsProfile = ref
        .read(employeeProfileServiceProvider)
        .needsProfile(widget.business.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const BosAccessGate();

    return FutureBuilder<bool>(
      future: _needsProfile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const BosStartupLoading();
        }
        if (snapshot.data == true) {
          return EmployeeOnboardingScreen(
            businessId: widget.business.id,
            businessName: widget.business.name,
            onFinished: () => setState(() => _done = true),
          );
        }
        return const BosAccessGate();
      },
    );
  }
}
