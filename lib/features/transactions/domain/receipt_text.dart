// lib/features/production/domain/receipt_text.dart
//
// Builds a plain-text receipt (for Copy / Share / SMS). No packages needed.
// For a Bluetooth thermal printer later, reuse the same data and swap the
// output stage.

import 'package:bos_application/core/format/money.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';

class ReceiptTextBuilder {
  ReceiptTextBuilder._();

  static String _qty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String build({
    required PosSale sale,
    required List<PosSaleItem> items,
    required List<PosSaleTender> tenders,
    required Map<String, String> accountNames,
    required String cashier,
    String? businessName,
    String? customerName,
    String? customerAddress,
    String? customerTin,
  }) {
    const rule = '--------------------------------';
    final b = StringBuffer();

    if (businessName != null && businessName.trim().isNotEmpty) {
      b.writeln(businessName.trim());
    }
    b.writeln(sale.isStockOnly ? 'STOCK DEDUCTION' : 'SALES RECEIPT');
    b.writeln(receiptLabel(sale, idLength: 8));
    b.writeln(DateFormat('MMM d, yyyy · h:mm a').format(sale.saleDate));
    b.writeln('Cashier: $cashier');
    if ((sale.orderType ?? '').isNotEmpty) {
      b.writeln('Order type: ${sale.orderType}');
    }
    if ((sale.tableLabel ?? '').isNotEmpty) {
      b.writeln(
        'Table: ${sale.tableLabel}'
        '${sale.guests == null ? '' : ' (${sale.guests} guests)'}',
      );
    }
    if ((sale.orderRef ?? '').isNotEmpty) {
      b.writeln('Order no.: ${sale.orderRef}');
    }
    if ((sale.contactName ?? '').isNotEmpty) {
      b.writeln(
        'Contact: ${sale.contactName}'
        '${(sale.contactPhone ?? '').isEmpty ? '' : ' · ${sale.contactPhone}'}',
      );
    }
    if ((sale.deliveryAddress ?? '').isNotEmpty) {
      b.writeln('Deliver to: ${sale.deliveryAddress}');
    }
    if (customerName != null && customerName.trim().isNotEmpty) {
      b.writeln('Customer: ${customerName.trim()}');
    }
    if (customerAddress != null && customerAddress.trim().isNotEmpty) {
      b.writeln('Address: ${customerAddress.trim()}');
    }
    if (customerTin != null && customerTin.trim().isNotEmpty) {
      b.writeln('TIN: ${customerTin.trim()}');
    }
    if (sale.isVoided) b.writeln('*** VOID ***');
    b.writeln(rule);

    for (final i in items) {
      b.writeln(i.productName);
      final left =
          '  ${_qty(i.quantity)} ${i.unit} x ${formatPeso(i.unitPrice)}';
      b.writeln(sale.isStockOnly ? left : '$left   ${formatPeso(i.lineTotal)}');
    }
    b.writeln(rule);

    if (!sale.isStockOnly) {
      if (sale.discountAmount > 0) {
        b.writeln(
          'Subtotal: ${formatPeso(sale.totalAmount + sale.discountAmount)}',
        );
        b.writeln(
          '${sale.discountLabel ?? 'Discount'}: '
          '-${formatPeso(sale.discountAmount)}',
        );
      }
      b.writeln('TOTAL: ${formatPeso(sale.totalAmount)}');
      for (final t in tenders) {
        final name = tenderLabel(accountNames[t.accountId]);
        final provider = t.provider == null ? '' : ' (${t.provider})';
        b.writeln('$name$provider: ${formatPeso(t.amount)}');
        final tendered = t.tendered;
        final int change = (t.changeGiven as int?) ?? 0;
        if (tendered != null && change > 0) {
          b.writeln('  Cash received: ${formatPeso(tendered)}');
          b.writeln('  Change: ${formatPeso(change)}');
        }
        final ref = t.referenceNo;
        if (ref != null && ref.isNotEmpty) b.writeln('  Ref: $ref');
      }
    } else {
      b.writeln('No income recorded.');
    }

    final notes = sale.notes;
    if (notes != null && notes.trim().isNotEmpty) {
      b.writeln(rule);
      b.writeln('Note: ${notes.trim()}');
    }
    b.writeln(rule);
    b.writeln('Thank you!');
    return b.toString();
  }
}

/// "A1B2-007" when the sale has a receipt number, else the old "#ABC123".
String receiptLabel(PosSale s, {int idLength = 6}) {
  final no = s.receiptNo;
  if (no != null && no.isNotEmpty) return no;
  return '#${s.id.substring(0, idLength).toUpperCase()}';
}

/// Account names shown to people: Accounts Receivable reads as "On credit".
String tenderLabel(String? accountName) => accountName == 'Accounts Receivable'
    ? 'On credit'
    : (accountName ?? 'Account');
