// lib/app/startup/startup_screens.dart
//
// Thin wrappers that wire the startup loading/error screens to sign-out.

import 'package:bos_application/features/transactions/presentation/screens/startup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/app/sign_out.dart';

class BosStartupLoading extends ConsumerWidget {
  const BosStartupLoading({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StartupLoadingScreen(onSignOut: () => signOutNow(ref));
  }
}

class BosStartupError extends ConsumerWidget {
  const BosStartupError({super.key, required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StartupErrorScreen(
      error: error,
      onRetry: onRetry,
      onSignOut: () => confirmSignOut(context, ref),
    );
  }
}
