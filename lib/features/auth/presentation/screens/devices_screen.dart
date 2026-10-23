import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/features/transactions/presentation/widgets/secruity_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/device/device_management_service.dart';
import '../../../../core/device/device_providers.dart';
import '../../../../core/sync/outbox_recovery_service.dart';

final _outboxRecoveryServiceProvider = Provider<OutboxRecoveryService>(
  (ref) => OutboxRecoveryService(ref.watch(databaseProvider)),
);

final _heldOutboxProvider = FutureProvider<HeldOutboxSummary?>((ref) async {
  final userId = ref.watch(authenticatedUserIdProvider);
  if (userId == null) return null;
  return ref.watch(_outboxRecoveryServiceProvider).summarize(userId);
});

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(myDevicesProvider);
    final currentUuid = ref.watch(currentDeviceUuidProvider);
    final heldOutbox = ref.watch(_heldOutboxProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My devices')),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _DeviceListError(
          message: error.toString(),
          onRetry: () => ref.invalidate(myDevicesProvider),
        ),
        data: (items) => currentUuid.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _DeviceListError(
            message: error.toString(),
            onRetry: () => ref.invalidate(currentDeviceUuidProvider),
          ),
          data: (deviceUuid) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myDevicesProvider);
              ref.invalidate(_heldOutboxProvider);
              await ref.read(myDevicesProvider.future);
            },
            child: _DeviceList(
              devices: items,
              currentDeviceUuid: deviceUuid,
              heldOutbox: heldOutbox,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceList extends ConsumerWidget {
  const _DeviceList({
    required this.devices,
    required this.currentDeviceUuid,
    required this.heldOutbox,
  });

  final List<DeviceRecord> devices;
  final String currentDeviceUuid;
  final AsyncValue<HeldOutboxSummary?> heldOutbox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final current = devices
        .where((d) => d.deviceUuid == currentDeviceUuid)
        .toList();
    final others = devices
        .where((d) => d.deviceUuid != currentDeviceUuid)
        .toList();

    final blockedCount = devices.where((d) => d.status != 'active').length;
    final signedInCount = devices
        .where((d) => d.status == 'active' && d.activeSessionCount > 0)
        .length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SummaryRow(
              total: devices.length,
              signedIn: signedInCount,
              blocked: blockedCount,
            ),
            const SizedBox(height: 16),
            heldOutbox.when(
              data: (summary) => summary == null || summary.total == 0
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ProtectedOutboxCard(summary: summary),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InfoBanner(
                  icon: Icons.warning_amber_rounded,
                  background: theme.colorScheme.errorContainer,
                  foreground: theme.colorScheme.onErrorContainer,
                  child: Text(
                    'Could not inspect pending local changes '
                    '(${error.runtimeType}).',
                  ),
                ),
              ),
            ),
            if (devices.isEmpty)
              const InfoBanner(
                icon: Icons.devices_other_rounded,
                child: Text('No BOS devices are registered to this account.'),
              ),
            if (current.isNotEmpty) ...[
              const _GroupLabel('This device'),
              for (final d in current)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DeviceCard(device: d, isCurrent: true),
                ),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: 8),
              _GroupLabel('Other devices (${others.length})'),
              for (final d in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DeviceCard(device: d, isCurrent: false),
                ),
            ],
            const SizedBox(height: 8),
            _SignOutOthersCard(
              onPressed: () => _confirmSignOutOthers(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOutOthers(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const IconBadge(icon: Icons.logout_rounded, size: 52),
        title: const Text('Sign out other devices?'),
        content: const Text(
          'Other Supabase sessions will be signed out. This device will stay '
          'signed in. Unsynchronized local data on those devices will remain '
          'on the device and cannot sync until an authorized session returns.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out other devices'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final audit = ref.read(auditLogServiceProvider);

    try {
      await ref.read(deviceManagementServiceProvider).signOutOtherSessions();
      await audit.tryRecord(
        const AuditEvent(
          module: AuditModule.security,
          actionType: AuditActionType.security,
          action: 'device.other_sessions_signed_out',
          entityType: 'user_devices',
          entityLabel: 'All other devices',
        ),
      );
      ref.invalidate(myDevicesProvider);
      if (context.mounted) {
        _showMessage(context, 'Other devices have been signed out.');
      }
    } on DeviceManagementException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          'Could not sign out other devices (${error.runtimeType}).',
        );
      }
    }
  }
}

// ───────────────────────── Summary & group headers ─────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.total,
    required this.signedIn,
    required this.blocked,
  });

  final int total;
  final int signedIn;
  final int blocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.devices_rounded,
            value: '$total',
            label: 'Registered',
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.wifi_tethering_rounded,
            value: '$signedIn',
            label: 'Signed in',
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.block_rounded,
            value: '$blocked',
            label: 'Blocked',
            color: blocked > 0 ? scheme.error : scheme.outline,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ───────────────────────── Sign out others ─────────────────────────

