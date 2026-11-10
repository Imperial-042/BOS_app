// lib/app/startup/no_access_screen.dart

import 'dart:async';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/features/transactions/presentation/screens/startup_screen.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_trigger_service.dart';
import 'package:bos_application/app/sign_out.dart';

class BosNoAccessScreen extends ConsumerStatefulWidget {
  const BosNoAccessScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  ConsumerState<BosNoAccessScreen> createState() => _NoAccessScreenState();
}

class _NoAccessScreenState extends ConsumerState<BosNoAccessScreen> {
  bool _busy = false;

  /// Pulls fresh memberships from the cloud, then opens the best active
  /// business ([prefer] first) as the current one.
  Future<void> _adoptAndSwitch({String? prefer}) async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) {
      throw StateError('You are signed out. Please sign in again.');
    }
    final db = ref.read(databaseProvider);
    final result = await adoptCloudAccess(
      db,
      ref.read(supabaseClientProvider),
      userId: userId,
    );

    final rows = await db
        .customSelect(
          'SELECT b.id FROM businesses b '
          'JOIN business_members m ON m.business_id = b.id '
          "WHERE m.user_id = ? AND m.status = 'active' AND b.is_active = 1 "
          'ORDER BY (b.id = ?) DESC, b.name LIMIT 1',
          variables: [
            Variable.withString(userId),
            Variable.withString(prefer ?? result.firstAdded ?? ''),
          ],
        )
        .get();
    if (rows.isEmpty) {
      throw StateError('Couldn\'t open your business yet. Please try again.');
    }
    await ref
        .read(syncTriggerServiceProvider)
        .switchToBusiness(rows.first.read<String>('id'));
    ref.invalidate(currentBusinessMembershipProvider);
  }

  Future<void> _joinWithCode() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _NoAccessInputDialog(
        title: 'Enter invite code',
        label: 'Invite code',
        hint: 'The 8-character code you were given',
        actionLabel: 'Join business',
        capitalization: TextCapitalization.characters,
        onSubmit: (code) async {
          await ref.read(cloudBusinessServiceProvider).redeemInviteCode(code);
          await _adoptAndSwitch();
        },
      ),
    );
  }

  Future<void> _createBusiness() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _NoAccessInputDialog(
        title: 'Create a business',
        label: 'Business name',
        hint: 'e.g. Maria\'s Bakery',
        actionLabel: 'Create business',
        capitalization: TextCapitalization.words,
        onSubmit: (name) async {
          final id = await ref
              .read(cloudBusinessServiceProvider)
              .createBusiness(name: name);
          await _adoptAndSwitch(prefer: id);
        },
      ),
    );
  }

  /// Cancel: switch to another business if there is one, otherwise sign out.
  Future<void> _cancel() async {
    final userId = ref.read(authenticatedUserIdProvider);
    final removedId = ref.read(selectedBusinessIdProvider);
    final sync = ref.read(syncTriggerServiceProvider);

    setState(() => _busy = true);
    var moved = false;
    try {
      if (userId != null) {
        moved = await sync.moveOffRemovedBusiness(userId, removedId);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!moved && mounted) await confirmSignOut(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    return NoAccessView(
      busy: _busy,
      onJoinWithCode: _joinWithCode,
      onCreateBusiness: _createBusiness,
      onRetry: widget.onRetry,
      onCancel: _cancel,
    );
  }
}

class _NoAccessInputDialog extends StatefulWidget {
  const _NoAccessInputDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.actionLabel,
    required this.capitalization,
    required this.onSubmit,
  });

  final String title;
  final String label;
  final String hint;
  final String actionLabel;
  final TextCapitalization capitalization;
  final Future<void> Function(String value) onSubmit;

  @override
  State<_NoAccessInputDialog> createState() => _NoAccessInputDialogState();
}

class _NoAccessInputDialogState extends State<_NoAccessInputDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(value);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError ? e.message : e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        textCapitalization: widget.capitalization,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : Text(widget.actionLabel),
        ),
      ],
    );
  }
}
