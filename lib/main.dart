// lib/main.dart
//
// BOS — Business Operating System
//
// Entry point only. Where things live:
//
//   app/auth_gate.dart              login / biometric gate
//   app/startup/                    startup service, repairs and screens
//   app/access_gate.dart            membership -> navigation shell
//   core/navigation/bos_registry.dart     every module and destination, ONCE
//   core/navigation/bos_permissions.dart  who may open what
//   core/navigation/shell/          phone + wide layouts, hubs
//
// To add a module (Documents, Projects, CRM…): add a value to `BosModule`, a
// `BosModuleInfo`, and its `BosDestination`s in bos_registry.dart.

import 'dart:async';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/navigation/app_navigator.dart';
import 'package:bos_application/core/settings/app_settings.dart';
import 'package:bos_application/features/transactions/presentation/screens/startup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bos_application/app/auth_gate.dart';

// Re-exported so files that still import main.dart keep compiling. Point them
// at the real libraries, then delete these lines.
export 'package:bos_application/app/startup/startup_gate.dart' show restartStartupFlow;
export 'package:bos_application/core/navigation/bos_registry.dart';
export 'package:bos_application/core/navigation/shell/navigation_shell.dart' show NavigationShell;

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
  await preloadStartupPersona();
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
      home: const BosAuthGate(),
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