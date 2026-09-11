// lib/features/transactions/data/repositories/transaction_repository_impl.dart
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  final AppDatabase db;
  TransactionRepositoryImpl(this.db);

  @override
  Future<List<Expense>> getExpenses(String businessId) {
    return (db.select(
      db.expenses,
    )..where((e) => e.businessId.equals(businessId))).get();
  }

  @override
  Future<void> addExpense({
    required String businessId,
    required String categoryId,
    required int amount,
    required DateTime date,
    String? description,
    String? paymentAccountId,
  }) async {
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: const Uuid().v4(), // from the `uuid` package
            businessId: businessId,
            categoryId: categoryId,
            amount: amount,
            expenseDate: date,
            description: Value(description),
            paymentAccountId: Value(paymentAccountId),
          ),
        );
  }
}
