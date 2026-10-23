// lib/features/production/presentation/widgets/pos_session_widgets.dart
//
// UI for opening and closing a shift.
//   PosShiftClosedView  - shown instead of the menu while no shift is open
//   PosShiftBar         - slim status bar shown while a shift is open
//   showCloseShiftSheet - end-of-day summary, cash count, and the button that
//                         finally posts the shift's sales to the journal

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId;
import '../../domain/pos_session_service.dart';
import '../screens/pos_order_state.dart';

String _peso(int cents) => formatPeso(cents);
String _time(DateTime d) => DateFormat('MMM d · h:mm a').format(d);

// ============================================================================
// SHIFT CLOSED — open a new one
// ============================================================================

class PosShiftClosedView extends ConsumerStatefulWidget {
  const PosShiftClosedView({super.key});

  @override
  ConsumerState<PosShiftClosedView> createState() => _PosShiftClosedViewState();
}

class _PosShiftClosedViewState extends ConsumerState<PosShiftClosedView> {
  final _cash = TextEditingController(text: '0.00');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final cents = parsePesoCents(_cash.text);
    if (cents == null) {
      setState(() => _error = 'Enter the cash in the drawer (0 if none).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(posSessionServiceProvider)
          .openSession(
            businessId: kCurrentBusinessId,
            branchId: ref.read(selectedBranchIdProvider),
            openingCashCents: cents,
            userId: ref.read(authenticatedUserIdProvider),
          );
      // currentPosSessionProvider streams the new shift; the page rebuilds.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_open_rounded,
                  size: 34,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Open the register',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a shift to begin selling. Sales are recorded as you go '
                'and posted to the journal when you close the shift.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _cash,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(
                  labelText: 'Opening cash in drawer',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: scheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _open,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Open shift',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SHIFT OPEN — status bar
// ============================================================================

class PosShiftBar extends ConsumerWidget {
  final PosSession session;
  final VoidCallback onClose;

  const PosShiftBar({super.key, required this.session, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final branchName = ref.watch(branchesProvider).length > 1
        ? ref.watch(selectedBranchProvider)?.name
        : null;
    final snap = ref.watch(posSaleSyncProvider).value;
    final online = ref.watch(isOnlineProvider).value ?? true;
    final unsynced = snap?.unsyncedCount ?? 0;
    final showSync =
        snap != null && snap.cloudEnabled && (!online || unsynced > 0);

    final syncColor = Colors.orange.shade800;
    final syncText = !online
        ? (unsynced > 0 ? 'Offline · $unsynced saved' : 'Offline')
        : '$unsynced to sync';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 9, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${branchName != null ? '$branchName · ' : ''}Shift open since ${_time(session.openedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade800,
                ),
              ),
            ),
            if (showSync) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: syncColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      online
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_off_outlined,
                      size: 13,
                      color: syncColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      syncText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: syncColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
            ],
            TextButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.lock_outline_rounded, size: 16),
              label: const Text(
                'Close shift',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
              style: TextButton.styleFrom(foregroundColor: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CLOSE SHIFT
// ============================================================================

Future<void> showCloseShiftSheet(
  BuildContext context,
  WidgetRef ref,
  PosSession session,
) async {
  if (ref.read(posOrderProvider).isNotEmpty ||
      ref.read(heldOrdersProvider).isNotEmpty) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Finish, clear, or discard held orders before closing the shift.',
          ),
        ),
      );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CloseShiftSheet(session: session),
  );
}

class _CloseShiftSheet extends ConsumerStatefulWidget {
  final PosSession session;
  const _CloseShiftSheet({required this.session});

  @override
  ConsumerState<_CloseShiftSheet> createState() => _CloseShiftSheetState();
}

class _CloseShiftSheetState extends ConsumerState<_CloseShiftSheet> {
  late final Future<ShiftSummary> _summary = ref
      .read(posSessionServiceProvider)
      .summarize(widget.session);
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _close(ShiftSummary summary) async {
    final counted = parsePesoCents(_counted.text);
    if (counted == null) {
      setState(() => _error = 'Enter the cash you counted in the drawer.');
      return;
    }
    final drawerVariance = counted - summary.expectedCashCents;
    if (drawerVariance != 0 && _notes.text.trim().isEmpty) {
      setState(
        () => _error =
            'The drawer is ${drawerVariance > 0 ? 'over' : 'short'} by '
            '${_peso(drawerVariance.abs())}. Add a note explaining why.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(posSessionServiceProvider)
          .closeSession(
            sessionId: widget.session.id,
            countedCashCents: counted,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            userId: ref.read(authenticatedUserIdProvider),
          );
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Text(
            result.postedCents == 0
                ? 'Shift closed. No sales to post.'
                : 'Shift closed — ${_peso(result.postedCents)} posted to the '
                      'journal.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FutureBuilder<ShiftSummary>(
        future: _summary,
        builder: (context, snap) {
          if (snap.hasError) {
            return SizedBox(
              height: 200,
              child: Center(child: Text('Unable to load shift: ${snap.error}')),
            );
          }
          if (!snap.hasData) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final s = snap.data!;
          final counted = parsePesoCents(_counted.text);
          final variance = counted == null
              ? null
              : counted - s.expectedCashCents;

          Widget row(String label, String value, {bool strong = false}) =>
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
                        fontSize: strong ? 16 : 14,
                      ),
                    ),
                  ],
                ),
              );

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Close shift',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Opened ${_time(widget.session.openedAt)}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      row('Sales', '${s.salesCount}'),
                      if (s.voidedCount > 0)
                        row('Voided (not counted)', '${s.voidedCount}'),
                      if (s.stockOnlyCount > 0)
                        row('Stock-only orders', '${s.stockOnlyCount}'),
                      const Divider(height: 24),
                      Text(
                        'TO POST TO THE JOURNAL',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (s.byAccountId.isEmpty)
                        Text(
                          'No sales this shift.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        )
                      else
                        for (final e in s.byAccountId.entries)
                          row(
                            s.accountNames[e.key] ?? 'Account',
                            _peso(e.value),
                          ),
                      const Divider(height: 24),
                      row('Opening cash', _peso(widget.session.openingCash)),
                      row('Cash sales', _peso(s.cashSalesCents)),
                      row(
                        'Expected in drawer',
                        _peso(s.expectedCashCents),
                        strong: true,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _counted,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() => _error = null),
                        decoration: const InputDecoration(
                          labelText: 'Cash counted in drawer',
                          prefixText: '₱ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (variance != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          variance == 0
                              ? 'Balanced'
                              : variance > 0
                              ? 'Over by ${_peso(variance)}'
                              : 'Short by ${_peso(-variance)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: variance == 0
                                ? Colors.green.shade700
                                : scheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notes,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Closing posts these sales to the journal and locks '
                          'this shift\'s receipts — they can no longer be '
                          'voided.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Material(
                color: scheme.surface,
                elevation: 6,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: scheme.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _close(s),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_rounded),
                          label: Text(
                            _busy
                                ? 'Closing...'
                                : 'Close shift & post to journal',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
