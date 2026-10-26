// lib/main.dart
//
// BOS — Business Operating System
//
// Entry point, startup gate, and adaptive navigation shell.
//
// NAVIGATION ARCHITECTURE
//
//   BOS
//   ├── Management       command center (opens the Dashboard directly)
//   ├── Finance          money & accounting
//   ├── Inventory        stock & purchasing
//   ├── Sales & POS      selling & customers
//   ├── People           employees / HR
//   └── Administration   configuration, profile, security
//
//   * Every module and destination is declared ONCE, in the registry below
//     (`bosModules`, `bosDestinations`). The bottom bar, drawer, rail, module
//     landing pages and breadcrumbs are all generated from it.
//   * A module either opens one page directly (`homeId`, e.g. Management →
//     Dashboard) or opens a landing page ("hub") listing its destinations.
//   * A destination with no `builder` is a "coming soon" placeholder. Nothing
//     is faked: it only renders a clear notice.
//   * `BosPresentation.route` destinations were built as full-screen pushed
//     pages, so they still open that way and behave exactly as before.
//
//   Phone  (< 600):  bottom bar (Management, Finance, Inventory, Sales & POS,
//                    More) + drawer behind "More" and the menu button
//   Tablet (600+):   compact rail (icon + short label)
//   Wide   (840+):   extended rail; the active module's pages nest under it
//
// To add a module (Documents, Projects, CRM…): add a value to `BosModule`, a
// `BosModuleInfo`, and its `BosDestination`s. No other code changes.

import 'dart:async';
import 'dart:math' as math;

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/auth/access_revoked_listener.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/device/device_session_watcher.dart';
import 'package:bos_application/core/navigation/app_navigator.dart';
import 'package:bos_application/core/navigation/nav_visibility.dart';
import 'package:bos_application/core/settings/app_settings.dart';
import 'package:bos_application/features/customer/presentation/customer_mode_gate.dart';
import 'package:bos_application/features/customer/presentation/customer_storefront_management_screen.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/core/sync/legacy_data_bootstrap.dart';
import 'package:bos_application/core/sync/sync_change_log.dart';
import 'package:bos_application/core/sync/transfer_repair.dart';
import 'package:bos_application/features/branches/branch_widgets.dart';
import 'package:bos_application/features/branches/branches_screen.dart';
import 'package:bos_application/features/inventory/stock_transfers_page.dart';
import 'package:bos_application/features/transactions/presentation/attendance_screen.dart';
import 'package:bos_application/features/transactions/presentation/leave_screen.dart';
import 'package:bos_application/features/transactions/presentation/payroll_screen.dart';
import 'package:bos_application/features/transactions/presentation/schedules_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/audit_trail_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/cashflow_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/categories_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/chart_of_accounts_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/dashboard_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/employee_onboarding_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/employees_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/financial_reports_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/aging_report_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/income_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/expenses_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/sales_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/orders_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/returns_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/transfers_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/receivables_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/payables_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/import_export_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/inventory_report_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/journal_entry_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/products_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/profile_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/settings_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/suppliers_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show businessProfileProvider, kCurrentBusinessId, ledgerVersionProvider;
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/auth_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart';
import 'package:bos_application/core/business/module_config_service.dart';
import 'package:bos_application/features/auth/presentation/screens/biometric_unlock_screen.dart';
import 'package:bos_application/features/auth/presentation/screens/login_screen.dart';
import 'package:bos_application/features/auth/presentation/screens/permissions_screen.dart';
import 'package:bos_application/features/auth/presentation/screens/security_screen.dart';
import 'package:bos_application/features/auth/presentation/screens/users_roles_screen.dart';
import 'package:bos_application/core/auth/session_store.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_trigger_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:bos_application/core/device/device_management_service.dart';
import 'package:bos_application/core/device/device_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, SignOutScope, SupabaseClient;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuditDeviceId.loadCached();
  await BranchPrefs.init();
  // Awaited (not fire-and-forget): the auth gate reads the cloud session
  // synchronously on first build, so the client must exist by then. This
  // is a local operation — it never blocks startup on network/cloud
  // availability, and it's a no-op when Supabase isn't configured.
  await SupabaseService.initialize();
  final preferences = await SharedPreferences.getInstance();
  final initialSettings = AppSettingsController.load(preferences);
  runApp(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWith(
          (ref) => AppSettingsController(
            preferences: preferences,
            initialSettings: initialSettings,
          ),
        ),
      ],
      child: const BosApp(),
    ),
  );
}

// ============================================================
// APP + THEME
// ============================================================

class BosApp extends ConsumerWidget {
  const BosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final colorOption = AppTheme.colorOptions.firstWhere(
      (option) => option.id == settings.colorId,
    );
    final fontFamily = switch (settings.fontFamily) {
      'serif' => 'serif',
      'monospace' => 'monospace',
      _ => null,
    };
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(
        seedColor: colorOption.color,
        fontFamily: fontFamily,
      ),
      darkTheme: AppTheme.dark(
        seedColor: colorOption.color,
        fontFamily: fontFamily,
      ),
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: _PreferenceTextScaler(
              mediaQuery.textScaler,
              settings.textScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _AuthGate(),
    );
  }
}

class _PreferenceTextScaler extends TextScaler {
  const _PreferenceTextScaler(this.parent, this.factor);

  final TextScaler parent;
  final double factor;

  @override
  double scale(double fontSize) => parent.scale(fontSize * factor);

  @override
  double get textScaleFactor => scale(1);
}

/// Thrown by startup when the account has no membership and no pending
/// invite, so the UI can ask "join or create?" instead of silently
/// creating a business.
class _NoBusinessYet implements Exception {
  const _NoBusinessYet();
}

class _JoinOrCreateScreen extends ConsumerStatefulWidget {
  const _JoinOrCreateScreen({required this.onCreate, required this.onJoined});

  final VoidCallback onCreate;
  final VoidCallback onJoined;

  @override
  ConsumerState<_JoinOrCreateScreen> createState() =>
      _JoinOrCreateScreenState();
}

class _JoinOrCreateScreenState extends ConsumerState<_JoinOrCreateScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  /// The invite-code field stays hidden until the person says they have one,
  /// so someone creating their own business is never asked for a code.
  bool _hasCode = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(cloudBusinessServiceProvider).redeemInviteCode(code);
      widget.onJoined();
    } on CloudBusinessException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not use that code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set up your business',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hasCode
                        ? 'Enter the code the business owner gave you.'
                        : 'Start your own business, or join one you were '
                              'invited to.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (!_hasCode) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : widget.onCreate,
                      icon: const Icon(Icons.add_business_rounded),
                      label: const Text('Create my business'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _hasCode = true),
                      icon: const Icon(Icons.vpn_key_outlined),
                      label: const Text('I have an invite code'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _confirmSignOut(context, ref),
                      child: const Text('Cancel'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _code,
                      autofocus: true,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _join(),
                      decoration: InputDecoration(
                        labelText: 'Invite code',
                        errorText: _error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _join,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Join business'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _hasCode = false;
                              _error = null;
                              _code.clear();
                            }),
                      child: const Text('Back'),
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

// ============================================================
// AUTH GATE — shows the login screen until someone is signed in.
// ============================================================

/// Restores a persisted session on first launch. If the user opted into
/// biometric/passcode unlock, [BiometricUnlockScreen] must confirm it's
/// them before the session resumes; otherwise it resumes right away, same
/// as before biometrics existed. Signing in and out both flow through
/// [authenticatedUserIdProvider], so most of this widget just watches it.
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool _forcePasswordLogin = false;
  StreamSubscription<AuthState>? _cloudAuthSub;

  /// Whether the device-level biometric/passcode lock is enabled. Loaded
  /// once per cold start; drives whether a restored session must confirm
  /// identity first. Only consulted when Supabase is configured.
  bool _biometricChecked = false;
  bool _biometricLockEnabled = false;

  @override
  void initState() {
    super.initState();
    if (SupabaseService.isAvailable) {
      // Expired sessions and sign-outs from another device arrive here:
      // drop the local session so no stale account data stays on screen.
      _cloudAuthSub = ref
          .read(cloudAuthServiceProvider)
          .onAuthStateChange
          .listen(_onCloudAuthChange);
    }
  }

  @override
  void dispose() {
    _cloudAuthSub?.cancel();
    super.dispose();
  }

  void _onCloudAuthChange(AuthState authState) {
    // Covers local sign-out, expired refresh tokens, and sessions revoked
    // from another device (gotrue emits signedOut for all of them).
    // if (authState.event == AuthChangeEvent.signedOut) {
    //   SessionStore.clear();
    //   SyncTracker.currentUserId = null;
    //   ref.read(authenticatedUserIdProvider.notifier).state = null;
    //   return;
    // }
    if (authState.event == AuthChangeEvent.signedOut) {
      SessionStore.clear();
      SyncTracker.currentUserId = null;
      ref.read(authenticatedUserIdProvider.notifier).state = null;
      resetNavigationToRoot();
      return;
    }
    final cloudUserId = authState.session?.user.id;
    if (cloudUserId != null) SyncTracker.currentUserId = cloudUserId;
  }

  void _resume(String userId) {
    SyncTracker.currentUserId = userId;
    ref.read(authenticatedUserIdProvider.notifier).state = userId;
  }

  /// Reads the device-level biometric/passcode lock flag once, then either
  /// gates the cloud session behind it or resumes right away.
  Future<void> _checkBiometricLock(String cloudUid) async {
    final enabled = await SessionStore.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricChecked = true;
      _biometricLockEnabled = enabled;
    });
  }

  /// "Use password instead" from the biometric gate for a cloud session:
  /// drop the persisted Supabase session and show the login form.
  Future<void> _forgetCloudSession() async {
    try {
      await ref
          .read(cloudAuthServiceProvider)
          .signOutWithScope(SignOutScope.local);
    } on Object catch (error) {
      // Best-effort; the local session flag is cleared regardless.
      debugPrint('[auth] local sign-out failed (${error.runtimeType})');
    }
    await SessionStore.clear();
    if (!mounted) return;
    setState(() {
      _forcePasswordLogin = true;
      _biometricChecked = false;
      _biometricLockEnabled = false;
    });
  }

  /// Resuming a persisted Supabase session: create the local identity shell
  /// (idempotent) BEFORE flipping authenticatedUserIdProvider, so profile /
  /// membership lookups keyed on the Users table never observe a missing
  /// row for the cloud UUID.
  Future<void> _resumeCloud(String cloudUid) async {
    final cloudAuth = ref.read(cloudAuthServiceProvider);
    var displayName = cloudAuth.currentDisplayName ?? '';
    try {
      final profile = await ref
          .read(cloudBusinessServiceProvider)
          .getMyProfile();
      if (profile != null && profile.displayName.trim().isNotEmpty) {
        displayName = profile.displayName;
      }
    } catch (_) {
      // Profile lookup is best-effort; auth metadata is enough to resume.
    }
    await ref
        .read(authServiceProvider)
        .ensureLocalUser(
          id: cloudUid,
          email: cloudAuth.currentEmail ?? '',
          displayName: displayName,
        );
    if (mounted) _resume(cloudUid);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authenticatedUserIdProvider);
    if (userId != null) {
      return CustomerModeGate(businessBuilder: (_) => const _StartupGate());
    }

    if (_forcePasswordLogin) return const LoginScreen();

    // When the cloud backend is configured, its session is the source of
    // truth: restore it (Supabase persists the session on-device) before
    // falling back to the local pending-session/biometric flow.
    if (ref.watch(supabaseAvailableProvider)) {
      final cloudAuth = ref.watch(cloudAuthServiceProvider);
      final cloudUid = cloudAuth.currentUserId;
      if (cloudUid != null) {
        // Honor the biometric/passcode lock for cloud sessions too — the
        // flag is stored on-device, independent of the auth backend.
        if (_biometricLockEnabled) {
          return BiometricUnlockScreen(
            session: PendingSession(
              userId: cloudUid,
              email: cloudAuth.currentEmail ?? '',
              displayName: cloudAuth.currentDisplayName ?? '',
              biometricEnabled: true,
            ),
            onUnlocked: () => unawaited(_resumeCloud(cloudUid)),
            onUsePassword: _forgetCloudSession,
          );
        }
        if (!_biometricChecked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _checkBiometricLock(cloudUid);
          });
          return const _StartupLoadingScreen();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_resumeCloud(cloudUid));
        });
        return const _StartupLoadingScreen();
      }
      return const LoginScreen();
    }

    final pending = ref.watch(pendingSessionProvider);
    return pending.when(
      loading: () => const _StartupLoadingScreen(),
      error: (_, _) => const LoginScreen(),
      data: (session) {
        if (session == null) return const LoginScreen();

        if (!session.biometricEnabled) {
          // No lock configured: resume the session right away, as before.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resume(session.userId);
          });
          return const _StartupLoadingScreen();
        }

        return BiometricUnlockScreen(
          session: session,
          onUnlocked: () => _resume(session.userId),
          onUsePassword: () => setState(() => _forcePasswordLogin = true),
        );
      },
    );
  }
}

