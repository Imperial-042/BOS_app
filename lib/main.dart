// lib/main.dart
//
// BOS — Business Operating System
//
// Application entry point + adaptive navigation shell.
//
// Adaptive behavior:
//   Phone   (< 600):  Bottom navigation + More sheet
//   Tablet  (600+):   Compact NavigationRail
//   Desktop (840+):   Extended NavigationRail
//
// Existing feature pages are kept intact.

import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/features/transactions/presentation/screens/suppliers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/database/app_database.dart';
import 'core/database/database_provider.dart';

import 'features/transactions/presentation/screens/cashflow_page.dart';
import 'features/transactions/presentation/screens/dashboard_page.dart';
import 'features/transactions/presentation/screens/journal_entry_page.dart';
import 'features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'features/transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: BosApp()));
}

// ============================================================
// APP
// ============================================================

class BosApp extends StatelessWidget {
  const BosApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Seeded from the brand navy, not a stock Material color — this
    // is what keeps buttons, indicators, and selection states on-brand
    // everywhere without hand-tinting each widget.
    const seedColor = AppColors.primary;

    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seedColor,
        brightness: Brightness.light,

        scaffoldBackgroundColor: const Color(0xFFF7F9F9),

        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),

        navigationBarTheme: NavigationBarThemeData(
          height: 72,
          elevation: 0,
          backgroundColor: Colors.white,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),

        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.white,
          elevation: 0,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          groupAlignment: -0.75,
          labelType: NavigationRailLabelType.none,
        ),

        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: seedColor, width: 1.5),
          ),
        ),
      ),
      home: const _StartupGate(),
    );
  }
}

// ============================================================
// STARTUP GATE
// ============================================================

class _StartupGate extends ConsumerStatefulWidget {
  const _StartupGate();

  @override
  ConsumerState<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<_StartupGate> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _ensureBusinessExists();
  }

  Future<void> _ensureBusinessExists() async {
    final db = ref.read(databaseProvider);

    final existing = await db.select(db.businesses).get();

    if (existing.isEmpty) {
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: kCurrentBusinessId,
              name: 'My Business',
              ownerUserId: 'owner_001',
            ),
          );

      await db.seedDefaultsForBusiness(kCurrentBusinessId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingScreen();
        }

        if (snapshot.hasError) {
          return _StartupErrorScreen(
            error: snapshot.error,
            onRetry: () {
              setState(() {
                _initFuture = _ensureBusinessExists();
              });
            },
          );
        }

        return const NavigationShell();
      },
    );
  }
}

// ============================================================
// STARTUP LOADING — logo-led, on-brand splash
// ============================================================

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
              // Logo, framed in a soft brand-tinted card rather than
              // floating bare — gives the splash a designed feel
              // instead of "just an image on a blank screen."
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.08),
                      AppColors.accent.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(36),
                ),
                padding: const EdgeInsets.all(24),
                child: const AppLogo(height: 92),
              ),

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

// ============================================================
// STARTUP ERROR
// ============================================================

class _StartupErrorScreen extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _StartupErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                        color: theme.colorScheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                        size: 32,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'Unable to start ${AppStrings.appName}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '${AppStrings.appName} could not finish preparing the local database.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$error', style: theme.textTheme.bodySmall),
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

// ============================================================
// BREAKPOINTS
// ============================================================

class Breakpoints {
  static const double compact = 600;
  static const double medium = 840;
}

// ============================================================
// NAVIGATION DESTINATION
// ============================================================

class NavDestinationInfo {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  const NavDestinationInfo({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });
}

const List<NavDestinationInfo> _destinations = [
  NavDestinationInfo(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
    screen: DashboardPage(),
  ),

  NavDestinationInfo(
    label: 'Journal',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    screen: JournalEntryPage(),
  ),

  NavDestinationInfo(
    label: 'Cashflow',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
    screen: CashflowPage(),
  ),

  NavDestinationInfo(
    label: 'Customers',
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    screen: _PlaceholderScreen(title: 'Customers'),
  ),

  NavDestinationInfo(
    label: 'Suppliers',
    icon: Icons.local_shipping_outlined,
    selectedIcon: Icons.local_shipping_rounded,
    screen: SuppliersPage(),
  ),

  NavDestinationInfo(
    label: 'Supplies',
    icon: Icons.shopping_cart_outlined,
    selectedIcon: Icons.shopping_cart_rounded,
    screen: SuppliesPriceListPage(),
  ),
];

// ============================================================
// NAVIGATION SHELL
// ============================================================

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _selectedIndex = 0;

  void _selectDestination(int index) {
    if (index < 0 || index >= _destinations.length) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < Breakpoints.compact) {
      return _CompactLayout(
        selectedIndex: _selectedIndex,
        onSelect: _selectDestination,
      );
    }

    return _WideLayout(
      selectedIndex: _selectedIndex,
      onSelect: _selectDestination,
      extended: width >= Breakpoints.medium,
    );
  }
}

