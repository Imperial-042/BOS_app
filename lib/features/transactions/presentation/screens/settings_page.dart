// lib/features/settings/presentation/screens/settings_page.dart
//
// Settings screen. Same behavior as before, redesigned:
//  - collapsing large app bar
//  - profile hero card (the one expressive element on the page)
//  - grouped, rounded sections with tinted icon badges
//  - module switches with short descriptions + a clear read-only state
//  - currency picker sheet with a visible selected state
//  - haptics on toggles, error handling on every write

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/business/module_config_service.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/core/settings/app_settings.dart';
import 'package:bos_application/features/transactions/presentation/screens/profile_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final currency = MoneyFormatting.supportedCurrencies.firstWhere(
      (option) => option.code == settings.currencyCode,
    );
    final messenger = ScaffoldMessenger.of(context);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          _SettingsHeader(
            onProfileTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            sliver: SliverList.list(
              children: [
                const _ModulesSection(),
                _SettingsGroup(
                  title: 'Appearance & format',
                  children: [
                    SwitchListTile(
                      contentPadding: _tilePadding,
                      secondary: _IconBadge(
                        icon: settings.isDarkMode
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: const Color(0xFF6D5BD0),
                        active: true,
                      ),
                      title: const Text('Dark theme'),
                      subtitle: const Text('Easier on the eyes in low light'),
                      value: settings.isDarkMode,
                      onChanged: (enabled) async {
                        HapticFeedback.selectionClick();
                        try {
                          await ref
                              .read(appSettingsProvider.notifier)
                              .setDarkMode(enabled);
                        } catch (error) {
                          _showSettingsError(messenger, error);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: _tilePadding,
                      leading: const _IconBadge(
                        icon: Icons.currency_exchange_rounded,
                        color: Color(0xFF1F9D74),
                        active: true,
                      ),
                      title: const Text('Currency'),
                      subtitle: Text(currency.label),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showCurrencyPicker(context),
                    ),
                    ListTile(
                      contentPadding: _tilePadding,
                      leading: const _IconBadge(
                        icon: Icons.text_fields_rounded,
                        color: Color(0xFF1769AA),
                        active: true,
                      ),
                      title: const Text('Font style'),
                      subtitle: Text(_fontFamilyLabel(settings.fontFamily)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showAppearancePicker(
                        context,
                        title: 'Font style',
                        selectedValue: settings.fontFamily,
                        choices: const [
                          _AppearanceChoice(
                            value: 'system',
                            label: 'System',
                            description: 'Default device font',
                          ),
                          _AppearanceChoice(
                            value: 'serif',
                            label: 'Serif',
                            description: 'Traditional, book-style lettering',
                            fontFamily: 'serif',
                          ),
                          _AppearanceChoice(
                            value: 'monospace',
                            label: 'Monospace',
                            description: 'Fixed-width lettering',
                            fontFamily: 'monospace',
                          ),
                        ],
                        onSelected: (ref, value) => ref
                            .read(appSettingsProvider.notifier)
                            .setFontFamily(value),
                      ),
                    ),
                    ListTile(
                      contentPadding: _tilePadding,
                      leading: const _IconBadge(
                        icon: Icons.format_size_rounded,
                        color: Color(0xFFB45309),
                        active: true,
                      ),
                      title: const Text('Font size'),
                      subtitle: Text(_textScaleLabel(settings.textScale)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showAppearancePicker(
                        context,
                        title: 'Font size',
                        selectedValue: settings.textScale.toString(),
                        choices: const [
                          _AppearanceChoice(
                            value: '0.9',
                            label: 'Small',
                            description: '90%',
                          ),
                          _AppearanceChoice(
                            value: '1.0',
                            label: 'Standard',
                            description: '100%',
                          ),
                          _AppearanceChoice(
                            value: '1.15',
                            label: 'Large',
                            description: '115%',
                          ),
                          _AppearanceChoice(
                            value: '1.3',
                            label: 'Extra large',
                            description: '130%',
                          ),
                        ],
                        onSelected: (ref, value) => ref
                            .read(appSettingsProvider.notifier)
                            .setTextScale(double.parse(value)),
                      ),
                    ),
                  ],
                ),
                const _SettingsGroup(
                  title: 'About',
                  children: [
                    ListTile(
                      contentPadding: _tilePadding,
                      leading: _IconBadge(
                        icon: Icons.info_outline_rounded,
                        color: Color(0xFF5C6B7A),
                        active: true,
                      ),
                      title: Text('About BOS'),
                      subtitle: Text(AppStrings.appFullName),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fontFamilyLabel(String fontFamily) => switch (fontFamily) {
    'serif' => 'Serif',
    'monospace' => 'Monospace',
    _ => 'System',
  };

  static String _textScaleLabel(double textScale) {
    final label = switch (textScale) {
      0.9 => 'Small',
      1.15 => 'Large',
      1.3 => 'Extra large',
      _ => 'Standard',
    };
    return '$label (${(textScale * 100).round()}%)';
  }

  void _showAppearancePicker(
    BuildContext context, {
    required String title,
    required String selectedValue,
    required List<_AppearanceChoice> choices,
    required Future<void> Function(WidgetRef ref, String value) onSelected,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    'Choose $title',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                RadioGroup<String>(
                  groupValue: selectedValue,
                  onChanged: (value) async {
                    if (value == null) return;
                    HapticFeedback.selectionClick();
                    try {
                      await onSelected(ref, value);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    } catch (error) {
                      _showSettingsError(messenger, error);
                    }
                  },
                  child: Column(
                    children: [
                      for (final choice in choices)
                        RadioListTile<String>(
                          value: choice.value,
                          title: Text(
                            choice.label,
                            style: choice.fontFamily == null
                                ? null
                                : TextStyle(fontFamily: choice.fontFamily),
                          ),
                          subtitle: Text(
                            choice.description,
                            style: choice.fontFamily == null
                                ? null
                                : TextStyle(fontFamily: choice.fontFamily),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCurrencyPicker(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final selectedCode = ref.watch(appSettingsProvider).currencyCode;

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    'Choose a currency',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                RadioGroup<String>(
                  groupValue: selectedCode,
                  onChanged: (code) async {
                    if (code == null) return;
                    HapticFeedback.selectionClick();
                    try {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setCurrencyCode(code);
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    } catch (error) {
                      _showSettingsError(messenger, error);
                    }
                  },
                  child: Column(
                    children: [
                      for (final currency
                          in MoneyFormatting.supportedCurrencies)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: currency.code == selectedCode
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: RadioListTile<String>(
                              value: currency.code,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(
                                currency.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(currency.code),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

void _showSettingsError(ScaffoldMessengerState messenger, Object error) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Couldn’t save that setting: $error'),
      ),
    );
}

const _tilePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 4);

class _AppearanceChoice {
  const _AppearanceChoice({
    required this.value,
    required this.label,
    required this.description,
    this.fontFamily,
  });

  final String value;
  final String label;
  final String description;
  final String? fontFamily;
}

// ---------------------------------------------------------------------------
// Header: the single expressive element on the page.
// ---------------------------------------------------------------------------

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onProfileTap});

  final VoidCallback onProfileTap;

  static const double _expanded = 232;
  static const double _radius = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topPad = MediaQuery.paddingOf(context).top;
    final collapsedHeight = topPad + kToolbarHeight;
    final maxHeight = topPad + _expanded;
    final hasBack = Navigator.canPop(context);

    final top = scheme.primary;
    final bottom = Color.alphaBlend(
      scheme.tertiary.withValues(alpha: 0.55),
      scheme.primary,
    );
    final onTop = scheme.onPrimary;

    return SliverAppBar(
      pinned: true,
      expandedHeight: _expanded,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: top,
      foregroundColor: onTop,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle:
          ThemeData.estimateBrightnessForColor(top) == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(_radius)),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          // 1 = fully expanded, 0 = fully collapsed.
          final t =
              ((constraints.maxHeight - collapsedHeight) /
                      (maxHeight - collapsedHeight))
                  .clamp(0.0, 1.0);
          final contentOpacity = ((t - 0.3) / 0.7).clamp(0.0, 1.0);
          final collapsedOpacity = (1 - t * 2.2).clamp(0.0, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [top, bottom],
                  ),
                ),
              ),
              Positioned(
                right: -40,
                top: -30 - (1 - t) * 20,
                child: _Ring(size: 170, color: onTop),
              ),
              Positioned(
                left: -50,
                bottom: -70,
                child: _Ring(size: 130, color: onTop),
              ),

              // Collapsed title, fades in as the header shrinks.
              Positioned(
                top: topPad,
                left: hasBack ? 56 : 20,
                right: 20,
                height: kToolbarHeight,
                child: Opacity(
                  opacity: collapsedOpacity,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Settings',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: onTop,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

              // Expanded content: title, tagline and the profile entry.
              Positioned(
                left: 20,
                right: 20,
                bottom: 22,
                child: Opacity(
                  opacity: contentOpacity,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: onTop,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your profile, modules and preferences',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: onTop.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _ProfileEntry(onTap: onProfileTap),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Frosted row inside the header that opens Profile & businesses.
class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTop = theme.colorScheme.onPrimary;

    return Semantics(
      button: true,
      label: 'Profile and businesses',
      child: Material(
        color: onTop.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: onTop.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onTop,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: theme.colorScheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile & businesses',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: onTop,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Edit details or switch business',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onTop.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: onTop),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.12), width: 18),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

/// A titled, rounded container that groups related rows.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.description,
    this.footer,
  });

  final String title;
  final String? description;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 76,
                      endIndent: 16,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      footer!,
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
    );
  }
}

/// Rounded-square icon tile. Tinted with [color] when [active], muted otherwise.
class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
    required this.active,
  });

  final IconData icon;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final background = active
        ? color.withValues(alpha: dark ? 0.28 : 0.16)
        : scheme.surfaceContainerHighest;
    final foreground = active
        ? (dark ? Color.alphaBlend(Colors.white38, color) : color)
        : scheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Icon(icon, key: ValueKey(icon), color: foreground, size: 24),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

/// Per-business module switches. Only users who may change business settings
/// can flip them; everyone else sees the read-only list.
class _ModulesSection extends ConsumerWidget {
  const _ModulesSection();

  // id -> (label, description, icon, accent)
  static const _modules = <String, (String, String, IconData, Color)>{
    BosModuleIds.management: (
      'Management',
      'Dashboards and business overview',
      Icons.dashboard_rounded,
      Color(0xFF3B82F6),
    ),
    BosModuleIds.finance: (
      'Finance',
      'Accounts, expenses and reports',
      Icons.account_balance_wallet_rounded,
      Color(0xFF1F9D74),
    ),
    BosModuleIds.inventory: (
      'Inventory',
      'Stock levels and products',
      Icons.inventory_2_rounded,
      Color(0xFFE08A1E),
    ),
    BosModuleIds.salesPos: (
      'Sales & POS',
      'Checkout and sales history',
      Icons.point_of_sale_rounded,
      Color(0xFFE5484D),
    ),
    BosModuleIds.people: (
      'People',
      'Team members and roles',
      Icons.groups_rounded,
      Color(0xFF8B5CF6),
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canProvider(BosPermission.businessSettings));
    final configsAsync = ref.watch(moduleConfigsProvider);
    final service = ref.read(moduleConfigServiceProvider);
    final audit = ref.read(auditLogServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    return configsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (configs) => _SettingsGroup(
        title: 'Modules',
        description:
            'Choose what this business uses. Applies to everyone in it.',
        footer: canEdit
            ? null
            : 'Only users with business settings access can change modules.',
        children: [
          for (final moduleId in BosModuleIds.toggleable)
            Builder(
              builder: (context) {
                final module = _modules[moduleId]!;
                final enabledNow = service.isEnabled(configs, moduleId);

                return SwitchListTile(
                  contentPadding: _tilePadding,
                  secondary: _IconBadge(
                    icon: module.$3,
                    color: module.$4,
                    active: enabledNow,
                  ),
                  title: Text(module.$1),
                  subtitle: Text(module.$2),
                  value: enabledNow,
                  onChanged: canEdit
                      ? (enabled) async {
                          HapticFeedback.selectionClick();
                          try {
                            await service.setEnabled(
                              businessId: kCurrentBusinessId,
                              moduleId: moduleId,
                              enabled: enabled,
                            );
                            await audit.tryRecord(
                              AuditEvent(
                                businessId: kCurrentBusinessId,
                                module: AuditModule.administration,
                                actionType: AuditActionType.update,
                                action: 'administration.module_toggled',
                                entityType: 'business_module_configs',
                                entityId: moduleId,
                                entityLabel: module.$1,
                                before: {'enabled': !enabled},
                                after: {'enabled': enabled},
                              ),
                            );
                          } catch (error) {
                            _showSettingsError(messenger, error);
                          }
                        }
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }
}