// ============================================================
// STARTUP GATE
// ============================================================

/// Lets screens outside main.dart restart the startup flow (for example
/// after the user's last business is deleted).
VoidCallback? restartStartupFlow;

class _StartupGate extends ConsumerStatefulWidget {
  const _StartupGate();

  @override
  ConsumerState<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<_StartupGate> {
  late Future<BusinessesData> _initFuture;
  bool _allowCreateFirstBusiness = false;

  @override
  void initState() {
    super.initState();
    restartStartupFlow = _reloadStartup;
    _initFuture = _ensureBusinessExists();
  }

  @override
  void dispose() {
    if (restartStartupFlow == _reloadStartup) restartStartupFlow = null;
    super.dispose();
  }

  // ============================================================
  // CREATE BUSINESS
  // ============================================================

  Future<String> _createFirstBusiness(AppDatabase db, String userId) async {
    String newId;

    if (ref.read(supabaseAvailableProvider)) {
      newId = await ref
          .read(cloudBusinessServiceProvider)
          .createBusiness(name: 'My Business');
    } else {
      newId = 'biz_${DateTime.now().microsecondsSinceEpoch}';
    }

    await db.transaction(() async {
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: newId,
              name: 'My Business',
              ownerUserId: userId,
              isCurrent: const Value(true),
            ),
            mode: InsertMode.insertOrIgnore,
          );

      await db.seedDefaultsForBusiness(newId);

      await MembershipService.insertOwnerMembership(
        db,
        businessId: newId,
        userId: userId,
      );
    });

