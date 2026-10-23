// lib/core/audit/audit_enums.dart
//
// Stable ids stored in audit_logs.module / audit_logs.action_type.
// Never rename an id once shipped: old rows (local and cloud) keep it.

enum AuditModule {
  finance('finance', 'Finance'),
  inventory('inventory', 'Inventory'),
  sales('sales', 'Sales & POS'),
  people('people', 'People'),
  administration('administration', 'Administration'),
  security('security', 'Security');

  const AuditModule(this.id, this.label);
  final String id;
  final String label;

  static AuditModule? fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
}

enum AuditActionType {
  create('create', 'Created'),
  update('update', 'Updated'),
  delete('delete', 'Deleted'),
  voided('void', 'Voided'),
  refund('refund', 'Refunded'),
  adjustment('adjustment', 'Adjusted'),
  permission('permission', 'Permission change'),
  export('export', 'Data export'),
  security('security', 'Security event');

  const AuditActionType(this.id, this.label);
  final String id;
  final String label;

  /// Destructive/financial actions must say why.
  bool get requiresReason =>
      this == voided || this == refund || this == adjustment;

  static AuditActionType? fromId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}