class _SignOutOthersCard extends StatelessWidget {
  const _SignOutOthersCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: Icons.shield_outlined, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Account sessions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Sign out other BOS sessions without ending this session. '
            'Their current access tokens may remain valid until expiry, '
            'but BOS data access is blocked by the device registry.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out other devices'),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Held outbox ─────────────────────────

class _ProtectedOutboxCard extends ConsumerStatefulWidget {
  const _ProtectedOutboxCard({required this.summary});

  final HeldOutboxSummary summary;

  @override
  ConsumerState<_ProtectedOutboxCard> createState() =>
      _ProtectedOutboxCardState();
}

class _ProtectedOutboxCardState extends ConsumerState<_ProtectedOutboxCard> {
  bool _working = false;

  String _plural(int n) => '$n pending change${n == 1 ? '' : 's'}';

  Future<void> _adopt() async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    final count = widget.summary.recoverable;
    final audit = ref.read(auditLogServiceProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const IconBadge(icon: Icons.cloud_upload_outlined, size: 52),
        title: const Text('Upload older changes as this account?'),
        content: Text(
          '${_plural(count)} from before account tracking exist on this '
          'device for businesses you belong to. Only continue if they were '
          'made by you. They will then upload under this account, and the '
          'server still checks that you may write to each business.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use this account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    try {
      final adopted = await ref
          .read(_outboxRecoveryServiceProvider)
          .adoptUnattributed(userId);
      if (adopted > 0) {
        await audit.tryRecord(
          AuditEvent(
            module: AuditModule.security,
            actionType: AuditActionType.security,
            action: 'security.outbox_adopted',
            entityType: 'sync_outbox',
            entityId: userId,
            entityLabel: 'Pending changes re-attributed to this account',
            details: {'adopted': adopted},
          ),
        );
      }
      ref.invalidate(_heldOutboxProvider);
      if (mounted) {
        _showMessage(
          context,
          '${_plural(adopted)} will sync with this account.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          context,
          'Could not update changes (${error.runtimeType}).',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onErrorContainer, height: 1.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Changes held on this device',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (summary.recoverable > 0)
              line(
                Icons.history_rounded,
                '${_plural(summary.recoverable)} predate account tracking. '
                'They are kept locally until you choose to upload them.',
              ),
            if (summary.otherAccounts > 0)
              line(
                Icons.person_off_outlined,
                '${_plural(summary.otherAccounts)} belong to a different '
                'account. Sign in with that account to upload them.',
              ),
            if (summary.otherBusinesses > 0)
              line(
                Icons.store_mall_directory_outlined,
                '${_plural(summary.otherBusinesses)} are for businesses this '
                'account does not belong to and cannot be uploaded from here.',
              ),
            if (summary.recoverable > 0) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  onPressed: _working ? null : _adopt,
                  icon: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    _working ? 'Updating…' : 'Upload older changes as me',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Device card ─────────────────────────

enum _DeviceAction { rename, signOut, block }

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device, required this.isCurrent});

  final DeviceRecord device;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocked = device.status != 'active';
    final signedIn = !blocked && device.activeSessionCount > 0;

    final statusText = blocked
        ? 'Blocked'
        : signedIn
        ? 'Signed in'
        : 'Signed out';
    final statusColor = blocked
        ? scheme.error
        : signedIn
        ? Colors.green.shade700
        : scheme.onSurfaceVariant;
    final accent = blocked ? scheme.error : scheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: _platformIcon(device.platform), color: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          device.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isCurrent)
                          const StatusPill(
                            label: 'THIS DEVICE',
                            color: Colors.blue,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _deviceSubtitle(device),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      label: statusText,
                      color: statusColor,
                      dot: true,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_DeviceAction>(
                tooltip: 'Device actions',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (action) => switch (action) {
                  _DeviceAction.rename => _rename(context, ref),
                  _DeviceAction.signOut => _signOut(context, ref),
                  _DeviceAction.block => _block(context, ref),
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _DeviceAction.rename,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                    ),
                  ),
                  if (!isCurrent && signedIn)
                    const PopupMenuItem(
                      value: _DeviceAction.signOut,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.logout_rounded),
                        title: Text('Sign out'),
                      ),
                    ),
                  if (!isCurrent && !blocked)
                    PopupMenuItem(
                      value: _DeviceAction.block,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.block_rounded, color: scheme.error),
                        title: Text(
                          'Block device',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _MetaRow(
                    icon: Icons.schedule_rounded,
                    label: 'Last active',
                    value: _formatDate(device.lastSeenAt),
                  ),
                  const SizedBox(height: 8),
                  _MetaRow(
                    icon: Icons.sync_rounded,
                    label: 'Last sync',
                    value: device.lastSyncAt == null
                        ? 'Never synced'
                        : _formatDate(device.lastSyncAt!),
                  ),
                  if (device.appVersion?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    _MetaRow(
                      icon: Icons.info_outline_rounded,
                      label: 'App version',
                      value: device.appVersion!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Must be reactivated on that device.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!isCurrent && signedIn)
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _signOut(context, ref),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out this device'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const IconBadge(icon: Icons.logout_rounded, size: 52),
        title: Text('Sign out ${device.displayName}?'),
        content: const Text(
          'That device will be signed out within a few seconds and sent to '
          'the login screen. Changes it has not synced yet stay on that '
          'device, and you can sign in again there at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final audit = ref.read(auditLogServiceProvider);

    try {
      await ref
          .read(deviceManagementServiceProvider)
          .signOutDevice(device.deviceUuid);
      await audit.tryRecord(
        AuditEvent(
          module: AuditModule.security,
          actionType: AuditActionType.security,
          action: 'device.signed_out',
          entityType: 'user_devices',
          entityId: device.deviceUuid,
          entityLabel: device.displayName,
          details: {
            'platform': device.platform,
            'lastSeenAt': device.lastSeenAt.toIso8601String(),
          },
        ),
      );
      ref.invalidate(myDevicesProvider);
      if (context.mounted) {
        _showMessage(context, '${device.displayName} was signed out.');
      }
    } on DeviceManagementException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          'Could not sign out this device (${error.runtimeType}).',
        );
      }
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDeviceDialog(initialName: device.displayName),
    );
    if (name == null || !context.mounted) return;
    final audit = ref.read(auditLogServiceProvider);
    final newName = name.trim();
    final oldName = device.deviceName;