    return newId;
  }

  // ============================================================
  // LOCAL BUSINESS DISCOVERY
  //
  // THIS IS THE IMPORTANT OFFLINE-FIRST PART.
  //
  // We look in Drift FIRST.
  // We do not contact Supabase just to determine whether BOS can open.
  // ============================================================

  Future<List<BusinessesData>> _findLocalBusinessesForUser(
    AppDatabase db,
    String userId,
  ) async {
    final memberships = await (db.select(
      db.businessMembers,
    )..where((m) => m.userId.equals(userId) & m.status.equals('active'))).get();

    final businessIds = memberships.map((m) => m.businessId).toSet();

    if (businessIds.isNotEmpty) {
      final businesses = await (db.select(
        db.businesses,
      )..where((b) => b.id.isIn(businessIds))).get();

      final active = businesses.where((business) => business.isActive).toList();

      if (active.isNotEmpty) {
        return active;
      }
    }

    // Compatibility fallback for older local databases where the owner
    // relationship may exist but the local membership row was not present.
    final owned = await (db.select(
      db.businesses,
    )..where((b) => b.ownerUserId.equals(userId))).get();

    return owned.where((business) => business.isActive).toList();
  }

  // ============================================================
  // LOCAL DEVICE AUTHORIZATION
  // ============================================================

  Future<void> _throwIfLocallyRevoked(String userId) async {
    if (!ref.read(supabaseAvailableProvider)) {
      return;
    }

    final deviceService = ref.read(deviceManagementServiceProvider);

    final cached = await deviceService.getCachedAuthorization(userId: userId);

    if (cached == null) {
      // Existing installations created before this offline authorization
      // cache existed have no cached state yet. They are allowed to use
      // their already-existing local business and will be reconciled online.
      return;
    }

    if (!cached.authorized) {
      throw DeviceAuthorizationException(
        _deviceAuthorizationMessage(cached.status, cached.requiresFreshLogin),
        status: cached.status,
        requiresFreshLogin: cached.requiresFreshLogin,
      );
    }
  }

  String _deviceAuthorizationMessage(String status, bool requiresFreshLogin) {
    return switch (status) {
      'revoked' when requiresFreshLogin =>
        'This device was revoked. Sign out, sign in again, then '
            'explicitly reactivate it to resume cloud access.',
      'revoked' =>
        'This device was revoked. Explicitly reactivate it to resume '
            'cloud access.',
      'blocked' =>
        'This device is blocked. Contact your organization administrator '
            'to restore cloud access.',
      _ => 'This device is not authorized for cloud access.',
    };
  }

  // ============================================================
  // SELECT / PREPARE CURRENT BUSINESS
  // ============================================================

  Future<BusinessesData> _selectCurrentBusiness(
    AppDatabase db,
    List<BusinessesData> myBusinesses,
  ) async {
    final active = myBusinesses.where((business) => business.isActive).toList();

    if (active.isEmpty) {
      throw StateError('You do not currently belong to an active business.');
    }

    final current = active.firstWhere(
      (business) => business.isCurrent,
      orElse: () => active.first,
    );

    await SyncChangeLog.suppressed(db, () {
      return db.transaction(() async {
        await (db.update(
          db.businesses,
        )).write(const BusinessesCompanion(isCurrent: Value(false)));

        await (db.update(db.businesses)..where((b) => b.id.equals(current.id)))
            .write(const BusinessesCompanion(isCurrent: Value(true)));
      });
    });

    final businessChanged = kCurrentBusinessId != current.id;

    kCurrentBusinessId = current.id;

    ref.invalidate(selectedBusinessIdProvider);

    if (businessChanged) {
      ref.read(ledgerVersionProvider.notifier).state++;
    }

    return current;
  }

  // ============================================================
  // ONLINE RECONCILIATION
  //
  // IMPORTANT:
  // This does NOT block the initial offline startup.
  //
  // It verifies the installation against Supabase after the local
  // business has already been allowed to open.
  // ============================================================

  Future<void> _reconcileCloudState({
    required AppDatabase db,
    required String userId,
    required String currentBusinessId,
  }) async {
    if (!ref.read(supabaseAvailableProvider)) {
      return;
    }

    try {
      final deviceService = ref.read(deviceManagementServiceProvider);

      final device = await deviceService.registerCurrentDevice().timeout(
        const Duration(seconds: 5),
      );

      debugPrint(
        '[device] background reconciliation '
        'status=${device.status} '
        'requiresFreshLogin=${device.requiresFreshLogin}',
      );

      await AuditDeviceId.remember(device.deviceUuid);

      if (device.status != 'active') {
        debugPrint(
          '[device] current device is no longer active '
          'after online reconciliation',
        );

        if (mounted) {
          ref.invalidate(currentBusinessMembershipProvider);
        }

        return;
      }

      final client = ref.read(supabaseClientProvider);

      // Drop businesses the owner deleted elsewhere BEFORE anything else
      // (claim_owner_membership, bootstrap) can act on them.
      try {
        final removed = await purgeDeletedBusinesses(db, client);
        if (removed.contains(currentBusinessId)) {
          if (!mounted) return;
          final moved = await ref
              .read(syncTriggerServiceProvider)
              .moveOffRemovedBusiness(userId, currentBusinessId);
          if (!moved) {
            // No business left: startup shows "Create or join".
            _reloadStartup();
          }
          return;
        }
      } catch (e) {
        debugPrint('[business] deleted-business check skipped: $e');
      }

      // TEMPORARY cleanup: hand a stuck supplies update to the signed-in account.
      // final stuck = await db
      //     .customSelect(
      //       "SELECT o.id, o.business_id, o.entity_id FROM sync_outbox o "
      //       "WHERE o.entity_type = 'supplies' AND o.operation = 'update' "
      //       "AND o.status = 'pending' "
      //       "AND EXISTS (SELECT 1 FROM sync_outbox_owners w "
      //       "WHERE w.outbox_id = o.id AND w.owner_user_id <> ?)",
      //       variables: [Variable.withString(userId)],
      //     )
      //     .get();
      // for (final r in stuck) {
      //   await db.transaction(() async {
      //     await db.customStatement(
      //       'DELETE FROM sync_outbox_owners WHERE outbox_id = ?',
      //       [r.read<String>('id')],
      //     );
      //     await db.customStatement('DELETE FROM sync_outbox WHERE id = ?', [
      //       r.read<String>('id'),
      //     ]);
      //     await SyncTracker.record(
      //       db,
      //       businessId: r.read<String>('business_id'),
      //       entityType: 'supplies',
      //       entityId: r.read<String>('entity_id'),
      //       operation: SyncOp.update,
      //       ownerUserId: userId,
      //     );
      //   });
      // }
      // debugPrint('[cleanup] re-queued ${stuck.length} stuck supply update(s)');

      final cloudMemberships = await client
          .from('business_memberships')
          .select('business_id, status, role')
          .eq('user_id', userId)
          .eq('status', 'active')
          .timeout(const Duration(seconds: 5));

      debugPrint(
        '[business] background membership '
        'reconciliation count=${cloudMemberships.length}',
      );
      if (cloudMemberships.isEmpty) {
        // Never invent a status the cloud doesn't hold. Heal owners whose
        // membership was never uploaded, then apply whatever the cloud says.
        final localBiz = await (db.select(
          db.businesses,
        )..where((b) => b.id.equals(currentBusinessId))).getSingleOrNull();
        if (localBiz != null && localBiz.ownerUserId == userId) {
          try {
            await client.rpc(
              'claim_owner_membership',
              params: {'p_business_id': currentBusinessId},
            );
          } catch (e) {
            debugPrint('[business] claim_owner_membership failed: $e');
          }
        }
        await adoptCloudAccess(db, client, userId: userId);
        if (mounted) ref.invalidate(currentBusinessMembershipProvider);
        return;
      }

      // Bring any cloud membership/business changes into Drift.
      await adoptCloudAccess(db, client, userId: userId);

      // Legacy bootstrap is now NON-FATAL and NON-BLOCKING at startup.
      try {
        final biz = await (db.select(
          db.businesses,
        )..where((b) => b.id.equals(currentBusinessId))).getSingleOrNull();
        final bootstrapped = biz?.ownerUserId == userId
            ? await ref
                  .read(legacyCloudBootstrapServiceProvider)
                  .bootstrapIfNeeded(currentBusinessId)
            : false;

        if (bootstrapped) {
          debugPrint('[bootstrap] legacy local data uploaded to cloud');
        }
      } catch (error, stack) {
        debugPrint('[bootstrap] background bootstrap skipped: $error');
        debugPrint(stack.toString());
      }

      // Profile upload is also best-effort.
      try {
        await queueLocalProfileIfCloudBlank(
          db,
          client,
          businessId: currentBusinessId,
        );
      } catch (error) {
        debugPrint('[bootstrap] background profile upload skipped: $error');
      }
    } on DeviceAuthorizationException catch (error) {
      debugPrint('[device] background reconciliation rejected device: $error');

      if (mounted) {
        ref.invalidate(currentBusinessMembershipProvider);
      }
    } on TimeoutException catch (error) {
      // No network / unreachable Supabase:
      // local BOS continues running normally.
      debugPrint('[offline] cloud reconciliation timed out: $error');
    } on Object catch (error, stack) {
      // Cloud failure must NOT destroy offline usability.
      debugPrint('[offline] cloud reconciliation skipped: $error');
      debugPrint(stack.toString());
    }
  }

  // ============================================================
  // CLOUD-FIRST INITIALIZATION
  //
  // Used only when there is NO local business.
  //
  // A brand-new installation still needs internet once to:
  // - load membership
  // - redeem invitation
  // - or create the cloud business
  //
  // Existing installations do NOT come through this path when offline.
  // ============================================================

  Future<List<BusinessesData>> _initializeCloudBusiness(
    AppDatabase db,
    SupabaseClient client,
    String userId,
  ) async {
    final deviceService = ref.read(deviceManagementServiceProvider);

    final device = await deviceService.registerCurrentDevice();

    debugPrint(
      '[device] initial registration '
      'status=${device.status} '
      'requiresFreshLogin=${device.requiresFreshLogin} '
      'uuid=${device.deviceUuid}',
    );

    await AuditDeviceId.remember(device.deviceUuid);

    if (device.status != 'active') {
      throw DeviceAuthorizationException(
        _deviceAuthorizationMessage(device.status, device.requiresFreshLogin),
        status: device.status,
        requiresFreshLogin: device.requiresFreshLogin,
      );
    }

    debugPrint('[business] querying cloud memberships for user=$userId');

    List<dynamic> cloudMemberships;

    try {
      cloudMemberships = await client
          .from('business_memberships')
          .select('business_id, status, role')
          .eq('user_id', userId)
          .eq('status', 'active')
          .timeout(const Duration(seconds: 8));

      debugPrint(
        '[business] cloud membership query '
        'SUCCESS count=${cloudMemberships.length}',
      );
    } on TimeoutException {
      throw StateError(
        'BOS could not reach the cloud. '
        'Your local session is still intact, but this device has '
        'no local business available for offline startup. '
        'Connect to the internet once and try again.',
      );
    } catch (e, st) {
      debugPrint('[business] cloud membership query FAILED: $e');
      debugPrint(st.toString());

      throw StateError(
        'Could not check your business membership in the cloud. ($e)',
      );
    }

    // ==========================================================
    // EXISTING CLOUD BUSINESS
    // ==========================================================

    if (cloudMemberships.isNotEmpty) {
      debugPrint('[business] existing cloud membership found');

      try {
        await adoptCloudAccess(db, client, userId: userId);
      } catch (e, st) {
        debugPrint('[business] adoptCloudAccess FAILED: $e');
        debugPrint(st.toString());

        throw StateError(
          'Could not load your existing business from the cloud. '
          'Check your connection and tap Try again. ($e)',
        );
      }

      final localMemberships =
          await (db.select(db.businessMembers)..where(
                (m) => m.userId.equals(userId) & m.status.equals('active'),
              ))
              .get();

      if (localMemberships.isEmpty) {
        throw StateError(
          'Your cloud account has an active business membership, '
          'but it could not be imported into the local database.',
        );
      }

      final businessIds = localMemberships.map((m) => m.businessId).toSet();

      final myBusinesses = await (db.select(
        db.businesses,
      )..where((b) => b.id.isIn(businessIds))).get();

      if (myBusinesses.isEmpty) {
        throw StateError(
          'Your business membership was found in the cloud, '
          'but the business record could not be loaded.',
        );
      }

      return myBusinesses;
    }

    // ==========================================================
    // NO CLOUD BUSINESS
    // ==========================================================

    final authUser = client.auth.currentUser;

    final prefs = await SharedPreferences.getInstance();

    final inviteKey = pendingInviteKey(authUser?.email ?? '');

    final pendingCode = prefs.getString(inviteKey);

    if (pendingCode != null && pendingCode.isNotEmpty) {
      debugPrint('[business] redeeming saved invite code');

      try {
        await ref
            .read(cloudBusinessServiceProvider)
            .redeemInviteCode(pendingCode);

        await prefs.remove(inviteKey);
      } on CloudBusinessException catch (e) {
        if (e.code == 'database_error') {
          await prefs.remove(inviteKey);
        }

        rethrow;
      } finally {
        await prefs.remove(inviteKey);
      }

      return _initializeCloudBusiness(db, client, userId);
    }

    final intentKey = createBusinessIntentKey(authUser?.email ?? '');
    final wantsOwnBusiness = prefs.getBool(intentKey) ?? false;

    if (!_allowCreateFirstBusiness && !wantsOwnBusiness) {
      throw const _NoBusinessYet();
    }

    debugPrint('[business] creating first cloud business');

    final newId = await _createFirstBusiness(db, userId);
    await prefs.remove(intentKey);

    final created = await (db.select(
      db.businesses,
    )..where((b) => b.id.equals(newId))).get();

    if (created.isEmpty) {
      throw StateError(
        'The new business was created but could not be loaded locally.',
      );
    }

    return created;
  }

  // ============================================================
  // MAIN STARTUP
  // ============================================================

  Future<BusinessesData> _ensureBusinessExists() async {
    final db = ref.read(databaseProvider);

    final cloudEnabled = ref.read(supabaseAvailableProvider);

    // ------------------------------------------------------------
    // CLOUD SESSION
    // ------------------------------------------------------------

    if (cloudEnabled) {
      final client = ref.read(supabaseClientProvider);

      final authUser = client.auth.currentUser;

      debugPrint('[business] Supabase current user = ${authUser?.id}');

      debugPrint('[business] Supabase current email = ${authUser?.email}');

      if (authUser == null) {
        throw StateError('Signed out during startup.');
      }

      final userId = authUser.id;

      // ----------------------------------------------------------
      // FIRST: USE THE LOCAL AUTHORIZATION CACHE
      //
      // If the server previously told us this device was revoked,
      // do not grant access even while offline.
      //
      // If there is no cached decision yet, legacy installations
      // can still use their existing local business.
      // ----------------------------------------------------------

      await _throwIfLocallyRevoked(userId);

      // ----------------------------------------------------------
      // FIRST: LOOK FOR LOCAL BUSINESS
      //
      // This is what makes an already-configured BOS installation
      // genuinely usable without internet.
      // ----------------------------------------------------------

      final localBusinesses = await _findLocalBusinessesForUser(db, userId);

      if (localBusinesses.isNotEmpty) {
        debugPrint(
          '[offline] local business found; '
          'startup does not require Supabase',
        );

        final current = await _selectCurrentBusiness(db, localBusinesses);

        // Cloud verification/reconciliation happens AFTER local
        // startup. It must never block this path.
        unawaited(
          _reconcileCloudState(
            db: db,
            userId: userId,
            currentBusinessId: current.id,
          ),
        );

        ref.read(authenticatedUserIdProvider.notifier).state = userId;

        await _repairTextTimestamps(db);
        unawaited(
          repairBranchTransfers(
            db,
          ).then((_) => ref.read(syncTriggerServiceProvider).syncNow()),
        );

        if (current.ownerUserId == userId) {
          unawaited(_backfillCashiers(db, userId));
        }

        // debugPrint(
        //   '[business] selected offline-capable business '
        //   'id=${current.id}',
        // );

        debugPrint('[business] business name=${current.name}');

        return current;
      }

      // ----------------------------------------------------------
      // NO LOCAL BUSINESS
      //
      // Therefore this is a first-time / not-yet-downloaded
      // installation. Cloud initialization is required.
      // ----------------------------------------------------------

      final myBusinesses = await _initializeCloudBusiness(db, client, userId);

      ref.read(authenticatedUserIdProvider.notifier).state = userId;

      final current = await _selectCurrentBusiness(db, myBusinesses);

      // Initial cloud load succeeded. Any bootstrap/profile work
      // is now safely background work.
      unawaited(
        _reconcileCloudState(
          db: db,
          userId: userId,
          currentBusinessId: current.id,
        ),
      );

      debugPrint('[business] selected business = ${current.id}');

      debugPrint('[business] business name = ${current.name}');

      return current;
    }

    // ------------------------------------------------------------
    // LOCAL-ONLY MODE
    // ------------------------------------------------------------

    final userId = ref.read(authenticatedUserIdProvider);

    debugPrint('[auth] local user id = $userId');

    if (userId == null) {
      throw StateError('Signed out during startup.');
    }

    var myBusinesses = await _findLocalBusinessesForUser(db, userId);

    if (myBusinesses.isEmpty) {
      final newId = await _createFirstBusiness(db, userId);

      myBusinesses = await (db.select(
        db.businesses,
      )..where((b) => b.id.equals(newId))).get();
    }

    return _selectCurrentBusiness(db, myBusinesses);
  }

  /// One-time repair: stamps old sales that have no cashier with the owner.
  /// Runs once per account on this device.
  Future<void> _backfillCashiers(AppDatabase db, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'cashier_backfill_v1:$userId';
      if (prefs.getBool(key) ?? false) return;

      final user = await (db.select(
        db.users,
      )..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (user == null) return;

      final name = user.displayName.trim().isNotEmpty
          ? user.displayName.trim()
          : user.email;

      await db.customStatement(
        'UPDATE pos_sales SET cashier_user_id = ?, cashier_name = ? '
        "WHERE cashier_user_id IS NULL AND (cashier_name IS NULL OR cashier_name = '')",
        [userId, name],
      );

      await prefs.setBool(key, true);
      debugPrint('[backfill] cashier stamped on old sales');
    } catch (e) {
      debugPrint('[backfill] cashier backfill skipped: $e');
    }
  }

  /// One-time repair: ISO date strings that an earlier pull wrote into
  /// INTEGER columns are converted back to Unix seconds.
  Future<void> _repairTextTimestamps(AppDatabase db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const flag = 'ts_repair_v1';
      if (prefs.getBool(flag) ?? false) return;

      await SyncChangeLog.suppressed(db, () async {
        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'sync_%'",
            )
            .get();

        for (final t in tables) {
          final table = t.read<String>('name');
          final cols = await db
              .customSelect('PRAGMA table_info("$table")')
              .get();
          for (final c in cols) {
            final col = c.read<String>('name');
            if (c.read<String>('type').toUpperCase() != 'INTEGER') continue;
            const test =
                "typeof(\"COL\") = 'text' AND \"COL\" LIKE '____-__-__%'";
            final where = test.replaceAll('COL', col);
            final bad = await db
                .customSelect('SELECT COUNT(*) AS n FROM "$table" WHERE $where')
                .getSingle();
            final n = bad.read<int>('n');
            if (n == 0) continue;
            debugPrint('[repair] $table.$col: $n rows');
            await db.customStatement(
              'UPDATE "$table" SET "$col" = '
              "CAST(strftime('%s', \"$col\") AS INTEGER) WHERE $where",
            );
          }
        }
      });

      await prefs.setBool(flag, true);
    } catch (e) {
      debugPrint('[repair] timestamp repair skipped: $e');
    }
  }

  void _reloadStartup() {
    if (!mounted) return;

    setState(() {
      _initFuture = _ensureBusinessExists();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BusinessesData>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingScreen();
        }

        if (snapshot.hasError) {
          if (snapshot.error is DeviceAuthorizationException) {
            return _DeviceAuthorizationScreen(
              error: snapshot.error as DeviceAuthorizationException,
              onRetry: _reloadStartup,
            );
          }

          if (snapshot.error is _NoBusinessYet) {
            return _JoinOrCreateScreen(
              onCreate: () {
                _allowCreateFirstBusiness = true;
                _reloadStartup();
              },
              onJoined: _reloadStartup,
            );
          }

          return _StartupErrorScreen(
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
          return _EmployeeProfileGate(
            key: ValueKey('emp-profile-${business.id}'),
            business: business,
          );
        }

        return const _AccessGate();
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LogoTile(size: 140, logoHeight: 92, radius: 36),
              const SizedBox(height: 28),
              Text(
                AppStrings.appName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.appFullName,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Preparing your business…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(height: 40),
                    const SizedBox(height: 20),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: scheme.error,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${AppStrings.appName} couldn\'t start',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The local database could not be prepared. '
                      'Try again, or restart the app if this keeps happening.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        '$error',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
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

class _DeviceAuthorizationScreen extends ConsumerStatefulWidget {
  const _DeviceAuthorizationScreen({
    required this.error,
    required this.onRetry,
  });

  final DeviceAuthorizationException error;
  final VoidCallback onRetry;

  @override
  ConsumerState<_DeviceAuthorizationScreen> createState() =>
      _DeviceAuthorizationScreenState();
}

class _DeviceAuthorizationScreenState
    extends ConsumerState<_DeviceAuthorizationScreen> {
  bool _working = false;

  Future<void> _reactivate() async {
    setState(() => _working = true);
    try {
      await ref.read(deviceManagementServiceProvider).reactivateCurrentDevice();
      if (!mounted) return;
      ref.invalidate(currentDeviceRegistrationProvider);
      widget.onRetry();
    } on DeviceManagementException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not reactivate this device (${error.runtimeType}).',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _working = true);
    try {
      await ref
          .read(cloudAuthServiceProvider)
          .signOutWithScope(SignOutScope.local);
      await SessionStore.clear();
      SyncTracker.currentUserId = null;
      ref.read(authenticatedUserIdProvider.notifier).state = null;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sign out: ${error.runtimeType}.')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phonelink_erase_outlined,
                      color: scheme.error,
                      size: 44,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This device needs authorization',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(widget.error.message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    const Text(
                      'No local business data or pending synchronization '
                      'changes have been deleted.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (widget.error.status == 'revoked' &&
                        !widget.error.requiresFreshLogin)
                      FilledButton(
                        onPressed: _working ? null : _reactivate,
                        child: _working
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Reactivate this device'),
                      ),
                    TextButton(
                      onPressed: _working ? null : _signOut,
                      child: const Text('Sign out and sign in again'),
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

/// Shows the employee profile form once (per business) before the app opens.
class _EmployeeProfileGate extends ConsumerStatefulWidget {
  const _EmployeeProfileGate({super.key, required this.business});

  final BusinessesData business;

  @override
  ConsumerState<_EmployeeProfileGate> createState() =>
      _EmployeeProfileGateState();
}

class _EmployeeProfileGateState extends ConsumerState<_EmployeeProfileGate> {
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
    if (_done) return const _AccessGate();

    return FutureBuilder<bool>(
      future: _needsProfile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingScreen();
        }
        if (snapshot.data == true) {
          return EmployeeOnboardingScreen(
            businessId: widget.business.id,
            businessName: widget.business.name,
            onFinished: () => setState(() => _done = true),
          );
        }
        return const _AccessGate();
      },
    );
  }
}

/// Signs this device out the moment the server revokes its session.
final _deviceSessionWatcherProvider =
    Provider.autoDispose<DeviceSessionWatcher>((ref) {
      // Capture everything now: signing out unmounts the gate, which disposes
      // this provider, so `ref` can't be used after the awaits below.
      final client = ref.watch(supabaseClientProvider);
      final cloudAuth = ref.read(cloudAuthServiceProvider);
      final sessionNotifier = ref.read(authenticatedUserIdProvider.notifier);

      final watcher = DeviceSessionWatcher(
        client: client,
        onRevoked: () async {
          try {
            await cloudAuth.signOutWithScope(SignOutScope.local);
          } on Object catch (error) {
            debugPrint('[device] local sign-out failed (${error.runtimeType})');
          }
          await SessionStore.clear();
          SyncTracker.currentUserId = null;
          sessionNotifier.state = null; // _AuthGate then shows the login screen
        },
      );
      ref.onDispose(watcher.dispose);
      watcher.start();
      return watcher;
    });

/// Waits for the membership to resolve, then opens the shell. The shell is
/// KEYED by business + user + role, so switching business or changing role
/// rebuilds it from scratch and no page state (or cached data) from the
/// previous business can leak into the next one.
class _AccessGate extends ConsumerWidget {
  const _AccessGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseAvailableProvider)) {
      ref.watch(_deviceSessionWatcherProvider); // keeps the watcher alive
    }
    final membership = ref.watch(currentBusinessMembershipProvider);

    // The listener wraps BOTH the shell and the "no access" screen, so the
    // removed-access dialog survives the swap between them.
    return AccessRevokedListener(
      child: membership.when(
        loading: () => const _StartupLoadingScreen(),
        error: (e, _) => _StartupErrorScreen(
          error: e,
          onRetry: () => ref.invalidate(currentBusinessMembershipProvider),
        ),
        data: (m) {
          final custom = m != null && m.role.startsWith(kCustomRolePrefix);
          if (m == null || (!custom && BosRole.fromId(m.role) == null)) {
            return _NoAccessScreen(
              onRetry: () => ref.invalidate(currentBusinessMembershipProvider),
            );
          }
          ref.read(syncTriggerServiceProvider).start();
          if (ref.read(supabaseAvailableProvider)) {
            ref.read(deviceSessionWatcherProvider);
          }
          ref.watch(stockProjectionProvider);
          // A custom role's definition arrives with the first sync.
          if (ref.watch(currentRoleProvider) == null) {
            return const _StartupLoadingScreen();
          }
          final assignments = ref.watch(branchMembershipsProvider);
          if (assignments.isLoading && !assignments.hasValue) {
            return const _StartupLoadingScreen();
          }
          return NavigationShell(
            key: ValueKey(
              '${m.businessId}:${ref.watch(selectedBranchIdProvider)}:'
              '${m.userId}:${m.role}',
            ),
          );
        },
      ),
    );
  }
}

class _NoAccessScreen extends ConsumerStatefulWidget {
  const _NoAccessScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  ConsumerState<_NoAccessScreen> createState() => _NoAccessScreenState();
}

class _NoAccessScreenState extends ConsumerState<_NoAccessScreen> {
  bool _busy = false;

  /// Pulls fresh memberships from the cloud, then opens the best active
  /// business ([prefer] first) as the current one.
  Future<void> _adoptAndSwitch({String? prefer}) async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) {
      throw StateError('You are signed out. Please sign in again.');
    }
    final db = ref.read(databaseProvider);
    final result = await adoptCloudAccess(
      db,
      ref.read(supabaseClientProvider),
      userId: userId,
    );

    final rows = await db
        .customSelect(
          'SELECT b.id FROM businesses b '
          'JOIN business_members m ON m.business_id = b.id '
          "WHERE m.user_id = ? AND m.status = 'active' AND b.is_active = 1 "
          'ORDER BY (b.id = ?) DESC, b.name LIMIT 1',
          variables: [
            Variable.withString(userId),
            Variable.withString(prefer ?? result.firstAdded ?? ''),
          ],
        )
        .get();
    if (rows.isEmpty) {
      throw StateError('Couldn\'t open your business yet. Please try again.');
    }
    await ref
        .read(syncTriggerServiceProvider)
        .switchToBusiness(rows.first.read<String>('id'));
    ref.invalidate(currentBusinessMembershipProvider);
  }

  Future<void> _joinWithCode() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _NoAccessInputDialog(
        title: 'Enter invite code',
        label: 'Invite code',
        hint: 'The 8-character code you were given',
        actionLabel: 'Join business',
        capitalization: TextCapitalization.characters,
        onSubmit: (code) async {
          await ref.read(cloudBusinessServiceProvider).redeemInviteCode(code);
          await _adoptAndSwitch();
        },
      ),
    );
  }

  Future<void> _createBusiness() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _NoAccessInputDialog(
        title: 'Create a business',
        label: 'Business name',
        hint: 'e.g. Maria\'s Bakery',
        actionLabel: 'Create business',
        capitalization: TextCapitalization.words,
        onSubmit: (name) async {
          final id = await ref
              .read(cloudBusinessServiceProvider)
              .createBusiness(name: name);
          await _adoptAndSwitch(prefer: id);
        },
      ),
    );
  }

  /// Cancel: switch to another business if there is one, otherwise sign out.
  Future<void> _cancel() async {
    final userId = ref.read(authenticatedUserIdProvider);
    final removedId = ref.read(selectedBusinessIdProvider);
    final sync = ref.read(syncTriggerServiceProvider);

    setState(() => _busy = true);
    var moved = false;
    try {
      if (userId != null) {
        moved = await sync.moveOffRemovedBusiness(userId, removedId);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!moved && mounted) await _confirmSignOut(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: scheme.error),
                const SizedBox(height: 16),
                Text(
                  'No access to this business',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account isn\'t an active member of this business, or '
                  'your access was removed or suspended. You can join '
                  'another business, start your own, or go back.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _joinWithCode,
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: const Text('Enter invite code'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _createBusiness,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Create a business'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check again'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancel'),
                ),
                Text(
                  'Cancel switches you to another business, or signs you out '
                  'if you don\'t have one.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoAccessInputDialog extends StatefulWidget {
  const _NoAccessInputDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.actionLabel,
    required this.capitalization,
    required this.onSubmit,
  });

  final String title;
  final String label;
  final String hint;
  final String actionLabel;
  final TextCapitalization capitalization;
  final Future<void> Function(String value) onSubmit;

  @override
  State<_NoAccessInputDialog> createState() => _NoAccessInputDialogState();
}

class _NoAccessInputDialogState extends State<_NoAccessInputDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(value);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError ? e.message : e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        textCapitalization: widget.capitalization,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : Text(widget.actionLabel),
        ),
      ],
    );
  }
}
// ============================================================
// NAVIGATION MODEL — single source of truth
// ============================================================

