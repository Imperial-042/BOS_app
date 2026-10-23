// lib/features/auth/presentation/screens/login_screen.dart
//
// Email + password sign-in. On success, persists the session and sets
// authenticatedUserIdProvider — the rest of the app (business selection,
// membership, permissions) reacts to that automatically.

import 'package:bos_application/core/auth/session_end.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/session_store.dart';
import '../../../../core/device/device_providers.dart';
import '../../../../core/sync/sync_tracker.dart';
import '../../../../core/branding/branding.dart';
import '../../../../core/supabase/cloud_business_service.dart';
import '../../../../core/supabase/supabase_auth_service.dart';
import '../../../../core/supabase/supabase_service.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Redeems an invite code saved during registration (email-confirmation
  /// flow). Never throws: a failure here must not block sign-in.
  Future<void> _redeemPendingInvite(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = pendingInviteKey(email);
      final pending = prefs.getString(key);
      if (pending == null) return;
      try {
        await ref.read(cloudBusinessServiceProvider).redeemInviteCode(pending);
        await prefs.remove(key);
      } on CloudBusinessException catch (e) {
        // Keep it only when the failure was a connectivity problem.
        if (e.code != 'network_error') await prefs.remove(key);
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    ref.read(sessionEndedNoticeProvider.notifier).state = null;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final sessionNotifier = ref.read(authenticatedUserIdProvider.notifier);

    final cloudAvailable = ref.read(supabaseAvailableProvider);

    try {
      debugPrint('[login] ========================================');
      debugPrint('[login] submit started');
      debugPrint('[login] email=${_emailController.text.trim()}');
      debugPrint('[login] cloudAvailable=$cloudAvailable');

      if (cloudAvailable) {
        final auth = ref.read(cloudAuthServiceProvider);

        debugPrint('[login] calling Supabase signIn...');

        final user = await auth.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        await ref.read(deviceManagementServiceProvider).registerCurrentDevice();

        debugPrint(
          '[login] Supabase signIn SUCCESS '
          'userId=${user.id} '
          'email=${user.email}',
        );

        debugPrint('[login] adopting cloud user locally...');

        await _adoptCloudUser(user);

        debugPrint('[login] _adoptCloudUser SUCCESS');

        debugPrint('[login] saving session...');

        await SessionStore.saveUserId(user.id);

        debugPrint('[login] SessionStore.saveUserId SUCCESS');

        debugPrint('[login] updating authenticatedUserIdProvider...');

        SyncTracker.currentUserId = user.id;
        sessionNotifier.state = user.id;

        debugPrint('[login] authenticatedUserIdProvider updated: ${user.id}');

        debugPrint('[login] login flow completed successfully');
        debugPrint('[login] ========================================');
      } else {
        debugPrint('[login] using local authentication');

        final user = await ref
            .read(authServiceProvider)
            .login(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );

        debugPrint('[login] local login SUCCESS');

        await _adoptCloudUser(user as User);

        debugPrint('[login] local _adoptCloudUser SUCCESS');

        await _redeemPendingInvite(user.email);

        await SessionStore.saveUserId(user.id);

        SyncTracker.currentUserId = user.id;
        sessionNotifier.state = user.id;
      }
    } on AuthException catch (e, st) {
      debugPrint('[login][AUTH EXCEPTION]');
      debugPrint('type=${e.runtimeType}');
      debugPrint('message=${e.message}');
      debugPrintStack(stackTrace: st);

      if (mounted) {
        setState(() {
          _error = e.message;
        });
      }
    } on CloudAuthException catch (e, st) {
      debugPrint('[login][CLOUD AUTH EXCEPTION]');
      debugPrint('message=${e.message}');
      debugPrint('isCancellation=${e.isCancellation}');
      debugPrintStack(stackTrace: st);

      if (mounted) {
        setState(() {
          _error = e.message;
        });
      }
    } catch (e, st) {
      debugPrint('[login][UNEXPECTED EXCEPTION]');
      debugPrint('type=${e.runtimeType}');
      debugPrint('error=$e');
      debugPrint(st.toString());

      if (mounted) {
        setState(() {
          _error = 'Login failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    // Captured before the awaits below: this notifier stays valid even if
    // the widget is unmounted by the time sign-in finishes.
    final sessionNotifier = ref.read(authenticatedUserIdProvider.notifier);

    try {
      final auth = ref.read(cloudAuthServiceProvider);
      final user = await auth.signInWithGoogle();
      await ref.read(deviceManagementServiceProvider).registerCurrentDevice();
      await _adoptCloudUser(user);
      await _redeemPendingInvite(user.email ?? '');
      await SessionStore.saveUserId(user.id);
      SyncTracker.currentUserId = user.id;
      sessionNotifier.state = user.id;
    } on CloudAuthException catch (e) {
      // Cancellation just returns to the idle login screen.
      if (!e.isCancellation) setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// After a cloud sign-in, make sure a matching local Users row exists for
  /// the cloud UUID so _StartupGate/businesses keep working on Drift.
  Future<void> _adoptCloudUser(User user) async {
    debugPrint('[login][adopt] cloud user id=${user.id}');

    var displayName =
        (user.userMetadata?['display_name'] as String?) ??
        (user.userMetadata?['full_name'] as String?) ??
        '';

    try {
      debugPrint('[login][adopt] loading cloud profile...');

      final profile = await ref
          .read(cloudBusinessServiceProvider)
          .getMyProfile();

      if (profile != null && profile.displayName.trim().isNotEmpty) {
        displayName = profile.displayName;
      }

      debugPrint(
        '[login][adopt] cloud profile lookup complete '
        'displayName="$displayName"',
      );
    } catch (e, st) {
      debugPrint(
        '[login][adopt] profile lookup failed '
        '(non-blocking): $e',
      );
      debugPrintStack(stackTrace: st);
    }

    debugPrint(
      '[login][adopt] ensureLocalUser '
      'id=${user.id} email=${user.email}',
    );

    await ref
        .read(authServiceProvider)
        .ensureLocalUser(
          id: user.id,
          email: user.email ?? '',
          displayName: displayName,
        );

    debugPrint('[login][adopt] ensureLocalUser SUCCESS');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloudAvailable = ref.watch(supabaseAvailableProvider);
    final endedNotice = ref.watch(sessionEndedNoticeProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(height: 88)),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to manage your business.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (endedNotice != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                endedNotice,
                                style: TextStyle(
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
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
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Enter your email.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter your password.'
                          : null,
                    ),
                    if (cloudAvailable) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _submitting
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordScreen(),
                                    ),
                                  );
                                },
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ] else
                      const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    if (cloudAvailable) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata_rounded),
                        label: const Text('Continue with Google'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                      child: const Text("Don't have an account? Create one"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
