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
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/products_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/profile_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/settings_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/suppliers_page.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/database/app_database.dart';
import 'core/database/database_provider.dart';
import 'features/transactions/presentation/screens/cashflow_page.dart';
import 'features/transactions/presentation/screens/dashboard_page.dart';
import 'features/transactions/presentation/screens/journal_entry_page.dart';
import 'features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'features/transactions/presentation/screens/transaction_page.dart'
    show businessProfileProvider, kCurrentBusinessId;

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
  late Future<BusinessesData> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _ensureBusinessExists();
  }

  Future<BusinessesData> _ensureBusinessExists() async {
    final db = ref.read(databaseProvider);

    var existing = await db.select(db.businesses).get();

    if (existing.isEmpty) {
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: kCurrentBusinessId,
              name: 'My Business',
              ownerUserId: 'owner_001',
              isCurrent: const Value(true),
            ),
          );

      await db.seedDefaultsForBusiness(kCurrentBusinessId);
      existing = await db.select(db.businesses).get();
    }

    final current = existing.firstWhere(
      (business) => business.isCurrent,
      orElse: () => existing.first,
    );
    kCurrentBusinessId = current.id;

    if (!current.isCurrent) {
      await (db.update(db.businesses)
            ..where((business) => business.id.equals(current.id)))
          .write(const BusinessesCompanion(isCurrent: Value(true)));
    }

    return (db.select(
      db.businesses,
    )..where((business) => business.id.equals(kCurrentBusinessId))).getSingle();
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
          return _StartupErrorScreen(
            error: snapshot.error,
            onRetry: () {
              setState(() {
                _initFuture = _ensureBusinessExists();
              });
            },
          );
        }

        final business = snapshot.data!;
        final profileIncomplete =
            business.ownerName == null || business.businessCategory == null;

        if (profileIncomplete) {
          return OnboardingScreen(
            onFinished: () {
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
    label: 'Profile',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    screen: ProfileScreen(),
  ),

  NavDestinationInfo(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    screen: SettingsScreen(),
  ),

  NavDestinationInfo(
    label: 'Customers',
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    screen: CustomersPage(),
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
  NavDestinationInfo(
    label: 'Inventory',
    icon: Icons.inventory,
    selectedIcon: Icons.shopping_cart_rounded,
    screen: ProductsPage(),
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
  ];

  @override
  Widget build(BuildContext context) {
    final destinations = [
      for (final index in _primaryIndexes)
        NavigationDestination(
          icon: Icon(_destinations[index].icon),
          selectedIcon: Icon(_destinations[index].selectedIcon),
          label: _destinations[index].label,
        ),
    ];

    return Scaffold(
      appBar: const _ShellAppBar(showMenu: true),
      body: IndexedStack(
        index: selectedIndex,
        children: [for (final destination in _destinations) destination.screen],
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _primaryIndexes
              .indexOf(selectedIndex)
              .clamp(0, 2)
              .toInt(),
          onDestinationSelected: (index) {
            onSelect(_primaryIndexes[index]);
          },
          destinations: destinations,
        ),
      ),
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
              child: Scaffold(
                appBar: const _ShellAppBar(showMenu: false),
                body: IndexedStack(
                  index: selectedIndex,
                  children: [
                    for (final destination in _destinations) destination.screen,
                  ],
                ),
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
    final scheme = theme.colorScheme;

    const railIndexes = [
      0, // Dashboard
      1, // Journal
      2, // Cashflow
      4, // Settings
      5, // Customers
      6, // Suppliers
      7, // Supplies
      8, // Inventory
    ];

    // Tablet: 13px
    // Desktop: 14px
    final fontSize = extended ? 14.0 : 13.0;

    final navigationRailTheme = theme.navigationRailTheme.copyWith(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      groupAlignment: -0.72,
    );

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: SizedBox(
          width: extended ? 240 : 150,
          child: Column(
            children: [
              _BosBrand(extended: extended),

              const SizedBox(height: 12),

              Expanded(
                child: Theme(
                  data: theme.copyWith(
                    navigationRailTheme: navigationRailTheme,
                    textTheme: theme.textTheme.copyWith(
                      labelMedium: theme.textTheme.labelMedium?.copyWith(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  child: NavigationRail(
                    selectedIndex: railIndexes.indexOf(selectedIndex),

                    onDestinationSelected: (index) {
                      if (index >= 0 && index < railIndexes.length) {
                        onSelect(railIndexes[index]);
                      }
                    },

                    extended: extended,

                    // Tablet: labels visible.
                    // Desktop: labels beside icons.
                    labelType: extended
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,

                    destinations: [
                      for (final index in railIndexes)
                        NavigationRailDestination(
                          icon: Icon(
                            _destinations[index].icon,
                            size: extended ? 24 : 23,
                          ),
                          selectedIcon: Icon(
                            _destinations[index].selectedIcon,
                            size: extended ? 25 : 24,
                          ),
                          label: Text(
                            _destinations[index].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: _NavigationFooter(
                  extended: extended,
                  onProfile: () => onSelect(3),
                  onSettings: () => onSelect(4),
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
// BOS BRAND — real logo, not a stand-in icon
// ============================================================

class _BosBrand extends ConsumerWidget {
  final bool extended;

  const _BosBrand({required this.extended});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final business = ref
        .watch(businessProfileProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);

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
                  business?.name.isNotEmpty == true
                      ? business!.name
                      : AppStrings.appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  business?.businessCategory?.isNotEmpty == true
                      ? business!.businessCategory!
                      : AppStrings.appFullName,
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

class _ShellAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final bool showMenu;

  const _ShellAppBar({required this.showMenu});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref
        .watch(businessProfileProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    return AppBar(
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(height: 28),
          const SizedBox(width: 10),
          Text(
            business?.name.isNotEmpty == true
                ? business!.name
                : AppStrings.appName,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
      actions: showMenu
          ? [
              PopupMenuButton<int>(
                tooltip: 'More',
                icon: const Icon(Icons.menu_rounded),
                onSelected: (index) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _destinations[index].screen,
                    ),
                  );
                },
                itemBuilder: (context) => [
                  for (var index = 3; index < _destinations.length; index++)
                    PopupMenuItem<int>(
                      value: index,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_destinations[index].icon),
                        title: Text(_destinations[index].label),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
            ]
          : null,
    );
  }
}

class _NavigationFooter extends ConsumerWidget {
  final bool extended;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  const _NavigationFooter({
    required this.extended,
    required this.onProfile,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (!extended) {
      return IconButton(
        tooltip: 'Settings',
        onPressed: onSettings,
        color: AppColors.primary,
        icon: const Icon(Icons.settings_rounded),
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
      child: InkWell(
        onTap: onSettings,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Profile',
              onPressed: onProfile,
              color: AppColors.primary,
              icon: const Icon(Icons.person_rounded),
            ),

            const Expanded(
              child: Text(
                'Profile',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),

            IconButton(
              tooltip: 'Open settings',
              visualDensity: VisualDensity.compact,
              onPressed: onSettings,
              color: AppColors.primary,
              icon: const Icon(Icons.settings_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
