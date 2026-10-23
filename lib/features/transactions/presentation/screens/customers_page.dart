// lib/features/customers/presentation/screens/customers_page.dart
//
// Customer directory + Accounts Receivable tracking. Mirrors the
// Suppliers/Payables page exactly, reversed in direction:
//
//   - A credit sale: Debit Accounts Receivable, Credit Sales Income.
//     Increases what a customer owes you.
//   - A paid-in-full sale: Debit the payment account, Credit Sales
//     Income directly (no receivable involved).
//   - A payment a customer makes against their balance: Debit the
//     payment account, Credit Accounts Receivable. Decreases what
//     they owe.
// Same invisible-ledger principle as everywhere else: the owner
// just taps "Record Sale" or "Record Payment" and enters an amount.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/features/transactions/domain/receipt_text.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/ledger/ledger_service.dart';
import '../../../../core/sync/sync_tracker.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId;

String _peso(int cents) => '₱${NumberFormat('#,##0.00').format(cents / 100)}';

// ============================================================
// PROVIDERS
// ============================================================

final customersProvider = StreamProvider<List<Customer>>((ref) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.customers)
        ..where(
          (c) =>
              c.businessId.equals(kCurrentBusinessId) & c.isActive.equals(true),
        )
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});

/// What a customer currently owes you: sum of credit sales minus
/// sum of payments they've made against them.
final customerBalanceProvider = FutureProvider.family<int, String>((
  ref,
  customerId,
) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final salesRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(amount), 0) AS total FROM income_transactions
    WHERE customer_id = ? AND business_id = ? AND payment_account_id IS NULL
    ''',
        variables: [
          Variable.withString(customerId),
          Variable.withString(kCurrentBusinessId),
        ],
      )
      .getSingle();

  final paymentsRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(amount), 0) AS total FROM receivable_payments
    WHERE customer_id = ? AND business_id = ? AND status = 'completed'
    ''',
        variables: [
          Variable.withString(customerId),
          Variable.withString(kCurrentBusinessId),
        ],
      )
      .getSingle();

  return salesRow.read<int>('total') - paymentsRow.read<int>('total');
});

