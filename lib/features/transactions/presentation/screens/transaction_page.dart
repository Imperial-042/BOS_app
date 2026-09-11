// lib/features/transactions/presentation/screens/transaction_page.dart

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/ledger/ledger_service.dart';

// ============================================================
// CONSTANTS
// ============================================================

const kCurrentBusinessId = 'biz_001';

const _incomeColor = Color(0xFF159B67);
const _expenseColor = Color(0xFFE05252);

// ============================================================
// PROVIDERS
// ============================================================

final ledgerVersionProvider = StateProvider<int>((ref) => 0);

final ledgerServiceProvider = Provider<LedgerService>((ref) {
  return LedgerService(ref.watch(databaseProvider));
});

final categoriesByTypeProvider = FutureProvider.family<List<Category>, String>((
  ref,
  txnType,
) {
  final db = ref.watch(databaseProvider);

  return (db.select(db.categories)..where(
        (c) =>
            c.businessId.equals(kCurrentBusinessId) &
            c.txnType.equals(txnType) &
            c.isActive.equals(true),
      ))
      .get();
});

final paymentAccountsProvider = FutureProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);

  return (db.select(db.accounts)..where(
        (a) =>
            a.businessId.equals(kCurrentBusinessId) &
            a.isPaymentAccount.equals(true) &
            a.isActive.equals(true),
      ))
      .get();
});

// ============================================================
// TRANSACTION SERVICE
// ============================================================

class TransactionService {
  final AppDatabase db;
  final LedgerService ledgerService;

  TransactionService(this.db, this.ledgerService);

