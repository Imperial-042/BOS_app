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
import 'package:bos_application/features/transactions/presentation/screens/suppliers_page.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'core/database/app_database.dart';
import 'core/database/database_provider.dart';

import 'features/transactions/presentation/screens/cashflow_page.dart';
import 'features/transactions/presentation/screens/dashboard_page.dart';
import 'features/transactions/presentation/screens/journal_entry_page.dart';
import 'features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'features/transactions/presentation/screens/transaction_page.dart'
    show
        businessProfileProvider,
        kCurrentBusinessId,
        ledgerVersionProvider,
        paymentAccountsProvider,
        transactionServiceProvider;

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
          return _OnboardingScreen(
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
    screen: _ProfileScreen(),
  ),

  NavDestinationInfo(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    screen: _SettingsScreen(),
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
    const railIndexes = [0, 1, 2, 4, 5, 6, 7];

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
                  selectedIndex: railIndexes.indexOf(selectedIndex),
                  onDestinationSelected: (index) =>
                      onSelect(railIndexes[index]),
                  extended: extended,
                  labelType: NavigationRailLabelType.none,
                  leading: null,
                  destinations: [
                    for (final index in railIndexes)
                      NavigationRailDestination(
                        icon: Icon(_destinations[index].icon),
                        selectedIcon: Icon(_destinations[index].selectedIcon),
                        label: Text(_destinations[index].label),
                      ),
                  ],
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

class _OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinished;

  const _OnboardingScreen({required this.onFinished});

  @override
  Widget build(BuildContext context) {
    return _BusinessProfileEditor(
      title: 'Set up your profile',
      subtitle: 'Add your details now or skip and update them later.',
      showSkip: true,
      showOwnerName: true,
      onFinished: onFinished,
    );
  }
}

