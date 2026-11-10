// lib/core/auth/bos_access.dart
//
// Roles, permissions, and the default role -> permission mapping.
// Pure Dart (no Flutter / Drift) so it is trivially unit-testable.
//
// Persist ONLY the stable `id` strings, never enum indexes.

enum BosRole {
  owner('owner', 'Owner'),
  manager('manager', 'Manager'),
  accountant('accountant', 'Accountant'),
  cashier('cashier', 'Cashier'),
  inventory('inventory', 'Inventory'),
  employee('employee', 'Employee'),
  hr('hr', 'HR'),
  staff('staff', 'Staff');

  const BosRole(this.id, this.label);

  /// Stable database value.
  final String id;
  final String label;

  /// Null for unknown / corrupted values. Callers must treat null as
  /// "no access" — never fall back to a permissive role.
  static BosRole? fromId(String? id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return null;
  }
}

enum BosPermission {
  dashboardView('dashboard.view'),

  salesView('sales.view'),
  salesCreate('sales.create'),
  salesEdit('sales.edit'),
  salesVoid('sales.void'),
  salesDiscount('sales.discount'),
  salesStockOnly('sales.stock_only'),
  salesOnCredit('sales.on_credit'),
  onlineStoreManage('online_store.manage'),

  customersView('customers.view'),
  customersCreate('customers.create'),
  customersEdit('customers.edit'),

  inventoryView('inventory.view'),
  inventoryCreate('inventory.create'),
  inventoryEdit('inventory.edit'),
  inventoryAdjust('inventory.adjust'),

  purchasingView('purchasing.view'),
  purchasingCreate('purchasing.create'),
  purchasingEdit('purchasing.edit'),
  purchasingReceive('purchasing.receive'),

  suppliersView('suppliers.view'),
  suppliersCreate('suppliers.create'),
  suppliersEdit('suppliers.edit'),

  financeView('finance.view'),
  financeCreate('finance.create'),
  financeEdit('finance.edit'),
  financePost('finance.post'),
  financeVoid('finance.void'),

  receivablesView('receivables.view'),
  receivablesCreate('receivables.create'),

  payablesView('payables.view'),
  payablesCreate('payables.create'),

  reportsView('reports.view'),

  employeesView('employees.view'),
  employeesManage('employees.manage'),

  hrSelf('hr.self'),
  hrManage('hr.manage'),

  usersView('users.view'),
  usersInvite('users.invite'),
  usersRemove('users.remove'),
  usersManageRoles('users.manage_roles'),

  businessSettings('business.settings'),
  businessManage('business.manage'),
  businessDelete('business.delete'),

  securityManage('security.manage'),

  branchManage('branch.manage'),
  stockTransferCreate('stock.transfer_create'),
  stockTransferReceive('stock.transfer_receive');

  const BosPermission(this.id);

  /// Stable identifier.
  final String id;

  static BosPermission? fromId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Default role -> permission mapping.
///
/// This is the single place role policy lives. It is the initial default,
/// not immutable policy: a later "custom permissions" feature can layer
/// per-business overrides on top of [of] without touching call sites.
abstract final class RolePermissions {
  static final Map<BosRole, Set<BosPermission>> _defaults = {
    BosRole.owner: Set.unmodifiable(BosPermission.values.toSet()),

    BosRole.manager: Set.unmodifiable(<BosPermission>{
      BosPermission.dashboardView,
      BosPermission.salesView,
      BosPermission.salesCreate,
      BosPermission.salesEdit,
      BosPermission.salesVoid,
      BosPermission.salesDiscount,
      BosPermission.salesStockOnly,
      BosPermission.salesOnCredit,
      BosPermission.customersView,
      BosPermission.customersCreate,
      BosPermission.customersEdit,
      BosPermission.inventoryView,
      BosPermission.inventoryCreate,
      BosPermission.inventoryEdit,
      BosPermission.inventoryAdjust,
      BosPermission.purchasingView,
      BosPermission.purchasingCreate,
      BosPermission.purchasingEdit,
      BosPermission.purchasingReceive,
      BosPermission.suppliersView,
      BosPermission.suppliersCreate,
      BosPermission.suppliersEdit,
      BosPermission.reportsView,
      BosPermission.employeesView,
      BosPermission.employeesManage,
      BosPermission.hrManage,
      BosPermission.hrSelf,
      BosPermission.stockTransferCreate,
      BosPermission.stockTransferReceive,
    }),

    BosRole.accountant: Set.unmodifiable(<BosPermission>{
      BosPermission.dashboardView,
      BosPermission.customersView,
      BosPermission.suppliersView,
      BosPermission.financeView,
      BosPermission.financeCreate,
      BosPermission.financeEdit,
      BosPermission.financePost,
      BosPermission.financeVoid,
      BosPermission.receivablesView,
      BosPermission.receivablesCreate,
      BosPermission.payablesView,
      BosPermission.payablesCreate,
      BosPermission.reportsView,
      BosPermission.hrSelf,
    }),

    BosRole.cashier: Set.unmodifiable(<BosPermission>{
      // BosPermission.dashboardView,
      BosPermission.salesView,
      BosPermission.salesCreate,
      BosPermission.onlineStoreManage,
      BosPermission.customersView,
      BosPermission.customersCreate,
      BosPermission.hrSelf,
    }),

    BosRole.inventory: Set.unmodifiable(<BosPermission>{
      // BosPermission.dashboardView,
      BosPermission.inventoryView,
      BosPermission.inventoryCreate,
      BosPermission.inventoryEdit,
      BosPermission.inventoryAdjust,
      BosPermission.purchasingView,
      BosPermission.purchasingCreate,
      BosPermission.purchasingEdit,
      BosPermission.purchasingReceive,
      BosPermission.suppliersView,
      BosPermission.suppliersCreate,
      BosPermission.suppliersEdit,
      BosPermission.hrSelf,
      BosPermission.stockTransferCreate,
      BosPermission.stockTransferReceive,
    }),

    // Read-only basics. Widen deliberately, never by default.
    BosRole.employee: Set.unmodifiable(<BosPermission>{
      // BosPermission.dashboardView,
      BosPermission.inventoryView,
      BosPermission.customersView,
      BosPermission.hrSelf,
    }),

    // People operations: schedules, attendance, leave approval, payroll.
    BosRole.hr: Set.unmodifiable(<BosPermission>{
      BosPermission.dashboardView,
      BosPermission.customersView,
      BosPermission.reportsView,
      BosPermission.employeesView,
      BosPermission.employeesManage,
      BosPermission.usersView,
      BosPermission.hrSelf,
      BosPermission.hrManage,
    }),

    // General floor staff: sell, look up stock, own time and leave.
    BosRole.staff: Set.unmodifiable(<BosPermission>{
      BosPermission.salesView,
      BosPermission.salesCreate,
      BosPermission.customersView,
      BosPermission.customersCreate,
      BosPermission.inventoryView,
      BosPermission.hrSelf,
    }),
  };

  static Set<BosPermission> of(BosRole role) =>
      _defaults[role] ?? const <BosPermission>{};

  static bool allows(BosRole role, BosPermission permission) =>
      of(role).contains(permission);
}

/// Custom roles are stored as `c_<uuid>` in business_members.role.
const String kCustomRolePrefix = 'c_';
