// lib/core/format/money.dart
//
// One place to format centavo amounts. 125050 -> ₱1,250.50

import 'package:intl/intl.dart';

final NumberFormat _pesoFormat = NumberFormat('#,##0.00');

class CurrencyOption {
  const CurrencyOption({
    required this.code,
    required this.name,
    required this.symbol,
  });

  final String code;
  final String name;
  final String symbol;

  String get label => '$name ($code)';
}

class MoneyFormatting {
  MoneyFormatting._();

  static const supportedCurrencies = <CurrencyOption>[
    CurrencyOption(code: 'PHP', name: 'Philippine Peso', symbol: '₱'),
    CurrencyOption(code: 'USD', name: 'US Dollar', symbol: r'$'),
    CurrencyOption(code: 'EUR', name: 'Euro', symbol: '€'),
    CurrencyOption(code: 'GBP', name: 'British Pound', symbol: '£'),
    CurrencyOption(code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
    CurrencyOption(code: 'SGD', name: 'Singapore Dollar', symbol: r'S$'),
  ];

  static String _currencyCode = 'PHP';

  static String get currencyCode => _currencyCode;

  static set currencyCode(String code) {
    if (!supportedCurrencies.any((currency) => currency.code == code)) {
      throw ArgumentError.value(code, 'code', 'Unsupported currency');
    }
    _currencyCode = code;
  }

  static CurrencyOption get selectedCurrency => supportedCurrencies.firstWhere(
    (currency) => currency.code == _currencyCode,
  );
}

String formatPeso(int cents) {
  final negative = cents < 0;
  final body = _pesoFormat.format(cents.abs() / 100);
  return '${negative ? '-' : ''}${MoneyFormatting.selectedCurrency.symbol}$body';
}
