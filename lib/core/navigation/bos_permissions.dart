// lib/core/navigation/bos_permissions.dart
//
// Which destinations and modules a signed-in member may see/open.
// Moved verbatim out of main.dart; names made public.

import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/navigation/bos_registry.dart';

/// Permission required to OPEN each destination. Missing => owner-only.
const Map<String, BosPermission> destPermission = {
  BosDest.dashboard: BosPermission.dashboardView,

  BosDest.journal: BosPermission.financeView,
  BosDest.cashflow: BosPermission.financeView,
  BosDest.reports: BosPermission.reportsView,
  BosDest.aging: BosPermission.reportsView,
  BosDest.income: BosPermission.financeView,
  BosDest.expenses: BosPermission.financeView,
  BosDest.receivables: BosPermission.receivablesView,
  BosDest.payables: BosPermission.payablesView,
  BosDest.transfers: BosPermission.financeView,

  BosDest.supplies: BosPermission.inventoryView,
  BosDest.inventoryReport: BosPermission.inventoryView,
  BosDest.products: BosPermission.inventoryView,
  BosDest.suppliers: BosPermission.suppliersView,
  BosDest.purchaseCart: BosPermission.purchasingView,
  BosDest.purchaseHistory: BosPermission.purchasingView,
  BosDest.stockAdjustments: BosPermission.inventoryView,

  BosDest.pos: BosPermission.salesView,
  BosDest.onlineStore: BosPermission.onlineStoreManage,
  BosDest.rewards: BosPermission.businessSettings,
  BosDest.customers: BosPermission.customersView,
  BosDest.sales: BosPermission.salesView,
  BosDest.orders: BosPermission.salesView,
  BosDest.returns: BosPermission.salesView,

  BosDest.employees: BosPermission.employeesView,
  BosDest.attendance: BosPermission.hrSelf,
  BosDest.schedules: BosPermission.hrSelf,
  BosDest.leave: BosPermission.hrSelf,
  BosDest.payroll: BosPermission.employeesManage,

  BosDest.settings: BosPermission.businessSettings,
  BosDest.usersRoles: BosPermission.usersView,
  BosDest.permissions: BosPermission.securityManage,
  BosDest.chartOfAccounts: BosPermission.financeEdit,
  BosDest.categories: BosPermission.financeEdit,
  BosDest.security: BosPermission.securityManage,
  BosDest.importExport: BosPermission.businessManage,
  BosDest.branches: BosPermission.branchManage,
  BosDest.stockTransfers: BosPermission.stockTransferCreate,
};

bool canOpen(AuthorizationService auth, String destinationId) {
  // Every active member may open their own profile.
  if (destinationId == BosDest.profile) {
    return auth.currentMembership != null;
  }
  // Transfers page: sending OR receiving is enough to open it.
  if (destinationId == BosDest.stockTransfers) {
    return auth.can(BosPermission.stockTransferCreate) ||
        auth.can(BosPermission.stockTransferReceive);
  }
  return auth.can(destPermission[destinationId] ?? BosPermission.businessManage);
}

List<BosDestination> visibleDestinations(
  AuthorizationService auth,
  BosModule module,
) => destinationsOf(module).where((d) => canOpen(auth, d.id)).toList();

List<BosDestination> visibleAvailable(
  AuthorizationService auth,
  BosModule module,
) => availableIn(module).where((d) => canOpen(auth, d.id)).toList();

bool moduleVisible(AuthorizationService auth, BosModule module) {
  final info = bosModuleInfo[module]!;
  final home = info.homeId;
  if (home != null) return canOpen(auth, home);
  return visibleDestinations(auth, module).isNotEmpty;
}

/// Per-business module switch, layered on top of role visibility.
/// Administration always stays on (it hosts the toggles themselves).
bool moduleEnabled(Map<String, bool> configs, BosModule module) =>
    module == BosModule.administration || (configs[module.name] ?? true);

List<BosModuleInfo> visibleModules(
  AuthorizationService auth, [
  Map<String, bool> moduleConfigs = const {},
]) => bosModules
    .where(
      (m) =>
          moduleEnabled(moduleConfigs, m.module) && moduleVisible(auth, m.module),
    )
    .toList();

/// In the wide rail, Administration is hidden when Profile is the only page
/// the person can open there (Profile already lives at the rail's bottom).
bool profileOnly(AuthorizationService auth, BosModuleInfo info) {
  if (info.module != BosModule.administration) return false;
  return visibleDestinations(auth, info.module)
      .every((d) => d.id == BosDest.profile);
}
