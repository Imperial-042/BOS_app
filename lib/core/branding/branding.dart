// lib/core/branding/app_branding.dart
//
// SINGLE SOURCE OF TRUTH for the app's visual identity and text
// labels. Change the logo, palette, or app name HERE — every
// screen that uses AppTheme/AppColors/AppAssets/AppStrings
// picks up the change automatically, no per-file edits needed.
//
// Setup:
// 1. Put the two logo files in your Flutter project at:
//      assets/images/bos_icon.png
//      assets/images/bos_logo_full.png
//    (PNG with transparency is strongly preferred over JPG here —
//    the versions you uploaded are .jpg, which bakes in a white/
//    checkered background instead of true transparency. If you
//    have the original PNG source, use that; otherwise these JPGs
//    will still work but won't blend cleanly over colored
//    backgrounds like the Dashboard's gradient hero card.)
//
// 2. Add to pubspec.yaml:
//      flutter:
//        assets:
//          - assets/images/
//
// 3. Use AppTheme.light() and AppTheme.dark() in MaterialApp.

import 'package:flutter/material.dart';

// ============================================================
// COLORS — change these two values and the whole app re-themes.
// ============================================================

class AppColors {
  AppColors._();

  /// The deep navy from the logo's loop mark.
  static const primary = Color(0xFF0D3B5C);

  /// The teal from the logo's arrow.
  static const accent = Color(0xFF1F9A96);

  // Derived / supporting shades — kept here so nothing downstream
  // hardcodes a color that isn't traceable back to this file.
  static const primaryLight = Color(0xFF2E6E92);
  static const accentLight = Color(0xFF4FC3BE);

  static const success = Color(0xFF2E9E5B);
  static const danger = Color(0xFFE0524B);
  static const warning = Color(0xFFF2A93B);

  /// Text-safe (darker) shades for badges and labels on light backgrounds.
  static const successDark = Color(0xFF237A47);
  static const warningDark = Color(0xFFC77700);

  /// The gradient used on hero/summary cards (Dashboard, Cashflow
  /// total balance). Kept as a named pair so every "big number"
  /// card in the app looks like it belongs to the same product.
  static const heroGradient = [primary, primaryLight];

  /// Accent palette for per-account/per-category color coding
  /// (Cashflow account cards, Dashboard category legends). Built
  /// from the brand pair plus a few complementary tones so charts
  /// stay legible without clashing with the primary brand color.
  static const chartPalette = <Color>[
    primary,
    accent,
    warning,
    danger,
    primaryLight,
    accentLight,
    Color(0xFF7C5CBF), // complementary violet, for a 7th+ category
  ];

  /// Card gradients for Cashflow account tiles — pairs, not single
  /// colors, since those cards use a diagonal gradient background.
  static const accountGradients = <List<Color>>[
    [primary, primaryLight],
    [accent, accentLight],
    [warning, Color(0xFFF2C94C)],
    [danger, warning],
    [Color(0xFF2F80ED), Color(0xFF56CCF2)],
    [Color(0xFF7C5CBF), Color(0xFFB18CF2)],
  ];
}

// ============================================================
// STRINGS — every user-facing label the app uses, in one place.
// Rename the app, retitle a screen, or adjust copy here instead
// of hunting through each screen file.
// ============================================================

class AppStrings {
  AppStrings._();

  static const appName = 'Business OS';
  static const appFullName = 'Business Operating System';
  static const tagline = 'Run your business from one place.';

  // Navigation labels
  static const navDashboard = 'Dashboard';
  static const navJournal = 'Journal';
  static const navCashflow = 'Cashflow';
  static const navCustomers = 'Customers';
  static const navSuppliers = 'Suppliers';
  static const navSupplies = 'Supplies';

  // Screen titles
  static const dashboardTitle = 'Dashboard';
  static const journalEntryTitle = 'Journal Entry';
  static const transactionTitle = 'Transaction';
  static const cashflowTitle = 'My Cashflow';
  static const suppliesPriceListTitle = 'Supplies Price List';
  static const cartTitle = 'Cart';

  // Common actions
  static const save = 'Save';
  static const update = 'Update';
  static const cancel = 'Cancel';
  static const delete = 'Delete';
  static const addNew = 'Add New';
}

// ============================================================
// ASSETS — every image path the app references, in one place.
// Swap the logo by changing the path here, not in every screen.
// ============================================================

class AppAssets {
  AppAssets._();

  static const logoIcon =
      'lib/core/assets/images/BOS_Icon.png'; // mark only, square — app icon, splash
  static const logoFull =
      'lib/core/assets/images/BOS_Icon.png'; // mark + wordmark — login/startup screens
}

class AppColorOption {
  const AppColorOption({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;
}

// ============================================================
// THEME — built entirely from AppColors above. Nothing in this
// class should ever hardcode a color that isn't from AppColors.
// ============================================================

class AppTheme {
  AppTheme._();

  static const colorOptions = <AppColorOption>[
    AppColorOption(id: 'bos', name: 'BOS navy', color: AppColors.primary),
    AppColorOption(id: 'ocean', name: 'Ocean blue', color: Color(0xFF1769AA)),
    AppColorOption(id: 'emerald', name: 'Emerald', color: Color(0xFF18794E)),
    AppColorOption(id: 'violet', name: 'Violet', color: Color(0xFF6941C6)),
    AppColorOption(id: 'amber', name: 'Amber', color: Color(0xFF9A5B00)),
  ];

  static ThemeData light({
    Color seedColor = AppColors.primary,
    String? fontFamily,
  }) => _build(Brightness.light, seedColor, fontFamily);

  static ThemeData dark({
    Color seedColor = AppColors.primary,
    String? fontFamily,
  }) => _build(Brightness.dark, seedColor, fontFamily);

  static ThemeData _build(
    Brightness brightness,
    Color seedColor,
    String? fontFamily,
  ) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      secondary: AppColors.accent,
      brightness: brightness,
    );
    final rounded16 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    OutlineInputBorder inputBorder([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: side,
        );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorShape: rounded16,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        indicatorShape: rounded16,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          backgroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        border: inputBorder(),
        enabledBorder: inputBorder(),
        focusedBorder: inputBorder(
          BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ============================================================
// LOGO WIDGET — a ready-to-use widget so screens don't each
// re-implement "show the logo with the right asset path."
// ============================================================

class AppLogo extends StatelessWidget {
  final double height;
  final bool showWordmark;
  const AppLogo({super.key, this.height = 48, this.showWordmark = false});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      showWordmark ? AppAssets.logoFull : AppAssets.logoIcon,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.business_center, size: height, color: AppColors.primary),
    );
  }
}
