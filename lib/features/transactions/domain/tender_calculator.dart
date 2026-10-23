// lib/features/production/domain/tender_calculator.dart
//
// Pure Dart (no Flutter, no database) so the payment maths can be unit-tested.
// Extracted from the old _Calc / _calc() inside pos_checkout_sheet.dart.
//
// RULES (unchanged from the checkout sheet)
//   * Only cash can overpay (that is what change is for).
//   * Bank / e-wallet amounts must not exceed what is still due.
//   * Cash covers whatever the non-cash payments leave unpaid.

import 'dart:math' as math;

class TenderLine {
  final bool isCash;
  final int cents;

  const TenderLine({required this.isCash, required this.cents});
}

class TenderCalc {
  final int nonCash;
  final int cashReceived;
  final int cashDue;
  final int cashApplied;
  final int change;
  final int shortfall;
  final bool nonCashOver;

  const TenderCalc({
    required this.nonCash,
    required this.cashReceived,
    required this.cashDue,
    required this.cashApplied,
    required this.change,
    required this.shortfall,
    required this.nonCashOver,
  });

  bool get covered => !nonCashOver && shortfall == 0;
}

class TenderCalculator {
  TenderCalculator._();

  static TenderCalc calculate({
    required int total,
    required Iterable<TenderLine> lines,
  }) {
    var nonCash = 0;
    var cashReceived = 0;
    for (final l in lines) {
      if (l.isCash) {
        cashReceived += l.cents;
      } else {
        nonCash += l.cents;
      }
    }

    final over = nonCash > total;
    final cashDue = math.max(0, total - nonCash);
    final applied = math.min(cashReceived, cashDue);

    return TenderCalc(
      nonCash: nonCash,
      cashReceived: cashReceived,
      cashDue: cashDue,
      cashApplied: applied,
      change: math.max(0, cashReceived - cashDue),
      shortfall: over ? 0 : math.max(0, total - nonCash - applied),
      nonCashOver: over,
    );
  }
}
