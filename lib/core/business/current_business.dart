// lib/core/business/current_business.dart
//
// The ONE place that changes which business is open.
//
// kCurrentBusinessId (transaction_page.dart) is a mutable global that many
// screens still read. It is now written only from applyCurrentBusiness(), and
// mirrored into currentBusinessIdProvider so code can migrate to the provider
// one call site at a time. When no reference to kCurrentBusinessId is left,
// delete the global and the first line of applyCurrentBusiness().

import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart' show kCurrentBusinessId, ledgerVersionProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';

/// The open business, or null before startup has chosen one.
final currentBusinessIdProvider = StateProvider<String?>((ref) => null);

/// Makes [businessId] the open business. Returns true if it changed.
bool applyCurrentBusiness(Ref ref, String businessId) {
  final changed = kCurrentBusinessId != businessId;

  kCurrentBusinessId = businessId; // legacy global, see header
  ref.read(currentBusinessIdProvider.notifier).state = businessId;
  ref.invalidate(selectedBusinessIdProvider);

  if (changed) {
    ref.read(ledgerVersionProvider.notifier).state++;
  }
  return changed;
}
