// lib/features/transactions/presentation/providers/ledger_providers.dart

import 'package:bos_application/core/business/current_business.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';

final businessProfileProvider = StreamProvider<BusinessesData>((ref) {
    ref.watch(ledgerVersionProvider);

    final db = ref.watch(databaseProvider);

    return (db.select(
      db.businesses,
    )..where((business) => business.id.equals(kCurrentBusinessId))).watchSingle();
  });

  

  final categoriesByTypeProvider = FutureProvider.family<List<Category>, String>((
    ref,
    txnType,
  ) {
    ref.watch(ledgerVersionProvider);

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