// ============================================================
// COMPACT / PHONE LAYOUT
// ============================================================

class _CompactLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _CompactLayout({required this.selectedIndex, required this.onSelect});

  static const List<int> _primaryIndexes = [
    0, // Dashboard
    1, // Journal
    2, // Cashflow
    5, // Supplies
  ];

  bool _isMoreSelected() {
    return selectedIndex == 3 || selectedIndex == 4;
  }

  Future<void> _showMore(BuildContext context) async {
    final theme = Theme.of(context);

    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'More',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                _MoreDestinationTile(
                  destination: _destinations[3],
                  selected: selectedIndex == 3,
                  onTap: () => Navigator.pop(context, 3),
                ),

                _MoreDestinationTile(
                  destination: _destinations[4],
                  selected: selectedIndex == 4,
                  onTap: () => Navigator.pop(context, 4),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null) {
      onSelect(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = [
      for (final index in _primaryIndexes)
        NavigationDestination(
          icon: Icon(_destinations[index].icon),
          selectedIcon: Icon(_destinations[index].selectedIcon),
          label: _destinations[index].label,
        ),

      NavigationDestination(
        icon: Icon(
          _isMoreSelected()
              ? Icons.more_horiz_rounded
              : Icons.more_horiz_outlined,
        ),
        label: 'More',
      ),
    ];

    final selectedNavIndex = _isMoreSelected()
        ? 4
        : _primaryIndexes.indexOf(selectedIndex);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(height: 28),
            const SizedBox(width: 10),
            Text(
              AppStrings.appName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: selectedIndex,
        children: [for (final destination in _destinations) destination.screen],
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: selectedNavIndex < 0 ? 0 : selectedNavIndex,
          onDestinationSelected: (index) {
            if (index == 4) {
              _showMore(context);
              return;
            }

            onSelect(_primaryIndexes[index]);
          },
          destinations: destinations,
        ),
      ),
    );
  }
}

// ============================================================
// MORE TILE
// ============================================================

class _MoreDestinationTile extends StatelessWidget {
  final NavDestinationInfo destination;
  final bool selected;
  final VoidCallback onTap;

  const _MoreDestinationTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          selected ? destination.selectedIcon : destination.icon,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        destination.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}

// ============================================================
// WIDE / TABLET + DESKTOP LAYOUT
// ============================================================

class _WideLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool extended;

  const _WideLayout({
    required this.selectedIndex,
    required this.onSelect,
    required this.extended,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          _BosNavigationRail(
            selectedIndex: selectedIndex,
            onSelect: onSelect,
            extended: extended,
          ),

          Container(
            width: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),

          Expanded(
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerLowest,
              child: IndexedStack(
                index: selectedIndex,
                children: [
                  for (final destination in _destinations) destination.screen,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BOS NAVIGATION RAIL
// ============================================================

class _BosNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool extended;

  const _BosNavigationRail({
    required this.selectedIndex,
    required this.onSelect,
    required this.extended,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: SizedBox(
          width: extended ? 240 : 88,
          child: Column(
            children: [
              _BosBrand(extended: extended),

              const SizedBox(height: 12),

              Expanded(
                child: NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  extended: extended,
                  labelType: NavigationRailLabelType.none,
                  leading: null,
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: _NavigationFooter(extended: extended),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOS BRAND — real logo, not a stand-in icon
// ============================================================

class _BosBrand extends StatelessWidget {
  final bool extended;

  const _BosBrand({required this.extended});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!extended) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.accent.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          padding: const EdgeInsets.all(8),
          child: const AppLogo(height: 32),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.08),
                  AppColors.accent.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(7),
            child: const AppLogo(height: 32),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  AppStrings.appFullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

// ============================================================
// NAVIGATION FOOTER
// ============================================================

class _NavigationFooter extends StatelessWidget {
  final bool extended;

  const _NavigationFooter({required this.extended});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!extended) {
      return IconButton(
        tooltip: 'Settings',
        onPressed: () {},
        icon: const Icon(Icons.settings_outlined),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person_rounded,
              size: 19,
              color: theme.colorScheme.primary,
            ),
          ),

          const SizedBox(width: 10),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Owner',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  'My Business',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PLACEHOLDER
// ============================================================

class _PlaceholderScreen extends StatelessWidget {
  final String title;

  const _PlaceholderScreen({required this.title});

  IconData get _icon {
    switch (title) {
      case 'Customers':
        return Icons.people_rounded;
      case 'Suppliers':
        return Icons.local_shipping_rounded;
      default:
        return Icons.construction_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    _icon,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'This module is coming soon.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 20),

                FilledButton.tonalIcon(
                  onPressed: () {},
                  icon: const Icon(Icons.info_outline_rounded),
                  label: const Text('Module information'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
