// lib/features/auth/presentation/screens/login_screen.dart
//
// Email + password sign-in. On success, persists the session and sets
// authenticatedUserIdProvider — the rest of the app (business selection,
// membership, permissions) reacts to that automatically.
//
// Presentation: one sign-in for everyone, with a quiet "signing in as"
// switch (Customer / Team / Owner). The selection is checked against the
// account's real role before the app session is established.

import 'dart:math' as math;

import 'package:bos_application/core/auth/session_end.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/startup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// ============================================================================
// PERSONAS (presentation only)
// ============================================================================

enum _Persona {
  customer(
    label: 'Customer',
    icon: Icons.shopping_bag_outlined,
    tagline: 'Your favourite places,\nclose by.',
    subtitle: 'Sign in to see your stores, orders and points.',
    createPrompt: 'New here?',
    createLabel: 'Create a customer account',
    createIcon: Icons.person_add_alt_1_outlined,
  ),
  team(
    label: 'Team',
    icon: Icons.badge_outlined,
    tagline: 'Your shifts, your tools,\none place.',
    subtitle: 'Sign in to start your day with your team.',
    createPrompt: 'Joining a team?',
    createLabel: 'Create an account with your invite code',
    createIcon: Icons.vpn_key_outlined,
  ),
  owner(
    label: 'Owner',
    icon: Icons.storefront_outlined,
    tagline: 'The whole business,\nat a glance.',
    subtitle: 'Sign in to pick up where you left off.',
    createPrompt: 'Starting a business?',
    createLabel: 'Create a business account',
    createIcon: Icons.add_business_outlined,
  );

  const _Persona({
    required this.label,
    required this.icon,
    required this.tagline,
    required this.subtitle,
    required this.createPrompt,
    required this.createLabel,
    required this.createIcon,
  });

  final String label;
  final IconData icon;
  final String tagline;
  final String subtitle;
  final String createPrompt;
  final String createLabel;
  final IconData createIcon;

  /// Two tones of the brand palette, shifted per persona. Always darkened
  /// a touch so white text stays readable on any theme.
  (Color, Color) tones(ColorScheme scheme) {
    Color deep(Color c) => Color.lerp(c, Colors.black, 0.2)!;
    return switch (this) {
      _Persona.customer => (
        deep(scheme.tertiary),
        deep(
          Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.45),
            scheme.tertiary,
          ),
        ),
      ),
      _Persona.team => (
        deep(scheme.secondary),
        deep(
          Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.5),
            scheme.secondary,
          ),
        ),
      ),
      _Persona.owner => (
        deep(scheme.primary),
        deep(
          Color.alphaBlend(
            scheme.tertiary.withValues(alpha: 0.55),
            scheme.primary,
          ),
        ),
      ),
    };
  }
}

const _personaPrefKey = 'login_persona';