class Breakpoints {
  static const double compact = 600;
  static const double medium = 840;

  /// Page content is centred and capped at this width on very wide screens.
  static const double maxContent = 1400;
}

/// The top-level business modules. Order = order in the rail and drawer.
enum BosModule {
  management,
  salesPos,
  finance,
  inventory,
  people,
  administration,
}

/// How modules are classified in the rail, drawer and phone menu.
enum BosGroup { operate, moneyStock, teamSetup }

extension BosGroupLabel on BosGroup {
  String get label => switch (this) {
    BosGroup.operate => 'Operate',
    BosGroup.moneyStock => 'Money & stock',
    BosGroup.teamSetup => 'Team & setup',
  };
}

/// How a destination is shown.
enum BosPresentation {
  /// Inside the shell, under the app bar (how every screen used to open).
  embedded,

  /// Pushed full-screen, for pages that were built as stand-alone routes.
  route,
}

/// Stable identifiers for every destination. Use these, never raw strings.
abstract final class BosDest {
  // Management
  static const dashboard = 'management.dashboard';

  // Finance
  static const journal = 'finance.journal';
  static const cashflow = 'finance.cashflow';
  static const reports = 'finance.reports';
  static const aging = 'finance.aging';
  static const income = 'finance.income';
  static const expenses = 'finance.expenses';
  static const receivables = 'finance.receivables';
  static const payables = 'finance.payables';
  static const transfers = 'finance.transfers';

  // Inventory
  static const supplies = 'inventory.supplies';
  static const inventoryReport = 'inventory.report';
  static const products = 'inventory.products';
  static const suppliers = 'inventory.suppliers';
  static const purchaseCart = 'inventory.cart';
  static const purchaseHistory = 'inventory.purchaseHistory';
  static const stockAdjustments = 'inventory.adjustments';
  static const stockTransfers = 'inventory.transfers';

  // Sales & POS
  static const pos = 'sales.pos';
  static const customers = 'sales.customers';
  static const sales = 'sales.sales';
  static const orders = 'sales.orders';
  static const returns = 'sales.returns';
  static const storefront = 'sales.storefront';

  // People
  static const employees = 'people.employees';
  static const attendance = 'people.attendance';
  static const schedules = 'people.schedules';
  static const leave = 'people.leave';
  static const payroll = 'people.payroll';

  // Administration
  static const settings = 'admin.settings';
  static const profile = 'admin.profile';
  static const usersRoles = 'admin.usersRoles';
  static const permissions = 'admin.permissions';
  static const chartOfAccounts = 'admin.chartOfAccounts';
  static const categories = 'admin.categories';
  static const security = 'admin.security';
  static const importExport = 'admin.importExport';
  static const auditTrail = 'admin.auditTrail';
  static const branches = 'admin.branches';
}

class BosModuleInfo {
  const BosModuleInfo({
    required this.module,
    required this.group,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.icon,
    required this.selectedIcon,
    this.homeId,
  });

  final BosModule module;
  final BosGroup group;
  final String label;

  /// Used where space is tight (bottom bar, compact rail).
  final String shortLabel;
  final String description;
  final IconData icon;
  final IconData selectedIcon;

  /// When set, opening the module goes straight to this destination instead
  /// of a landing page (Management → Dashboard).
  final String? homeId;
}

class BosDestination {
  BosDestination({
    required this.id,
    required this.module,
    required this.label,
    required this.description,
    required this.icon,
    this.builder,
    this.presentation = BosPresentation.embedded,
  }) : assert(
         presentation == BosPresentation.embedded || builder != null,
         'A route destination needs a builder.',
       );

  final String id;
  final BosModule module;
  final String label;
  final String description;
  final IconData icon;

  /// Null means "coming soon" — a placeholder is shown instead of a screen.
  final WidgetBuilder? builder;
  final BosPresentation presentation;

  bool get isAvailable => builder != null;
}

final List<BosModuleInfo> bosModules = [
  const BosModuleInfo(
    module: BosModule.management,
    group: BosGroup.operate,
    label: 'Management',
    shortLabel: 'Manage',
    description: 'Your business command center.',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
    homeId: BosDest.dashboard,
  ),
  const BosModuleInfo(
    module: BosModule.salesPos,
    group: BosGroup.operate,
    label: 'Sales & POS',
    shortLabel: 'Sales',
    description: 'Sell to customers and keep track of who they are.',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale_rounded,
  ),
  const BosModuleInfo(
    module: BosModule.finance,
    group: BosGroup.moneyStock,
    label: 'Finance',
    shortLabel: 'Finance',
    description: 'Record money in and out, and see where you stand.',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
  ),
  const BosModuleInfo(
    module: BosModule.inventory,
    group: BosGroup.moneyStock,
    label: 'Inventory',
    shortLabel: 'Inventory',
    description: 'Supplies, purchasing, stock levels and costing.',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
  ),
  const BosModuleInfo(
    module: BosModule.people,
    group: BosGroup.teamSetup,
    label: 'People',
    shortLabel: 'People',
    description: 'Your team: employees, schedules and payroll.',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups_rounded,
  ),
  const BosModuleInfo(
    module: BosModule.administration,
    group: BosGroup.teamSetup,
    label: 'Administration',
    shortLabel: 'Admin',
    description: 'Business settings, profile, access and security.',
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings_rounded,
  ),
];

