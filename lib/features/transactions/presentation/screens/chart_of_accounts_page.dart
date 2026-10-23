// lib/features/transactions/presentation/screens/chart_of_accounts_page.dart
//
// Administration -> Chart of Accounts. Every account every financial
// transaction posts to, grouped by type, with live balances from the
// ledger. Accounts with posted history can be deactivated but never
// deleted; untouched custom accounts can be removed.

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/authorization_service.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import 'transaction_page.dart' show kCurrentBusinessId, ledgerVersionProvider;

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

const _typeOrder = ['asset', 'liability', 'equity', 'income', 'expense'];
const _typeLabels = {
  'asset': 'Assets',
  'liability': 'Liabilities',
  'equity': 'Equity',
  'income': 'Income',
  'expense': 'Expenses',
};

class AccountWithBalance {
  final Account account;
  final int balance;
  final int transactionCount;
  const AccountWithBalance({
    required this.account,
    required this.balance,
    required this.transactionCount,
  });
}

final chartOfAccountsProvider = FutureProvider<List<AccountWithBalance>>((
  ref,
) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final rows = await db
      .customSelect(
        '''
      SELECT
        a.*,
        CASE
          WHEN a.type IN ('liability', 'equity', 'income')
            THEN a.starting_balance + COALESCE(SUM(ll.credit), 0) - COALESCE(SUM(ll.debit), 0)
          ELSE a.starting_balance + COALESCE(SUM(ll.debit), 0) - COALESCE(SUM(ll.credit), 0)
        END AS computed_balance,
        COUNT(DISTINCT ll.journal_entry_id) AS txn_count
      FROM accounts a
      LEFT JOIN ledger_lines ll ON ll.account_id = a.id
      WHERE a.business_id = ?
      GROUP BY a.id
      ORDER BY
        CASE a.type
          WHEN 'asset' THEN 1 WHEN 'liability' THEN 2 WHEN 'equity' THEN 3
          WHEN 'income' THEN 4 ELSE 5 END,
        a.name
      ''',
        variables: [Variable.withString(kCurrentBusinessId)],
        readsFrom: {db.accounts, db.ledgerLines},
      )
      .get();

  return rows.map((row) {
    final account = db.accounts.map(row.data);
    return AccountWithBalance(
      account: account,
      balance: row.read<int>('computed_balance'),
      transactionCount: row.read<int>('txn_count'),
    );
  }).toList();
});