class _ProfileScreen extends ConsumerWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(businessProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load profile.')),
        data: (business) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.person_rounded,
                size: 44,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              business.ownerName?.isNotEmpty == true
                  ? business.ownerName!
                  : 'Your name',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              business.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (business.businessCategory?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                business.businessCategory!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (business.managerName?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                'Manager: ${business.managerName}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (business.addressCity?.isNotEmpty == true ||
                business.addressProvince?.isNotEmpty == true ||
                business.addressCountry?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                [
                      business.addressCity,
                      business.addressBarangay,
                      business.addressProvince,
                      business.addressCountry,
                      business.addressZipCode,
                    ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(', '),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _BusinessProfileEditor(
                      title: 'Edit profile',
                      subtitle: 'Update your name and business details.',
                      onFinished: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openBusinessSwitcher(context, ref),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Switch business'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _addBusiness(context, ref, business),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add another business'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBusinessSwitcher(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final db = ref.read(databaseProvider);
    final businesses = await db.select(db.businesses).get();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Your businesses',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final item in businesses)
              ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(item.name),
                subtitle: Text(item.businessCategory ?? 'Business'),
                selected: item.id == kCurrentBusinessId,
                onTap: () async {
                  if (item.id != kCurrentBusinessId) {
                    await db.transaction(() async {
                      await (db.update(db.businesses)).write(
                        const BusinessesCompanion(isCurrent: Value(false)),
                      );
                      await (db.update(db.businesses)
                            ..where((business) => business.id.equals(item.id)))
                          .write(
                            const BusinessesCompanion(isCurrent: Value(true)),
                          );
                    });
                    kCurrentBusinessId = item.id;
                    ref.read(ledgerVersionProvider.notifier).state++;
                  }
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBusiness(
    BuildContext context,
    WidgetRef ref,
    BusinessesData currentBusiness,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _BusinessNameDialog(),
    );

    if (name == null || !context.mounted) return;

    try {
      final db = ref.read(databaseProvider);
      final businessId = const Uuid().v4();

      await db.transaction(() async {
        await (db.update(
          db.businesses,
        )).write(const BusinessesCompanion(isCurrent: Value(false)));
        await db
            .into(db.businesses)
            .insert(
              BusinessesCompanion.insert(
                id: businessId,
                name: name,
                ownerUserId: currentBusiness.ownerUserId,
                isCurrent: const Value(true),
              ),
            );
        await db.seedDefaultsForBusiness(businessId);
      });

      kCurrentBusinessId = businessId;
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _BusinessProfileEditor(
            title: 'Set up $name',
            subtitle:
                'Complete the business details. Owner name is optional here.',
            showSkip: true,
            showOwnerName: false,
            onFinished: () => Navigator.pop(context),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to add business: $error')));
    }
  }
}

class _BusinessNameDialog extends StatefulWidget {
  const _BusinessNameDialog();

  @override
  State<_BusinessNameDialog> createState() => _BusinessNameDialogState();
}

class _BusinessNameDialogState extends State<_BusinessNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add another business'),
      content: TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.words,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Business name',
          prefixIcon: Icon(Icons.business_outlined),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(context, value);
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _PsgcPlace {
  final String code;
  final String name;

  const _PsgcPlace({required this.code, required this.name});

  factory _PsgcPlace.fromJson(Map<String, dynamic> json) {
    return _PsgcPlace(
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }
}

class _BusinessProfileEditor extends ConsumerStatefulWidget {
  final String title;
  final String subtitle;
  final bool showSkip;
  final bool showOwnerName;
  final VoidCallback onFinished;

  const _BusinessProfileEditor({
    required this.title,
    required this.subtitle,
    this.showSkip = false,
    this.showOwnerName = true,
    required this.onFinished,
  });

  @override
  ConsumerState<_BusinessProfileEditor> createState() =>
      _BusinessProfileEditorState();
}

class _BusinessProfileEditorState
    extends ConsumerState<_BusinessProfileEditor> {
  final _ownerController = TextEditingController();
  final _managerController = TextEditingController();
  final _businessController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _zipController = TextEditingController();
  final _capitalController = TextEditingController();
  String? _category;
  String? _country;
  String? _province;
  String? _city;
  String? _barangay;
  String? _capitalAccountId;
  BusinessesData? _business;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  static const _categories = [
    'Retail',
    'Food and beverage',
    'Services',
    'Manufacturing',
    'Agriculture',
    'Construction',
    'Online business',
    'Other',
  ];

  static const _countries = [
    'Philippines',
    'United States',
    'Canada',
    'United Kingdom',
    'Australia',
    'Other',
  ];

  List<_PsgcPlace> _provinces = [];
  List<_PsgcPlace> _cities = [];
  List<_PsgcPlace> _barangays = [];
  bool _locationsLoading = false;
  String? _locationsError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(databaseProvider);
      final business = await (db.select(
        db.businesses,
      )..where((item) => item.id.equals(kCurrentBusinessId))).getSingle();

      if (!mounted) return;
      _ownerController.text = business.ownerName ?? '';
      _managerController.text = business.managerName ?? '';
      _business = business;
      _businessController.text = business.name == 'My Business'
          ? ''
          : business.name;
      _category = business.businessCategory?.isEmpty == true
          ? null
          : business.businessCategory;
      _country = business.addressCountry;
      _province = business.addressProvince;
      _city = business.addressCity;
      _barangay = business.addressBarangay;
      _provinceController.text = business.addressProvince ?? '';
      _cityController.text = business.addressCity ?? '';
      _zipController.text = business.addressZipCode ?? '';
      _capitalController.text = business.startingCapital == 0
          ? ''
          : (business.startingCapital / 100).toStringAsFixed(2);
      _capitalAccountId = business.startingCapitalAccountId;
      if (_country == 'Philippines') {
        await _loadProvinces();
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Unable to load your profile. Please try again.';
      });
    }
  }

  Future<List<_PsgcPlace>> _fetchPlaces(String path) async {
    final response = await http.get(
      Uri.parse('https://psgc.gitlab.io/api/$path'),
    );
    if (response.statusCode != 200) {
      throw StateError('Location service returned ${response.statusCode}.');
    }
    final values = jsonDecode(response.body) as List<dynamic>;
    return values
        .map((value) => _PsgcPlace.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadProvinces() async {
    setState(() {
      _locationsLoading = true;
      _locationsError = null;
    });
    try {
      final provinces = await _fetchPlaces('provinces');
      if (!mounted) return;
      setState(() {
        _provinces = provinces;
        _locationsLoading = false;
      });
      final selected = provinces
          .where((item) => item.name == _province)
          .firstOrNull;
      if (selected != null) await _loadCities(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationsLoading = false;
        _locationsError = 'Unable to load Philippine locations.';
      });
    }
  }

  Future<void> _loadCities(_PsgcPlace province) async {
    final cities = await _fetchPlaces(
      'provinces/${province.code}/cities-municipalities',
    );
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _barangays = [];
    });
    final selected = cities.where((item) => item.name == _city).firstOrNull;
    if (selected != null) await _loadBarangays(selected);
  }

  Future<void> _loadBarangays(_PsgcPlace city) async {
    final barangays = await _fetchPlaces(
      'cities-municipalities/${city.code}/barangays',
    );
    if (!mounted) return;
    setState(() => _barangays = barangays);
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _managerController.dispose();
    _businessController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _zipController.dispose();
    _capitalController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool skip}) async {
    final capitalText = _capitalController.text.replaceAll(',', '').trim();
    final capital = capitalText.isEmpty ? null : double.tryParse(capitalText);
    if (!skip && capitalText.isNotEmpty && (capital == null || capital < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid starting capital amount.')),
      );
      return;
    }

    if (!skip && capital != null && capital > 0 && _capitalAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select the account holding the starting capital.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final business = _business;
    final capitalCents = capital == null || capital <= 0
        ? 0
        : (capital * 100).round();
    final province = _country == 'Philippines'
        ? _province
        : (_provinceController.text.trim().isEmpty
              ? null
              : _provinceController.text.trim());
    final city = _country == 'Philippines'
        ? _city
        : (_cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim());

    if (!skip &&
        capitalCents > 0 &&
        business != null &&
        business.startingCapital == 0) {
      final categories =
          await (db.select(db.categories)..where(
                (category) =>
                    category.businessId.equals(kCurrentBusinessId) &
                    category.name.equals('Additional Capital') &
                    category.txnType.equals('income'),
              ))
              .get();
      if (categories.isNotEmpty) {
        await ref
            .read(transactionServiceProvider)
            .saveIncome(
              date: DateTime.now(),
              categoryId: categories.first.id,
              amount: capitalCents,
              paymentAccountId: _capitalAccountId,
              description: 'Starting capital',
              markAsPending: false,
            );
      }
    }

    await (db.update(
      db.businesses,
    )..where((business) => business.id.equals(kCurrentBusinessId))).write(
      BusinessesCompanion(
        name: Value(
          skip || _businessController.text.trim().isEmpty
              ? 'My Business'
              : _businessController.text.trim(),
        ),
        ownerName: Value(
          skip || _ownerController.text.trim().isEmpty
              ? ''
              : _ownerController.text.trim(),
        ),
        managerName: Value(
          skip || _managerController.text.trim().isEmpty
              ? null
              : _managerController.text.trim(),
        ),
        businessCategory: Value(skip ? '' : _category ?? ''),
        addressCountry: Value(skip ? '' : _country ?? ''),
        addressProvince: Value(skip ? '' : province ?? ''),
        addressCity: Value(skip ? '' : city ?? ''),
        addressBarangay: Value(skip ? '' : _barangay ?? ''),
        addressZipCode: Value(
          skip || _zipController.text.trim().isEmpty
              ? null
              : _zipController.text.trim(),
        ),
        startingCapital: Value(skip ? 0 : capitalCents),
        startingCapitalAccountId: Value(skip ? null : _capitalAccountId),
      ),
    );

    if (!mounted) return;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: FilledButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _loadError = null;
              });
              _load();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Text(
            widget.subtitle,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (widget.showOwnerName) ...[
            TextField(
              controller: _ownerController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _managerController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Manager name (optional)',
              prefixIcon: Icon(Icons.manage_accounts_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _businessController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Business name',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Business category',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: _categories
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 24),
          Text(
            'Business address',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _country,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Country',
              prefixIcon: Icon(Icons.public_outlined),
            ),
            items: _countries
                .map(
                  (country) =>
                      DropdownMenuItem(value: country, child: Text(country)),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) async {
                    setState(() {
                      _country = value;
                      _province = null;
                      _city = null;
                      _barangay = null;
                      _provinces = [];
                      _cities = [];
                      _barangays = [];
                      _provinceController.clear();
                      _cityController.clear();
                    });
                    if (value == 'Philippines') await _loadProvinces();
                  },
          ),
          const SizedBox(height: 12),
          if (_country == 'Philippines') ...[
            if (_locationsLoading) const LinearProgressIndicator(),
            if (_locationsError != null)
              Text(_locationsError!, style: TextStyle(color: scheme.error)),
            DropdownButtonFormField<String>(
              initialValue: _provinces.any((item) => item.name == _province)
                  ? _province
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Province',
                prefixIcon: Icon(Icons.map_outlined),
              ),
              items: _provinces
                  .map(
                    (province) => DropdownMenuItem<String>(
                      value: province.name,
                      child: Text(province.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) async {
                      final place = _provinces
                          .where((item) => item.name == value)
                          .firstOrNull;
                      setState(() {
                        _province = value;
                        _city = null;
                        _barangay = null;
                      });
                      if (place != null) await _loadCities(place);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cities.any((item) => item.name == _city)
                  ? _city
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'City',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: _cities
                  .map(
                    (city) => DropdownMenuItem<String>(
                      value: city.name,
                      child: Text(city.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) async {
                      final place = _cities
                          .where((item) => item.name == value)
                          .firstOrNull;
                      setState(() {
                        _city = value;
                        _barangay = null;
                      });
                      if (place != null) await _loadBarangays(place);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _barangays.any((item) => item.name == _barangay)
                  ? _barangay
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Barangay',
                prefixIcon: Icon(Icons.holiday_village_outlined),
              ),
              items: _barangays
                  .map(
                    (barangay) => DropdownMenuItem<String>(
                      value: barangay.name,
                      child: Text(barangay.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _barangay = value),
            ),
          ] else ...[
            TextField(
              controller: _provinceController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Province / state',
                prefixIcon: Icon(Icons.map_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'City',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _zipController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'ZIP / postal code (optional)',
              prefixIcon: Icon(Icons.markunread_mailbox_outlined),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Starting capital',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _capitalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Starting capital (optional)',
              prefixText: '₱ ',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: 12),
          accountsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => Text(
              'Unable to load accounts.',
              style: TextStyle(color: scheme.error),
            ),
            data: (accounts) => DropdownButtonFormField<String>(
              initialValue:
                  accounts.any((account) => account.id == _capitalAccountId)
                  ? _capitalAccountId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Capital account',
                hintText: 'Cash, bank, or e-wallet',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              items: accounts
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _capitalAccountId = value),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(skip: false),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save profile'),
          ),
          if (widget.showSkip)
            TextButton(
              onPressed: _saving ? null : () => _save(skip: true),
              child: const Text('Skip for now'),
            ),
        ],
      ),
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Profile & businesses'),
            subtitle: const Text('Manage your profile and switch businesses'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _ProfileScreen()),
              );
            },
          ),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Theme preferences'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          ListTile(
            leading: Icon(Icons.currency_exchange_rounded),
            title: Text('Currency'),
            subtitle: Text('Philippine Peso (PHP)'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('About BOS'),
            subtitle: Text('Business Operating System'),
          ),
        ],
      ),
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
