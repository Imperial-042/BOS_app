// lib/features/transactions/presentation/providers/finance_list_providers.dart
//
// Business-scoped, ledger-version-aware list providers for the Finance
// module pages. Each re-reads when ledgerVersionProvider bumps (any
// business switch or financial write bumps it), so a switch never shows a
// stale business's rows.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../screens/transaction_page.dart'
    show kCurrentBusinessId, ledgerVersionProvider;

final incomeListProvider = StreamProvider<List<IncomeTransaction>>((ref) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.incomeTransactions)
        ..where((i) => i.businessId.equals(kCurrentBusinessId))
        ..orderBy([(i) => OrderingTerm.desc(i.txnDate)]))
      .watch();
});

final expenseListProvider = StreamProvider<List<Expense>>((ref) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.expenses)
        ..where((e) => e.businessId.equals(kCurrentBusinessId))
        ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
      .watch();
});

final accountTransferListProvider = StreamProvider<List<AccountTransfer>>((
  ref,
) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.accountTransfers)
        ..where((t) => t.businessId.equals(kCurrentBusinessId))
        ..orderBy([(t) => OrderingTerm.desc(t.transferDate)]))
      .watch();
});

/// Open receivables: credit sales (no payment account) not yet collected.
final openReceivablesProvider = StreamProvider<List<IncomeTransaction>>((ref) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.incomeTransactions)
        ..where(
          (i) =>
              i.businessId.equals(kCurrentBusinessId) &
              i.paymentAccountId.isNull() &
              i.customerId.isNotNull(),
        )
        ..orderBy([(i) => OrderingTerm.desc(i.txnDate)]))
      .watch();
});

/// Open payables: supplier purchases made on credit not yet paid.
final openPayablesProvider = StreamProvider<List<SupplierPurchase>>((ref) {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.supplierPurchases)
        ..where(
          (p) =>
              p.businessId.equals(kCurrentBusinessId) &
              p.isOnCredit.equals(true),
        )
        ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
      .watch();
});
