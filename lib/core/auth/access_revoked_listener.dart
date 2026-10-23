// lib/core/auth/access_revoked_listener.dart
//
// Wrap the signed-in app shell with this widget. When the sync service flags
// that this user's access to the selected business was removed, a
// non-dismissible dialog offers: enter an invite code, create a business, or
// cancel.

import 'package:bos_application/core/auth/session_store.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_provider.dart';
import '../supabase/cloud_business_service.dart';
import '../supabase/cloud_membership_bootstrap.dart';
import '../supabase/supabase_service.dart';
import '../sync/sync_trigger_service.dart';
import 'access_revocation.dart';
import 'authorization_providers.dart';

class AccessRevokedListener extends ConsumerStatefulWidget {
  const AccessRevokedListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AccessRevokedListener> createState() =>
      _AccessRevokedListenerState();
}

class _AccessRevokedListenerState extends ConsumerState<AccessRevokedListener> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    // The revocation may have been detected before this widget mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ref.read(accessRevocationProvider);
      if (current != null) _show(current);
    });
  }

  Future<void> _show(AccessRevocation revocation) async {
    if (_open || !mounted) return;
    _open = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _RevokedDialog(revocation: revocation, onSignOut: _signOut),
    );
    _open = false;
  }

  Future<void> _signOut() async {
    // Capture before the awaits: signing out unmounts the signed-in tree.
    final notifier = ref.read(authenticatedUserIdProvider.notifier);
    final cloudAuth = ref.read(supabaseAvailableProvider)
        ? ref.read(cloudAuthServiceProvider)
        : null;

    if (cloudAuth != null) {
      try {
        await cloudAuth.signOutWithScope(SignOutScope.local);
      } on Object catch (_) {
        // Sign-out must still complete locally if the network is down.
      }
    }
    await SessionStore.clear();
    SyncTracker.currentUserId = null;
    notifier.state = null; // _AuthGate then shows the login screen
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AccessRevocation?>(accessRevocationProvider, (prev, next) {
      if (next != null) _show(next);
    });
    return widget.child;
  }
}

// ============================================================================
// DIALOG
// ============================================================================

class _RevokedDialog extends ConsumerWidget {
  const _RevokedDialog({required this.revocation, required this.onSignOut});

  final AccessRevocation revocation;
  final Future<void> Function() onSignOut;

  void _finish(BuildContext context, WidgetRef ref) {
    ref.read(accessRevocationProvider.notifier).state = null;
    Navigator.of(context).pop();
  }

  /// Pulls fresh memberships from the cloud, then opens the best active
  /// business ([prefer] first) as the current one.
  Future<void> _adoptAndSwitch(WidgetRef ref, {String? prefer}) async {
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
  }

  Future<void> _joinWithCode(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Enter invite code',
        label: 'Invite code',
        hint: 'The 8-character code you were given',
        actionLabel: 'Join business',
        capitalization: TextCapitalization.characters,
        onSubmit: (code) async {
          await ref.read(cloudBusinessServiceProvider).redeemInviteCode(code);
          await _adoptAndSwitch(ref);
        },
      ),
    );
    if (ok == true && context.mounted) _finish(context, ref);
  }

  Future<void> _createBusiness(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Create a business',
        label: 'Business name',
        hint: 'e.g. Maria\'s Bakery',
        actionLabel: 'Create business',
        capitalization: TextCapitalization.words,
        onSubmit: (name) async {
          final id = await ref
              .read(cloudBusinessServiceProvider)
              .createBusiness(name: name);
          await _adoptAndSwitch(ref, prefer: id);
        },
      ),
    );
    if (ok == true && context.mounted) _finish(context, ref);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final userId = ref.read(authenticatedUserIdProvider);
    var moved = false;
    if (userId != null) {
      moved = await ref
          .read(syncTriggerServiceProvider)
          .moveOffRemovedBusiness(userId, revocation.businessId);
    }
    if (!context.mounted) return;
    _finish(context, ref);
    if (!moved) await onSignOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.gpp_maybe_rounded, size: 40, color: scheme.error),
        title: const Text(
          'Your access was removed',
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The owner of ${revocation.businessName} removed your access, '
                'so you can no longer open it. To keep working, join another '
                'business or start your own.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => _joinWithCode(context, ref),
                icon: const Icon(Icons.confirmation_number_outlined),
                label: const Text('Enter invite code'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => _createBusiness(context, ref),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Create a business'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => _cancel(context, ref),
                child: const Text('Cancel'),
              ),
              Text(
                'Cancel switches you to another business, or signs you out if '
                'you don\'t have one.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({
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
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
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
