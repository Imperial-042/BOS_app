// // test/core/ledger/ledger_service_test.dart
// import 'package:drift/drift.dart';
// import 'package:drift/native.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:bos_application/core/database/app_database.dart';
// import 'package:bos_application/core/ledger/ledger_service.dart';

// void main() {
//   late AppDatabase db;
//   late LedgerService ledgerService;

//   const businessId = 'biz_test';

//   setUp(() async {
//     // fresh, in-memory database for every single test — no leftover state
//     db = AppDatabase.forTesting(NativeDatabase.memory());
//     ledgerService = LedgerService(db);

//     // seed the minimum needed: a business, one payment account, one expense category
//     await db
//         .into(db.businesses)
//         .insert(
//           BusinessesCompanion.insert(
//             id: businessId,
//             ownerUserId: 'owner_test',
//             name: 'Test Business',
//           ),
//         );

//     await db
//         .into(db.accounts)
//         .insert(
//           AccountsCompanion.insert(
//             id: 'acc_bank_test',
//             businessId: businessId,
//             name: 'Bank Account',
//             type: 'asset',
//             isPaymentAccount: const Value(true),
//           ),
//         );

//     await db
//         .into(db.accounts)
//         .insert(
//           AccountsCompanion.insert(
//             id: 'acc_rent_exp_test',
//             businessId: businessId,
//             name: 'Rent Expense',
//             type: 'expense',
//           ),
//         );

//     await db
//         .into(db.categories)
//         .insert(
//           CategoriesCompanion.insert(
//             id: 'cat_rent_test',
//             businessId: businessId,
//             name: 'Rent',
//             txnType: 'expense',
//             ledgerAccountId: 'acc_rent_exp_test',
//           ),
//         );
//   });

//   tearDown(() async {
//     await db.close();
//   });

//   test(
//     'posting an expense creates one journal entry with two balanced ledger lines',
//     () async {
//       await ledgerService.postEntry(
//         businessId: businessId,
//         categoryId: 'cat_rent_test',
//         amount: 500000, // ₱5,000.00 in cents
//         paymentAccountId: 'acc_bank_test',
//         sourceType: 'expense',
//       );

//       final entries = await db.select(db.journalEntries).get();
//       final lines = await db.select(db.ledgerLines).get();

//       expect(entries.length, 1);
//       expect(lines.length, 2);

//       final totalDebits = lines.fold<int>(0, (sum, l) => sum + l.debit);
//       final totalCredits = lines.fold<int>(0, (sum, l) => sum + l.credit);
//       expect(
//         totalDebits,
//         totalCredits,
//       ); // the core invariant — never allowed to drift apart
//       expect(totalDebits, 500000);
//     },
//   );

//   test(
//     'expense debits the Rent Expense account and credits the payment account',
//     () async {
//       await ledgerService.postEntry(
//         businessId: businessId,
//         categoryId: 'cat_rent_test',
//         amount: 500000,
//         paymentAccountId: 'acc_bank_test',
//         sourceType: 'expense',
//       );

//       final lines = await db.select(db.ledgerLines).get();

//       final rentLine = lines.firstWhere(
//         (l) => l.accountId == 'acc_rent_exp_test',
//       );
//       final bankLine = lines.firstWhere((l) => l.accountId == 'acc_bank_test');

//       expect(rentLine.debit, 500000);
//       expect(rentLine.credit, 0);
//       expect(bankLine.credit, 500000);
//       expect(bankLine.debit, 0);
//     },
//   );
// }