/// Total receivable across every customer — for the overview hero.
final totalReceivableProvider = FutureProvider<int>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final salesRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(it.amount), 0) AS total
    FROM income_transactions it
    JOIN customers c ON c.id = it.customer_id
    WHERE c.business_id = ? AND it.payment_account_id IS NULL AND it.customer_id IS NOT NULL
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .getSingle();

  final paymentsRow = await db
      .customSelect(
        '''
    SELECT COALESCE(SUM(rp.amount), 0) AS total
    FROM receivable_payments rp
    JOIN customers c ON c.id = rp.customer_id
    WHERE c.business_id = ? AND rp.status = 'completed'
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
      )
      .getSingle();

  return salesRow.read<int>('total') - paymentsRow.read<int>('total');
});

final customerActivityProvider =
    FutureProvider.family<List<_ActivityItem>, String>((ref, customerId) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);

      final sales =
          await (db.select(db.incomeTransactions)
                ..where(
                  (i) =>
                      i.customerId.equals(customerId) &
                      i.businessId.equals(kCurrentBusinessId),
                )
                ..orderBy([(i) => OrderingTerm.desc(i.txnDate)]))
              .get();

      final payments =
          await (db.select(db.receivablePayments)
                ..where(
                  (p) =>
                      p.customerId.equals(customerId) &
                      p.businessId.equals(kCurrentBusinessId),
                )
                ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
              .get();

      final items = <_ActivityItem>[
        ...sales.map(
          (s) => _ActivityItem(
            isSale: true,
            amount: s.amount,
            date: s.txnDate,
            isOnCredit: s.paymentAccountId == null,
            isPending: false,
            notes: s.notes,
          ),
        ),
        ...payments.map(
          (p) => _ActivityItem(
            isSale: false,
            amount: p.amount,
            date: p.paymentDate,
            isOnCredit: false,
            isPending: p.isOnCredit,
            notes: p.notes,
          ),
        ),
      ];
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });

/// Every POS order linked to one customer, newest first (voided ones included,
/// shown with a VOID tag).
final customerOrdersProvider = StreamProvider.family<List<PosSale>, String>((
  ref,
  customerId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.posSales)
        ..where(
          (s) =>
              s.businessId.equals(kCurrentBusinessId) &
              s.customerId.equals(customerId),
        )
        ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]))
      .watch();
});

class CustomerOrderStats {
  CustomerOrderStats();
  int count = 0;
  int totalCents = 0;
  DateTime? last;
}

/// Order count / total spent / last order for every customer (voided sales
/// are not counted).
final customerOrderStatsProvider =
    StreamProvider<Map<String, CustomerOrderStats>>((ref) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.posSales)..where(
            (s) =>
                s.businessId.equals(kCurrentBusinessId) &
                s.customerId.isNotNull() &
                s.isVoided.equals(false) &
                s.isStockOnly.equals(false),
          ))
          .watch()
          .map((rows) {
            final out = <String, CustomerOrderStats>{};
            for (final s in rows) {
              final stats = out.putIfAbsent(
                s.customerId!,
                () => CustomerOrderStats(),
              );
              stats.count++;
              stats.totalCents += s.totalAmount;
              if (stats.last == null || s.saleDate.isAfter(stats.last!)) {
                stats.last = s.saleDate;
              }
            }
            return out;
          });
    });

class _ActivityItem {
  final bool isSale; // false = a payment received
  final int amount;
  final DateTime date;
  final bool isOnCredit;
  final bool isPending;
  final String? notes;
  _ActivityItem({
    required this.isSale,
    required this.amount,
    required this.date,
    required this.isOnCredit,
    required this.isPending,
    this.notes,
  });
}

// ============================================================
// SERVICE
// ============================================================

class CustomerService {
  final AppDatabase db;
  CustomerService(this.db);

  Future<String> addCustomer({
    required String name,
    String? address,
    String? tin,
    String? phone,
    String? notes,
  }) async {
    final id = const Uuid().v4();
    await db.transaction(() async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: id,
              businessId: kCurrentBusinessId,
              name: name,
              phone: Value(phone),
              address: Value(address),
              tin: Value(tin),
              notes: Value(notes),
            ),
          );
      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'customers',
        entityId: id,
        operation: SyncOp.create,
      );
    });
    return id;
  }

  Future<void> updateCustomer(
    Customer customer, {
    required String name,
    String? address,
    String? tin,
    String? phone,
    String? notes,
  }) async {
    await (db.update(
      db.customers,
    )..where((c) => c.id.equals(customer.id))).write(
      CustomersCompanion(
        name: Value(name),
        phone: Value(phone),
        address: Value(address),
        tin: Value(tin),
        notes: Value(notes),
      ),
    );
  }

  Future<void> deleteCustomer(String customerId) async {
    await db.transaction(() async {
      final customer = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingleOrNull();
      if (customer == null) return;

      final payments = await (db.select(
        db.receivablePayments,
      )..where((p) => p.customerId.equals(customerId))).get();
      final sales = await (db.select(
        db.incomeTransactions,
      )..where((i) => i.customerId.equals(customerId))).get();

      await (db.delete(
        db.receivablePayments,
      )..where((p) => p.customerId.equals(customerId))).go();
      await (db.update(db.incomeTransactions)
            ..where((i) => i.customerId.equals(customerId)))
          .write(const IncomeTransactionsCompanion(customerId: Value(null)));
      await (db.delete(
        db.customers,
      )..where((c) => c.id.equals(customerId))).go();

      await AuditWriter.write(
        db,
        businessId: customer.businessId,
        userId: null,
        action: 'finance.customer_deleted',
        module: AuditModule.finance,
        actionType: AuditActionType.delete,
        entityType: 'customers',
        entityId: customerId,
        entityLabel: customer.name,
        before: {'name': customer.name, 'phone': customer.phone},
        details: {
          'paymentCount': payments.length,
          'paymentTotal': payments.fold<int>(0, (s, p) => s + p.amount),
          'unlinkedSaleCount': sales.length,
          'unlinkedSaleTotal': sales.fold<int>(0, (s, i) => s + i.amount),
        },
      );
    });
  }

  Future<void> recordSale({
    required String customerId,
    required int amount,
    required DateTime date,
    required bool isOnCredit,
    String? paymentAccountId,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Sale amount must be greater than zero.');
    }

    await db.transaction(() async {
      final customer =
          await (db.select(db.customers)..where(
                (c) =>
                    c.id.equals(customerId) &
                    c.businessId.equals(kCurrentBusinessId),
              ))
              .getSingleOrNull();
      if (customer == null) {
        throw StateError('That customer does not belong to this business.');
      }

      final ledger = LedgerService(db);
      final salesIncome = await ledger.requireAccount(
        'acc_sales_$kCurrentBusinessId',
        kCurrentBusinessId,
      );
      final debitAccountId = isOnCredit
          ? (await ledger.receivableAccount(kCurrentBusinessId)).id
          : (await ledger.requirePaymentAccount(
              paymentAccountId!,
              kCurrentBusinessId,
            )).id;

      final saleId = const Uuid().v4();

      await ledger.postSimpleEntry(
        businessId: kCurrentBusinessId,
        date: date,
        amount: amount,
        debitAccountId: debitAccountId,
        creditAccountId: salesIncome.id,
        sourceType: 'income',
        sourceId: saleId,
        description: notes,
      );

      await db
          .into(db.incomeTransactions)
          .insert(
            IncomeTransactionsCompanion.insert(
              id: saleId,
              businessId: kCurrentBusinessId,
              txnDate: date,
              categoryId: AppDatabase.cloudCompatibleDefaultId(
                'categories',
                'Sale_$kCurrentBusinessId',
              ),
              amount: amount,
              customerId: Value(customerId),
              paymentAccountId: Value(isOnCredit ? null : paymentAccountId),
              notes: Value(notes),
              status: const Value('completed'),
            ),
          );
      await AuditWriter.write(
        db,
        businessId: kCurrentBusinessId,
        userId: null,
        action: 'sales.customer_sale_recorded',
        module: AuditModule.sales,
        actionType: AuditActionType.create,
        entityType: 'income_transactions',
        entityId: saleId,
        entityLabel: customer.name,
        after: {
          'amount': amount,
          'isOnCredit': isOnCredit,
          'paymentAccountId': isOnCredit ? null : paymentAccountId,
          'date': date,
        },
        details: {'notes': notes},
      );
    });
  }

  Future<void> recordPayment({
    required String customerId,
    required int amount,
    required String paymentAccountId,
    required DateTime date,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }

    await db.transaction(() async {
      final customer =
          await (db.select(db.customers)..where(
                (c) =>
                    c.id.equals(customerId) &
                    c.businessId.equals(kCurrentBusinessId),
              ))
              .getSingleOrNull();
      if (customer == null) {
        throw StateError('That customer does not belong to this business.');
      }

      // Same outstanding-balance rule as supplier payments: credit sales
      // increase what is owed, completed payments decrease it. Never allow
      // a payment above what this customer actually owes.
      final salesRow = await db
          .customSelect(
            '''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM income_transactions
        WHERE customer_id = ?
          AND business_id = ?
          AND payment_account_id IS NULL
        ''',
            variables: [
              Variable.withString(customerId),
              Variable.withString(kCurrentBusinessId),
            ],
          )
          .getSingle();

      final paymentsRow = await db
          .customSelect(
            '''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM receivable_payments
        WHERE customer_id = ?
          AND business_id = ?
          AND status = 'completed'
        ''',
            variables: [
              Variable.withString(customerId),
              Variable.withString(kCurrentBusinessId),
            ],
          )
          .getSingle();

      final totalSales = salesRow.read<int>('total');
      final totalPayments = paymentsRow.read<int>('total');

      final outstandingBalance = totalSales - totalPayments;

      if (outstandingBalance <= 0) {
        throw StateError('This customer has no outstanding balance to pay.');
      }

      if (amount > outstandingBalance) {
        throw StateError(
          'Payment cannot exceed the outstanding balance of '
          '${_peso(outstandingBalance)}.',
        );
      }

      final paymentId = const Uuid().v4();

      // Customer payment:
      // Dr Payment Account
      // Cr Accounts Receivable
      final ledger = LedgerService(db);
      final receivable = await ledger.receivableAccount(kCurrentBusinessId);
      await ledger.requirePaymentAccount(paymentAccountId, kCurrentBusinessId);

      await ledger.postSimpleEntry(
        businessId: kCurrentBusinessId,
        date: date,
        amount: amount,
        debitAccountId: paymentAccountId,
        creditAccountId: receivable.id,
        sourceType: 'receivable_payment',
        sourceId: paymentId,
        description: notes,
      );

      await db
          .into(db.receivablePayments)
          .insert(
            ReceivablePaymentsCompanion.insert(
              id: paymentId,
              businessId: kCurrentBusinessId,
              customerId: customerId,
              amount: amount,
              paymentAccountId: Value(paymentAccountId),
              isOnCredit: const Value(false),
              status: const Value('completed'),
              paymentDate: date,
              notes: Value(notes),
            ),
          );

      await AuditWriter.write(
        db,
        businessId: kCurrentBusinessId,
        userId: null,
        action: 'finance.customer_payment_recorded',
        module: AuditModule.finance,
        actionType: AuditActionType.create,
        entityType: 'receivable_payments',
        entityId: paymentId,
        entityLabel: customer.name,
        after: {
          'amount': amount,
          'paymentAccountId': paymentAccountId,
          'date': date,
        },
        details: {'outstandingBefore': outstandingBalance, 'notes': notes},
      );

      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'receivable_payments',
        entityId: paymentId,
        operation: SyncOp.create,
      );
    });
  }

  /// Removes a payment and its matching ledger posting together.
  Future<void> deleteReceivablePayment(String paymentId) async {
    await db.transaction(() async {
      final payment = await (db.select(
        db.receivablePayments,
      )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) return;

      final customer = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(payment.customerId))).getSingleOrNull();

      await (db.delete(db.journalEntries)..where(
            (j) =>
                j.sourceType.equals('receivable_payment') &
                j.sourceId.equals(paymentId),
          ))
          .go();
      await (db.delete(
        db.receivablePayments,
      )..where((p) => p.id.equals(paymentId))).go();

      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'receivable_payments',
        entityId: paymentId,
        operation: SyncOp.delete,
      );

      await AuditWriter.write(
        db,
        businessId: payment.businessId,
        userId: null,
        action: 'finance.customer_payment_deleted',
        module: AuditModule.finance,
        actionType: AuditActionType.delete,
        entityType: 'receivable_payments',
        entityId: paymentId,
        entityLabel: customer?.name ?? 'Customer payment',
        before: {
          'amount': payment.amount,
          'paymentAccountId': payment.paymentAccountId,
          'date': payment.paymentDate,
          'notes': payment.notes,
        },
      );
    });
  }
}

final customerServiceProvider = Provider<CustomerService>((ref) {
  return CustomerService(ref.watch(databaseProvider));
});

final _paymentAccountsProvider = FutureProvider<List<Account>>((ref) {
  ref.watch(ledgerVersionProvider);
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
// PAGE — Customers list
// ============================================================

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Customer> _filter(List<Customer> customers) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return customers;
    return customers.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final customersAsync = ref.watch(customersProvider);
    final totalReceivableAsync = ref.watch(totalReceivableProvider);

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
              'Customers',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Sales & receivables',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: customersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: 'Unable to load customers.',
          onRetry: () => ref.invalidate(customersProvider),
        ),
        data: (customers) {
          final filtered = _filter(customers);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (customers.isEmpty)
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: _EmptyState(onAdd: _openAddCustomerSheet),
                      )
                    else ...[
                      totalReceivableAsync.when(
                        data: (total) => _ReceivableOverviewCard(
                          totalReceivable: total,
                          customerCount: customers.length,
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
                                  ? 'All Customers'
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
                              'No customers match "$_query".',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      else
                        ...filtered.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _CustomerCard(customer: c),
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
        onPressed: _openAddCustomerSheet,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _openAddCustomerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CustomerForm(),
    );
  }
}

// ============================================================
// OVERVIEW HERO — brand gradient, adaptive via LayoutBuilder
// ============================================================

class _ReceivableOverviewCard extends StatelessWidget {
  final int totalReceivable;
  final int customerCount;
  const _ReceivableOverviewCard({
    required this.totalReceivable,
    required this.customerCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.accent],
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
                        Icons.people_outline_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Total Receivable',
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
                  totalReceivable > 0 ? _peso(totalReceivable) : '₱0.00',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 26 : 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  totalReceivable > 0
                      ? 'Owed by $customerCount customer${customerCount == 1 ? '' : 's'}'
                      : 'Nothing outstanding',
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
        hintText: 'Search customers...',
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
// CUSTOMER CARD — adaptive: Expanded/Flexible + ellipsis throughout
// ============================================================

class _CustomerCard extends ConsumerWidget {
  final Customer customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balanceAsync = ref.watch(customerBalanceProvider(customer.id));
    final orderStats = ref
        .watch(customerOrderStatsProvider)
        .value?[customer.id];

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerDetailPage(customer: customer),
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
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: Text(
                  customer.name.trim().isEmpty
                      ? '?'
                      : customer.name.trim()[0].toUpperCase(),
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
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (customer.phone != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.call_outlined,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              customer.phone!,
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
                    if (orderStats != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${orderStats.count} order'
                        '${orderStats.count == 1 ? '' : 's'} · '
                        '${_peso(orderStats.totalCents)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
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
    final owes = balance > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          owes ? _peso(balance) : 'Settled',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: owes ? AppColors.accent : Colors.green,
          ),
        ),
        if (owes)
          Text(
            'owes you',
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
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No customers yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'Add your customers to track sales and what they owe you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add customer'),
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
// ADD / EDIT CUSTOMER FORM
// ============================================================

class _CustomerForm extends ConsumerStatefulWidget {
  final Customer? existing;
  const _CustomerForm({this.existing});

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
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
  late final _tinController = TextEditingController(
    text: widget.existing?.tin ?? '',
  );
  late final _notesController = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _tinController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final service = ref.read(customerServiceProvider);

    try {
      if (widget.existing == null) {
        await service.addCustomer(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          tin: _tinController.text.trim().isEmpty
              ? null
              : _tinController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await service.updateCustomer(
          widget.existing!,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }
      ref.invalidate(customersProvider);
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
                62,
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
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.person_add_alt_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.existing == null
                                ? 'Add Customer'
                                : 'Edit Customer',
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
                        labelText: 'Customer name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a customer name'
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
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Address (optional)',
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'TIN (optional)',
                        hintText: '000-000-000-000',
                        prefixIcon: Icon(Icons.badge_outlined),
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
                                    ? 'Save Customer'
                                    : 'Update Customer',
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
// CUSTOMER DETAIL PAGE
// ============================================================

class CustomerDetailPage extends ConsumerWidget {
  final Customer customer;
  const CustomerDetailPage({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balanceAsync = ref.watch(customerBalanceProvider(customer.id));
    final activityAsync = ref.watch(customerActivityProvider(customer.id));
    final ordersAsync = ref.watch(customerOrdersProvider(customer.id));

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(customer.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _CustomerForm(existing: customer),
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
                    Text('Delete customer'),
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
                _CustomerBalanceHero(customer: customer, balance: balance),
            loading: () => const _HeroSkeleton(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 340;
              final buttons = [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openSaleSheet(context, ref),
                    icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                    label: const Text('Record Sale'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                SizedBox(width: stacked ? 0 : 12, height: stacked ? 10 : 0),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openPaymentSheet(context, ref),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Record Payment'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ];
              return stacked
                  ? Column(children: [buttons[0], buttons[1], buttons[2]])
                  : Row(children: buttons);
            },
          ),
          const SizedBox(height: 24),
          if (customer.phone != null ||
              (customer.address ?? '').isNotEmpty ||
              (customer.tin ?? '').isNotEmpty) ...[
            _InfoCard(customer: customer),
            const SizedBox(height: 24),
          ],
          ordersAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (orders) {
              final live = orders.where((o) => !o.isVoided).toList();
              final spent = live.fold<int>(0, (s, o) => s + o.totalAmount);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Orders',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (live.isNotEmpty)
                        Text(
                          '${live.length} · ${_peso(spent)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (orders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No POS orders yet. Choose this customer at checkout '
                        'and their orders will show here.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    for (final o in orders.take(30))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OrderTile(sale: o),
                      ),
                  if (orders.length > 30)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Showing the latest 30 of ${orders.length} orders.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
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
                      'No sales or payments recorded yet.',
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

  void _openSaleSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordSaleSheet(customer: customer),
    );
  }

  void _openPaymentSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPaymentSheet(customer: customer),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete this customer?'),
        content: Text(
          'This removes "${customer.name}" and their payment history. Past sales stay in Journal Entry, unlinked from any customer.',
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
    await ref.read(customerServiceProvider).deleteCustomer(customer.id);
    ref.invalidate(customersProvider);
    if (context.mounted) Navigator.pop(context);
  }
}

class _CustomerBalanceHero extends StatelessWidget {
  final Customer customer;
  final int balance;
  const _CustomerBalanceHero({required this.customer, required this.balance});

  @override
  Widget build(BuildContext context) {
    final owes = balance > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: owes
              ? [AppColors.primary, AppColors.accent]
              : [Colors.green.shade600, Colors.green.shade400],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Owes You',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            owes ? _peso(balance) : '₱0.00',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            owes
                ? 'from ${customer.name}'
                : 'All settled up with ${customer.name}',
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
  final Customer customer;
  const _InfoCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(child: Text(text)),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customer.phone != null) row(Icons.call_outlined, customer.phone!),
          if ((customer.address ?? '').isNotEmpty)
            row(Icons.home_outlined, customer.address!),
          if ((customer.tin ?? '').isNotEmpty)
            row(Icons.badge_outlined, 'TIN ${customer.tin}'),
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
    final color = item.isSale ? AppColors.accent : Colors.green;
    final icon = item.isSale
        ? Icons.point_of_sale_outlined
        : Icons.payments_outlined;
    final label = item.isSale
        ? (item.isOnCredit ? 'Sale (credit)' : 'Sale (paid)')
        : (item.isPending ? 'Payment (on credit)' : 'Payment received');

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
              color: color.withValues(alpha: 0.14),
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
            '${item.isSale ? '+' : '-'}${_peso(item.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: item.isSale ? AppColors.accent : Colors.green,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RECORD SALE SHEET
// ============================================================

class _RecordSaleSheet extends ConsumerStatefulWidget {
  final Customer customer;
  const _RecordSaleSheet({required this.customer});

  @override
  ConsumerState<_RecordSaleSheet> createState() => _RecordSaleSheetState();
}

class _RecordSaleSheetState extends ConsumerState<_RecordSaleSheet> {
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
              const Text(
                'Record Sale',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                'to ${widget.customer.name}',
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('On credit'),
                subtitle: const Text(
                  'Customer hasn\'t paid yet — adds to what they owe',
                ),
                value: _isOnCredit,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _isOnCredit = v),
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
                          'Save Sale',
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
    final service = ref.read(customerServiceProvider);
    try {
      await service.recordSale(
        customerId: widget.customer.id,
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
  final Customer customer;
  const _RecordPaymentSheet({required this.customer});

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
    final balanceAsync = ref.watch(customerBalanceProvider(widget.customer.id));

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

              const Text(
                'Record Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),

              balanceAsync.when(
                data: (balance) => Text(
                  balance > 0
                      ? '${widget.customer.name} owes ${_peso(balance)}'
                      : 'from ${widget.customer.name}',
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
                'Received via',
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
                          onSelected: (_) {
                            setState(() {
                              _paymentAccountId = a.id;
                            });
                          },
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

    if (amount == null || amount <= 0) return;

    if (_paymentAccountId == null) return;

    setState(() => _saving = true);

    final service = ref.read(customerServiceProvider);

    try {
      await service.recordPayment(
        customerId: widget.customer.id,
        amount: (amount * 100).round(),
        paymentAccountId: _paymentAccountId!,
        date: DateTime.now(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _OrderTile extends ConsumerWidget {
  final PosSale sale;
  const _OrderTile({required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(posSaleItemsProvider(sale.id)).value ?? const [];
    final names = items
        .take(3)
        .map((i) {
          final q = i.quantity == i.quantity.roundToDouble()
              ? i.quantity.toInt().toString()
              : i.quantity.toStringAsFixed(1);
          return '${i.productName} ×$q';
        })
        .join(', ');
    final more = items.length > 3 ? ' +${items.length - 3} more' : '';

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => POSSaleDetailPage(sale: sale)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 17,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            receiptLabel(sale),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (sale.isVoided) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'VOID',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      DateFormat('MMM d, yyyy · h:mm a').format(sale.saleDate),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (names.isNotEmpty)
                      Text(
                        '$names$more',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _peso(sale.totalAmount),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  decoration: sale.isVoided ? TextDecoration.lineThrough : null,
                  color: sale.isVoided ? scheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
