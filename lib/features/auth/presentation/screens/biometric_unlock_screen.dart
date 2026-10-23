// lib/features/auth/presentation/screens/biometric_unlock_screen.dart
//
// Shown instead of the login form when a session was persisted AND the
// user opted into fingerprint/face/device-passcode unlock (Security
// screen). Confirms it's really them before resuming the session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/branding/branding.dart';

class BiometricUnlockScreen extends ConsumerStatefulWidget {
  const BiometricUnlockScreen({
    super.key,
    required this.session,
    required this.onUnlocked,
    required this.onUsePassword,
  });

  final PendingSession session;
  final VoidCallback onUnlocked;
  final VoidCallback onUsePassword;

  @override
  ConsumerState<BiometricUnlockScreen> createState() =>
      _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends ConsumerState<BiometricUnlockScreen> {
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    final ok = await ref
        .read(biometricAuthServiceProvider)
        .authenticate(reason: 'Unlock ${AppStrings.appName}');

    if (!mounted) return;
    setState(() => _checking = false);

    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = "Couldn't verify it's you. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(height: 88),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome back, ${widget.session.displayName}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.session.email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: _checking ? null : _unlock,
                    icon: _checking
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.fingerprint_rounded),
                    label: Text(_checking ? 'Verifying…' : 'Unlock'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _checking ? null : widget.onUsePassword,
                    child: const Text('Use password instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
