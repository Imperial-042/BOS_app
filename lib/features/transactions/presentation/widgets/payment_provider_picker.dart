// lib/features/production/presentation/widgets/payment_provider_picker.dart
//
// Lets the cashier choose WHICH bank or e-wallet a customer paid through.
//   * Built-in lists of common Philippine banks and e-wallets.
//   * "Not listed?" -> type a name and add it; it is saved per business and
//     shows up in the list from then on. Custom entries can be removed.
//
// Which list to show depends on the payment account picked at checkout:
//   Bank account      -> banks
//   E-Wallet account  -> e-wallets
//   Cash / unknown    -> no picker (paymentKindOf returns null)

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId;

// ============================================================================
// KINDS + BUILT-IN LISTS
// ============================================================================

enum PaymentProviderKind {
  bank('bank', 'Bank', 'bank', Icons.account_balance_outlined),
  ewallet(
    'ewallet',
    'E-wallet',
    'e-wallet',
    Icons.account_balance_wallet_outlined,
  );

  const PaymentProviderKind(this.key, this.label, this.noun, this.icon);

  /// Stored in the database.
  final String key;

  /// Capitalised, for field labels ("Bank").
  final String label;

  /// Lower-case, for sentences ("Select the bank ...").
  final String noun;
  final IconData icon;
}

const List<String> kBankProviders = [
  'BDO',
  'BPI',
  'Metrobank',
  'Landbank',
  'UnionBank',
  'Security Bank',
  'PNB',
  'RCBC',
  'China Bank',
  'EastWest Bank',
  'GoTyme Bank',
  'Maya Bank',
  'SeaBank',
  'UNOBank',
  'Tonik',
  'CIMB Bank',
  'Maybank',
  'PBCom',
  'OFBank',
];

const List<String> kEwalletProviders = [
  'GCash',
  'Maya',
  'ShopeePay',
  'GrabPay',
  'Coins.ph',
  'PayPal',
  'Palawan Pay',
];

List<String> builtInProvidersFor(PaymentProviderKind kind) =>
    kind == PaymentProviderKind.bank ? kBankProviders : kEwalletProviders;

/// Decides whether a payment account is a bank, an e-wallet, or neither.
///
/// Uses the account id prefixes the app seeds ('acc_bank_…', 'acc_ewallet_…',
/// 'acc_cash_…'). Accounts you create yourself fall back to a name check.
/// Returns null for cash (and anything unrecognised) — no picker is shown.
PaymentProviderKind? paymentKindOf(String accountId, String accountName) {
  final id = accountId.toLowerCase();
  if (id.startsWith('acc_ewallet_')) return PaymentProviderKind.ewallet;
  if (id.startsWith('acc_bank_')) return PaymentProviderKind.bank;
  if (id.startsWith('acc_cash_')) return null;

  final name = accountName.toLowerCase();
  if (name.contains('bank')) return PaymentProviderKind.bank;
  if (RegExp(
    r'e-?wallet|wallet|gcash|maya|paymaya|shopeepay|grabpay|coins\.ph|paypal',
  ).hasMatch(name)) {
    return PaymentProviderKind.ewallet;
  }
  return null;
}

// ============================================================================
// CUSTOM (USER-ADDED) PROVIDERS
// ============================================================================

final customPaymentProvidersProvider =
    StreamProvider.family<List<PaymentProvider>, String>((ref, kindKey) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.paymentProviders)
            ..where(
              (p) =>
                  p.businessId.equals(kCurrentBusinessId) &
                  p.kind.equals(kindKey) &
                  p.isActive.equals(true),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch();
    });

// ============================================================================
// PICKER SHEET
// ============================================================================

/// Returns the chosen provider name, or null if dismissed.
Future<String?> showPaymentProviderPicker(
  BuildContext context, {
  required PaymentProviderKind kind,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ProviderPickerSheet(kind: kind, selected: selected),
  );
}

