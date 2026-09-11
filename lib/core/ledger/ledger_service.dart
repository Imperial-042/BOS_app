// lib/core/ledger/ledger_service.dart
import 'package:bos_application/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class LedgerService {
  final AppDatabase db;
  LedgerService(this.db);

  Future<String> postEntry({
    required String businessId,
    required String categoryId,
    required int amount,
    required String paymentAccountId,
    required String sourceType, // 'expense' | 'income' | 'transfer'
    String? sourceId,
    String? description,
  }) async {
    final category = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(categoryId))).getSingle();

    final isExpense = category.txnType == 'expense';
    final debitAccountId = isExpense
        ? category.ledgerAccountId
        : paymentAccountId;
    final creditAccountId = isExpense
        ? paymentAccountId
        : category.ledgerAccountId;

    final entryId = const Uuid().v4();

    await db.transaction(() async {
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: entryId,
              businessId: businessId,
              entryDate: DateTime.now(),
              sourceType: sourceType,
              sourceId: Value(sourceId),
              description: Value(description),
            ),
          );

      await db
          .into(db.ledgerLines)
          .insert(
            LedgerLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: entryId,
              accountId: debitAccountId,
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
    });

    return entryId;
  }
}
