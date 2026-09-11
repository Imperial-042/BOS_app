// lib/features/suppliers/presentation/screens/suppliers_page.dart
//
// Supplier directory + Accounts Payable tracking. Mirrors the
// Customers/Receivables pattern (not yet built) so the two stay
// symmetric when Customers is built next.
//
// Ledger behavior:
//   - A credit purchase: Debit Inventory/Stock Expense, Credit
//     Accounts Payable. Increases what you owe.
//   - A paid-in-full purchase: Debit Inventory/Stock Expense,
//     Credit the payment account directly (no payable involved).
//   - A payment against a supplier's balance: Debit Accounts
//     Payable, Credit the payment account. Decreases what you owe.
// All of this happens invisibly — the owner only ever taps
// "Record Purchase" or "Record Payment" and fills in an amount.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId;

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

// ============================================================
// PROVIDERS
// ============================================================

final suppliersProvider = StreamProvider<List<Supplier>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.suppliers)
        ..where(
          (s) =>
              s.businessId.equals(kCurrentBusinessId) & s.isActive.equals(true),
        )
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch();
});

/// What you currently owe this supplier: sum of credit purchases
/// minus sum of payments made against them.
final supplierBalanceProvider = FutureProvider.family<int, String>((
  ref,
  supplierId,
) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final purchasesRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(amount), 0) AS total FROM supplier_purchases
    WHERE supplier_id = ? AND is_on_credit = 1
    ''',
        variables: [Variable.withString(supplierId)],
      )
      .getSingle();

  final paymentsRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(amount), 0) AS total FROM payable_payments
    WHERE supplier_id = ?
    ''',
        variables: [Variable.withString(supplierId)],
      )
      .getSingle();

  return purchasesRow.read<int>('total') - paymentsRow.read<int>('total');
});

/// Total payable across every supplier — for the overview hero.
final totalPayableProvider = FutureProvider<int>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final purchasesRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(sp.amount), 0) AS total
    FROM supplier_purchases sp
    JOIN suppliers s ON s.id = sp.supplier_id
    WHERE s.business_id = ? AND sp.is_on_credit = 1
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .getSingle();

  final paymentsRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(pp.amount), 0) AS total
    FROM payable_payments pp
    JOIN suppliers s ON s.id = pp.supplier_id
    WHERE s.business_id = ?
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .getSingle();

  return purchasesRow.read<int>('total') - paymentsRow.read<int>('total');
});

final supplierActivityProvider =
    FutureProvider.family<List<_ActivityItem>, String>((ref, supplierId) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);

      final purchases =
          await (db.select(db.supplierPurchases)
                ..where((p) => p.supplierId.equals(supplierId))
                ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
              .get();

      final payments =
          await (db.select(db.payablePayments)
                ..where((p) => p.supplierId.equals(supplierId))
                ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
              .get();

      final items = <_ActivityItem>[
        ...purchases.map(
          (p) => _ActivityItem(
            isPurchase: true,
            amount: p.amount,
            date: p.purchaseDate,
            isOnCredit: p.isOnCredit,
            notes: p.notes,
          ),
        ),
        ...payments.map(
          (p) => _ActivityItem(
            isPurchase: false,
            amount: p.amount,
            date: p.paymentDate,
            isOnCredit: false,
            notes: p.notes,
          ),
        ),
      ];
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });

class _ActivityItem {
  final bool isPurchase; // false = a payment
  final int amount;
  final DateTime date;
  final bool isOnCredit;
  final String? notes;
  _ActivityItem({
    required this.isPurchase,
    required this.amount,
    required this.date,
    required this.isOnCredit,
    this.notes,
  });
}

// ============================================================
// SERVICE — writes the supplier record AND the matching ledger
// entry together, so Cashflow/Dashboard stay correct automatically.
// ============================================================

class SupplierService {
  final AppDatabase db;
  SupplierService(this.db);