class _ProviderPickerSheet extends ConsumerStatefulWidget {
  final PaymentProviderKind kind;
  final String? selected;

  const _ProviderPickerSheet({required this.kind, required this.selected});

  @override
  ConsumerState<_ProviderPickerSheet> createState() =>
      _ProviderPickerSheetState();
}

class _ProviderPickerSheetState extends ConsumerState<_ProviderPickerSheet> {
  final _search = TextEditingController();
  String _query = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool _isSelected(String name) =>
      widget.selected != null &&
      widget.selected!.toLowerCase() == name.toLowerCase();

  Future<void> _addAndSelect(String raw, List<PaymentProvider> customs) async {
    final name = _clean(raw);
    if (name.length < 2) {
      setState(() => _error = 'Enter at least 2 characters.');
      return;
    }
    if (name.length > 40) {
      setState(() => _error = 'Keep the name under 40 characters.');
      return;
    }

    // Already there (built-in or added earlier)? Just select that one.
    final lower = name.toLowerCase();
    for (final existing in [
      ...builtInProvidersFor(widget.kind),
      ...customs.map((c) => c.name),
    ]) {
      if (existing.toLowerCase() == lower) {
        Navigator.pop(context, existing);
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      await db
          .into(db.paymentProviders)
          .insert(
            PaymentProvidersCompanion.insert(
              id: const Uuid().v4(),
              businessId: kCurrentBusinessId,
              name: name,
              kind: widget.kind.key,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context, name);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove(PaymentProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${provider.name}?'),
        content: const Text(
          'It will no longer appear in this list. Past receipts keep the '
          'name they were saved with.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.paymentProviders)
          ..where((t) => t.id.equals(provider.id)))
        .write(const PaymentProvidersCompanion(isActive: Value(false)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = widget.kind;

    final customs =
        ref.watch(customPaymentProvidersProvider(kind.key)).value ??
        const <PaymentProvider>[];

    final q = _query.trim().toLowerCase();
    bool matches(String n) => q.isEmpty || n.toLowerCase().contains(q);

    final customMatches = customs.where((c) => matches(c.name)).toList();
    final builtInMatches = builtInProvidersFor(kind).where(matches).toList();

    final typed = _clean(_query);
    final exists = [
      ...builtInProvidersFor(kind),
      ...customs.map((c) => c.name),
    ].any((n) => n.toLowerCase() == typed.toLowerCase());
    final showAdd = typed.isNotEmpty && !exists;

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );

    Widget tile(String name, {PaymentProvider? custom}) {
      final selected = _isSelected(name);
      return ListTile(
        leading: Icon(kind.icon, color: scheme.onSurfaceVariant),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
        selected: selected,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) Icon(Icons.check_circle, color: scheme.primary),
            if (custom != null)
              IconButton(
                tooltip: 'Remove from list',
                onPressed: () => _confirmRemove(custom),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
          ],
        ),
        onTap: () => Navigator.pop(context, name),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Select ${kind.noun}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() {
                _query = v;
                _error = null;
              }),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search or type a new ${kind.noun}',
                helperText: 'Not listed? Type its name to add it.',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                          _error = null;
                        }),
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (showAdd)
                  ListTile(
                    leading: Icon(
                      Icons.add_circle_outline_rounded,
                      color: scheme.primary,
                    ),
                    title: Text(
                      'Add “$typed”',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text('Save as a new ${kind.noun} and select it'),
                    enabled: !_busy,
                    onTap: () => _addAndSelect(_query, customs),
                  ),
                if (customMatches.isNotEmpty) ...[
                  sectionLabel('Added by you'),
                  ...customMatches.map((c) => tile(c.name, custom: c)),
                ],
                if (builtInMatches.isNotEmpty) ...[
                  sectionLabel(
                    kind == PaymentProviderKind.bank ? 'Banks' : 'E-wallets',
                  ),
                  ...builtInMatches.map(tile),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
