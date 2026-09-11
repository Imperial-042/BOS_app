// lib/features/transactions/presentation/providers/transaction_providers.dart
import 'package:bos_application/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database_provider.dart';
import '../../data/repositories/transaction_repository_impl.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final db = ref.watch(
    databaseProvider,
  ); // the AppDatabase singleton from earlier
  return TransactionRepositoryImpl(db);
});
