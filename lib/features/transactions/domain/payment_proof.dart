// lib/features/production/domain/payment_proof.dart
//
// Pure Dart (no Flutter, no ML Kit) so it can be unit-tested with plain
// strings. The OCR step lives in the sheet; this file only interprets text.
//
// Reference parsing is label-aware. Payment screenshots often contain several
// numbers (amount, Trace ID, account number, date, etc.), while a reference
// number may be alphanumeric, for example: IT0260924071403016.
//
// The parser returns null for anything it isn't reasonably sure about.
// The cashier fills gaps on the review screen — a wrong guess is worse
// than an empty field.

/// What gets saved with a sale.
class PaymentProofInput {
  /// Already normalized (see [normalizeReference]).
  final String? referenceNo;
  final int amountCents;
  final DateTime? paidAt;
  final String? provider;
  final String? photoPath;

  const PaymentProofInput({
    required this.referenceNo,
    required this.amountCents,
    this.paidAt,
    this.provider,
    this.photoPath,
  });

  /// Canonical form used for duplicate-reference checks.
  ///
  /// Separators and OCR-introduced whitespace are removed so equivalent
  /// representations compare equal. Letters are upper-cased.
  ///
  /// Example:
  ///   IT 026-0924-071403016 -> IT0260924071403016
  static String? normalizeReference(String? raw) {
    if (raw == null) return null;

    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

    return cleaned.isEmpty ? null : cleaned;
  }
}

class ParsedPaymentProof {
  final String? referenceNo;
  final int? amountCents;
  final DateTime? paidAt;
  final String? provider;

  const ParsedPaymentProof({
    this.referenceNo,
    this.amountCents,
    this.paidAt,
    this.provider,
  });
}

class PaymentProofParser {
  PaymentProofParser._();

  static ParsedPaymentProof parse(String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return ParsedPaymentProof(
      referenceNo: _reference(lines),
      amountCents: _amount(lines),
      paidAt: _date(rawText),
      provider: _provider(rawText),
    );
  }

  // --------------------------------------------------------------
  // Amount
  // --------------------------------------------------------------

  static final _money = RegExp(r'(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})\b');

  static final _amountLabel = RegExp(
    r'\b(?:amount|total|sent|paid|payment|transferred)\b',
    caseSensitive: false,
  );

  static final _notAmount = RegExp(
    r'\b(?:balance|fee|charge|discount)\b',
    caseSensitive: false,
  );

  static final _currencyMark = RegExp(r'₱|php|\bp\s?\d', caseSensitive: false);

  static int? _cents(RegExpMatch m) {
    return int.parse(m.group(1)!.replaceAll(',', '')) * 100 +
        int.parse(m.group(2)!);
  }

  static int? _amount(List<String> lines) {
    // 1) A labelled line, or the value on the immediately following line.
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (_notAmount.hasMatch(line) || !_amountLabel.hasMatch(line)) {
        continue;
      }

      final same = _money.firstMatch(line);
      if (same != null) return _cents(same);

      if (i + 1 < lines.length && !_notAmount.hasMatch(lines[i + 1])) {
        final next = _money.firstMatch(lines[i + 1]);
        if (next != null) return _cents(next);
      }
    }

    // 2) Otherwise the first money value carrying a currency mark.
    for (final line in lines) {
      if (_notAmount.hasMatch(line) || !_currencyMark.hasMatch(line)) {
        continue;
      }

      final m = _money.firstMatch(line);
      if (m != null) return _cents(m);
    }