// ============================================================================
// SCREEN
// ============================================================================

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
  _Persona _persona = _Persona.owner;

  @override
  void initState() {
    super.initState();
    _restorePersona();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restorePersona() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_personaPrefKey);
      final match = _Persona.values.where((p) => p.name == saved);
      if (match.isNotEmpty && mounted) setState(() => _persona = match.first);
    } catch (_) {
      // Purely cosmetic; ignore storage problems.
    }
  }

  Future<void> _setPersona(_Persona persona) async {
    if (persona == _persona) return;
    HapticFeedback.selectionClick();
    setState(() => _persona = persona);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_personaPrefKey, persona.name);
      setStartupPersona(persona.name);
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // AUTH LOGIC (unchanged)
  // --------------------------------------------------------------------------

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

  Future<void> _restorePendingCustomerProfile({
    required String userId,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = pendingCustomerProfileKey(email);
    final displayName = prefs.getString(key);
    if (displayName == null) return;
    await ref
        .read(customerCommerceServiceProvider)
        .ensureCustomerProfile(userId: userId, displayName: displayName);
    await prefs.remove(key);
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
        await _restorePendingCustomerProfile(
          userId: user.id,
          email: user.email ?? _emailController.text,
        );
        if (!await _matchesSelectedPersona(user.id)) {
          await auth.signOut();
          return;
        }

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
        await _restorePendingCustomerProfile(
          userId: user.id,
          email: user.email,
        );
        if (!await _matchesSelectedPersona(user.id)) return;

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

  Future<bool> _matchesSelectedPersona(String userId) async {
    final service = ref.read(customerCommerceServiceProvider);
    final hasCustomer = await service.hasCustomerProfile(userId);
    final hasOwner = await service.hasOwnerBusinessMembership(userId);
    final hasTeam = await service.hasTeamBusinessMembership(userId);

    final valid = switch (_persona) {
      _Persona.customer => hasCustomer && !hasOwner && !hasTeam,
      _Persona.team => hasTeam,
      _Persona.owner => hasOwner,
    };
    if (valid) return true;

    final message = switch (_persona) {
      _Persona.customer =>
        'This account is not a customer account. Select Team or Owner.',
      _Persona.team =>
        'This account is not a team account. Select Customer or Owner.',
      _Persona.owner =>
        'This account is not a business owner account. Select Customer or Team.',
    };
    if (mounted) setState(() => _error = message);
    return false;
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
      if (!await _matchesSelectedPersona(user.id)) {
        await auth.signOut();
        return;
      }
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

  void _openCreateAccount() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _persona == _Persona.customer
            ? const RegisterScreen(customerMode: true)
            : const RegisterScreen(),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (toneA, toneB) = _persona.tones(scheme);
    final accent = toneA;
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;

    // Inputs, focus rings, links and the primary button follow the persona.
    final personaTheme = theme.copyWith(
      colorScheme: scheme.copyWith(primary: accent, onPrimary: onAccent),
    );

    return Theme(
      data: personaTheme,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            if (wide) {
              return Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _Stage(
                      persona: _persona,
                      toneA: toneA,
                      toneB: toneB,
                      wide: true,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: _formColumn(context, accent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final stageHeight = (constraints.maxHeight * 0.3).clamp(
              200.0,
              280.0,
            );
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: stageHeight + 40,
                  child: _Stage(
                    persona: _persona,
                    toneA: toneA,
                    toneB: toneB,
                    wide: false,
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(top: stageHeight - 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _EntranceFade(
                          child: Container(
                            width: double.infinity,
                            // Keep the last row clear of the Android
                            // navigation bar / gesture area.
                            padding: EdgeInsets.fromLTRB(
                              22,
                              24,
                              22,
                              28 + MediaQuery.paddingOf(context).bottom,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(32),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 30,
                                  offset: const Offset(0, -8),
                                ),
                              ],
                            ),
                            child: _formColumn(context, accent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _formColumn(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cloudAvailable = ref.watch(supabaseAvailableProvider);
    final endedNotice = ref.watch(sessionEndedNoticeProvider);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Who is signing in ──
          Text(
            'Signing in as',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _PersonaSwitch(
            selected: _persona,
            onChanged: _submitting ? null : _setPersona,
          ),
          const SizedBox(height: 22),

          // ── Heading ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            child: Column(
              key: ValueKey(_persona),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _persona.subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          if (endedNotice != null) ...[
            _Banner(
              icon: Icons.info_outline_rounded,
              text: endedNotice,
              background: scheme.tertiaryContainer,
              foreground: scheme.onTertiaryContainer,
            ),
            const SizedBox(height: 14),
          ],
          if (_error != null) ...[
            _Banner(
              icon: Icons.error_outline_rounded,
              text: _error!,
              background: scheme.errorContainer,
              foreground: scheme.onErrorContainer,
            ),
            const SizedBox(height: 14),
          ],

          // ── Fields ──
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Enter your email.'
                : null,
          ),
          const SizedBox(height: 14),
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
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) => (value == null || value.isEmpty)
                ? 'Enter your password.'
                : null,
          ),
          if (cloudAvailable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                child: const Text('Forgot password?'),
              ),
            )
          else
            const SizedBox(height: 22),

          // ── Primary action ──
          SizedBox(
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _submitting ? null : _submit,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _submitting
                    ? SizedBox(
                        key: const ValueKey('busy'),
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Row(
                        key: ValueKey('idle'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Sign in',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ),

          if (cloudAvailable) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _submitting ? null : _signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                label: const Text(
                  'Continue with Google',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],

          // ── Create account (changes with the persona) ──
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Container(
              key: ValueKey(_persona),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_persona.createIcon, size: 19, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _persona.createPrompt,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        InkWell(
                          onTap: _submitting ? null : _openCreateAccount,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _persona.createLabel,
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PIECES
// ============================================================================

class _EntranceFade extends StatelessWidget {
  const _EntranceFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 650),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, (1 - value) * 28),
        child: child,
      ),
    ),
    child: child,
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: foreground),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: foreground, height: 1.35)),
        ),
      ],
    ),
  );
}

/// Quiet three-way switch. Reads as a tab bar, not as a role picker.
class _PersonaSwitch extends StatelessWidget {
  const _PersonaSwitch({required this.selected, required this.onChanged});

  final _Persona selected;
  final ValueChanged<_Persona>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final persona in _Persona.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: persona == selected,
                label: 'Sign in as ${persona.label}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onChanged == null ? null : () => onChanged!(persona),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: persona == selected
                          ? scheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: persona == selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          persona.icon,
                          size: 18,
                          color: persona == selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              persona.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: persona == selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: persona == selected
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// STAGE — gradient with a faint motif per persona
// ============================================================================

class _Stage extends StatelessWidget {
  const _Stage({
    required this.persona,
    required this.toneA,
    required this.toneB,
    required this.wide,
  });

  final _Persona persona;
  final Color toneA;
  final Color toneB;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: Container(
        key: ValueKey(persona),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [toneA, toneB],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MotifPainter(persona: persona, color: Colors.white),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  wide ? 48 : 24,
                  wide ? 40 : 18,
                  wide ? 48 : 24,
                  wide ? 48 : 52,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: AppLogo(height: wide ? 44 : 34),
                    ),
                    const Spacer(),
                    Text(
                      persona.tagline,
                      style:
                          (wide
                                  ? theme.textTheme.displaySmall
                                  : theme.textTheme.headlineMedium)
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                height: 1.1,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faint, abstract shapes — a suggestion of each audience's world, never
/// a literal illustration.
///   customer: soft overlapping circles (shop windows, bubbles of choice)
///   team:     a grid of schedule blocks
///   owner:    rising bars with a trend line
class _MotifPainter extends CustomPainter {
  _MotifPainter({required this.persona, required this.color});

  final _Persona persona;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = color.withValues(alpha: 0.09);
    final strong = Paint()..color = color.withValues(alpha: 0.17);
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (persona) {
      case _Persona.customer:
        final base = size.shortestSide;
        final c1 = Offset(size.width * 0.84, size.height * 0.26);
        canvas.drawCircle(c1, base * 0.44, soft);
        canvas.drawCircle(c1, base * 0.58, stroke);
        canvas.drawCircle(
          Offset(size.width * 0.96, size.height * 0.72),
          base * 0.26,
          strong,
        );
        canvas.drawCircle(
          Offset(size.width * 0.08, size.height * 0.98),
          base * 0.32,
          soft,
        );

      case _Persona.team:
        const cols = 7;
        const rows = 4;
        const gap = 8.0;
        final gridWidth = size.width * 0.62;
        final cell = (gridWidth - (cols - 1) * gap) / cols;
        final x0 = size.width - gridWidth - 14;
        final y0 = size.height * 0.1 + 12;
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            final rect = RRect.fromRectAndRadius(
              Rect.fromLTWH(
                x0 + c * (cell + gap),
                y0 + r * (cell + gap),
                cell,
                cell,
              ),
              Radius.circular(cell * 0.28),
            );
            final lit = (r * 3 + c * 2) % 5 == 0;
            canvas.drawRRect(rect, lit ? strong : soft);
          }
        }

      case _Persona.owner:
        const bars = 7;
        const gap = 10.0;
        final areaWidth = size.width * 0.58;
        final barWidth = (areaWidth - (bars - 1) * gap) / bars;
        final baseY = size.height - 60;
        final maxHeight = size.height * 0.52;
        final x0 = size.width - areaWidth - 16;
        final heights = [0.28, 0.42, 0.36, 0.58, 0.5, 0.78, 1.0];
        final line = Path();
        for (var i = 0; i < bars; i++) {
          final h = maxHeight * heights[i];
          final left = x0 + i * (barWidth + gap);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, baseY - h, barWidth, h),
              Radius.circular(math.min(8, barWidth / 2)),
            ),
            i == bars - 1 ? strong : soft,
          );
          final point = Offset(left + barWidth / 2, baseY - h - 14);
          if (i == 0) {
            line.moveTo(point.dx, point.dy);
          } else {
            line.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(line, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MotifPainter oldDelegate) =>
      oldDelegate.persona != persona || oldDelegate.color != color;
}
