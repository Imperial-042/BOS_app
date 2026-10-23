// lib/features/production/domain/pos_discount.dart
//
// Order-level discount for the POS. Pure Dart, unit-tested.
// The sale's totalAmount is stored NET of the discount, so payments, the
// shift close and the journal all keep working on the amount actually paid.

import 'dart:math' as math;

class PosDiscount {
  final String label;
  final double? percent;
  final int? fixedCents;

  const PosDiscount.percent(this.label, double value)
    : percent = value,
      fixedCents = null;

  const PosDiscount.fixed(this.label, int cents)
    : percent = null,
      fixedCents = cents;

  /// Senior Citizen / PWD preset. IMPORTANT: for VAT-registered businesses
  /// the law applies the 20% AFTER removing VAT, so confirm the exact
  /// computation with your accountant. For non-VAT businesses a flat 20% of
  /// the price is the usual treatment.
  static const seniorPwd = PosDiscount.percent('Senior/PWD 20%', 20);

  /// The discount in centavos for a given subtotal. Never negative and never
  /// more than the subtotal.
  int amountFor(int subtotalCents) {
    if (subtotalCents <= 0) return 0;
    final raw = percent != null
        ? (subtotalCents * percent! / 100).round()
        : (fixedCents ?? 0);
    return math.min(math.max(raw, 0), subtotalCents);
  }
}
