import 'package:bos_application/core/auth/auth_providers.dart';
import 'package:bos_application/core/auth/session_store.dart';
import 'package:bos_application/core/device/device_providers.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/features/auth/presentation/screens/devices_screen.dart';
import 'package:bos_application/features/transactions/presentation/widgets/secruity_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Account security for the signed-in member. Open to every role.
class MySecurityScreen extends ConsumerStatefulWidget {
  const MySecurityScreen({super.key});

  @override
  ConsumerState<MySecurityScreen> createState() => _MySecurityScreenState();
}

class _MySecurityScreenState extends ConsumerState<MySecurityScreen> {
  bool _prefsLoading = true;
  bool _biometricSupported = false;
  bool _biometricOn = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  Future<void> _loadPrefs() async {
    final supported = await ref
        .read(biometricAuthServiceProvider)
        .isSupported();
    final on = await SessionStore.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _biometricOn = on;
      _prefsLoading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    HapticFeedback.selectionClick();
    if (value) {
      final ok = await ref
          .read(biometricAuthServiceProvider)
          .authenticate(reason: 'Confirm it\'s you to turn on the app lock');
      if (!ok) return;
    }
    await SessionStore.setBiometricEnabled(value);
    if (mounted) setState(() => _biometricOn = value);
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true) _snack('Password updated.');
  }

  @override
  Widget build(BuildContext context) {
    final cloud = ref.watch(supabaseAvailableProvider);
    final auth = cloud ? ref.read(cloudAuthServiceProvider) : null;
    final provider = cloud
        ? ref
              .read(supabaseClientProvider)
              .auth
              .currentUser
              ?.appMetadata['provider']
        : null;
    final usesPassword = provider == null || provider == 'email';
    final email = auth?.currentEmail;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SecurityHeader(
                    email: email,
                    cloud: cloud,
                    usesPassword: usesPassword,
                    appLockOn: _biometricOn,
                    appLockLoading: _prefsLoading,
                  ),
                  const SizedBox(height: 24),
                  SecuritySection(
                    title: 'Sign-in',
                    footer: cloud && !usesPassword
                        ? 'Your password is managed by your Google account.'
                        : null,
                    children: [
                      SecurityTile(
                        icon: usesPassword
                            ? Icons.alternate_email_rounded
                            : Icons.verified_user_outlined,
                        title: email ?? 'Local account',
                        subtitle: usesPassword
                            ? 'Email and password'
                            : 'Signed in with Google',
                      ),
                      if (cloud && usesPassword)
                        SecurityTile(
                          icon: Icons.password_rounded,
                          title: 'Change password',
                          subtitle: 'Update the password you sign in with',
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _changePassword,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SecuritySection(
                    title: 'App lock',
                    children: [
                      if (_prefsLoading)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: LinearProgressIndicator(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        )
                      else
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          enabled: _biometricSupported,
                          onTap: _biometricSupported
                              ? () => _toggleBiometric(!_biometricOn)
                              : null,
                          leading: IconBadge(
                            icon: Icons.fingerprint_rounded,
                            color: _biometricSupported
                                ? null
                                : Theme.of(context).disabledColor,
                          ),
                          title: Text(
                            'Unlock with fingerprint / face',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _biometricSupported
                                ? 'Ask for it when you open the app. Your '
                                      'device passcode works too.'
                                : 'This device has no screen lock set up.',
                          ),
                          trailing: Switch(
                            value: _biometricOn,
                            onChanged: _biometricSupported
                                ? _toggleBiometric
                                : null,
                          ),
                        ),
                    ],
                  ),
                  if (cloud) ...[
                    const SizedBox(height: 20),
                    SecuritySection(
                      title: 'Your devices',
                      children: [
                        SecurityTile(
                          icon: Icons.devices_other_rounded,
                          title: 'My devices',
                          subtitle:
                              'Review signed-in devices and manage access.',
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DevicesScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero card: avatar, email and an at-a-glance protection summary.
class _SecurityHeader extends StatelessWidget {
  const _SecurityHeader({
    required this.email,
    required this.cloud,
    required this.usesPassword,
    required this.appLockOn,
    required this.appLockLoading,
  });

  final String? email;
  final bool cloud;
  final bool usesPassword;
  final bool appLockOn;
  final bool appLockLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = (email?.isNotEmpty == true ? email![0] : 'L').toUpperCase();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.tertiaryContainer.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primary,
                child: Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account security',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email ?? 'Local account',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                icon: cloud ? Icons.cloud_done_outlined : Icons.cloud_off,
                label: cloud ? 'Cloud account' : 'Local only',
                color: scheme.primary,
              ),
              StatusPill(
                icon: usesPassword ? Icons.key_rounded : Icons.g_mobiledata,
                label: usesPassword ? 'Password' : 'Google',
                color: scheme.primary,
              ),
              if (!appLockLoading)
                StatusPill(
                  icon: appLockOn
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  label: appLockOn ? 'App lock on' : 'App lock off',
                  color: appLockOn ? Colors.green.shade700 : scheme.error,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _next.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// 0..4 rough strength score for the meter (guidance only).
  int _strength(String p) {
    var s = 0;
    if (p.length >= 6) s++;
    if (p.length >= 10) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s;
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _next.text;
    if (current.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (next.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (next != _confirm.text) {
      setState(() => _error = 'The new passwords don\'t match.');
      return;
    }
    if (next == current) {
      setState(
        () => _error = 'Choose a password different from your current one.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(cloudAuthServiceProvider);
      final email = auth.currentEmail;
      if (email == null) {
        throw const CloudAuthException(
          'not_signed_in',
          'You are signed out. Sign in again first.',
        );
      }
      // Proves the person knows the current password. A fresh sign-in gets a
      // new session, which must be registered for this device again.
      await auth.signIn(email: email, password: current);
      await ref.read(deviceManagementServiceProvider).registerCurrentDevice();
      await auth.updatePassword(next);
      if (mounted) Navigator.pop(context, true);
    } on CloudAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not change your password. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strength = _strength(_next.text);
    final strengthColors = [
      scheme.error,
      scheme.error,
      Colors.orange.shade700,
      Colors.lightGreen.shade700,
      Colors.green.shade700,
    ];
    final strengthLabels = ['Too short', 'Weak', 'Fair', 'Good', 'Strong'];

    return AlertDialog(
      icon: const IconBadge(icon: Icons.password_rounded, size: 52),
      title: const Text('Change password'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PasswordField(
                  controller: _current,
                  label: 'Current password',
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.password],
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                _PasswordField(
                  controller: _next,
                  label: 'New password',
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                if (_next.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: (strength + 1) / 5,
                            color: strengthColors[strength],
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        strengthLabels[strength],
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: strengthColors[strength],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _PasswordField(
                  controller: _confirm,
                  label: 'Confirm new password',
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.newPassword],
                  action: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  InfoBanner(
                    icon: Icons.error_outline_rounded,
                    background: scheme.errorContainer,
                    foreground: scheme.onErrorContainer,
                    child: Text(_error!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update password'),
        ),
      ],
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.autofillHints,
    this.autofocus = false,
    this.action = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      autofillHints: widget.autofillHints,
      textInputAction: widget.action,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show' : 'Hide',
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