class ChartOfAccountsPage extends ConsumerWidget {
  const ChartOfAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canProvider(BosPermission.financeEdit));
    final accountsAsync = ref.watch(chartOfAccountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chart of Accounts'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'New account',
              onPressed: () => _showAccountEditor(context, ref, null),
            ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load accounts.')),
        data: (accounts) {
          final active = accounts
              .where((entry) => entry.account.isActive)
              .toList();
          final inactive = accounts
              .where((entry) => !entry.account.isActive)
              .toList();

          final netWorth = active
              .where((entry) => entry.account.type == 'asset')
              .fold<int>(0, (sum, entry) => sum + entry.balance);
          final liabilities = active
              .where((entry) => entry.account.type == 'liability')
              .fold<int>(0, (sum, entry) => sum + entry.balance);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _BalanceSheetCard(assets: netWorth, liabilities: liabilities),
              const SizedBox(height: 20),
              for (final type in _typeOrder)
                _AccountTypeSection(
                  title: _typeLabels[type]!,
                  entries: active
                      .where((entry) => entry.account.type == type)
                      .toList(),
                  canEdit: canEdit,
                  onEdit: (entry) => _showAccountEditor(context, ref, entry),
                ),
              if (inactive.isNotEmpty)
                _AccountTypeSection(
                  title: 'Archived',
                  entries: inactive,
                  canEdit: canEdit,
                  onEdit: (entry) => _showAccountEditor(context, ref, entry),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showAccountEditor(
    BuildContext context,
    WidgetRef ref,
    AccountWithBalance? existing,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccountEditorSheet(existing: existing),
    );
  }
}

class _BalanceSheetCard extends StatelessWidget {
  const _BalanceSheetCard({required this.assets, required this.liabilities});

  final int assets;
  final int liabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final equity = assets - liabilities;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Books at a glance',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _GlanceMetric(label: 'Assets', value: _peso(assets)),
                _GlanceMetric(label: 'Liabilities', value: _peso(liabilities)),
                _GlanceMetric(label: 'Equity', value: _peso(equity)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GlanceMetric extends StatelessWidget {
  const _GlanceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTypeSection extends StatelessWidget {
  const _AccountTypeSection({
    required this.title,
    required this.entries,
    required this.canEdit,
    required this.onEdit,
  });

  final String title;
  final List<AccountWithBalance> entries;
  final bool canEdit;
  final ValueChanged<AccountWithBalance> onEdit;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '$title (${entries.length})'.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  _AccountTile(
                    entry: entries[i],
                    canEdit: canEdit,
                    onTap: () => onEdit(entries[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.entry,
    required this.canEdit,
    required this.onTap,
  });

  final AccountWithBalance entry;
  final bool canEdit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = entry.account;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          account.isPaymentAccount
              ? Icons.account_balance_wallet_outlined
              : Icons.account_tree_outlined,
          size: 20,
        ),
      ),
      title: Text(
        account.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${account.isPaymentAccount ? 'Payment account' : 'GL account'}'
        ' · ${entry.transactionCount} txn',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _peso(entry.balance),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (canEdit) const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: canEdit ? onTap : null,
    );
  }
}

class _AccountEditorSheet extends ConsumerStatefulWidget {
  const _AccountEditorSheet({this.existing});

  final AccountWithBalance? existing;

  @override
  ConsumerState<_AccountEditorSheet> createState() =>
      _AccountEditorSheetState();
}

class _AccountEditorSheetState extends ConsumerState<_AccountEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late String _type;
  late bool _isPaymentAccount;
  late String? _subtype;
  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.existing != null;
  bool get _hasHistory =>
      (widget.existing?.transactionCount ?? 0) > 0 ||
      widget.existing?.account.startingBalance != 0;

  static const _subtypes = <String, Map<String, String>>{
    'asset': {
      'current_asset': 'Current asset',
      'non_current_asset': 'Non-current asset',
    },
    'liability': {
      'trade_payable': 'Trade payable',
      'loan_payable': 'Loan payable',
      'other_payable': 'Other payable',
    },
  };

  @override
  void initState() {
    super.initState();
    final account = widget.existing?.account;
    _nameController = TextEditingController(text: account?.name ?? '');
    _balanceController = TextEditingController(
      text: (account?.startingBalance ?? 0) == 0
          ? ''
          : (account!.startingBalance / 100).toStringAsFixed(2),
    );
    _type = account?.type ?? 'asset';
    _isPaymentAccount = account?.isPaymentAccount ?? false;
    _subtype = account?.subtype;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final db = ref.read(databaseProvider);
    final name = _nameController.text.trim();
    final balanceText = _balanceController.text.replaceAll(',', '').trim();
    final balance = balanceText.isEmpty
        ? 0.0
        : (double.tryParse(balanceText) ?? 0.0);
    final startingBalanceCents = (balance * 100).round();

    try {
      if (_isEditing) {
        await (db.update(
          db.accounts,
        )..where((a) => a.id.equals(widget.existing!.account.id))).write(
          AccountsCompanion(
            name: Value(name),
            isPaymentAccount: Value(_isPaymentAccount),
            subtype: Value(_subtype),
          ),
        );
      } else {
        await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                id: const Uuid().v4(),
                businessId: kCurrentBusinessId,
                name: name,
                type: _type,
                subtype: Value(_subtype),
                isPaymentAccount: Value(_isPaymentAccount),
                startingBalance: Value(startingBalanceCents),
              ),
            );
      }

      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } on PermissionDeniedException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _archive() async {
    final db = ref.read(databaseProvider);
    await (db.update(db.accounts)
          ..where((a) => a.id.equals(widget.existing!.account.id)))
        .write(const AccountsCompanion(isActive: Value(false)));
    ref.read(ledgerVersionProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final db = ref.read(databaseProvider);
    await (db.delete(
      db.accounts,
    )..where((a) => a.id.equals(widget.existing!.account.id))).go();
    ref.read(ledgerVersionProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? 'Edit account' : 'New account',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter an account name.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Account type',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: [
                  for (final entry in _typeLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: _isEditing
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _type = value;
                          _subtype = null;
                        });
                      },
              ),
              if (_type == 'asset' || _type == 'liability') ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _subtype,
                  decoration: const InputDecoration(
                    labelText: 'Classification',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                  items: [
                    for (final entry in (_subtypes[_type] ?? {}).entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() => _subtype = value),
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Payment account'),
                subtitle: const Text(
                  'Can be selected when recording cash, bank or e-wallet '
                  'movements.',
                ),
                value: _isPaymentAccount,
                onChanged: (value) => setState(() => _isPaymentAccount = value),
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Starting balance (optional)',
                    prefixIcon: Icon(Icons.payments_outlined),
                    prefixText: '₱ ',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Text(_isEditing ? 'Save changes' : 'Create account'),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 8),
                if (_hasHistory)
                  OutlinedButton.icon(
                    onPressed: _archive,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive account'),
                  )
                else
                  TextButton.icon(
                    onPressed: _delete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      'Delete account',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
