  import 'package:bos_application/core/auth/authorization_providers.dart';
  import 'package:bos_application/core/auth/bos_access.dart';
  import 'package:bos_application/core/business/current_business.dart';
  export 'package:bos_application/core/business/current_business.dart'
       show kCurrentBusinessId, ledgerVersionProvider;
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:image_picker/image_picker.dart';

  import '../../../../core/database/app_database.dart';
import 'package:bos_application/features/transactions/domain/transaction_service.dart';
import 'package:bos_application/features/transactions/presentation/providers/ledger_providers.dart';
export 'package:bos_application/features/transactions/domain/transaction_service.dart';
export 'package:bos_application/features/transactions/presentation/providers/ledger_providers.dart';


  // ============================================================
  // CONSTANTS
  // ============================================================


  const _incomeColor = Color(0xFF159B67);
  const _expenseColor = Color(0xFFE05252);

  // ============================================================
  // TRANSACTION PAGE
  // ============================================================

  class TransactionPage extends ConsumerStatefulWidget {
    final Expense? existingExpense;
    final IncomeTransaction? existingIncome;

    /// Which type a NEW transaction starts as. Ignored when editing.
    final bool initialIsIncome;

    const TransactionPage({
      super.key,
      this.existingExpense,
      this.existingIncome,
      this.initialIsIncome = false,
    });

    bool get isEditMode => existingExpense != null || existingIncome != null;

    @override
    ConsumerState<TransactionPage> createState() => _TransactionPageState();
  }

  class _TransactionPageState extends ConsumerState<TransactionPage> {
    static const _visibleCategoryCount = 6;
    static const _quickAmounts = [100, 500, 1000, 5000];

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

    String? _receiptPhotoPath;

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
        _receiptPhotoPath = e.receiptPhotoPath;
        _showAdvanced =
            (e.notes ?? '').isNotEmpty ||
            (e.reference ?? '').isNotEmpty ||
            e.receiptPhotoPath != null;
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
        _showAdvanced =
            (i.notes ?? '').isNotEmpty || (i.reference ?? '').isNotEmpty;
      } else {
        _isIncome = widget.initialIsIncome;
        _date = DateTime.now();
      }

      // Keeps the summary in the save bar live.
      _amountController.addListener(() {
        if (mounted) setState(() {});
      });
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

    // ==========================================================
    // BUILD
    // ==========================================================

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final canSave = ref.watch(
        canProvider(
          widget.isEditMode
              ? BosPermission.financeEdit
              : BosPermission.financeCreate,
        ),
      );

      final categoriesAsync = ref.watch(
        categoriesByTypeProvider(_isIncome ? 'income' : 'expense'),
      );
      final accountsAsync = ref.watch(paymentAccountsProvider);

      final categoryName = _categoryId == null
          ? null
          : categoriesAsync.value
                ?.where((c) => c.id == _categoryId)
                .firstOrNull
                ?.name;
      final accountName = _paymentAccountId == null
          ? null
          : accountsAsync.value
                ?.where((a) => a.id == _paymentAccountId)
                .firstOrNull
                ?.name;

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
            if (widget.isEditMode &&
                ref.watch(canProvider(BosPermission.financeVoid)))
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
        bottomNavigationBar: _buildSaveBar(
          categoryName,
          accountName,
          canSave: canSave,
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _buildTypeSelector(),
                  const SizedBox(height: 16),
                  _buildAmountSection(),
                  const SizedBox(height: 16),
                  _buildDetailsCard(),
                  const SizedBox(height: 22),
                  _buildPickerCard(categoriesAsync, accountsAsync),
                  const SizedBox(height: 22),
                  _buildPendingCard(),
                  const SizedBox(height: 12),
                  _buildAdvancedSection(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ==========================================================
    // SAVE BAR (sticks above the keyboard)
    // ==========================================================

    Widget _buildSaveBar(
      String? categoryName,
      String? accountName, {
      required bool canSave,
    }) {
      final theme = Theme.of(context);
      final amount = double.tryParse(_amountController.text.trim()) ?? 0;

      final parts = <String>[
        if (categoryName != null) categoryName,
        if (accountName != null) accountName,
        if (_markAsPending) 'Pending',
      ];

      return Material(
        color: theme.colorScheme.surface,
        elevation: 8,
        shadowColor: Colors.black26,
        child: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_isIncome ? '+' : '-'}₱${_money(amount)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: _accentColor,
                            ),
                          ),
                          Text(
                            parts.isEmpty
                                ? (_isIncome ? 'Income' : 'Expense')
                                : parts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _isSaving || !canSave ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
                                  widget.isEditMode ? 'Update' : 'Save',
                                  key: const ValueKey('text'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ==========================================================
    // TYPE SELECTOR
    // ==========================================================

    Widget _buildTypeSelector() {
      return Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: _typeButton(
                label: 'Expense',
                icon: Icons.north_east_rounded,
                selected: !_isIncome,
                color: _expenseColor,
                enabled: !widget.isEditMode,
                onTap: () => setState(() {
                  _isIncome = false;
                  _categoryId = null;
                }),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _typeButton(
                label: 'Income',
                icon: Icons.south_west_rounded,
                selected: _isIncome,
                color: _incomeColor,
                enabled: !widget.isEditMode,
                onTap: () => setState(() {
                  _isIncome = true;
                  _categoryId = null;
                }),
              ),
            ),
          ],
        ),
      );
    }

    Widget _typeButton({
      required String label,
      required IconData icon,
      required bool selected,
      required Color color,
      required bool enabled,
      required VoidCallback onTap,
    }) {
      final fg = selected
          ? Colors.white
          : Theme.of(context).colorScheme.onSurfaceVariant;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled && !selected ? onTap : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
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
      final hasAmount = _amountController.text.trim().isNotEmpty;

      return Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accentColor.withValues(alpha: .13),
              theme.colorScheme.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _accentColor.withValues(alpha: .25)),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: .10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Amount',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (hasAmount)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _amountController.clear(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Row(
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
                      filled: false,
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
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pesos in _quickAmounts)
                  ActionChip(
                    onPressed: () => _addAmount(pesos),
                    label: Text('+₱${_money(pesos.toDouble(), decimals: 0)}'),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _accentColor,
                    ),
                    backgroundColor: _accentColor.withValues(alpha: .08),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    void _addAmount(int pesos) {
      final current = double.tryParse(_amountController.text.trim()) ?? 0;
      final next = current + pesos;
      _amountController.text = next == next.roundToDouble()
          ? next.toStringAsFixed(0)
          : next.toStringAsFixed(2);
      _amountController.selection = TextSelection.collapsed(
        offset: _amountController.text.length,
      );
    }

    // ==========================================================
    // DATE + DESCRIPTION
    // ==========================================================

    Widget _buildDetailsCard() {
      final theme = Theme.of(context);
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final yesterdayOnly = todayOnly.subtract(const Duration(days: 1));
      final dateOnly = DateTime(_date.year, _date.month, _date.day);

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconContainer(Icons.calendar_today_rounded, _accentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                TextButton(onPressed: _pickDate, child: const Text('Pick date')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: dateOnly == todayOnly,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _date = DateTime.now()),
                ),
                ChoiceChip(
                  label: const Text('Yesterday'),
                  selected: dateOnly == yesterdayOnly,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    final y = DateTime.now().subtract(const Duration(days: 1));
                    _date = y;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDivider(),
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.notes_rounded, size: 21),
                hintText: _isIncome
                    ? 'What was this income for? (e.g. Walk-in sales)'
                    : 'What was this for? (e.g. Ice and packaging)',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ==========================================================
    // ACCOUNTS (cards)
    // ==========================================================

    IconData _accountIcon(String name) {
      final n = name.toLowerCase();
      if (n.contains('cash')) return Icons.payments_outlined;
      if (n.contains('bank') ||
          n.contains('bpi') ||
          n.contains('bdo') ||
          n.contains('metro') ||
          n.contains('union')) {
        return Icons.account_balance_outlined;
      }
      return Icons.account_balance_wallet_outlined;
    }

    // ==========================================================
    // CATEGORIES (top chips + searchable "All")
    // ==========================================================

    // ==========================================================
    // PICKER CARD (dropdown menus)
    // ==========================================================

    static const _addSentinel = '__add__';
    static const _noneSentinel = '__none__';

    Widget _buildPickerCard(
      AsyncValue<List<Category>> categoriesAsync,
      AsyncValue<List<Account>> accountsAsync,
    ) {
      final theme = Theme.of(context);

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              'Category',
              subtitle: _isIncome
                  ? 'What type of income is this?'
                  : 'What type of expense is this?',
            ),
            const SizedBox(height: 10),
            _buildCategoryDropdown(categoriesAsync),
            const SizedBox(height: 18),
            _buildSectionTitle(
              'Payment account',
              subtitle: _markAsPending
                  ? 'Optional while pending'
                  : (_isIncome
                        ? 'Where the money went in'
                        : 'Where the money came from'),
            ),
            const SizedBox(height: 10),
            _buildAccountDropdown(accountsAsync),
          ],
        ),
      );
    }

    Widget _dropdownShell({
      required IconData icon,
      required bool filled,
      required Widget child,
    }) {
      final theme = Theme.of(context);

      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        decoration: BoxDecoration(
          color: filled
              ? _accentColor.withValues(alpha: .07)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: filled
                ? _accentColor.withValues(alpha: .5)
                : theme.colorScheme.outlineVariant,
            width: filled ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            _iconContainer(
              icon,
              filled ? _accentColor : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(child: DropdownButtonHideUnderline(child: child)),
          ],
        ),
      );
    }

    Widget _menuRow(
      IconData icon,
      String text, {
      Color? color,
      bool bold = false,
    }) {
      return Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      );
    }

    Widget _buildCategoryDropdown(AsyncValue<List<Category>> categoriesAsync) {
      final theme = Theme.of(context);

      return categoriesAsync.when(
        loading: _loadingBox,
        error: (_, _) => _errorBox('Could not load categories.'),
        data: (categories) {
          final matching = categories
              .where((c) => c.txnType == (_isIncome ? 'income' : 'expense'))
              .toList();

          if (_categoryId != null && !matching.any((c) => c.id == _categoryId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _categoryId != null) {
                setState(() => _categoryId = null);
              }
            });
          }

          if (matching.isEmpty) {
            return _emptySelection(
              text: _isIncome
                  ? 'No income categories yet'
                  : 'No expense categories yet',
              actionText: 'Add category',
              onPressed: _addNewCategory,
            );
          }

          final value = matching.any((c) => c.id == _categoryId)
              ? _categoryId
              : null;

          return _dropdownShell(
            icon: Icons.label_outline_rounded,
            filled: value != null,
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              menuMaxHeight: 360,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: theme.colorScheme.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              hint: Text(
                'Select a category',
                style: TextStyle(
                  fontSize: 14.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              items: [
                for (final c in matching)
                  DropdownMenuItem<String>(
                    value: c.id,
                    child: _menuRow(
                      Icons.label_outline_rounded,
                      c.name,
                      color: c.id == value ? _accentColor : null,
                      bold: c.id == value,
                    ),
                  ),
                DropdownMenuItem<String>(
                  value: _addSentinel,
                  child: _menuRow(
                    Icons.add_rounded,
                    'Add category',
                    color: theme.colorScheme.primary,
                    bold: true,
                  ),
                ),
              ],
              onChanged: (v) {
                if (v == _addSentinel) {
                  _addNewCategory();
                  return;
                }
                setState(() => _categoryId = v);
              },
            ),
          );
        },
      );
    }

    Widget _buildAccountDropdown(AsyncValue<List<Account>> accountsAsync) {
      final theme = Theme.of(context);

      return accountsAsync.when(
        loading: _loadingBox,
        error: (_, _) => _errorBox('Could not load payment accounts.'),
        data: (accounts) {
          if (accounts.isEmpty) {
            return _emptySelection(
              text: 'No payment accounts yet',
              actionText: 'Add account',
              onPressed: _addNewAccount,
            );
          }

          final value = accounts.any((a) => a.id == _paymentAccountId)
              ? _paymentAccountId
              : null;

          return _dropdownShell(
            icon: Icons.account_balance_wallet_outlined,
            filled: value != null,
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              menuMaxHeight: 360,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: theme.colorScheme.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              hint: Text(
                _markAsPending ? 'No account (optional)' : 'Select an account',
                style: TextStyle(
                  fontSize: 14.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              items: [
                if (_markAsPending)
                  DropdownMenuItem<String>(
                    value: _noneSentinel,
                    child: _menuRow(
                      Icons.block_rounded,
                      'No account yet',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                for (final a in accounts)
                  DropdownMenuItem<String>(
                    value: a.id,
                    child: _menuRow(
                      _accountIcon(a.name),
                      a.name,
                      color: a.id == value ? _accentColor : null,
                      bold: a.id == value,
                    ),
                  ),
                DropdownMenuItem<String>(
                  value: _addSentinel,
                  child: _menuRow(
                    Icons.add_rounded,
                    'Add account',
                    color: theme.colorScheme.primary,
                    bold: true,
                  ),
                ),
              ],
              onChanged: (v) {
                if (v == _addSentinel) {
                  _addNewAccount();
                  return;
                }
                setState(() => _paymentAccountId = v == _noneSentinel ? null : v);
              },
            ),
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
              onChanged: (value) => setState(() => _markAsPending = value),
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
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
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
                    Text(
                      'Notes, reference${_isIncome ? '' : ', receipt'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
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
                    if (!_isIncome) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickReceipt,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _receiptPhotoPath == null
                                    ? Icons.receipt_long_outlined
                                    : Icons.check_circle_outline_rounded,
                                color: _receiptPhotoPath == null
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _receiptPhotoPath == null
                                      ? 'Attach receipt photo (optional)'
                                      : 'Receipt attached — tap to replace',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              if (_receiptPhotoPath != null)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                  onPressed: () =>
                                      setState(() => _receiptPhotoPath = null),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      );
    }

    // ==========================================================
    // COMPONENTS
    // ==========================================================

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
    // FORMATTING + DATE
    // ==========================================================

    String _money(double value, {int decimals = 2}) {
      final fixed = value.toStringAsFixed(decimals);
      final parts = fixed.split('.');
      final whole = parts[0].replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return parts.length > 1 ? '$whole.${parts[1]}' : whole;
    }

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
        setState(() => _date = picked);
      }
    }

    Future<void> _pickReceipt() async {
      final picker = ImagePicker();

      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final file = await picker.pickImage(source: source, imageQuality: 70);

      if (file != null && mounted) {
        setState(() => _receiptPhotoPath = file.path);
      }
    }

    // ==========================================================
    // ADD ACCOUNT / CATEGORY
    // ==========================================================

    Future<void> _addNewAccount() async {
      final name = await _promptForName(
        title: 'Add payment account',
        hint: 'e.g. GCash, GoTyme, BPI',
      );

      if (name == null || name.trim().isEmpty) return;

      final account = await ref
          .read(transactionServiceProvider)
          .addPaymentAccount(name.trim());

      ref.invalidate(paymentAccountsProvider);

      if (mounted) setState(() => _paymentAccountId = account.id);
    }

    Future<void> _addNewCategory() async {
      final name = await _promptForName(
        title: 'Add category',
        hint: _isIncome ? 'e.g. Rental Income' : 'e.g. Delivery Fuel',
      );

      if (name == null || name.trim().isEmpty) return;

      final category = await ref
          .read(transactionServiceProvider)
          .addCategory(name.trim(), isIncome: _isIncome);

      ref.invalidate(categoriesByTypeProvider(_isIncome ? 'income' : 'expense'));

      if (mounted) setState(() => _categoryId = category.id);
    }

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
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (value) => Navigator.pop(ctx, value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    }

    // ==========================================================
    // SAVE (logic unchanged)
    // ==========================================================

    Future<void> _save() async {
      FocusScope.of(context).unfocus();

      if (_categoryId == null) {
        _showError('Choose a category first.');
        return;
      }

      final amountValue = double.tryParse(_amountController.text.trim());

      if (amountValue == null || !amountValue.isFinite || amountValue <= 0) {
        _showError('Enter a valid amount.');
        return;
      }

      if (!_markAsPending && _paymentAccountId == null) {
        _showError(
          'Choose a payment account, or '
          'mark the transaction as pending.',
        );
        return;
      }

      setState(() => _isSaving = true);

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
            receiptPhotoPath: _receiptPhotoPath,
            markAsPending: _markAsPending,
          );
        }

        ref.read(ledgerVersionProvider.notifier).state++;

        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        _showError('Could not save transaction: $e');
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }

    // ==========================================================
    // DELETE (logic unchanged)
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
              'This will remove the transaction '
              'and reverse its ledger entry.',
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

      setState(() => _isSaving = true);

      final service = ref.read(transactionServiceProvider);

      try {
        if (widget.existingExpense != null) {
          await service.deleteExpense(widget.existingExpense!.id);
        } else if (widget.existingIncome != null) {
          await service.deleteIncome(widget.existingIncome!.id);
        }

        ref.read(ledgerVersionProvider.notifier).state++;

        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        _showError('Could not delete transaction: $e');

        if (mounted) setState(() => _isSaving = false);
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