  Future<void> saveExpense({
    String? existingId,
    required DateTime date,
    required String categoryId,
    required int amount,
    String? paymentAccountId,
    String? description,
    String? notes,
    String? reference,
    required bool markAsPending,
  }) async {
    final id = existingId ?? const Uuid().v4();
    final status = markAsPending ? 'pending' : 'completed';

    await db.transaction(() async {
      String? previousJournalEntryId;

      if (existingId != null) {
        final existing = await (db.select(
          db.expenses,
        )..where((e) => e.id.equals(existingId))).getSingleOrNull();

        previousJournalEntryId = existing?.journalEntryId;
      }

      // Remove the previous ledger posting when editing.
      if (previousJournalEntryId != null) {
        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(previousJournalEntryId!))).go();
      }

      String? journalEntryId;

      if (status == 'completed' && paymentAccountId != null) {
        journalEntryId = await ledgerService.postEntry(
          businessId: kCurrentBusinessId,
          categoryId: categoryId,
          amount: amount,
          paymentAccountId: paymentAccountId,
          sourceType: 'expense',
          sourceId: id,
          description: description,
        );
      }

      final companion = ExpensesCompanion(
        id: Value(id),
        businessId: const Value(kCurrentBusinessId),
        expenseDate: Value(date),
        categoryId: Value(categoryId),
        amount: Value(amount),
        paymentAccountId: Value(paymentAccountId),
        description: Value(description),
        notes: Value(notes),
        reference: Value(reference),
        status: Value(status),
        journalEntryId: Value(journalEntryId),
        updatedAt: Value(DateTime.now()),
      );

      if (existingId == null) {
        await db.into(db.expenses).insert(companion);
      } else {
        await db.update(db.expenses).replace(companion);
      }
    });
  }

  Future<void> saveIncome({
    String? existingId,
    required DateTime date,
    required String categoryId,
    required int amount,
    String? paymentAccountId,
    String? customerId,
    String? description,
    String? notes,
    String? reference,
    required bool markAsPending,
  }) async {
    final id = existingId ?? const Uuid().v4();
    final status = markAsPending ? 'pending' : 'completed';

    await db.transaction(() async {
      String? previousJournalEntryId;

      if (existingId != null) {
        final existing = await (db.select(
          db.incomeTransactions,
        )..where((i) => i.id.equals(existingId))).getSingleOrNull();

        previousJournalEntryId = existing?.journalEntryId;
      }

      if (previousJournalEntryId != null) {
        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(previousJournalEntryId!))).go();
      }

      String? journalEntryId;

      if (status == 'completed' && paymentAccountId != null) {
        journalEntryId = await ledgerService.postEntry(
          businessId: kCurrentBusinessId,
          categoryId: categoryId,
          amount: amount,
          paymentAccountId: paymentAccountId,
          sourceType: 'income',
          sourceId: id,
          description: description,
        );
      }

      final companion = IncomeTransactionsCompanion(
        id: Value(id),
        businessId: const Value(kCurrentBusinessId),
        txnDate: Value(date),
        categoryId: Value(categoryId),
        amount: Value(amount),
        paymentAccountId: Value(paymentAccountId),
        customerId: Value(customerId),
        description: Value(description),
        notes: Value(notes),
        reference: Value(reference),
        status: Value(status),
        journalEntryId: Value(journalEntryId),
        updatedAt: Value(DateTime.now()),
      );

      if (existingId == null) {
        await db.into(db.incomeTransactions).insert(companion);
      } else {
        await db.update(db.incomeTransactions).replace(companion);
      }
    });
  }

  Future<void> deleteExpense(String id) async {
    await db.transaction(() async {
      final expense = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(id))).getSingle();

      if (expense.journalEntryId != null) {
        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(expense.journalEntryId!))).go();
      }

      await (db.delete(db.expenses)..where((e) => e.id.equals(id))).go();
    });
  }

  Future<void> deleteIncome(String id) async {
    await db.transaction(() async {
      final income = await (db.select(
        db.incomeTransactions,
      )..where((i) => i.id.equals(id))).getSingle();

      if (income.journalEntryId != null) {
        await (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals(income.journalEntryId!))).go();
      }

      await (db.delete(
        db.incomeTransactions,
      )..where((i) => i.id.equals(id))).go();
    });
  }

  Future<Account> addPaymentAccount(String name) async {
    final account = AccountsCompanion.insert(
      id: const Uuid().v4(),
      businessId: kCurrentBusinessId,
      name: name,
      type: 'asset',
      isPaymentAccount: const Value(true),
    );

    await db.into(db.accounts).insert(account);

    return (db.select(
      db.accounts,
    )..where((a) => a.id.equals(account.id.value))).getSingle();
  }

  Future<Category> addCategory(String name, {required bool isIncome}) async {
    final fallbackAccountId = isIncome
        ? 'acc_other_inc_$kCurrentBusinessId'
        : 'acc_other_exp_$kCurrentBusinessId';

    final category = CategoriesCompanion.insert(
      id: const Uuid().v4(),
      businessId: kCurrentBusinessId,
      name: name,
      txnType: isIncome ? 'income' : 'expense',
      ledgerAccountId: fallbackAccountId,
      isCustom: const Value(true),
    );

    await db.into(db.categories).insert(category);

    return (db.select(
      db.categories,
    )..where((c) => c.id.equals(category.id.value))).getSingle();
  }
}

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(
    ref.watch(databaseProvider),
    ref.watch(ledgerServiceProvider),
  );
});

// ============================================================
// TRANSACTION PAGE
// ============================================================

class TransactionPage extends ConsumerStatefulWidget {
  final Expense? existingExpense;
  final IncomeTransaction? existingIncome;

  const TransactionPage({super.key, this.existingExpense, this.existingIncome});

  bool get isEditMode => existingExpense != null || existingIncome != null;

