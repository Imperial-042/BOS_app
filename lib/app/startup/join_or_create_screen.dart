// lib/app/startup/join_or_create_screen.dart

import 'dart:async';
import 'package:bos_application/features/transactions/presentation/screens/startup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/app/sign_out.dart';

class BosJoinOrCreateScreen extends ConsumerStatefulWidget {
  const BosJoinOrCreateScreen({super.key, required this.onCreate, required this.onJoined});

  final VoidCallback onCreate;
  final VoidCallback onJoined;

  @override
  ConsumerState<BosJoinOrCreateScreen> createState() =>
      _JoinOrCreateScreenState();
}

class _JoinOrCreateScreenState extends ConsumerState<BosJoinOrCreateScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  /// The invite-code field stays hidden until the person says they have one,
  /// so someone creating their own business is never asked for a code.
  bool _hasCode = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(cloudBusinessServiceProvider).redeemInviteCode(code);
      widget.onJoined();
    } on CloudBusinessException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not use that code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return JoinOrCreateView(
      hasCode: _hasCode,
      busy: _busy,
      error: _error,
      codeController: _code,
      onCreate: widget.onCreate,
      onHaveCode: () => setState(() => _hasCode = true),
      onSubmitCode: _join,
      onBack: () => setState(() {
        _hasCode = false;
        _error = null;
        _code.clear();
      }),
      onCancel: () => confirmSignOut(context, ref),
    );
  }
}
