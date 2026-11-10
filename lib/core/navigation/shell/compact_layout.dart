// lib/core/navigation/shell/compact_layout.dart
//
// Phone layout: app bar, bottom bar with floating menu button, drawer.

import 'dart:async';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/customer/presentation/customer_mode_gate.dart';
import 'package:bos_application/features/branches/branch_widgets.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart' show businessProfileProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/auth_providers.dart';
import 'package:bos_application/core/navigation/bos_registry.dart';
import 'package:bos_application/core/navigation/bos_permissions.dart';
import 'package:bos_application/core/navigation/shell/module_body.dart';
import 'package:bos_application/app/sign_out.dart';

class BosCompactLayout extends ConsumerWidget {
  const BosCompactLayout({super.key, 
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
    final visible = visibleModules(auth, moduleConfigs);

    final barInfos = [
      for (final info in visible)
        if (phoneBarModules.contains(info.module)) info,
    ];
    final menuInfos = [
      for (final info in visible)
        if (!phoneBarModules.contains(info.module)) info,
    ];

    final onProfile = destinationId == BosDest.profile;
    final onPos = destinationId == BosDest.pos;
    final menuActive =
        onProfile ||
        (!phoneBarModules.contains(module) && menuInfos.isNotEmpty);

    final canProfile = canOpen(auth, BosDest.profile);
    final grouped = groupModules(visible);

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
      body: BosModuleBody(
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
    final modules = visibleModules(auth, moduleConfigs);
    final shortcuts = accountShortcuts
        .where((id) => canOpen(auth, id))
        .toList();
    final grouped = groupModules(modules);
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
                icon: Icon(bosDestById[id]!.icon),
                label: Text(bosDestById[id]!.label),
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
              onTap: () => confirmSignOut(context, ref),
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
    final info = bosModuleInfo[module]!;
    final destination = destinationId == null ? null : bosDestById[destinationId];

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
