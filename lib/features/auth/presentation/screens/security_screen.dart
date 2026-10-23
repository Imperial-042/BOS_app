// lib/features/auth/presentation/screens/security_screen.dart
//
// Administration -> Security. Shows who is signed in, lets them change
// their password, toggle biometric/passcode unlock, and manage devices. This is the login
// system's attachment point in the Administration module (BosDest.security).
// Signing out lives in the navigation drawer, not here.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/session_store.dart';
import '../../../../core/branding/branding.dart';
import 'devices_screen.dart';
import '../../../../core/supabase/supabase_auth_service.dart';
import '../../../../core/supabase/supabase_service.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool? _biometricSupported;
  bool _biometricEnabled = false;
  bool _togglingBiometric = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final supported = await ref
        .read(biometricAuthServiceProvider)
        .isSupported();
    final enabled = await SessionStore.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _biometricEnabled = enabled;
    });
  }

  Future<void> _toggleBiometric(bool enable) async {
    final audit = ref.read(auditLogServiceProvider);
    setState(() => _togglingBiometric = true);

    if (enable) {
      final confirmed = await ref
          .read(biometricAuthServiceProvider)
          .authenticate(reason: 'Confirm it\'s you to enable unlock');
      if (!confirmed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't verify it's you.")),
          );
          setState(() => _togglingBiometric = false);
        }
        return;
      }
    }

    await SessionStore.setBiometricEnabled(enable);
    await audit.tryRecord(
      AuditEvent(
        module: AuditModule.security,
        actionType: AuditActionType.security,
        action: enable
            ? 'security.biometric_enabled'
            : 'security.biometric_disabled',
        entityType: 'device_setting',
        entityLabel: 'Biometric unlock',
      ),
    );
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enable;
      _togglingBiometric = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Security')),
      body: user.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load your account.')),
        data: (account) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _AccountHeaderCard(
              displayName: account?.displayName ?? 'Signed in',
              email: account?.email ?? '',
            ),
            const SizedBox(height: 28),
            const _SectionLabel('Login & security'),
            const SizedBox(height: 8),
            _SecuritySectionCard(
              children: [
                _SecurityTile(
                  icon: Icons.password_rounded,
                  iconColor: AppColors.primary,
                  title: 'Change password',
                  subtitle: 'Update the password you sign in with.',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const _ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
                if (_biometricSupported != false) ...[
                  const Divider(height: 1, indent: 68),
                  _SecurityTile(
                    icon: Icons.fingerprint_rounded,
                    iconColor: AppColors.accent,
                    title: 'Biometric unlock',
                    subtitle: _biometricSupported == null
                        ? 'Checking what this device supports…'
                        : _biometricEnabled
                        ? 'Enabled — skip your password with fingerprint, '
                              'face or device passcode.'
                        : 'Use fingerprint, face or device passcode instead '
                              'of typing your password.',
                    trailing: _biometricSupported == null
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : _togglingBiometric
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Switch(
                            value: _biometricEnabled,
                            onChanged: _toggleBiometric,
                          ),
                  ),
                ] else ...[
                  const Divider(height: 1, indent: 68),
                  _SecurityTile(
                    icon: Icons.fingerprint_rounded,
                    iconColor: AppColors.accent,
                    title: 'Biometric unlock',
                    subtitle:
                        'Not available — set up a fingerprint, face unlock '
                        'or screen lock passcode in your device settings '
                        'first.',
                    trailing: const Switch(value: false, onChanged: null),
                  ),
                ],
              ],
            ),
            if (SupabaseService.isAvailable) ...[
              const SizedBox(height: 24),
              const _SectionLabel('Devices & sessions'),
              const SizedBox(height: 8),
              _SecuritySectionCard(
                children: [
                  _SecurityTile(
                    icon: Icons.devices_other_rounded,
                    iconColor: AppColors.primary,
                    title: 'My devices',
                    subtitle: 'Review active devices and manage access.',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DevicesScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your password is never stored in plain text on this '
                      'device.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountHeaderCard extends StatelessWidget {
  const _AccountHeaderCard({required this.displayName, required this.email});

  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SecuritySectionCard extends StatelessWidget {
  const _SecuritySectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordScreen extends ConsumerStatefulWidget {
  const _ChangePasswordScreen();

  @override
  ConsumerState<_ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<_ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    final audit = ref.read(auditLogServiceProvider);

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (ref.read(supabaseAvailableProvider)) {
        // Cloud session: Supabase owns the credential. The active session
        // is proof of identity; the local Users row is only an identity
        // shell and its hash isn't a real password.
        await ref
            .read(cloudAuthServiceProvider)
            .updatePassword(_newController.text);
      } else {
        await ref
            .read(authServiceProvider)
            .changePassword(
              userId: userId,
              currentPassword: _currentController.text,
              newPassword: _newController.text,
            );
      }
      await audit.tryRecord(
        AuditEvent(
          module: AuditModule.security,
          actionType: AuditActionType.security,
          action: 'auth.password_changed',
          entityType: 'user',
          entityId: userId,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
      Navigator.pop(context);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on CloudAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloudAvailable = ref.watch(supabaseAvailableProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Cloud sessions own the credential in Supabase — the local
                // Users row is an identity shell with no real password, so
                // there is no current password to verify locally.
                if (!cloudAvailable) ...[
                  TextFormField(
                    controller: _currentController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                    ),
                    validator: (value) =>
                        (value == null || value.isEmpty) ? 'Required.' : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _newController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (value) => (value == null || value.length < 6)
                      ? 'At least 6 characters.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  validator: (value) => value != _newController.text
                      ? 'Passwords don\'t match.'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('Update password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
