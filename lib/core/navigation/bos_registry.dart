// lib/core/navigation/bos_registry.dart
//
// Navigation model — single source of truth for modules and destinations.
// Moved verbatim out of main.dart. Private names became public so the shell,
// permissions and layouts can share them.
//
// To add a module: add a value to [BosModule], a [BosModuleInfo] in
// [bosModules], and its [BosDestination]s in [bosDestinations].

import 'package:flutter/material.dart';

// CartPage, PurchaseHistoryPage and AllStockAdjustmentsPage come from one of the
// imports below; if the analyzer reports them undefined, add the import that
// declares them.
import 'package:bos_application/features/branches/branches_screen.dart';
import 'package:bos_application/features/customer/presentation/customer_storefront_management_screen.dart';
import 'package:bos_application/features/customer/presentation/rewards_page.dart';
import 'package:bos_application/features/inventory/stock_transfers_page.dart';
import 'package:bos_application/features/auth/presentation/screens/permissions_screen.dart';
import 'package:bos_application/features/auth/presentation/screens/security_screen.dart';
import 'package:bos_application/features/auth/presentation/screens/users_roles_screen.dart';
import 'package:bos_application/features/transactions/presentation/attendance_screen.dart';
import 'package:bos_application/features/transactions/presentation/leave_screen.dart';
import 'package:bos_application/features/transactions/presentation/payroll_screen.dart';
import 'package:bos_application/features/transactions/presentation/schedules_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/aging_report_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/audit_trail_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/cashflow_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/categories_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/chart_of_accounts_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/customers_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/dashboard_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/employees_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/expenses_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/financial_reports_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/import_export_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/income_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/inventory_report_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/journal_entry_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/orders_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/payables_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/products_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/profile_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/receivables_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/returns_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/sales_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/settings_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/suppliers_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/transfers_page.dart';

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
  /// Inside the shell, under the app bar.
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
  static const onlineStore = 'sales.onlineStore';
  static const rewards = 'sales.rewards';

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
    id: BosDest.onlineStore,
    module: BosModule.salesPos,
    label: 'Online store',
    description: 'Manage branch listings and online customer orders.',
    icon: Icons.storefront_outlined,
    builder: (_) => const CustomerStorefrontManagementScreen(),
  ),
  BosDestination(
    id: BosDest.rewards,
    module: BosModule.salesPos,
    label: 'Rewards',
    description: 'Manage customer loyalty points and rewards.',
    icon: Icons.stars_outlined,
    builder: (_) => const RewardsPage(),
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

final Map<BosModule, BosModuleInfo> bosModuleInfo = {
  for (final m in bosModules) m.module: m,
};

final Map<String, BosDestination> bosDestById = {
  for (final d in bosDestinations) d.id: d,
};

List<BosDestination> destinationsOf(BosModule module) =>
    bosDestinations.where((d) => d.module == module).toList();

/// Pages listed in a module's rail group, bar and quick switcher.
List<BosDestination> availableIn(BosModule module) =>
    destinationsOf(module).where((d) => d.isAvailable).toList();

String bosHubKey(BosModule module) => 'hub.${module.name}';

/// Everything that lives in the shell's IndexedStack: a landing page per
/// module without a `homeId`, plus every embedded destination.
final List<String> bosViewKeys = [
  for (final info in bosModules) ...[
    if (info.homeId == null) bosHubKey(info.module),
    for (final d in destinationsOf(info.module))
      if (d.presentation == BosPresentation.embedded) d.id,
  ],
];

/// Modules pinned beside the phone's centre menu button. Every other module
/// opens from the floating menu.
const List<BosModule> phoneBarModules = [
  BosModule.management,
  BosModule.salesPos,
  BosModule.finance,
  BosModule.inventory,
];

/// Account shortcuts shown under "More" / in the drawer. They open pages that
/// belong to Administration.
const List<String> accountShortcuts = [BosDest.profile, BosDest.settings];

/// Visible modules bucketed by classification, in BosGroup order.
Map<BosGroup, List<BosModuleInfo>> groupModules(List<BosModuleInfo> infos) => {
  for (final g in BosGroup.values)
    if (infos.any((i) => i.group == g))
      g: [
        for (final i in infos)
          if (i.group == g) i,
      ],
};
