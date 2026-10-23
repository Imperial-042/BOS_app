// lib/features/settings/presentation/screens/settings_page.dart
//
// Extracted from main.dart: the Settings list screen.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/business/module_config_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/profile_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          const _ModulesSection(),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Theme preferences'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          const ListTile(
            leading: Icon(Icons.currency_exchange_rounded),
            title: Text('Currency'),
            subtitle: Text('Philippine Peso (PHP)'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('About BOS'),
            subtitle: Text('Business Operating System'),
          ),
        ],
      ),
    );
  }
}

/// Per-business module switches. Only users who may change business settings
/// can flip them; everyone else sees the read-only list.
class _ModulesSection extends ConsumerWidget {
  const _ModulesSection();

  static const _labels = <String, (String, IconData)>{
    BosModuleIds.management: ('Management', Icons.dashboard_outlined),
    BosModuleIds.finance: ('Finance', Icons.account_balance_wallet_outlined),
    BosModuleIds.inventory: ('Inventory', Icons.inventory_2_outlined),
    BosModuleIds.salesPos: ('Sales & POS', Icons.point_of_sale_outlined),
    BosModuleIds.people: ('People', Icons.groups_outlined),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canEdit = ref.watch(canProvider(BosPermission.businessSettings));
    final configsAsync = ref.watch(moduleConfigsProvider);
    final service = ref.read(moduleConfigServiceProvider);
    final audit = ref.read(auditLogServiceProvider);

    return configsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (configs) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'MODULES',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Choose what this business uses. Applies to everyone in it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final moduleId in BosModuleIds.toggleable)
            SwitchListTile(
              secondary: Icon(_labels[moduleId]!.$2),
              title: Text(_labels[moduleId]!.$1),
              value: service.isEnabled(configs, moduleId),
              onChanged: canEdit
                  ? (enabled) async {
                      await service.setEnabled(
                        businessId: kCurrentBusinessId,
                        moduleId: moduleId,
                        enabled: enabled,
                      );
                      await audit.tryRecord(
                        AuditEvent(
                          businessId: kCurrentBusinessId,
                          module: AuditModule.administration,
                          actionType: AuditActionType.update,
                          action: 'administration.module_toggled',
                          entityType: 'business_module_configs',
                          entityId: moduleId,
                          entityLabel: _labels[moduleId]!.$1,
                          before: {'enabled': !enabled},
                          after: {'enabled': enabled},
                        ),
                      );
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}
