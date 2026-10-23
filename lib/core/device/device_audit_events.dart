import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';

abstract final class DeviceAuditEvents {
  static AuditEvent revoked({required String deviceUuid, String? deviceName}) =>
      AuditEvent(
        module: AuditModule.security,
        actionType: AuditActionType.security,
        action: 'device.revoked',
        entityType: 'user_devices',
        entityId: deviceUuid,
        entityLabel: deviceName,
        before: {'status': 'active'},
        after: {'status': 'revoked'},
      );

  static AuditEvent reactivated({
    required String deviceUuid,
    String? deviceName,
  }) => AuditEvent(
    module: AuditModule.security,
    actionType: AuditActionType.security,
    action: 'device.reactivated',
    entityType: 'user_devices',
    entityId: deviceUuid,
    entityLabel: deviceName,
    before: {'status': 'revoked'},
    after: {'status': 'active'},
  );

  static AuditEvent renamed({
    required String deviceUuid,
    required String oldName,
    required String newName,
  }) => AuditEvent(
    module: AuditModule.security,
    actionType: AuditActionType.security,
    action: 'device.renamed',
    entityType: 'user_devices',
    entityId: deviceUuid,
    entityLabel: newName,
    before: {'name': oldName},
    after: {'name': newName},
  );

  static const othersSignedOut = AuditEvent(
    module: AuditModule.security,
    actionType: AuditActionType.security,
    action: 'device.other_sessions_signed_out',
    entityType: 'user_devices',
    entityLabel: 'All other devices',
  );
}
