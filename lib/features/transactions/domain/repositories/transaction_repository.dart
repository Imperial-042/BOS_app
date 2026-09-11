// lib/features/transactions/domain/repositories/transaction_repository.dart
import 'package:bos_application/core/database/app_database.dart';

abstract class TransactionRepository {
  Future<List<Expense>> getExpenses(String businessId);
  Future<void> addExpense({
    required String businessId,
    required String categoryId,
    required int amount,
    required DateTime date,
    String? description,
    String? paymentAccountId,
  });
}
