// lib/core/navigation/shell/navigation_shell.dart
//
// Owns which module/destination is open and chooses the phone or wide layout.

import 'package:bos_application/core/navigation/nav_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/business/module_config_service.dart';
import 'package:bos_application/core/navigation/bos_registry.dart';
import 'package:bos_application/core/navigation/bos_permissions.dart';
import 'package:bos_application/core/navigation/shell/compact_layout.dart';
import 'package:bos_application/core/navigation/shell/wide_layout.dart';

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
  BosModuleInfo? get _rootModule => visibleModules(
    ref.read(authorizationServiceProvider),
    ref.read(moduleConfigsProvider).value ?? const {},
  ).firstOrNull;

  /// Key of the view currently on screen.
  String get _viewKey => _destinationId ?? bosHubKey(_module);

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
    if (!moduleEnabled(configs, module)) return;
    if (!moduleVisible(ref.read(authorizationServiceProvider), module)) return;
    final target = bosModuleInfo[module]!.homeId;
    if (module == _module && target == _destinationId) return;
    HapticFeedback.selectionClick();
    _go(module, target);
  }

  void _openDestination(String id) {
    ref.read(bosNavDrawerOpenProvider.notifier).state = false;
    final destination = bosDestById[id];
    if (destination == null) return;

    if (!canOpen(ref.read(authorizationServiceProvider), id)) {
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
    final hasLanding = bosModuleInfo[_module]!.homeId == null;
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
    if (open != null && !canOpen(auth, open)) {
      final fallback = visibleModules(auth, moduleConfigs).firstOrNull;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || fallback == null) return;
        setState(() {
          _module = fallback.module;
          _destinationId = fallback.homeId;
        });
      });
    }
    if (!moduleEnabled(moduleConfigs, _module)) {
      // The open module was just disabled for this business: fall back to
      // the first enabled, permitted module.
      final fallback = visibleModules(auth, moduleConfigs).firstOrNull;
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
        ? BosCompactLayout(
            scaffoldKey: _scaffoldKey,
            module: _module,
            destinationId: _destinationId,
            viewKey: _viewKey,
            moduleConfigs: moduleConfigs,
            onOpenModule: _openModule,
            onOpenDestination: _openDestination,
          )
        : BosWideLayout(
            module: _module,
            destinationId: _destinationId,
            viewKey: _viewKey,
            moduleConfigs: moduleConfigs,
            onOpenModule: _openModule,
            onOpenDestination: _openDestination,
            extended: width >= Breakpoints.medium,
          );

    return PopScope(
      canPop: _atRoot && !ref.watch(bosNavDrawerOpenProvider),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: layout,
    );
  }
}
