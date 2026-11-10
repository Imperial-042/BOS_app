// lib/core/navigation/shell/wide_layout.dart
//
// Tablet / desktop layout: top bar and navigation rail.

import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/navigation/nav_visibility.dart';
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

class BosWideLayout extends ConsumerWidget {
  const BosWideLayout({super.key, 
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
                        child: BosModuleBody(
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
    final grouped = groupModules([
      for (final m in visibleModules(auth, moduleConfigs))
        if (!profileOnly(auth, m)) m,
    ]);
    final canProfile = canOpen(auth, BosDest.profile);
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
                                for (final d in visibleAvailable(
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
        onTap: () => confirmSignOut(context, ref),
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