    try {
      await ref
          .read(deviceManagementServiceProvider)
          .renameDevice(deviceUuid: device.deviceUuid, name: name);
      if (newName != oldName) {
        await audit.tryRecord(
          AuditEvent(
            module: AuditModule.security,
            actionType: AuditActionType.security,
            action: 'device.renamed',
            entityType: 'user_devices',
            entityId: device.deviceUuid,
            entityLabel: newName,
            before: {'name': oldName},
            after: {'name': newName},
          ),
        );
      }
      ref.invalidate(myDevicesProvider);
    } on DeviceManagementException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          'Could not rename this device (${error.runtimeType}).',
        );
      }
    }
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: IconBadge(
          icon: Icons.block_rounded,
          size: 52,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text('Block ${device.displayName}?'),
        content: const Text(
          'A blocked device can\'t sync or sign in until it is reactivated '
          'from that device. Use "Sign out" instead if you only want it '
          'logged out. Blocking does not erase its local data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block device'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final audit = ref.read(auditLogServiceProvider);

    try {
      await ref
          .read(deviceManagementServiceProvider)
          .revokeDevice(device.deviceUuid);
      await audit.tryRecord(
        AuditEvent(
          module: AuditModule.security,
          actionType: AuditActionType.security,
          action: 'device.revoked',
          entityType: 'user_devices',
          entityId: device.deviceUuid,
          entityLabel: device.displayName,
          before: {'status': device.status},
          after: {'status': 'revoked'},
          details: {
            'platform': device.platform,
            'clientType': device.clientType,
            'lastSeenAt': device.lastSeenAt.toIso8601String(),
          },
        ),
      );
      ref.invalidate(myDevicesProvider);
      if (context.mounted) {
        _showMessage(context, 'Device blocked. Its local data was not erased.');
      }
    } on DeviceManagementException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          'Could not block this device (${error.runtimeType}).',
        );
      }
    }
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const IconBadge(icon: Icons.edit_outlined, size: 52),
      title: const Text('Rename device'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Device name',
            prefixIcon: const Icon(Icons.smartphone_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DeviceListError extends StatelessWidget {
  const _DeviceListError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon: Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load device information',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Helpers ─────────────────────────

IconData _platformIcon(String platform) => switch (platform) {
  'android' || 'ios' => Icons.smartphone_rounded,
  'web' => Icons.language_rounded,
  _ => Icons.computer_rounded,
};

String _platformName(String platform) => switch (platform) {
  'android' => 'Android',
  'ios' => 'iOS',
  'windows' => 'Windows',
  'macos' => 'macOS',
  'linux' => 'Linux',
  'web' => 'Web',
  _ => platform,
};

String _formatDate(DateTime date) => DateFormat.yMMMd().add_jm().format(date);

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
}

const _genericDeviceNames = {
  'android phone',
  'iphone or ipad',
  'windows pc',
  'mac',
  'linux pc',
  'bos web client',
  'bos device',
};

extension on DeviceRecord {
  /// Old devices were all registered with a generic name. Prefer the real
  /// model when the name is still the generic default.
  String get displayName {
    final model = (deviceModel ?? '').trim();
    final generic = _genericDeviceNames.contains(
      deviceName.trim().toLowerCase(),
    );
    return (generic && model.isNotEmpty) ? model : deviceName;
  }
}

String _deviceSubtitle(DeviceRecord d) {
  final model = (d.deviceModel ?? '').trim();
  return [
    if (model.isNotEmpty && model != d.displayName) model,
    _platformName(d.platform),
    d.clientType,
  ].join(' · ');
}
