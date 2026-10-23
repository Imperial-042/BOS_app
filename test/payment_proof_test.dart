import 'package:bos_application/features/transactions/domain/payment_proof.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentProofParser reference extraction', () {
    test('prefers Reference No. over Trace ID', () {
      final parsed = PaymentProofParser.parse('''
Trace ID
000016
Reference No.
IT0260924071403016
''');
      expect(parsed.referenceNo, 'IT0260924071403016');
    });

    test('extracts same-line alphanumeric reference', () {
      final parsed = PaymentProofParser.parse(
        'Reference No. IT0260924071403016\nTrace ID 000016',
      );
      expect(parsed.referenceNo, 'IT0260924071403016');
    });

    test('extracts hyphenated reference and normalizes separators', () {
      final parsed = PaymentProofParser.parse('''
Reference Number:
REF-2026-09-24-00125
''');
      // Separators are removed but every digit is preserved so dedup never
      // collapses distinct serials (00125 must not become 0125).
      expect(parsed.referenceNo, 'REF2026092400125');
    });

    test('handles OCR-spaced alphanumeric reference', () {
      final parsed = PaymentProofParser.parse('''
Reference No.
IT 0260924071403016
''');
      expect(parsed.referenceNo, 'IT0260924071403016');
    });

    test('normalizes lower-case alphanumeric reference', () {
      final parsed = PaymentProofParser.parse('''
Reference No.
it0260924071403016
''');
      expect(parsed.referenceNo, 'IT0260924071403016');
    });

    test('still supports numeric references', () {
      final parsed = PaymentProofParser.parse('''
Reference No.
20260924071403016
''');
      expect(parsed.referenceNo, '20260924071403016');
    });

    test('does not select Trace ID when a Reference No. exists', () {
      final parsed = PaymentProofParser.parse('''
Trace ID
000016
Amount
₱550.00
Reference No.
G-XC12345678
''');
      expect(parsed.referenceNo, 'GXC12345678');
    });
  });
}