  Future<void> addSupplier({
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: const Uuid().v4(),
            businessId: kCurrentBusinessId,
            name: name,
            phone: Value(phone),
            address: Value(address),
            notes: Value(notes),
          ),
        );
  }

  Future<void> updateSupplier(
    Supplier supplier, {
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    await (db.update(
      db.suppliers,
    )..where((s) => s.id.equals(supplier.id))).write(
      SuppliersCompanion(
        name: Value(name),
        phone: Value(phone),
        address: Value(address),
        notes: Value(notes),
      ),
    );
  }

  Future<void> deleteSupplier(String supplierId) async {
    await (db.delete(
      db.payablePayments,
    )..where((p) => p.supplierId.equals(supplierId))).go();
    await (db.delete(
      db.supplierPurchases,
    )..where((p) => p.supplierId.equals(supplierId))).go();
    await (db.delete(db.suppliers)..where((s) => s.id.equals(supplierId))).go();
  }

  Future<void> recordPurchase({
    required String supplierId,
    required int amount,
    required DateTime date,
    required bool isOnCredit,
    String? paymentAccountId,
    String? notes,
  }) async {
    await db.transaction(() async {
      final entryId = const Uuid().v4();
      final creditAccountId = isOnCredit
          ? 'acc_ap_$kCurrentBusinessId'
          : (paymentAccountId ?? 'acc_ap_$kCurrentBusinessId');

      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: entryId,
              businessId: kCurrentBusinessId,
              entryDate: date,
              sourceType: 'supplier_purchase',
              description: Value(notes),
            ),
          );
      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: entryId,
              accountId: 'acc_inv_exp_$kCurrentBusinessId',
              debit: Value(amount),
            ),
          );
      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: entryId,
              accountId: creditAccountId,
              credit: Value(amount),
            ),
          );

      await db
          .into(db.supplierPurchases)
          .insert(
            SupplierPurchasesCompanion.insert(
              id: const Uuid().v4(),
              businessId: kCurrentBusinessId,
              supplierId: supplierId,
              purchaseDate: date,
              amount: amount,
              isOnCredit: Value(isOnCredit),
              paymentAccountId: Value(isOnCredit ? null : paymentAccountId),
              notes: Value(notes),
              status: const Value('completed'),
            ),
          );
    });
  }

  Future<void> recordPayment({
    required String supplierId,
    required int amount,
    required String paymentAccountId,
    required DateTime date,
    String? notes,
  }) async {
    await db.transaction(() async {
      final entryId = const Uuid().v4();

      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: entryId,
              businessId: kCurrentBusinessId,
              entryDate: date,
              sourceType: 'payable_payment',
              description: Value(notes),
            ),
          );
      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: entryId,
              accountId: 'acc_ap_$kCurrentBusinessId',
              debit: Value(amount),
            ),
          );
      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: entryId,
              accountId: paymentAccountId,
              credit: Value(amount),
            ),
          );

      await db
          .into(db.payablePayments)
          .insert(
            PayablePaymentsCompanion.insert(
              id: const Uuid().v4(),
              businessId: kCurrentBusinessId,
              supplierId: supplierId,
              amount: amount,
              paymentAccountId: paymentAccountId,
              paymentDate: date,
              notes: Value(notes),
            ),
          );
    });
  }
}

final supplierServiceProvider = Provider<SupplierService>((ref) {
  return SupplierService(ref.watch(databaseProvider));
});

// ============================================================
// PAGE — Suppliers list
// ============================================================

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Supplier> _filter(List<Supplier> suppliers) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return suppliers;
    return suppliers.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suppliersAsync = ref.watch(suppliersProvider);
    final totalPayableAsync = ref.watch(totalPayableProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Suppliers',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Purchases & payables',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: suppliersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: 'Unable to load suppliers.',
          onRetry: () => ref.invalidate(suppliersProvider),
        ),
        data: (suppliers) {
          final filtered = _filter(suppliers);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (suppliers.isEmpty)
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: _EmptyState(onAdd: _openAddSupplierSheet),
                      )
                    else ...[
                      totalPayableAsync.when(
                        data: (total) => _PayableOverviewCard(
                          totalPayable: total,
                          supplierCount: suppliers.length,
                        ),
                        loading: () => const _HeroSkeleton(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),
                      _SearchField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        onClear: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _query.trim().isEmpty
                                  ? 'All Suppliers'
                                  : 'Search results',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${filtered.length}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No suppliers match "$_query".',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      else
                        ...filtered.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SupplierCard(supplier: s),
                          ),
                        ),
                    ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _openAddSupplierSheet,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _openAddSupplierSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupplierForm(),
    );
  }
}

// ============================================================
// OVERVIEW HERO — brand gradient, adaptive via LayoutBuilder
// ============================================================

