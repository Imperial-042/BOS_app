import 'package:flutter/material.dart';

/// Lets non-widget code (session handling) reach the app's Navigator.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Closes every pushed page, bottom sheet and dialog, so the auth gate at
/// the root of the app is what the person actually sees.
void resetNavigationToRoot() {
  appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
}

/// A clear, blocking notice shown on top of the login screen.
Future<void> showSignedOutDialog(String message) async {
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.logout_rounded,
        size: 36,
        color: Theme.of(dialogContext).colorScheme.error,
      ),
      title: const Text('You were signed out'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Sign in again'),
        ),
      ],
    ),
  );
}