/// Every screen, in the order it appears on its module's landing page.
/// A destination without a `builder` is a "coming soon" placeholder.
final List<BosDestination> bosDestinations = [
  // ---- Management ----
  BosDestination(
    id: BosDest.dashboard,
    module: BosModule.management,
    label: 'Dashboard',
    description: 'Business summary, alerts and quick actions.',
    icon: Icons.dashboard_outlined,
    builder: (_) => const DashboardPage(),
  ),

  // ---- Finance ----
  BosDestination(
    id: BosDest.journal,
    module: BosModule.finance,
    label: 'Journal Entry',
    description: 'Record and review transactions.',
    icon: Icons.receipt_long_outlined,
    builder: (_) => const JournalEntryPage(),
  ),
  BosDestination(
    id: BosDest.cashflow,
    module: BosModule.finance,
    label: 'Accounts',
    description: 'Your cash, bank and e-wallet accounts.',
    icon: Icons.account_balance_wallet_outlined,
    builder: (_) => const CashflowPage(),
  ),
  BosDestination(
    id: BosDest.reports,
    module: BosModule.finance,
    label: 'Financial Reports',
    description: 'Profit, balance and performance reports.',
    icon: Icons.bar_chart_outlined,
    builder: (_) => const FinancialReportsPage(),
  ),
  BosDestination(
    id: BosDest.aging,
    module: BosModule.finance,
    label: 'Aging report',
    description: 'How long balances have been outstanding.',
    icon: Icons.schedule_outlined,
    builder: (_) => const AgingReportPage(),
  ),
  BosDestination(
    id: BosDest.income,
    module: BosModule.finance,
    label: 'Income',
    description: 'Everything your business earns.',
    icon: Icons.trending_up_rounded,
    builder: (_) => const IncomePage(),
  ),
  BosDestination(
    id: BosDest.expenses,
    module: BosModule.finance,
    label: 'Expenses',
    description: 'Everything your business spends.',
    icon: Icons.trending_down_rounded,
    builder: (_) => const ExpensesPage(),
  ),
  BosDestination(
    id: BosDest.receivables,
    module: BosModule.finance,
    label: 'Receivables',
    description: 'Money customers still owe you.',
    icon: Icons.request_quote_outlined,
    builder: (_) => const ReceivablesPage(),
  ),
  BosDestination(
    id: BosDest.payables,
    module: BosModule.finance,
    label: 'Payables',
    description: 'Money you still owe suppliers.',
    icon: Icons.payments_outlined,
    builder: (_) => const PayablesPage(),
  ),
  BosDestination(
    id: BosDest.transfers,
    module: BosModule.finance,
    label: 'Transfers',
    description: 'Move money between your accounts.',
    icon: Icons.swap_horiz_rounded,
    builder: (_) => const TransfersPage(),
  ),

  // ---- Inventory ----
  BosDestination(
    id: BosDest.supplies,
    module: BosModule.inventory,
    label: 'Supplies',
    description: 'Price list, purchasing and shopping cart.',
    icon: Icons.shopping_cart_outlined,
    builder: (_) => const SuppliesPriceListPage(),
  ),
  BosDestination(
    id: BosDest.inventoryReport,
    module: BosModule.inventory,
    label: 'Inventory Report',
    description: 'Stock value, movements and reorder list.',
    icon: Icons.assessment_outlined,
    builder: (_) => const InventoryReportPage(),
  ),
  BosDestination(
    id: BosDest.products,
    module: BosModule.inventory,
    label: 'Products & Recipes',
    description: 'Recipes, costing and what you can make.',
    icon: Icons.restaurant_menu_outlined,
    builder: (_) => const ProductsPage(),
  ),
  BosDestination(
    id: BosDest.stockTransfers,
    module: BosModule.inventory,
    label: 'Stock Transfers',
    description: 'Send stock to another branch.',
    icon: Icons.local_shipping_outlined,
    builder: (_) => const StockTransfersPage(),
  ),
  BosDestination(
    id: BosDest.suppliers,
    module: BosModule.inventory,
    label: 'Suppliers',
    description: 'Who you buy from.',
    icon: Icons.local_shipping_outlined,
    builder: (_) => const SuppliersPage(),
  ),
  BosDestination(
    id: BosDest.purchaseCart,
    module: BosModule.inventory,
    label: 'Purchase Cart',
    description: 'Review items before you buy.',
    icon: Icons.shopping_basket_outlined,
    presentation: BosPresentation.route,
    builder: (_) => const CartPage(),
  ),
  BosDestination(
    id: BosDest.purchaseHistory,
    module: BosModule.inventory,
    label: 'Purchase History',
    description: 'Past purchases from your suppliers.',
    icon: Icons.history_rounded,
    presentation: BosPresentation.route,
    builder: (_) => const PurchaseHistoryPage(),
  ),
  BosDestination(
    id: BosDest.stockAdjustments,
    module: BosModule.inventory,
    label: 'Stock Adjustments',
    description: 'Corrections, waste and write-offs.',
    icon: Icons.tune_rounded,
    presentation: BosPresentation.route,
    builder: (_) => const AllStockAdjustmentsPage(),
  ),

  // ---- Sales & POS ----
  BosDestination(
    id: BosDest.pos,
    module: BosModule.salesPos,
    label: 'Point of Sale',
    description: 'Ring up customer orders.',
    icon: Icons.point_of_sale_outlined,
    builder: (_) => const POSPage(),
  ),
  BosDestination(
    id: BosDest.customers,
    module: BosModule.salesPos,
    label: 'Customers',
    description: 'Your customer list and their details.',
    icon: Icons.people_outline_rounded,
    builder: (_) => const CustomersPage(),
  ),
  BosDestination(
    id: BosDest.sales,
    module: BosModule.salesPos,
    label: 'Sales',
    description: 'Sales history and performance.',
    icon: Icons.receipt_outlined,
    builder: (_) => const SalesPage(),
  ),
  BosDestination(
    id: BosDest.storefront,
    module: BosModule.salesPos,
    label: 'Storefront',
    description: 'Manage online storefront settings and customer orders.',
    icon: Icons.storefront_outlined,
    builder: (_) => const CustomerStorefrontManagementScreen(),
  ),
  BosDestination(
    id: BosDest.orders,
    module: BosModule.salesPos,
    label: 'Orders',
    description: 'Customer orders from start to finish.',
    icon: Icons.list_alt_rounded,
    builder: (_) => const OrdersPage(),
  ),
  BosDestination(
    id: BosDest.returns,
    module: BosModule.salesPos,
    label: 'Returns',
    description: 'Refunds and returned items.',
    icon: Icons.assignment_return_outlined,
    builder: (_) => const ReturnsPage(),
  ),
  // ---- People ----
  BosDestination(
    id: BosDest.employees,
    module: BosModule.people,
    label: 'Employees',
    description: 'Your team and their details.',
    icon: Icons.badge_outlined,
    builder: (_) => const EmployeesScreen(),
  ),
  BosDestination(
    id: BosDest.attendance,
    module: BosModule.people,
    label: 'Attendance',
    description: 'Who worked and when.',
    icon: Icons.event_available_outlined,
    builder: (_) => const AttendanceScreen(),
  ),
  BosDestination(
    id: BosDest.schedules,
    module: BosModule.people,
    label: 'Schedules',
    description: 'Plan shifts and days off.',
    icon: Icons.calendar_month_outlined,
    builder: (_) => const SchedulesScreen(),
  ),
  BosDestination(
    id: BosDest.leave,
    module: BosModule.people,
    label: 'Leave',
    description: 'Leave requests and balances.',
    icon: Icons.beach_access_outlined,
    builder: (_) => const LeaveScreen(),
  ),
  BosDestination(
    id: BosDest.payroll,
    module: BosModule.people,
    label: 'Payroll',
    description: 'Pay your team accurately and on time.',
    icon: Icons.payments_outlined,
    builder: (_) => const PayrollScreen(),
  ),
  // ---- Administration ----
  BosDestination(
    id: BosDest.profile,
    module: BosModule.administration,
    label: 'Profile',
    description: 'Your details, workplace and account security.',
    icon: Icons.person_outline_rounded,
    builder: (_) => const ProfileScreen(),
  ),
  BosDestination(
    id: BosDest.settings,
    module: BosModule.administration,
    label: 'Business Settings',
    description: 'Preferences for how your business runs.',
    icon: Icons.settings_outlined,
    builder: (_) => const SettingsScreen(),
  ),
  BosDestination(
    id: BosDest.usersRoles,
    module: BosModule.administration,
    label: 'Users & Roles',
    description: 'Who can sign in, and as what.',
    icon: Icons.manage_accounts_outlined,
    builder: (_) => const UsersRolesScreen(),
  ),
  BosDestination(
    id: BosDest.permissions,
    module: BosModule.administration,
    label: 'Permissions',
    description: 'Control what each role can do.',
    icon: Icons.verified_user_outlined,
    builder: (_) => const PermissionsScreen(),
  ),
  BosDestination(
    id: BosDest.chartOfAccounts,
    module: BosModule.administration,
    label: 'Chart of Accounts',
    description: 'The accounts your books are built on.',
    icon: Icons.account_tree_outlined,
    builder: (_) => const ChartOfAccountsPage(),
  ),
  BosDestination(
    id: BosDest.categories,
    module: BosModule.administration,
    label: 'Categories',
    description: 'Organize income, expenses and products.',
    icon: Icons.category_outlined,
    builder: (_) => const CategoriesPage(),
  ),
  BosDestination(
    id: BosDest.security,
    module: BosModule.administration,
    label: 'Security',
    description: 'Passcodes, backups and access safety.',
    icon: Icons.security_outlined,
    builder: (_) => const SecurityScreen(),
  ),
  BosDestination(
    id: BosDest.importExport,
    module: BosModule.administration,
    label: 'Import / Export',
    description: 'Bring data in, or take a copy out.',
    icon: Icons.import_export_rounded,
    builder: (_) => const ImportExportPage(),
  ),
  BosDestination(
    id: BosDest.auditTrail,
    module: BosModule.administration,
    label: 'Audit Trail',
    description: 'Who changed what, when and why.',
    icon: Icons.fact_check_outlined,
    builder: (_) => const AuditTrailScreen(),
  ),
  BosDestination(
    id: BosDest.branches,
    module: BosModule.administration,
    label: 'Branches',
    description: 'Locations, staff and cash drawers.',
    icon: Icons.store_mall_directory_outlined,
    builder: (_) => const BranchesScreen(),
  ),
];

// ---- Lookups derived from the registry above ----

final Map<BosModule, BosModuleInfo> _moduleInfo = {
  for (final m in bosModules) m.module: m,
};

final Map<String, BosDestination> _destById = {
  for (final d in bosDestinations) d.id: d,
};

List<BosDestination> _destinationsOf(BosModule module) =>
    bosDestinations.where((d) => d.module == module).toList();

/// Pages listed in a module's rail group, bar and quick switcher.
List<BosDestination> _availableIn(BosModule module) =>
    _destinationsOf(module).where((d) => d.isAvailable).toList();

String _hubKey(BosModule module) => 'hub.${module.name}';

/// Everything that lives in the shell's IndexedStack: a landing page per
/// module without a `homeId`, plus every embedded destination.
final List<String> _viewKeys = [
  for (final info in bosModules) ...[
    if (info.homeId == null) _hubKey(info.module),
    for (final d in _destinationsOf(info.module))
      if (d.presentation == BosPresentation.embedded) d.id,
  ],
];

/// Modules pinned beside the phone's centre menu button. Every other module
/// opens from the floating menu.
const List<BosModule> _phoneBarModules = [
  BosModule.management,
  BosModule.salesPos,
  BosModule.finance,
  BosModule.inventory,
];

/// Visible modules bucketed by classification, in BosGroup order.
Map<BosGroup, List<BosModuleInfo>> _grouped(List<BosModuleInfo> infos) => {
  for (final g in BosGroup.values)
    if (infos.any((i) => i.group == g))
      g: [
        for (final i in infos)
          if (i.group == g) i,
      ],
};

/// In the wide rail, Administration is hidden when Profile is the only page
/// the person can open there (Profile already lives at the rail's bottom).
bool _profileOnly(AuthorizationService auth, BosModuleInfo info) {
  if (info.module != BosModule.administration) return false;
  return _visibleDestinations(
    auth,
    info.module,
  ).every((d) => d.id == BosDest.profile);
}

/// Account shortcuts shown under "More" / in the drawer. They open pages that
/// belong to Administration.
const List<String> _accountShortcuts = [BosDest.profile, BosDest.settings];