class _PayableOverviewCard extends StatelessWidget {
  final int totalPayable;
  final int supplierCount;
  const _PayableOverviewCard({
    required this.totalPayable,
    required this.supplierCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final compact = width < 380;
          final padding = compact ? 16.0 : 20.0;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.local_shipping_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Total Payable',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  totalPayable > 0 ? _peso(totalPayable) : '₱0.00',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 26 : 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  totalPayable > 0
                      ? 'Across $supplierCount supplier${supplierCount == 1 ? '' : 's'}'
                      : 'All settled up',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ============================================================
// SEARCH
// ============================================================

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search suppliers...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ============================================================
// SUPPLIER CARD — fully adaptive: text areas use Expanded/Flexible
// with ellipsis so nothing can overflow at any width.
// ============================================================

class _SupplierCard extends ConsumerWidget {
  final Supplier supplier;
  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balanceAsync = ref.watch(supplierBalanceProvider(supplier.id));

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupplierDetailPage(supplier: supplier),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: Text(
                  supplier.name.trim().isEmpty
                      ? '?'
                      : supplier.name.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (supplier.phone != null || supplier.address != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              supplier.phone ?? supplier.address ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              balanceAsync.when(
                data: (balance) => _BalanceChip(balance: balance),
                loading: () =>
                    const SizedBox(width: 60, child: LinearProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final int balance;
  const _BalanceChip({required this.balance});

  @override
  Widget build(BuildContext context) {
    final owed = balance > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          owed ? _peso(balance) : 'Settled',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: owed ? Colors.redAccent : Colors.green,
          ),
        ),
        if (owed)
          Text(
            'owed',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
      ],
    );
  }
}

// ============================================================
// EMPTY / ERROR STATES
// ============================================================

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No suppliers yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'Add your suppliers to track purchases and what you owe.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add supplier'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 46,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ADD / EDIT SUPPLIER FORM
// ============================================================

class _SupplierForm extends ConsumerStatefulWidget {
  final Supplier? existing;
  const _SupplierForm({this.existing});

  @override
  ConsumerState<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends ConsumerState<_SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _phoneController = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final _addressController = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final _notesController = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final service = ref.read(supplierServiceProvider);

    try {
      if (widget.existing == null) {
        await service.addSupplier(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await service.updateSupplier(
          widget.existing!,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }
      ref.invalidate(suppliersProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 360 ? 14.0 : 20.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                10,
                horizontalPadding,
                24,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.local_shipping_outlined,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.existing == null
                                ? 'Add Supplier'
                                : 'Edit Supplier',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Supplier name',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a supplier name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        prefixIcon: Icon(Icons.call_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Address (optional)',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.existing == null
                                    ? 'Save Supplier'
                                    : 'Update Supplier',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// SUPPLIER DETAIL PAGE
// ============================================================

class SupplierDetailPage extends ConsumerWidget {
  final Supplier supplier;
  const SupplierDetailPage({super.key, required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balanceAsync = ref.watch(supplierBalanceProvider(supplier.id));
    final activityAsync = ref.watch(supplierActivityProvider(supplier.id));

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(supplier.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _SupplierForm(existing: supplier),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _confirmDelete(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 10),
                    Text('Delete supplier'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          balanceAsync.when(
            data: (balance) =>
                _SupplierBalanceHero(supplier: supplier, balance: balance),
            loading: () => const _HeroSkeleton(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 340;

              final purchaseButton = OutlinedButton.icon(
                onPressed: () => _openPurchaseSheet(context, ref),
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                label: const Text(
                  'Record Purchase',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              );

              final paymentButton = FilledButton.icon(
                onPressed: () => _openPaymentSheet(context, ref),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text(
                  'Record Payment',
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    purchaseButton,
                    const SizedBox(height: 10),
                    paymentButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: purchaseButton),
                  const SizedBox(width: 12),
                  Expanded(child: paymentButton),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (supplier.phone != null || supplier.address != null) ...[
            _InfoCard(supplier: supplier),
            const SizedBox(height: 24),
          ],
          Text(
            'Activity',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          activityAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No purchases or payments recorded yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: items
                    .map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ActivityTile(item: i),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }

  void _openPurchaseSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPurchaseSheet(supplier: supplier),
    );
  }

  void _openPaymentSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPaymentSheet(supplier: supplier),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete this supplier?'),
        content: Text(
          'This removes "${supplier.name}" and all its purchase/payment history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(supplierServiceProvider).deleteSupplier(supplier.id);
    ref.invalidate(suppliersProvider);
    if (context.mounted) Navigator.pop(context);
  }
}

class _SupplierBalanceHero extends StatelessWidget {
  final Supplier supplier;
  final int balance;
  const _SupplierBalanceHero({required this.supplier, required this.balance});

  @override
  Widget build(BuildContext context) {
    final owed = balance > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: owed
              ? [AppColors.primary, AppColors.primaryLight]
              : [Colors.green.shade600, Colors.green.shade400],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You Owe',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            owed ? _peso(balance) : '₱0.00',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            owed
                ? 'to ${supplier.name}'
                : 'All settled up with ${supplier.name}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Supplier supplier;
  const _InfoCard({required this.supplier});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (supplier.phone != null)
            Row(
              children: [
                Icon(
                  Icons.call_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(supplier.phone!, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          if (supplier.phone != null && supplier.address != null)
            const SizedBox(height: 8),
          if (supplier.address != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(supplier.address!)),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final _ActivityItem item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.isPurchase ? Colors.redAccent : Colors.green;
    final icon = item.isPurchase
        ? Icons.add_shopping_cart_outlined
        : Icons.payments_outlined;
    final label = item.isPurchase
        ? (item.isOnCredit ? 'Purchase (credit)' : 'Purchase (paid)')
        : 'Payment';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(item.date),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${item.isPurchase ? '+' : '-'}${_peso(item.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: item.isPurchase ? Colors.redAccent : Colors.green,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RECORD PURCHASE SHEET
// ============================================================

class _RecordPurchaseSheet extends ConsumerStatefulWidget {
  final Supplier supplier;
  const _RecordPurchaseSheet({required this.supplier});

  @override
  ConsumerState<_RecordPurchaseSheet> createState() =>
      _RecordPurchaseSheetState();
}

class _RecordPurchaseSheetState extends ConsumerState<_RecordPurchaseSheet> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isOnCredit = true;
  String? _paymentAccountId;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(_paymentAccountsProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Record Purchase',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'from ${widget.supplier.name}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Material(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('On credit'),
                  subtitle: const Text('Not paid yet — adds to what you owe'),
                  value: _isOnCredit,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _isOnCredit = v),
                ),
              ),
              if (!_isOnCredit) ...[
                const SizedBox(height: 8),
                Text(
                  'Paid via',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                accountsAsync.when(
                  data: (accounts) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: accounts
                        .map(
                          (a) => ChoiceChip(
                            label: Text(a.name),
                            selected: _paymentAccountId == a.id,
                            onSelected: (_) =>
                                setState(() => _paymentAccountId = a.id),
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.16,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Purchase',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;
    if (!_isOnCredit && _paymentAccountId == null) return;

    setState(() => _saving = true);
    final service = ref.read(supplierServiceProvider);
    try {
      await service.recordPurchase(
        supplierId: widget.supplier.id,
        amount: (amount * 100).round(),
        date: DateTime.now(),
        isOnCredit: _isOnCredit,
        paymentAccountId: _paymentAccountId,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ============================================================
// RECORD PAYMENT SHEET
// ============================================================

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  final Supplier supplier;
  const _RecordPaymentSheet({required this.supplier});

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String? _paymentAccountId;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(_paymentAccountsProvider);
    final balanceAsync = ref.watch(supplierBalanceProvider(widget.supplier.id));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Record Payment',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              balanceAsync.when(
                data: (balance) => Text(
                  balance > 0
                      ? 'You owe ${_peso(balance)} to ${widget.supplier.name}'
                      : 'to ${widget.supplier.name}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Paid via',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              accountsAsync.when(
                data: (accounts) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: accounts
                      .map(
                        (a) => ChoiceChip(
                          label: Text(a.name),
                          selected: _paymentAccountId == a.id,
                          onSelected: (_) =>
                              setState(() => _paymentAccountId = a.id),
                          selectedColor: AppColors.primary.withValues(
                            alpha: 0.16,
                          ),
                        ),
                      )
                      .toList(),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Payment',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0 || _paymentAccountId == null) return;

    setState(() => _saving = true);
    final service = ref.read(supplierServiceProvider);
    try {
      await service.recordPayment(
        supplierId: widget.supplier.id,
        amount: (amount * 100).round(),
        paymentAccountId: _paymentAccountId!,
        date: DateTime.now(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

final _paymentAccountsProvider = FutureProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)..where(
        (a) =>
            a.businessId.equals(kCurrentBusinessId) &
            a.isPaymentAccount.equals(true) &
            a.isActive.equals(true),
      ))
      .get();
});