    return null;
  }

  // --------------------------------------------------------------
  // Reference number
  // --------------------------------------------------------------

  /// Highest-priority labels. Deliberately do not treat a generic
  /// "Transaction" label as a reference because many receipts separately
  /// display "Transaction ID" and "Trace ID".
  static final _strongReferenceLabel = RegExp(
    r'\b(?:'
    r'reference\s*(?:no|number|num)?'
    r'|ref\s*(?:no|number|num)'
    r'|payment\s+reference'
    r'|transaction\s+reference'
    r'|confirmation\s*(?:no|number|code)?'
    r')\b\s*[\.:#-]?\s*',
    caseSensitive: false,
  );

  /// Also support providers that simply print "Reference:".
  static final _plainReferenceLabel = RegExp(
    r'\breference\b\s*[\.:#-]?\s*',
    caseSensitive: false,
  );

  /// Fields that should not be used as primary reference sources.
  static final _referenceExcludedLabel = RegExp(
    r'\b(?:'
    r'trace\s*(?:id|no|number|#)?'
    r'|transaction\s*(?:id|no|number|#)'
    r'|account\s*(?:no|number|#)'
    r'|mobile(?:\s*(?:no|number))?'
    r'|phone(?:\s*(?:no|number))?'
    r'|otp'
    r'|pin'
    r')\b',
    caseSensitive: false,
  );

  /// A reference token with optional separators inside it.
  ///
  /// Supports values such as:
  ///   IT0260924071403016
  ///   REF-2026-09-24-00125
  ///   G-XC12345678
  ///   ABC123456789
  static final _referenceToken = RegExp(
    r'(?<![A-Za-z0-9])'
    r'[A-Za-z0-9]+(?:[._/-][A-Za-z0-9]+)*'
    r'(?![A-Za-z0-9])',
  );

  /// Numeric references may be split by OCR spaces, e.g. 1234 567 890123.
  static final _spacedNumericReference = RegExp(
    r'(?<!\d)\d(?:\s?\d){7,24}(?!\d)',
  );

  static final _dateLike = RegExp(r'^\d{1,4}[./-]\d{1,2}[./-]\d{1,4}$');

  static final _timeLike = RegExp(r'^\d{1,2}:\d{2}(?::\d{2})?$');

  static String? _reference(List<String> lines) {
    final candidates = <_ReferenceCandidate>[];

    // ------------------------------------------------------------
    // 1) Prefer explicitly labelled Reference fields.
    // ------------------------------------------------------------
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      final strong = _strongReferenceLabel.firstMatch(line);
      final plain = strong == null
          ? _plainReferenceLabel.firstMatch(line)
          : null;
      final label = strong ?? plain;

      if (label == null) continue;

      final labelScore = strong != null ? 100 : 88;
      final remainder = line.substring(label.end).trim();

      // Same-line value is the strongest layout.
      if (remainder.isNotEmpty) {
        _collectReferenceCandidates(
          candidates,
          _beforeExcludedField(remainder),
          scoreBase: labelScore + 40,
          fallbackMode: false,
        );
      }

      // Label-only line -> value normally appears immediately below it.
      if (i + 1 < lines.length) {
        final nextLine = lines[i + 1];
        if (!_referenceExcludedLabel.hasMatch(nextLine)) {
          _collectReferenceCandidates(
            candidates,
            nextLine,
            scoreBase: labelScore + 32,
            fallbackMode: false,
          );
        }
      }

      // Weaker fallback for OCR layouts with a decorative/intervening line.
      if (i + 2 < lines.length) {
        final nearLine = lines[i + 2];
        if (!_referenceExcludedLabel.hasMatch(nearLine)) {
          _collectReferenceCandidates(
            candidates,
            nearLine,
            scoreBase: labelScore + 18,
            fallbackMode: false,
          );
        }
      }
    }

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.score.compareTo(a.score));
      return candidates.first.normalized;
    }

    // ------------------------------------------------------------
    // 2) Conservative fallback when no reference label was recognized.
    // ------------------------------------------------------------
    for (final line in lines) {
      if (_referenceExcludedLabel.hasMatch(line)) continue;

      _collectReferenceCandidates(
        candidates,
        line,
        scoreBase: 0,
        fallbackMode: true,
      );
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => b.score.compareTo(a.score));

    // Weak fallback candidates are intentionally rejected.
    final best = candidates.first;
    if (best.score < 18) return null;

    return best.normalized;
  }

  static String _beforeExcludedField(String text) {
    // OCR can flatten several receipt fields onto one line:
    // "Reference No. IT... Trace ID 000016"
    // Stop before the unrelated field so the reference candidate cannot swallow
    // the remainder of the receipt line.
    final match = _referenceExcludedLabel.firstMatch(text);
    if (match == null) return text.trim();
    return text.substring(0, match.start).trim();
  }

  static void _collectReferenceCandidates(
    List<_ReferenceCandidate> output,
    String text, {
    required int scoreBase,
    required bool fallbackMode,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_referenceExcludedLabel.hasMatch(trimmed)) return;

    // ------------------------------------------------------------
    // A) Normal alphanumeric/separated tokens.
    // ------------------------------------------------------------
    for (final match in _referenceToken.allMatches(trimmed)) {
      final raw = match.group(0)!;
      final normalized = PaymentProofInput.normalizeReference(raw);

      if (!_isValidReferenceCandidate(normalized)) continue;

      var score = scoreBase + _shapeScore(normalized!);

      if (_dateLike.hasMatch(raw) || _timeLike.hasMatch(raw)) {
        score -= 80;
      }

      output.add(_ReferenceCandidate(normalized: normalized, score: score));
    }

    // ------------------------------------------------------------
    // B) Numeric reference with OCR-introduced spaces.
    // ------------------------------------------------------------
    for (final match in _spacedNumericReference.allMatches(trimmed)) {
      final raw = match.group(0)!;
      final normalized = PaymentProofInput.normalizeReference(raw);

      if (!_isValidReferenceCandidate(normalized)) continue;

      var score = scoreBase + 6 + _shapeScore(normalized!);

      if (_dateLike.hasMatch(raw) || _timeLike.hasMatch(raw)) {
        score -= 80;
      }

      output.add(_ReferenceCandidate(normalized: normalized, score: score));
    }

    // ------------------------------------------------------------
    // C) OCR can insert spaces inside an alphanumeric reference:
    //    IT 0260924071403016
    //    IT026 0924071403016
    //
    // Only do this on a short value-like line, so normal receipt prose is not
    // merged into one giant candidate.
    // ------------------------------------------------------------
    if (_looksLikeSingleReferenceValueLine(trimmed)) {
      final parts = RegExp(
        r'[A-Za-z0-9]+',
      ).allMatches(trimmed).map((m) => m.group(0)!).toList();

      if (parts.length >= 2 && parts.length <= 5) {
        final joined = PaymentProofInput.normalizeReference(parts.join());

        if (_isValidReferenceCandidate(joined)) {
          final score = scoreBase + 20 + _shapeScore(joined!);
          output.add(_ReferenceCandidate(normalized: joined, score: score));
        }
      }
    }

    // ------------------------------------------------------------
    // D) No-label fallback for a long compact numeric reference.
    // ------------------------------------------------------------
    if (fallbackMode && trimmed.length <= 48) {
      final matches = RegExp(r'\b\d{8,25}\b').allMatches(trimmed);

      for (final match in matches) {
        final raw = match.group(0)!;
        final normalized = PaymentProofInput.normalizeReference(raw);

        if (!_isValidReferenceCandidate(normalized)) continue;

        var score = 12 + _shapeScore(normalized!);

        if (_dateLike.hasMatch(raw) || _timeLike.hasMatch(raw)) {
          score -= 80;
        }

        output.add(_ReferenceCandidate(normalized: normalized, score: score));
      }
    }
  }

  static bool _isValidReferenceCandidate(String? normalized) {
    if (normalized == null) return false;

    if (normalized.length < 6 || normalized.length > 40) return false;

    // Keep ordinary words such as "Reference" out of the result.
    if (!RegExp(r'\d').hasMatch(normalized)) return false;

    return RegExp(r'[A-Z0-9]').hasMatch(normalized);
  }

  static int _shapeScore(String normalized) {
    final hasLetter = RegExp(r'[A-Z]').hasMatch(normalized);
    final digitCount = RegExp(r'\d').allMatches(normalized).length;

    var score = 0;

    // Explicitly alphanumeric references are more distinctive than short
    // numeric IDs such as Trace ID 000016.
    if (hasLetter && digitCount > 0) score += 20;

    if (normalized.length >= 10) score += 8;
    if (digitCount >= 8) score += 6;

    // Short purely-numeric values are suspicious in fallback mode because
    // receipts commonly display Trace IDs and other short IDs.
    if (!hasLetter && normalized.length <= 7) score -= 18;

    return score;
  }

  static bool _looksLikeSingleReferenceValueLine(String text) {
    // Accept compact values and OCR-spaced values, but reject ordinary prose.
    final valueLike = RegExp(r'^[A-Za-z0-9][A-Za-z0-9\s._/-]{5,40}$');

    if (!valueLike.hasMatch(text)) return false;

    final normalized = PaymentProofInput.normalizeReference(text);
    if (!_isValidReferenceCandidate(normalized)) return false;

    final alphaGroups = RegExp(r'[A-Za-z]+').allMatches(text).length;
    final digitCount = RegExp(r'\d').allMatches(text).length;

    if (digitCount < 3) return false;
    if (alphaGroups > 3) return false;

    return true;
  }

  // --------------------------------------------------------------
  // Date / time
  // --------------------------------------------------------------

  static const _monthAlt = 'jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec';

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  // Optional " 3:45 PM" / ", 15:45" / " at 3:45 pm".
  static const _time =
      r'(?:[,\s]+(?:at\s+)?(\d{1,2}):(\d{2})(?::\d{2})?\s*([ap]\.?m\.?)?)?';

  // Oct 12, 2025 3:45 PM
  static final _mdy = RegExp(
    r'\b(' + _monthAlt + r')[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})' + _time,
    caseSensitive: false,
  );

  // 12 Oct 2025 3:45 PM
  static final _dmy = RegExp(
    r'\b(\d{1,2})\s+(' + _monthAlt + r')[a-z]*\.?\,?\s+(\d{4})' + _time,
    caseSensitive: false,
  );

  // 2025-10-12 15:45
  static final _iso = RegExp(
    r'\b(\d{4})-(\d{2})-(\d{2})(?:[T\s]+(\d{1,2}):(\d{2}))?',
  );

  static DateTime? _date(String text) {
    var m = _mdy.firstMatch(text);

    if (m != null) {
      return _make(
        int.parse(m.group(3)!),
        _months[m.group(1)!.toLowerCase()]!,
        int.parse(m.group(2)!),
        m.group(4),
        m.group(5),
        m.group(6),
      );
    }

    m = _dmy.firstMatch(text);

    if (m != null) {
      return _make(
        int.parse(m.group(3)!),
        _months[m.group(2)!.toLowerCase()]!,
        int.parse(m.group(1)!),
        m.group(4),
        m.group(5),
        m.group(6),
      );
    }

    m = _iso.firstMatch(text);

    if (m != null) {
      return _make(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        m.group(4),
        m.group(5),
        null,
      );
    }

    // Numeric 10/12/2025 is deliberately NOT parsed: MM/DD vs DD/MM is
    // ambiguous and a wrong date is worse than a blank one.
    return null;
  }

  static DateTime? _make(
    int y,
    int mo,
    int d,
    String? hh,
    String? mm,
    String? ampm,
  ) {
    var hour = hh == null ? 0 : int.parse(hh);
    final minute = mm == null ? 0 : int.parse(mm);

    if (ampm != null) {
      final pm = ampm.toLowerCase().startsWith('p');

      if (pm && hour < 12) hour += 12;
      if (!pm && hour == 12) hour = 0;
    }

    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    if (hour > 23 || minute > 59) return null;

    final result = DateTime(y, mo, d, hour, minute);

    // DateTime silently rolls over (Feb 31 -> Mar 3); reject that.
    if (result.month != mo || result.day != d) return null;

    return result;
  }

  // --------------------------------------------------------------
  // Provider (only used as a label)
  // --------------------------------------------------------------

  static String? _provider(String text) {
    final t = text.toLowerCase();

    if (t.contains('gcash')) return 'GCash';
    if (t.contains('gotyme') || t.contains('go tyme')) return 'GoTyme';
    if (t.contains('maya')) return 'Maya';
    if (t.contains('instapay')) return 'InstaPay';
    if (t.contains('pesonet')) return 'PESONet';

    return null;
  }
}

class _ReferenceCandidate {
  final String normalized;
  final int score;

  const _ReferenceCandidate({required this.normalized, required this.score});
}
