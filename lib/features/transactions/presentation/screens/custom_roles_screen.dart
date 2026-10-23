// lib/features/auth/presentation/screens/custom_roles_screen.dart
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/membership_service.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Map<BosRole, String> _baseBlurbs = {
  BosRole.manager: 'Runs sales, stock, purchasing and the team.',
  BosRole.accountant: 'Finance, receivables, payables and reports.',
  BosRole.cashier: 'Rings up sales and adds customers.',
  BosRole.inventory: 'Stock, purchasing and suppliers.',
  BosRole.employee: 'Basic view access and own time records.',
  BosRole.hr: 'Schedules, attendance, leave and payroll.',
  BosRole.staff: 'Sells, looks up stock, own time and leave.',
};

String _err(Object e) => e is StateError
    ? e.message
    : e is PermissionDeniedException
    ? e.message
    : 'Something went wrong. Please try again.';

class CustomRolesScreen extends ConsumerWidget {
  const CustomRolesScreen({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CustomRole role,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${role.name}"?'),
        content: const Text(
          'Its permission changes are removed too. This only works when '
          'nobody has the role.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(customRoleServiceProvider).delete(role);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(_err(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOwner = ref.watch(authorizationServiceProvider).isOwner;
    final roles = ref.watch(customRolesProvider).value ?? const <CustomRole>[];
    final members =
        ref.watch(businessMembersProvider).value ?? const <BusinessMember>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Custom roles')),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _RoleEditorDialog(),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New role'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Create roles that fit your business, like "Barista" or '
              '"Supervisor". Each one starts with a built-in role\'s '
              'permissions; fine-tune them in Permissions. The starting role '
              'also decides what the cloud allows, so pick HR for people who '
              'must run schedules and payroll.',
              style: TextStyle(color: scheme.onPrimaryContainer, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          if (roles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 40,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No custom roles yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!isOwner)
                    Text(
                      'Only the owner can create roles.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            )
          else
            for (final r in roles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        Icons.tune_rounded,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      r.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Starts as ${BosRole.fromId(r.baseRole)?.label ?? r.baseRole}'
                      ' · ${members.where((m) => m.role == r.roleId).length} people',
                    ),
                    trailing: isOwner
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _RoleEditorDialog(role: r),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: scheme.error,
                                ),
                                onPressed: () => _delete(context, ref, r),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _RoleEditorDialog extends ConsumerStatefulWidget {
  const _RoleEditorDialog({this.role});

  final CustomRole? role;

  @override
  ConsumerState<_RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends ConsumerState<_RoleEditorDialog> {
  late final _name = TextEditingController(text: widget.role?.name ?? '');
  late BosRole _base = () {
    final b = BosRole.fromId(widget.role?.baseRole);
    return (b != null && kCustomBaseRoles.contains(b)) ? b : BosRole.staff;
  }();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(customRoleServiceProvider);
      if (widget.role == null) {
        await service.create(name: _name.text, base: _base);
      } else {
        await service.update(widget.role!, name: _name.text, base: _base);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.role != null;

    return AlertDialog(
      title: Text(editing ? 'Edit role' : 'New role'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Role name',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BosRole>(
              initialValue: _base,
              decoration: const InputDecoration(labelText: 'Starts as'),
              items: [
                for (final r in kCustomBaseRoles)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (v) => setState(() => _base = v ?? _base),
            ),
            const SizedBox(height: 8),
            Text(
              _baseBlurbs[_base] ?? '',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              Text(
                'Changing the starting role changes what the cloud allows '
                'this role to do.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