/// Permission required to OPEN each destination. Missing => owner-only.
const Map<String, BosPermission> _destPermission = {
  BosDest.dashboard: BosPermission.dashboardView,

  // BosDest.myProfile: BosPermission.dashboardView,
  // BosDest.mySecurity: BosPermission.dashboardView,
  BosDest.journal: BosPermission.financeView,
  BosDest.cashflow: BosPermission.financeView,
  BosDest.reports: BosPermission.reportsView,
  BosDest.aging: BosPermission.reportsView,
  BosDest.income: BosPermission.financeView,
  BosDest.expenses: BosPermission.financeView,
  BosDest.receivables: BosPermission.receivablesView,
  BosDest.payables: BosPermission.payablesView,
  BosDest.transfers: BosPermission.financeView,

  BosDest.supplies: BosPermission.inventoryView,
  BosDest.inventoryReport: BosPermission.inventoryView,
  BosDest.products: BosPermission.inventoryView,
  BosDest.suppliers: BosPermission.suppliersView,
  BosDest.purchaseCart: BosPermission.purchasingView,
  BosDest.purchaseHistory: BosPermission.purchasingView,
  BosDest.stockAdjustments: BosPermission.inventoryView,

  BosDest.pos: BosPermission.salesView,
  BosDest.storefront: BosPermission.salesView,
  BosDest.customers: BosPermission.customersView,
  BosDest.sales: BosPermission.salesView,
  BosDest.orders: BosPermission.salesView,
  BosDest.returns: BosPermission.salesView,

  BosDest.employees: BosPermission.employeesView,
  BosDest.attendance: BosPermission.hrSelf,
  BosDest.schedules: BosPermission.hrSelf,
  BosDest.leave: BosPermission.hrSelf,
  BosDest.payroll: BosPermission.employeesManage,

  BosDest.settings: BosPermission.businessSettings,
  //BosDest.profile: BosPermission.businessSettings,
  BosDest.usersRoles: BosPermission.usersView,
  BosDest.permissions: BosPermission.securityManage,
  BosDest.chartOfAccounts: BosPermission.financeEdit,
  BosDest.categories: BosPermission.financeEdit,
  BosDest.security: BosPermission.securityManage,
  BosDest.importExport: BosPermission.businessManage,
  BosDest.branches: BosPermission.branchManage,
  BosDest.stockTransfers: BosPermission.stockTransferCreate,
};

bool _canOpen(AuthorizationService auth, String destinationId) {
  // Profile is self-service: every active member, whatever their role.
  if (destinationId == BosDest.profile) return auth.currentRole != null;
  // Transfers page: sending OR receiving is enough to open it.
  if (destinationId == BosDest.stockTransfers) {
    return auth.can(BosPermission.stockTransferCreate) ||
        auth.can(BosPermission.stockTransferReceive);
  }
  return auth.can(
    _destPermission[destinationId] ?? BosPermission.businessManage,
  );
}

List<BosDestination> _visibleDestinations(
  AuthorizationService auth,
  BosModule module,
) => _destinationsOf(module).where((d) => _canOpen(auth, d.id)).toList();

List<BosDestination> _visibleAvailable(
  AuthorizationService auth,
  BosModule module,
) => _availableIn(module).where((d) => _canOpen(auth, d.id)).toList();

bool _moduleVisible(AuthorizationService auth, BosModule module) {
  final info = _moduleInfo[module]!;
  final home = info.homeId;
  if (home != null) return _canOpen(auth, home);
  return _visibleDestinations(auth, module).isNotEmpty;
}

/// Per-business module switch, layered on top of role visibility.
/// Administration always stays on (it hosts the toggles themselves).
bool _moduleEnabled(Map<String, bool> configs, BosModule module) =>
    module == BosModule.administration || (configs[module.name] ?? true);

List<BosModuleInfo> _visibleModules(
  AuthorizationService auth, [
  Map<String, bool> moduleConfigs = const {},
]) => bosModules
    .where(
      (m) =>
          _moduleEnabled(moduleConfigs, m.module) &&
          _moduleVisible(auth, m.module),
    )
    .toList();

// ============================================================
// NAVIGATION SHELL
// ============================================================

class NavigationShell extends ConsumerStatefulWidget {
  const NavigationShell({super.key});

  @override
  ConsumerState<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<NavigationShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Single place that changes the open page. Any open slide-over drawer
  /// closes when you pick a destination.
  void _go(BosModule module, String? destinationId) {
    ref.read(bosNavDrawerOpenProvider.notifier).state = false;
    setState(() {
      _module = module;
      _destinationId = destinationId;
    });
  }

  BosModule _module = BosModule.management;

  /// The open destination, or null when the module's landing page is showing.
  String? _destinationId;

  @override
  void initState() {
    super.initState();
    // Start on the first module this person is allowed to open.
    final first = _rootModule;
    if (first != null) {
      _module = first.module;
      _destinationId = first.homeId;
    }
  }

  /// First module the signed-in member can open (the "home" of their app).
  BosModuleInfo? get _rootModule => _visibleModules(
    ref.read(authorizationServiceProvider),
    ref.read(moduleConfigsProvider).value ?? const {},
  ).firstOrNull;

  /// Key of the view currently on screen.
  String get _viewKey => _destinationId ?? _hubKey(_module);

  bool get _atRoot {
    final root = _rootModule;
    if (root == null) return true;
    return _module == root.module && _destinationId == root.homeId;
  }

  /// Opens a module: its home page, or its landing page.
  /// Tapping the module you are already in returns to its landing page.
  void _openModule(BosModule module) {
    ref.read(bosNavDrawerOpenProvider.notifier).state = false;
    final configs = ref.read(moduleConfigsProvider).value ?? const {};
    if (!_moduleEnabled(configs, module)) return;
    if (!_moduleVisible(ref.read(authorizationServiceProvider), module)) return;
    final target = _moduleInfo[module]!.homeId;
    if (module == _module && target == _destinationId) return;
    HapticFeedback.selectionClick();
    _go(module, target);
  }

  void _openDestination(String id) {
    ref.read(bosNavDrawerOpenProvider.notifier).state = false;
    final destination = _destById[id];
    if (destination == null) return;

    if (!_canOpen(ref.read(authorizationServiceProvider), id)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Your role can\'t open that page.')),
        );
      return;
    }

    // Stand-alone pages are pushed, exactly as they were before.
    if (destination.presentation == BosPresentation.route) {
      final builder = destination.builder;
      if (builder != null) {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
      }
      return;
    }

    if (destination.module == _module && id == _destinationId) return;
    HapticFeedback.selectionClick();
    _go(destination.module, id);
  }

  /// Back: close the POS drawer → page → its module landing page →
  /// their first module → exit.
  void _back() {
    final drawer = ref.read(bosNavDrawerOpenProvider.notifier);
    if (drawer.state) {
      drawer.state = false;
      return;
    }
    final hasLanding = _moduleInfo[_module]!.homeId == null;
    if (_destinationId != null && hasLanding) {
      setState(() => _destinationId = null);
    } else {
      final root = _rootModule;
      if (root != null) _openModule(root.module);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authorizationServiceProvider);
    final moduleConfigs = ref.watch(moduleConfigsProvider).value ?? const {};
    final open = _destinationId;
    if (open != null && !_canOpen(auth, open)) {
      final fallback = _visibleModules(auth, moduleConfigs).firstOrNull;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || fallback == null) return;
        setState(() {
          _module = fallback.module;
          _destinationId = fallback.homeId;
        });
      });
    }
    if (!_moduleEnabled(moduleConfigs, _module)) {
      // The open module was just disabled for this business: fall back to
      // the first enabled, permitted module.
      final fallback = _visibleModules(auth, moduleConfigs).firstOrNull;
      if (fallback != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _module = fallback.module;
              _destinationId = fallback.homeId;
            });
          }
        });
      }
    }
    final width = MediaQuery.sizeOf(context).width;

    final layout = width < Breakpoints.compact
        ? _CompactLayout(
            scaffoldKey: _scaffoldKey,
            module: _module,
            destinationId: _destinationId,
            viewKey: _viewKey,
            moduleConfigs: moduleConfigs,
            onOpenModule: _openModule,
            onOpenDestination: _openDestination,
          )
        : _WideLayout(
            module: _module,
            destinationId: _destinationId,
            viewKey: _viewKey,
            moduleConfigs: moduleConfigs,
            onOpenModule: _openModule,
            onOpenDestination: _openDestination,
            extended: width >= Breakpoints.medium,
          );

    return PopScope(
      canPop: _atRoot && !ref.watch(bosNavDrawerOpenProvider), // ← changed
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: layout,
    );
  }
}

/// Builds a view the first time it is opened, then keeps it alive.
class _LazyStack extends StatefulWidget {
  const _LazyStack({required this.selectedKey, required this.onOpen});

  final String selectedKey;
  final ValueChanged<String> onOpen;

  @override
  State<_LazyStack> createState() => _LazyStackState();
}

