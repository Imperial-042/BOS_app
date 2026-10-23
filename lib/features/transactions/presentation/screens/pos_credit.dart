// lib/features/production/presentation/screens/pos_credit.dart
//
// Credit ("pay later / utang") sales at the POS.
//
// A credit sale is stored as a normal tender whose account is the business's
// Accounts Receivable account, plus the customer on the sale. When the shift
// is closed it is posted exactly the way CustomerService.recordSale posts a
// credit sale (Dr Accounts Receivable, Cr Sales Income, income transaction with
// the customer and NO payment account), so the Customers and Receivables
// screens pick it up with no changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ledger/ledger_service.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show kCurrentBusinessId, ledgerServiceProvider, ledgerVersionProvider;

/// The id of this business's Accounts Receivable account, or null if the
/// business has none (credit is then simply not offered).
final posReceivableAccountIdProvider = FutureProvider<String?>((ref) async {
  ref.watch(ledgerVersionProvider);
  final ledger = ref.watch(ledgerServiceProvider);
  try {
    return (await ledger.receivableAccount(kCurrentBusinessId)).id;
  } on LedgerException {
    return null;
  }
});
