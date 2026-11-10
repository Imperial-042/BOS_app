// lib/app/sign_out.dart
//
// Sign-out flows shared by the shell, the rail and the startup screens.

import 'dart:async';
import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/session_store.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;

Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  // Capture everything we need from `ref` before the awaits below: signing
  // out unmounts this widget (the whole shell swaps to the login screen),
  // so `ref` itself can't be touched again afterward.
  final audit = ref.read(auditLogServiceProvider);
  final actorId = ref.read(authenticatedUserIdProvider);
  final sessionNotifier = ref.read(authenticatedUserIdProvider.notifier);
  final cloudAuth = ref.read(supabaseAvailableProvider)
      ? ref.read(cloudAuthServiceProvider)
      : null;

  // Close the drawer only if one is open. The wide-layout rail has no
  // drawer, and popping there removes the app's only route (black screen).
  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
    Navigator.of(context).pop();
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: const Text('Sign out?'),
      content: const Text(
        "You'll need your email and password to sign back in.",
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await audit.tryRecord(
    AuditEvent(
      module: AuditModule.security,
      actionType: AuditActionType.security,
      action: 'auth.sign_out',
      entityType: 'users',
      entityId: actorId,
    ),
  );

  if (cloudAuth != null) {
    try {
      await cloudAuth.signOutWithScope(SignOutScope.local);
    } on Object catch (error) {
      // Sign-out must still complete locally even if the network is down.
      debugPrint('[auth] local sign-out failed (${error.runtimeType})');
    }
  }

  await SessionStore.clear();
  SyncTracker.currentUserId = null;
  sessionNotifier.state = null;
}

Future<void> signOutNow(WidgetRef ref) async {
  // Capture before awaiting: signing out unmounts the gate.
  final cloudAuth = ref.read(supabaseAvailableProvider)
      ? ref.read(cloudAuthServiceProvider)
      : null;
  final sessionNotifier = ref.read(authenticatedUserIdProvider.notifier);
  try {
    await cloudAuth?.signOutWithScope(SignOutScope.local);
  } on Object catch (error) {
    debugPrint('[auth] local sign-out failed (${error.runtimeType})');
  }
  await SessionStore.clear();
  SyncTracker.currentUserId = null;
  sessionNotifier.state = null;
}