class _LazyStackState extends State<_LazyStack>
    with SingleTickerProviderStateMixin {
  final Set<String> _visited = {};
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(covariant _LazyStack old) {
    super.didUpdateWidget(old);
    if (old.selectedKey != widget.selectedKey) _fade.forward(from: 0.15);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Widget _buildView(BuildContext context, String key) {
    final destination = _destById[key];

    // Not a destination, so it is a module landing page.
    if (destination == null) {
      final module = BosModule.values.firstWhere((m) => _hubKey(m) == key);
      return _ModuleHub(info: _moduleInfo[module]!, onOpen: widget.onOpen);
    }

    final builder = destination.builder;
    return builder != null
        ? builder(context)
        : _ComingSoonView(destination: destination);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.selectedKey);
    final index = _viewKeys.indexOf(widget.selectedKey);

    return FadeTransition(
      opacity: _opacity,
      child: IndexedStack(
        index: index < 0 ? 0 : index,
        children: [
          for (final key in _viewKeys)
            _visited.contains(key)
                ? _buildView(context, key)
                : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Screen area: an optional module page switcher above the current view.
/// Screen area: an optional module page switcher above the current view.
/// On very wide screens the content is centred and capped in width.
class _ModuleBody extends StatelessWidget {
  const _ModuleBody({
    required this.module,
    required this.destinationId,
    required this.viewKey,
    required this.showSwitcher,
    required this.onOpenModule,
    required this.onOpenDestination,
  });

  final BosModule module;
  final String? destinationId;
  final String viewKey;

  /// Rail-less layouts have no sub-menu, so a page switcher is shown here.
  final bool showSwitcher;
  final ValueChanged<BosModule> onOpenModule;
  final ValueChanged<String> onOpenDestination;

  @override
  Widget build(BuildContext context) {
    final info = _moduleInfo[module]!;
    final inModulePage = info.homeId == null && destinationId != null;

    return Column(
      children: [
        if (showSwitcher && inModulePage)
          _ModuleSwitcher(
            info: info,
            destinationId: destinationId,
            onBack: () => onOpenModule(module),
            onOpen: onOpenDestination,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(
                constraints.maxWidth,
                Breakpoints.maxContent,
              );
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: _LazyStack(
                    selectedKey: viewKey,
                    onOpen: onOpenDestination,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PHONE LAYOUT
// ============================================================

class _CompactLayout extends ConsumerWidget {
  const _CompactLayout({
    required this.scaffoldKey,
    required this.module,
    required this.destinationId,
    required this.viewKey,
    required this.moduleConfigs,
    required this.onOpenModule,
    required this.onOpenDestination,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final BosModule module;
  final String? destinationId;
  final String viewKey;
  final Map<String, bool> moduleConfigs;
  final ValueChanged<BosModule> onOpenModule;
  final ValueChanged<String> onOpenDestination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authorizationServiceProvider);
    final visible = _visibleModules(auth, moduleConfigs);

    final barInfos = [
      for (final info in visible)
        if (_phoneBarModules.contains(info.module)) info,
    ];
    final menuInfos = [
      for (final info in visible)
        if (!_phoneBarModules.contains(info.module)) info,
    ];

    final onProfile = destinationId == BosDest.profile;
    final onPos = destinationId == BosDest.pos;
    final menuActive =
        onProfile ||
        (!_phoneBarModules.contains(module) && menuInfos.isNotEmpty);

    final canProfile = _canOpen(auth, BosDest.profile);
    final grouped = _grouped(visible);

    void openMenu() {
      final sections = <_MenuSection>[
        for (final g in grouped.entries)
          _MenuSection(g.key.label, [
            for (final info in g.value)
              _MenuEntry(
                icon: info.icon,
                selectedIcon: info.selectedIcon,
                label: info.label,
                selected: !onProfile && module == info.module,
                onTap: () => onOpenModule(info.module),
              ),
          ]),
        if (canProfile)
          _MenuSection('Account', [
            _MenuEntry(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: 'Profile',
              selected: onProfile,
              onTap: () => onOpenDestination(BosDest.profile),
            ),
          ]),
      ];
      _showPhoneMenu(context, sections);
    }

    return Scaffold(
      key: scaffoldKey,
      drawer: _BosDrawer(
        module: module,
        destinationId: destinationId,
        moduleConfigs: moduleConfigs,
        onOpenModule: onOpenModule,
        onOpenDestination: onOpenDestination,
      ),
      appBar: _ShellAppBar(
        module: module,
        destinationId: destinationId,
        showMenu: true,
        onOpenProfile: () => onOpenDestination(BosDest.profile),
      ),
      body: _ModuleBody(
        module: module,
        destinationId: destinationId,
        viewKey: viewKey,
        showSwitcher: true,
        onOpenModule: onOpenModule,
        onOpenDestination: onOpenDestination,
      ),
      // Text scaling is capped so large system fonts can't overflow the bar.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: _PhoneBottomBar(
          items: barInfos,
          selectedModule: onProfile ? null : module,
          menuActive: menuActive,
          showMenuButton: !onPos,
          onOpenModule: onOpenModule,
          onMenu: openMenu,
        ),
      ),
    );
  }
}
// ============================================================
// PHONE BOTTOM BAR + FLOATING MENU
// ============================================================

const double _kBarHeight = 64;
const double _kMenuButton = 72; // was 60
const double _kMenuLift = 32; // how far the button rises above the bar

class _PhoneBottomBar extends StatelessWidget {
  const _PhoneBottomBar({
    required this.items,
    required this.selectedModule,
    required this.menuActive,
    required this.showMenuButton,
    required this.onOpenModule,
    required this.onMenu,
  });

  final List<BosModuleInfo> items;
  final BosModule? selectedModule;
  final bool menuActive;

  /// False on the POS page, where the floating menu button is hidden.
  final bool showMenuButton;
  final ValueChanged<BosModule> onOpenModule;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final split = (items.length / 2).ceil();
    final left = items.take(split).toList();
    final right = items.skip(split).toList();

    Widget side(List<BosModuleInfo> list) => Expanded(
      child: Row(
        children: [
          for (final info in list)
            Expanded(
              child: _BarItem(
                info: info,
                selected: selectedModule == info.module,
                onTap: () => onOpenModule(info.module),
              ),
            ),
        ],
      ),
    );

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 8,
      shadowColor: scheme.shadow.withValues(alpha: 0.26),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kBarHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  side(left),
                  // The gap closes smoothly when the button is hidden.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    width: showMenuButton ? _kMenuButton + 24 : 0,
                  ),
                  side(right),
                ],
              ),
              Positioned(
                top: -_kMenuLift,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !showMenuButton,
                  child: AnimatedScale(
                    scale: showMenuButton ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedOpacity(
                      opacity: showMenuButton ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: _MenuFab(active: menuActive, onTap: onMenu),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big circular menu button with a smooth press animation.
class _MenuFab extends StatefulWidget {
  const _MenuFab({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  State<_MenuFab> createState() => _MenuFabState();
}

class _MenuFabState extends State<_MenuFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Menu',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _kMenuButton,
            height: _kMenuButton,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: AppColors.heroGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: widget.active ? scheme.primaryContainer : Colors.white,
                width: 5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 22,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.apps_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final BosModuleInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: info.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? info.selectedIcon : info.icon,
                size: 24,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              info.shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuEntry {
  const _MenuEntry({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.selected = false,
  }) : destructive = false;

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool destructive;
}

class _MenuSection {
  const _MenuSection(this.title, this.entries);
  final String title;
  final List<_MenuEntry> entries;
}

Future<void> _showPhoneMenu(BuildContext context, List<_MenuSection> sections) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => _PhoneMenuSheet(sections: sections),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: curved,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      );
    },
  );
}

/// Panel that hovers above the bar's centre button, grouped by classification.
class _PhoneMenuSheet extends StatelessWidget {
  const _PhoneMenuSheet({required this.sections});

  final List<_MenuSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            right: 16,
            bottom: inset + _kBarHeight + _kMenuLift + 16,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 360,
                  maxHeight: maxHeight,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in sections) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                            child: Text(
                              s.title.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          Wrap(
                            runSpacing: 10,
                            children: [
                              for (final e in s.entries)
                                SizedBox(
                                  width: 104,
                                  child: _MenuItem(
                                    entry: e,
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      e.onTap();
                                    },
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Close button sits where the bar's menu button is.
          Positioned(
            left: 0,
            right: 0,
            bottom: inset + _kBarHeight + _kMenuLift - _kMenuButton,
            child: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: _kMenuButton,
                  height: _kMenuButton,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.inverseSurface,
                    border: Border.all(color: Colors.white, width: 5),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: scheme.onInverseSurface,
                    size: 28,
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

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.entry, required this.onTap});

  final _MenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = entry.destructive
        ? scheme.error
        : (entry.selected ? scheme.onPrimaryContainer : scheme.primary);
    final bg = entry.destructive
        ? scheme.errorContainer
        : (entry.selected
              ? scheme.primaryContainer
              : scheme.primary.withValues(alpha: 0.08));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(
                entry.selected ? entry.selectedIcon : entry.icon,
                color: fg,
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.15,
                fontWeight: entry.selected ? FontWeight.w800 : FontWeight.w600,
                color: entry.destructive ? scheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ============================================================
// DRAWER (phone "More")
// ============================================================

Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
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

class _BosDrawer extends ConsumerWidget {
  const _BosDrawer({
    required this.module,
    required this.destinationId,
    required this.moduleConfigs,
    required this.onOpenModule,
    required this.onOpenDestination,
  });

  final BosModule module;
  final String? destinationId;
  final Map<String, bool> moduleConfigs;
  final ValueChanged<BosModule> onOpenModule;
  final ValueChanged<String> onOpenDestination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessProfileProvider).asData?.value;
    final auth = ref.watch(authorizationServiceProvider);
    final modules = _visibleModules(auth, moduleConfigs);
    final shortcuts = _accountShortcuts
        .where((id) => _canOpen(auth, id))
        .toList();
    final grouped = _grouped(modules);
    final ordered = [for (final g in grouped.values) ...g];
    final moduleCount = ordered.length;

    final shortcutIndex = shortcuts.indexOf(destinationId ?? '');
    final selectedIndex = shortcutIndex >= 0
        ? moduleCount + shortcutIndex
        : ordered.indexWhere((m) => m.module == module);

    return SizedBox(
      width: _adaptiveDrawerWidth(context),
      child: NavigationDrawer(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (i) {
          Navigator.of(context).pop();
          if (i < moduleCount) {
            onOpenModule(ordered[i].module);
          } else {
            onOpenDestination(shortcuts[i - moduleCount]);
          }
        },
        children: [
          _DrawerHeader(
            business: business,
            onTap: () {
              Navigator.of(context).pop();
              onOpenDestination(BosDest.profile);
            },
          ),
          for (final entry in grouped.entries) ...[
            _SectionLabel(
              entry.key.label,
              padding: const EdgeInsets.fromLTRB(28, 18, 16, 8),
            ),
            for (final info in entry.value)
              NavigationDrawerDestination(
                icon: Icon(info.icon),
                selectedIcon: Icon(info.selectedIcon),
                label: Text(info.label),
              ),
          ],
          if (shortcuts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              child: Divider(height: 1),
            ),
            const _SectionLabel(
              'Account',
              padding: EdgeInsets.fromLTRB(28, 6, 16, 8),
            ),
            for (final id in shortcuts)
              NavigationDrawerDestination(
                icon: Icon(_destById[id]!.icon),
                label: Text(_destById[id]!.label),
              ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: Divider(height: 1),
          ),
          if (ref.watch(customerAccountAvailableProvider) &&
              ref.watch(selectedAccountModeProvider) == 'business')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Switch account mode'),
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(selectedAccountModeProvider.notifier).state = null;
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: Icon(
                Icons.logout_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Sign out',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _confirmSignOut(context, ref),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Drawers default to a fixed 304dp width, which wastes space on tablets and
/// can overflow on narrow landscape phones. Cap it to the smaller of 85% of
/// the screen width or the Material 360dp maximum.
double _adaptiveDrawerWidth(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  const maxWidth = 360.0;
  final adaptive = screenWidth * 0.85;
  return adaptive < maxWidth ? adaptive : maxWidth;
}

/// Gradient header: business, signed-in person and role. Opens Profile.
class _DrawerHeader extends ConsumerWidget {
  const _DrawerHeader({required this.business, required this.onTap});

  final BusinessesData? business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).value;
    final roleLabel = ref.watch(currentRoleLabelProvider);

    final businessName = business?.name.trim() ?? '';
    final userName = (user?.displayName ?? '').trim();
    final person = userName.isNotEmpty ? userName : (user?.email ?? '');
    final initial = (person.isEmpty ? '?' : person[0]).toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.heroGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white.withValues(alpha: 0.22),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                person.isEmpty ? 'Your profile' : person,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (roleLabel.isNotEmpty)
                                Text(
                                  roleLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.storefront_outlined,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              businessName.isEmpty
                                  ? AppStrings.appName
                                  : businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.padding});

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================
// TABLET / DESKTOP LAYOUT
// ============================================================

class _WideLayout extends ConsumerWidget {
  const _WideLayout({
    required this.module,
    required this.destinationId,
    required this.viewKey,
    required this.moduleConfigs,
    required this.onOpenModule,
    required this.onOpenDestination,
    required this.extended,
  });

  final BosModule module;
  final String? destinationId;
  final String viewKey;
  final Map<String, bool> moduleConfigs;
  final ValueChanged<BosModule> onOpenModule;
  final ValueChanged<String> onOpenDestination;
  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(bosNavHiddenProvider);
    final drawerOpen = ref.watch(bosNavDrawerOpenProvider);
    final width = MediaQuery.sizeOf(context).width;

    // On POS the navigation slides over the page instead of docking.
    final overlay =
        destinationId == BosDest.pos && width >= kPosSplitBreakpoint;
    final railShown = !overlay && !hidden;
    final navOpen = overlay ? drawerOpen : railShown;
    final railWidth = extended ? 248.0 : 92.0;
    final divider = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: 0.35);

    void toggle() {
      HapticFeedback.selectionClick();
      if (overlay) {
        ref.read(bosNavDrawerOpenProvider.notifier).state = !drawerOpen;
      } else {
        ref.read(bosNavHiddenProvider.notifier).state = !hidden;
      }
    }

    Widget rail() => _BosRail(
      module: module,
      destinationId: destinationId,
      extended: extended,
      moduleConfigs: moduleConfigs,
      onOpenModule: onOpenModule,
      onOpenDestination: onOpenDestination,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _WideTopBar(
              module: module,
              destinationId: destinationId,
              extended: extended,
              railShown: railShown,
              navOpen: navOpen,
              onToggle: toggle,
              onOpenProfile: () => onOpenDestination(BosDest.profile),
            ),
            Expanded(
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!overlay)
                        ClipRect(
                          child: AnimatedAlign(
                            alignment: Alignment.centerLeft,
                            widthFactor: hidden ? 0 : 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOutCubic,
                            child: Row(
                              children: [
                                rail(),
                                VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: divider,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: _ModuleBody(
                          module: module,
                          destinationId: destinationId,
                          viewKey: viewKey,
                          showSwitcher: !overlay && (!extended || hidden),
                          onOpenModule: onOpenModule,
                          onOpenDestination: onOpenDestination,
                        ),
                      ),
                    ],
                  ),

                  // ---- POS: slide-over drawer + scrim ----
                  if (overlay) ...[
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !drawerOpen,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              ref
                                      .read(bosNavDrawerOpenProvider.notifier)
                                      .state =
                                  false,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            color: drawerOpen
                                ? Colors.black38
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      left: drawerOpen ? 0 : -(railWidth + 32),
                      top: 0,
                      bottom: 0,
                      child: Material(
                        elevation: 18,
                        shadowColor: Colors.black45,
                        child: rail(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tablet / desktop top bar. The left cluster (menu button + logo) is the
/// ONLY menu control; it resizes with the rail so the logo stays aligned.
class _WideTopBar extends ConsumerWidget {
  const _WideTopBar({
    required this.module,
    required this.destinationId,
    required this.extended,
    required this.onOpenProfile,
    required this.railShown,
    required this.navOpen,
    required this.onToggle,
  });

  final BosModule module;
  final String? destinationId;
  final bool extended;
  final VoidCallback onOpenProfile;
  final bool railShown; // docked rail occupies space
  final bool navOpen; // rail shown, or POS drawer open
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hidden = !railShown;
    final info = _moduleInfo[module]!;
    final destination = destinationId == null ? null : _destById[destinationId];

    final business =
        ref.watch(businessProfileProvider).asData?.value.name.trim() ?? '';
    final userName = ref.watch(currentUserProvider).value?.displayName ?? '';
    final initial = (userName.trim().isEmpty ? '?' : userName.trim()[0])
        .toUpperCase();

    final title = destination?.label ?? info.label;
    final inSection = destination != null && info.homeId == null;
    final subtitle = [
      if (business.isNotEmpty) business else AppStrings.appName,
      if (inSection) info.label,
    ].join(' · ');

    final line = scheme.outlineVariant.withValues(alpha: 0.35);
    // Same width as the rail below it, so the logo sits above the rail.
    final leftWidth = hidden ? 104.0 : (extended ? 248.0 : 92.0);
    final showName = extended && !hidden;

    return Material(
      color: scheme.surface,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              width: leftWidth,
              height: 64,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: hidden ? Colors.transparent : line),
                ),
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NavToggleButton(open: navOpen, onTap: onToggle),
                        SizedBox(width: extended ? 10 : 4),
                        const _LogoTile(size: 38, logoHeight: 24, radius: 12),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                          alignment: Alignment.centerLeft,
                          child: showName
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: SizedBox(
                                    width: 118,
                                    child: Text(
                                      business.isEmpty
                                          ? AppStrings.appName
                                          : business,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                            color: AppColors.primary,
                                          ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Align(
                      key: ValueKey(title),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const BranchChip(),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: 'Profile',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onOpenProfile,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The single menu button. Always a menu icon (never a back arrow).
class _NavToggleButton extends StatelessWidget {
  const _NavToggleButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: open ? 'Close menu' : 'Menu',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: open
              ? scheme.primary
              : scheme.primaryContainer.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => RotationTransition(
                  turns: Tween(begin: 0.85, end: 1.0).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  open ? Icons.menu_open_rounded : Icons.menu_rounded,
                  key: ValueKey(open),
                  size: 22,
                  color: open ? scheme.onPrimary : scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BosRail extends ConsumerWidget {
  const _BosRail({
    required this.module,
    required this.destinationId,
    required this.extended,
    required this.moduleConfigs,
    required this.onOpenModule,
    required this.onOpenDestination,
  });

  final BosModule module;
  final String? destinationId;
  final bool extended;
  final Map<String, bool> moduleConfigs;
  final ValueChanged<BosModule> onOpenModule;
  final ValueChanged<String> onOpenDestination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authorizationServiceProvider);
    final grouped = _grouped([
      for (final m in _visibleModules(auth, moduleConfigs))
        if (!_profileOnly(auth, m)) m,
    ]);
    final canProfile = _canOpen(auth, BosDest.profile);
    var groupIndex = 0;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false, // the top bar already handles the top inset
        child: SizedBox(
          width: extended ? 248 : 92,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  children: [
                    for (final entry in grouped.entries) ...[
                      _RailGroupLabel(
                        label: entry.key.label,
                        extended: extended,
                        first: groupIndex++ == 0,
                      ),
                      for (final info in entry.value) ...[
                        _RailTile(
                          info: info,
                          selected: module == info.module,
                          extended: extended,
                          onTap: () => onOpenModule(info.module),
                        ),
                        // The active module's pages expand under it.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: Column(
                            children: [
                              if (extended &&
                                  module == info.module &&
                                  info.homeId == null)
                                for (final d in _visibleAvailable(
                                  auth,
                                  info.module,
                                ))
                                  _RailSubTile(
                                    destination: d,
                                    selected: d.id == destinationId,
                                    onTap: () => onOpenDestination(d.id),
                                  ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              if (canProfile)
                _RailProfileTile(
                  extended: extended,
                  selected: destinationId == BosDest.profile,
                  onTap: () => onOpenDestination(BosDest.profile),
                ),
              _RailSignOutTile(extended: extended),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small heading (wide) or hairline (compact) between module groups.
class _RailGroupLabel extends StatelessWidget {
  const _RailGroupLabel({
    required this.label,
    required this.extended,
    required this.first,
  });

  final String label;
  final bool extended;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    if (!extended) {
      return Padding(
        padding: EdgeInsets.fromLTRB(14, first ? 2 : 10, 14, 6),
        child: first
            ? const SizedBox(height: 0)
            : Divider(height: 1, color: color.withValues(alpha: 0.25)),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(14, first ? 6 : 18, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Signed-in person at the bottom of the rail. Opens Profile.
class _RailProfileTile extends ConsumerWidget {
  const _RailProfileTile({
    required this.extended,
    required this.selected,
    required this.onTap,
  });

  final bool extended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(currentUserProvider).value;
    final roleLabel = ref.watch(currentRoleLabelProvider);

    final name = (user?.displayName ?? '').trim();
    final person = name.isNotEmpty ? name : (user?.email ?? 'Profile');
    final initial = (person.isEmpty ? '?' : person[0]).toUpperCase();

    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final content = extended
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (roleLabel.isNotEmpty)
                        Text(
                          roleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(8),
            child: Center(child: avatar),
          );

    final tile = Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: extended ? tile : Tooltip(message: 'Profile', child: tile),
    );
  }
}

class _RailSignOutTile extends ConsumerWidget {
  const _RailSignOutTile({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.error;
    final icon = Icon(Icons.logout_rounded, size: 24, color: color);

    final content = extended
        ? SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Text(
                    'Sign out',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          )
        : SizedBox(height: 46, child: Center(child: icon));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _confirmSignOut(context, ref),
        child: content,
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.info,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final BosModuleInfo info;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? Colors.white : scheme.onSurfaceVariant;
    final icon = Icon(
      selected ? info.selectedIcon : info.icon,
      size: 24,
      color: color,
    );

    final content = extended
        ? SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      info.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 4),
                Text(
                  info.shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          );

    final tile = Semantics(
      selected: selected,
      button: true,
      label: info.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: AppColors.heroGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: content),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: extended ? tile : Tooltip(message: info.label, child: tile),
    );
  }
}

/// A page nested under its module in the extended rail.
class _RailSubTile extends StatelessWidget {
  const _RailSubTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final BosDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final opensAsRoute = destination.presentation == BosPresentation.route;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 1, 0, 1),
      child: Semantics(
        selected: selected,
        button: true,
        label: destination.label,
        child: Material(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(destination.icon, size: 19, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                    if (opensAsRoute)
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
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

// ============================================================
// MODULE LANDING PAGE ("hub"), SWITCHER AND PLACEHOLDER
// ============================================================

/// A module's landing page: what it offers, and what is still to come.
class _ModuleHub extends ConsumerWidget {
  const _ModuleHub({required this.info, required this.onOpen});

  final BosModuleInfo info;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(authorizationServiceProvider);
    final all = _visibleDestinations(auth, info.module);
    final ready = all.where((d) => d.isAvailable).toList();
    final soon = all.where((d) => !d.isAvailable).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(16.0, (constraints.maxWidth - 1000) / 2);

        return ListView(
          padding: EdgeInsets.fromLTRB(side, 20, side, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    info.selectedIcon,
                    size: 26,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        info.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (ready.isNotEmpty) _HubGrid(items: ready, onOpen: onOpen),
            if (soon.isNotEmpty) ...[
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'Coming soon',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _HubGrid(items: soon, onOpen: onOpen),
            ],
          ],
        );
      },
    );
  }
}

/// Responsive card grid. Cards size to their content, so nothing can overflow
/// at large text sizes.
class _HubGrid extends StatelessWidget {
  const _HubGrid({required this.items, required this.onOpen});

  final List<BosDestination> items;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    const minCardWidth = 300.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = math.min(
          3,
          math.max(1, ((available + gap) / (minCardWidth + gap)).floor()),
        );
        final cardWidth = (available - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final d in items)
              SizedBox(
                width: cardWidth,
                child: _HubCard(destination: d, onTap: () => onOpen(d.id)),
              ),
          ],
        );
      },
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.destination, required this.onTap});

  final BosDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = destination.isAvailable;
    final opensAsRoute = destination.presentation == BosPresentation.route;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: available
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  destination.icon,
                  size: 22,
                  color: available
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: available ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!available)
                const _SoonPill()
              else
                Icon(
                  opensAsRoute
                      ? Icons.open_in_new_rounded
                      : Icons.chevron_right_rounded,
                  size: opensAsRoute ? 18 : 22,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoonPill extends StatelessWidget {
  const _SoonPill();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Soon',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Back-to-module button plus quick switching between the module's pages.
/// Shown when there is no extended rail to nest them in.
class _ModuleSwitcher extends ConsumerWidget {
  const _ModuleSwitcher({
    required this.info,
    required this.destinationId,
    required this.onBack,
    required this.onOpen,
  });

  final BosModuleInfo info;
  final String? destinationId;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authorizationServiceProvider);
    final pages = _visibleAvailable(
      auth,
      info.module,
    ).where((d) => d.presentation == BosPresentation.embedded).toList();

    return Material(
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'All of ${info.label}',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    for (final d in pages)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: ChoiceChip(
                          label: Text(d.label),
                          showCheckmark: false,
                          selected: d.id == destinationId,
                          onSelected: (_) => onOpen(d.id),
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

/// Placeholder for destinations that are planned but not built. Deliberately
/// does nothing except say so.
class _ComingSoonView extends StatelessWidget {
  const _ComingSoonView({required this.destination});

  final BosDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  destination.icon,
                  size: 34,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                destination.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const _SoonPill(),
              const SizedBox(height: 12),
              Text(
                destination.description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This part of BOS isn\'t available yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SHARED WIDGETS
// ============================================================

/// Top bar: current page, business + section underneath, profile shortcut.
/// Top bar: current page, business + section underneath, profile shortcut.
class _ShellAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _ShellAppBar({
    required this.module,
    required this.destinationId,
    required this.showMenu,
    required this.onOpenProfile,
  });
  final BosModule module;
  final String? destinationId;
  final bool showMenu;
  final VoidCallback onOpenProfile;

  // 64 toolbar + 1 divider
  @override
  Size get preferredSize => const Size.fromHeight(65);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = _moduleInfo[module]!;
    final destination = destinationId == null ? null : _destById[destinationId];

    final business =
        ref.watch(businessProfileProvider).asData?.value.name.trim() ?? '';
    final userName = ref.watch(currentUserProvider).value?.displayName ?? '';
    final initial = (userName.trim().isEmpty ? '?' : userName.trim()[0])
        .toUpperCase();

    final title = destination?.label ?? info.label;
    final inSection = destination != null && info.homeId == null;
    final subtitle = [
      if (business.isNotEmpty) business else AppStrings.appName,
      if (inSection) info.label,
    ].join(' · ');

    return AppBar(
      automaticallyImplyLeading: showMenu,
      toolbarHeight: 64,
      titleSpacing: showMenu ? 0 : 20,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        const BranchChip(),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Tooltip(
            message: 'Profile',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onOpenProfile,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// Brand logo on a soft tinted tile. Padding is derived from the sizes.
class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.size,
    required this.logoHeight,
    required this.radius,
  });

  final double size;
  final double logoHeight;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all((size - logoHeight) / 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.accent.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: AppLogo(height: logoHeight),
    );
  }
}

/// The Businesses table has no logo field yet, so the avatar picks an icon
/// from the business category. Swap the body for an image when one exists.
// ignore: unused_element
class _BusinessAvatar extends StatelessWidget {
  const _BusinessAvatar({required this.business}) : radius = 22;

  final BusinessesData? business;
  final double radius;

  static const _iconRules = <(List<String>, IconData)>[
    (
      ['restaurant', 'food', 'cafe', 'coffee', 'bakery'],
      Icons.restaurant_rounded,
    ),
    (['retail', 'store', 'shop'], Icons.storefront_rounded),
    (['logistics', 'transport', 'delivery'], Icons.local_shipping_rounded),
    (['farm', 'agri'], Icons.agriculture_rounded),
    (['construction'], Icons.construction_rounded),
    (['service'], Icons.handyman_rounded),
  ];

  IconData _iconFor(String? category) {
    final value = (category ?? '').trim().toLowerCase();
    for (final (keywords, icon) in _iconRules) {
      if (keywords.any(value.contains)) return icon;
    }
    return Icons.business_center_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.secondary],
        ),
      ),
      child: Icon(
        _iconFor(business?.businessCategory),
        size: radius * 0.9,
        color: scheme.onPrimary,
      ),
    );
  }
}
