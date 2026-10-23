// lib/features/production/presentation/widgets/manager_approval_dialog.dart
//
//   requestManagerApproval  - asks for an owner/manager PIN, returns who approved
//   showSetApprovalPinDialog - lets the signed-in owner/manager set or change
//                              their own approval PIN

import 'package:bos_application/core/auth/approval_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/auth/permission_overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<Approver?> requestManagerApproval(
  BuildContext context, {
  required String title,
  required String message,
  BosPermission permission = BosPermission.salesVoid,
}) {
  return showDialog<Approver>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _ApprovalDialog(title: title, message: message, permission: permission),
  );
}

class _ApprovalDialog extends ConsumerStatefulWidget {
  final String title;
  final String message;
  final BosPermission permission;

  const _ApprovalDialog({
    required this.title,
    required this.message,
    required this.permission,
  });

  @override
  ConsumerState<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends ConsumerState<_ApprovalDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final overrides =
          ref.read(rolePermissionOverridesProvider).value ?? const [];
      final approver = await ref
          .read(approvalServiceProvider)
          .verifyPin(
            businessId: ref.read(selectedBusinessIdProvider),
            pin: _pin.text.trim(),
            permission: widget.permission,
            permissionsOf: (role, roleId) =>
                PermissionsResolver.effectivePermissions(
                  role,
                  overrides,
                  roleId: roleId,
                ),
          );
      if (mounted) Navigator.pop(context, approver);
    } on ApprovalException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _pin.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.verified_user_outlined, size: 30),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 14),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: 'Approval PIN',
              border: const OutlineInputBorder(),
              counterText: '',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

// ============================================================================
// SET / CHANGE MY PIN
// ============================================================================

Future<bool> showSetApprovalPinDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _SetPinDialog(),
  );
  return saved == true;
}

class _SetPinDialog extends ConsumerStatefulWidget {
  const _SetPinDialog();

  @override
  ConsumerState<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends ConsumerState<_SetPinDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _hasPin = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = ref.read(authenticatedUserIdProvider);
      final has = uid == null
          ? false
          : await ref.read(approvalServiceProvider).hasPin(uid);
      if (mounted) setState(() => _hasPin = has);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load PIN: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = ref.read(authenticatedUserIdProvider);
    if (uid == null) {
      setState(() => _error = 'You are not signed in.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'The two new PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(approvalServiceProvider)
          .setPin(
            businessId: ref.read(selectedBusinessIdProvider),
            userId: uid,
            newPin: _new.text.trim(),
            currentPin: _hasPin ? _current.text.trim() : null,
          );
      ref.invalidate(approvalEnabledProvider);
      if (mounted) Navigator.pop(context, true);
    } on ApprovalException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save PIN: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 8,
      onChanged: (_) => setState(() => _error = null),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_hasPin ? 'Change approval PIN' : 'Set approval PIN'),
      content: _loading
          ? const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A 4 to 8 digit PIN used to approve voids on this device. '
                    'Do not share it.',
                  ),
                  const SizedBox(height: 14),
                  if (_hasPin) _field(_current, 'Current PIN'),
                  _field(_new, 'New PIN'),
                  _field(_confirm, 'Confirm new PIN'),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || _loading) ? null : _save,
          child: const Text('Save PIN'),
        ),
      ],
    );
  }
}
