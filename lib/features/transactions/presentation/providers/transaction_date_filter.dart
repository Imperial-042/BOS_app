import 'package:flutter/material.dart';

/// Date selection shared by the dashboard and journal entry screens.
enum TransactionDatePreset { today, week, month, year, lastYear, custom }

class TransactionDateFilter {
  final TransactionDatePreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;

  const TransactionDateFilter({
    required this.preset,
    this.customStart,
    this.customEnd,
  });

  const TransactionDateFilter.today()
    : this(preset: TransactionDatePreset.today);
  const TransactionDateFilter.week() : this(preset: TransactionDatePreset.week);
  const TransactionDateFilter.month()
    : this(preset: TransactionDatePreset.month);
  const TransactionDateFilter.year() : this(preset: TransactionDatePreset.year);
  const TransactionDateFilter.lastYear()
    : this(preset: TransactionDatePreset.lastYear);

  factory TransactionDateFilter.custom(DateTimeRange range) {
    return TransactionDateFilter(
      preset: TransactionDatePreset.custom,
      customStart: _dayStart(range.start),
      customEnd: _dayStart(range.end).add(const Duration(days: 1)),
    );
  }

  DateTimeRange get range {
    final now = DateTime.now();
    final today = _dayStart(now);

    switch (preset) {
      case TransactionDatePreset.today:
        return DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 1)),
        );
      case TransactionDatePreset.week:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 7)),
        );
      case TransactionDatePreset.month:
        final start = DateTime(now.year, now.month, 1);
        return DateTimeRange(
          start: start,
          end: DateTime(now.year, now.month + 1, 1),
        );
      case TransactionDatePreset.year:
        return DateTimeRange(
          start: DateTime(now.year),
          end: DateTime(now.year + 1),
        );
      case TransactionDatePreset.lastYear:
        return DateTimeRange(
          start: DateTime(now.year - 1),
          end: DateTime(now.year),
        );
      case TransactionDatePreset.custom:
        return DateTimeRange(
          start: customStart ?? today,
          end: customEnd ?? today.add(const Duration(days: 1)),
        );
    }
  }

  String get label {
    switch (preset) {
      case TransactionDatePreset.today:
        return 'Today';
      case TransactionDatePreset.week:
        return 'This Week';
      case TransactionDatePreset.month:
        return 'This Month';
      case TransactionDatePreset.year:
        return 'This Year';
      case TransactionDatePreset.lastYear:
        return 'Last Year';
      case TransactionDatePreset.custom:
        final selected = range;
        return '${_displayDate(selected.start)} - ${_displayDate(selected.end.subtract(const Duration(days: 1)))}';
    }
  }

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _displayDate(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

  @override
  bool operator ==(Object other) {
    return other is TransactionDateFilter &&
        other.preset == preset &&
        other.customStart == customStart &&
        other.customEnd == customEnd;
  }

  @override
  int get hashCode => Object.hash(preset, customStart, customEnd);
}