  @override
  ConsumerState<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends ConsumerState<TransactionPage> {
  late bool _isIncome;
  late DateTime _date;

  String? _paymentAccountId;
  String? _categoryId;

  bool _markAsPending = false;
  bool _showAdvanced = false;
  bool _isSaving = false;

  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _referenceController = TextEditingController();

  @override
  void initState() {
    super.initState();

    if (widget.existingExpense != null) {
      final e = widget.existingExpense!;

      _isIncome = false;
      _date = e.expenseDate;
      _paymentAccountId = e.paymentAccountId;
      _categoryId = e.categoryId;
      _markAsPending = e.status == 'pending';

      _descriptionController.text = e.description ?? '';
      _amountController.text = (e.amount / 100).toStringAsFixed(2);
      _notesController.text = e.notes ?? '';
      _referenceController.text = e.reference ?? '';
    } else if (widget.existingIncome != null) {
      final i = widget.existingIncome!;

      _isIncome = true;
      _date = i.txnDate;
      _paymentAccountId = i.paymentAccountId;
      _categoryId = i.categoryId;
      _markAsPending = i.status == 'pending';

      _descriptionController.text = i.description ?? '';
      _amountController.text = (i.amount / 100).toStringAsFixed(2);
      _notesController.text = i.notes ?? '';
      _referenceController.text = i.reference ?? '';
    } else {
      _isIncome = false;
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Color get _accentColor => _isIncome ? _incomeColor : _expenseColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final categoriesAsync = ref.watch(
      categoriesByTypeProvider(_isIncome ? 'income' : 'expense'),
    );

    final accountsAsync = ref.watch(paymentAccountsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,

      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 20,
        title: Text(
          widget.isEditMode ? 'Edit transaction' : 'New transaction',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          if (widget.isEditMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Delete',
                onPressed: _isSaving ? null : _confirmDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),

      // --------------------------------------------------------
      // BOTTOM SAVE BUTTON
      // --------------------------------------------------------
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _isSaving
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.isEditMode
                            ? 'Update transaction'
                            : 'Save transaction',
                        key: const ValueKey('text'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            // --------------------------------------------------
            // TYPE SELECTOR
            // --------------------------------------------------

            _buildTypeSelector(),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // AMOUNT
            // --------------------------------------------------
            _buildAmountSection(),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // BASIC INFORMATION CARD
            // --------------------------------------------------
            _buildSectionCard(
              child: Column(
                children: [
                  _buildDateTile(),
                  const SizedBox(height: 8),
                  _buildDivider(),
                  const SizedBox(height: 8),
                  _buildDescriptionField(),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --------------------------------------------------
            // PAYMENT ACCOUNT
            // --------------------------------------------------
            _buildSectionTitle(
              'Payment account',
              subtitle: _markAsPending
                  ? 'Optional while pending'
                  : 'Where the money came from or went',
            ),

            const SizedBox(height: 10),

            _buildAccounts(accountsAsync),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // CATEGORY
            // --------------------------------------------------
            _buildSectionTitle(
              'Category',
              subtitle: _isIncome
                  ? 'What type of income is this?'
                  : 'What type of expense is this?',
            ),

            const SizedBox(height: 10),

            _buildCategories(categoriesAsync),

            const SizedBox(height: 18),

            // --------------------------------------------------
            // PENDING STATUS
            // --------------------------------------------------
            _buildPendingCard(),

            const SizedBox(height: 12),

            // --------------------------------------------------
            // ADVANCED
            // --------------------------------------------------
            _buildAdvancedSection(),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // TYPE SELECTOR
  // ==========================================================

  Widget _buildTypeSelector() {
    final theme = Theme.of(context);

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _typeButton(
              label: 'Expense',
              selected: !_isIncome,
              color: _expenseColor,
              enabled: !widget.isEditMode,
              onTap: () {
                if (widget.isEditMode) return;

                setState(() {
                  _isIncome = false;
                  _categoryId = null;
                });
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _typeButton(
              label: 'Income',
              selected: _isIncome,
              color: _incomeColor,
              enabled: !widget.isEditMode,
              onTap: () {
                if (widget.isEditMode) return;

                setState(() {
                  _isIncome = true;
                  _categoryId = null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeButton({
    required String label,
    required bool selected,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // AMOUNT
  // ==========================================================

  Widget _buildAmountSection() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '₱',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _accentColor,
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),

          Container(
            height: 3,
            width: 56,
            decoration: BoxDecoration(
              color: _accentColor,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DATE
  // ==========================================================

  Widget _buildDateTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pickDate,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            _iconContainer(Icons.calendar_today_rounded, _accentColor),
            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(_date),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // DESCRIPTION
  // ==========================================================

  Widget _buildDescriptionField() {
    return TextField(
      controller: _descriptionController,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.notes_rounded, size: 21),
        hintText: 'What was this transaction for?',
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 14,
        ),
      ),
    );
  }

  // ==========================================================
  // ACCOUNTS
  // ==========================================================

  Widget _buildAccounts(AsyncValue<List<Account>> accountsAsync) {
    return accountsAsync.when(
      loading: () => _loadingBox(),
      error: (error, _) => _errorBox('Could not load payment accounts.'),
      data: (accounts) {
        if (accounts.isEmpty) {
          return _emptySelection(
            text: 'No payment accounts yet',
            actionText: 'Add account',
            onPressed: _addNewAccount,
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...accounts.map((account) {
              final selected = _paymentAccountId == account.id;

              return _selectionChip(
                label: account.name,
                selected: selected,
                icon: Icons.account_balance_wallet_outlined,
                onTap: () {
                  setState(() {
                    _paymentAccountId = selected ? null : account.id;
                  });
                },
              );
            }),
            _addChip(label: 'Add account', onTap: _addNewAccount),
          ],
        );
      },
    );
  }

  // ==========================================================
  // CATEGORIES
  // ==========================================================

  Widget _buildCategories(AsyncValue<List<Category>> categoriesAsync) {
    return categoriesAsync.when(
      loading: () => _loadingBox(),
      error: (error, _) => _errorBox('Could not load categories.'),
      data: (categories) {
        if (categories.isEmpty) {
          return _emptySelection(
            text: 'No categories yet',
            actionText: 'Add category',
            onPressed: _addNewCategory,
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...categories.map((category) {
              final selected = _categoryId == category.id;

              return _selectionChip(
                label: category.name,
                selected: selected,
                icon: Icons.label_outline_rounded,
                onTap: () {
                  setState(() {
                    _categoryId = selected ? null : category.id;
                  });
                },
              );
            }),
            _addChip(label: 'Add category', onTap: _addNewCategory),
          ],
        );
      },
    );
  }

  // ==========================================================
  // PENDING
  // ==========================================================

  Widget _buildPendingCard() {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _markAsPending
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: .7)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _markAsPending
              ? theme.colorScheme.tertiary.withValues(alpha: .25)
              : theme.colorScheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          _iconContainer(
            Icons.schedule_rounded,
            _markAsPending
                ? theme.colorScheme.tertiary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pending transaction',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _markAsPending
                      ? 'This will not affect your balance yet.'
                      : 'Transaction will be recorded immediately.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          Switch.adaptive(
            value: _markAsPending,
            onChanged: (value) {
              setState(() {
                _markAsPending = value;
              });
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ADVANCED
  // ==========================================================

  Widget _buildAdvancedSection() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() {
                _showAdvanced = !_showAdvanced;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),

                  const Expanded(
                    child: Text(
                      'Additional details',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),

                  AnimatedRotation(
                    turns: _showAdvanced ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _showAdvanced
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _buildDivider(),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Notes',
                      hintText: 'Optional additional information',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _referenceController,
                    decoration: InputDecoration(
                      labelText: 'Reference number',
                      hintText: 'Optional',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPONENTS
  // ==========================================================

  Widget _buildSectionCard({required Widget child}) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _selectionChip({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _accentColor.withValues(alpha: .11)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? _accentColor.withValues(alpha: .55)
                  : theme.colorScheme.outlineVariant.withValues(alpha: .7),
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : icon,
                size: 17,
                color: selected
                    ? _accentColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? _accentColor : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addChip({required String label, required VoidCallback onTap}) {
    final theme = Theme.of(context);

    return ActionChip(
      onPressed: onTap,
      avatar: Icon(
        Icons.add_rounded,
        size: 17,
        color: theme.colorScheme.primary,
      ),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      backgroundColor: theme.colorScheme.surface,
    );
  }

  Widget _iconContainer(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: .45),
    );
  }

  Widget _loadingBox() {
    return Container(
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySelection({
    required String text,
    required String actionText,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(actionText)),
        ],
      ),
    );
  }

  // ==========================================================
  // DATE
  // ==========================================================

  String _formatDate(DateTime date) {
    final today = DateTime.now();

    final sameDay =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (sameDay) return 'Today';

    final yesterday = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));

    final isYesterday =
        date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;

    if (isYesterday) return 'Yesterday';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _date = picked;
      });
    }
  }

  // ==========================================================
  // ADD ACCOUNT
  // ==========================================================

  Future<void> _addNewAccount() async {
    final name = await _promptForName(
      title: 'Add payment account',
      hint: 'e.g. GCash, GoTyme, BPI',
    );

    if (name == null || name.trim().isEmpty) return;

    final service = ref.read(transactionServiceProvider);

    final account = await service.addPaymentAccount(name.trim());

    ref.invalidate(paymentAccountsProvider);

    setState(() {
      _paymentAccountId = account.id;
    });
  }

  // ==========================================================
  // ADD CATEGORY
  // ==========================================================

  Future<void> _addNewCategory() async {
    final name = await _promptForName(
      title: 'Add category',
      hint: _isIncome ? 'e.g. Rental Income' : 'e.g. Delivery Fuel',
    );

    if (name == null || name.trim().isEmpty) return;

    final service = ref.read(transactionServiceProvider);

    final category = await service.addCategory(
      name.trim(),
      isIncome: _isIncome,
    );

    ref.invalidate(categoriesByTypeProvider(_isIncome ? 'income' : 'expense'));

    setState(() {
      _categoryId = category.id;
    });
  }

  // ==========================================================
  // NAME DIALOG
  // ==========================================================

  Future<String?> _promptForName({
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (value) {
              Navigator.pop(ctx, value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, controller.text);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // SAVE
  // ==========================================================

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_categoryId == null) {
      _showError('Choose a category first.');
      return;
    }

    final amountValue = double.tryParse(_amountController.text.trim());

    if (amountValue == null || amountValue <= 0) {
      _showError('Enter a valid amount.');
      return;
    }

    if (!_markAsPending && _paymentAccountId == null) {
      _showError(
        'Choose a payment account, or mark the transaction as pending.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final amountCents = (amountValue * 100).round();

    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    final reference = _referenceController.text.trim().isEmpty
        ? null
        : _referenceController.text.trim();

    final service = ref.read(transactionServiceProvider);

    try {
      if (_isIncome) {
        await service.saveIncome(
          existingId: widget.existingIncome?.id,
          date: _date,
          categoryId: _categoryId!,
          amount: amountCents,
          paymentAccountId: _paymentAccountId,
          description: description,
          notes: notes,
          reference: reference,
          markAsPending: _markAsPending,
        );
      } else {
        await service.saveExpense(
          existingId: widget.existingExpense?.id,
          date: _date,
          categoryId: _categoryId!,
          amount: amountCents,
          paymentAccountId: _paymentAccountId,
          description: description,
          notes: notes,
          reference: reference,
          markAsPending: _markAsPending,
        );
      }

      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Could not save transaction: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ==========================================================
  // DELETE
  // ==========================================================

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          icon: Icon(
            Icons.delete_outline_rounded,
            size: 32,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Delete transaction?'),
          content: const Text(
            'This will remove the transaction and reverse its ledger entry.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isSaving = true;
    });

    final service = ref.read(transactionServiceProvider);

    try {
      if (widget.existingExpense != null) {
        await service.deleteExpense(widget.existingExpense!.id);
      } else if (widget.existingIncome != null) {
        await service.deleteIncome(widget.existingIncome!.id);
      }

      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Could not delete transaction: $e');

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(message),
        ),
      );
  }
}
