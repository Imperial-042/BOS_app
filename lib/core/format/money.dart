// lib/core/format/money.dart
//
// One place to format centavo amounts. 125050 -> ₱1,250.50

import 'package:intl/intl.dart';

final NumberFormat _pesoFormat = NumberFormat('#,##0.00');

String formatPeso(int cents) {
  final negative = cents < 0;
  final body = _pesoFormat.format(cents.abs() / 100);
  return '${negative ? '-' : ''}₱$body';
}
