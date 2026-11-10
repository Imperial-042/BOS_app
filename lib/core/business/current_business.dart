// lib/core/business/current_business.dart
//
// The ONE place that changes which business is open.
//
// kCurrentBusinessId is a read-only view for call sites that have no `ref`.
// Only applyCurrentBusiness() changes it, and it also feeds
// currentBusinessIdProvider so screens can migrate to the provider one at a
// time. When nothing reads kCurrentBusinessId any more, delete it.

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Tests only: pretend [id] is the open business.
@visibleForTesting
void setCurrentBusinessIdForTest(String id) => _currentBusinessId = id;

String _currentBusinessId = 'biz_001';

/// Read-only. Use currentBusinessIdProvider in new code.
String get kCurrentBusinessId => _currentBusinessId;

/// The open business, or null before startup has chosen one.
final currentBusinessIdProvider = StateProvider<String?>((ref) => null);

/// Bumped whenever ledger data or the open business changes, so providers
/// that read the ledger refresh.
final ledgerVersionProvider = StateProvider<int>((ref) => 0);

/// Makes [businessId] the open business. Returns true if it changed.
bool applyCurrentBusiness(Ref ref, String businessId) {
  final changed = _currentBusinessId != businessId;

  _currentBusinessId = businessId;
  ref.read(currentBusinessIdProvider.notifier).state = businessId;
  ref.invalidate(selectedBusinessIdProvider);

  if (changed) {
    ref.read(ledgerVersionProvider.notifier).state++;
  }
  return changed;
}