// lib/features/transactions/presentation/screens/journal_entry_screen.dart
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JournalEntryScreen extends ConsumerWidget {
  const JournalEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesListProvider);

    return Scaffold(
      body: expensesAsync.when(
        data: (expenses) => ListView.builder(
          itemCount: expenses.length,
          itemBuilder: (_, i) =>
              ListTile(title: Text(expenses[i].description ?? '')),
        ),
        loading: () => const CircularProgressIndicator(),
        error: (e, _) => Text('Error: $e'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: 'Add Expense',
        onPressed: () async {
          await ref
              .read(transactionRepositoryProvider)
              .addExpense(
                businessId: 'biz_001',
                categoryId: 'rent_biz_001',
                amount: 500000, // ₱5,000.00 in cents
                date: DateTime.now(),
              );
          ref.invalidate(expensesListProvider); // trigger a refresh
        },
      ),
    );
  }
}

// the list-reading provider, separate from the repository provider itself
final expensesListProvider = FutureProvider<List<Expense>>((ref) {
  return ref.watch(transactionRepositoryProvider).getExpenses('biz_001');
});
