// lib/features/production/presentation/widgets/payment_proof_sheet.dart

//

// Snap/pick a payment screenshot -> on-device OCR -> editable review.

// Returns a PaymentProofInput, or null if the cashier backs out.

//

// Layout: header + scrollable form + a PINNED bottom bar holding the

// confirm button, so it is always reachable (never under the keyboard or

// the system navigation bar).

//

// Needs in pubspec.yaml:

//   google_mlkit_text_recognition, image_picker, path_provider, path

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bos_application/core/format/money.dart';
import 'package:flutter/material.dart';

import 'package:gal/gal.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:image_picker/image_picker.dart';

import 'package:intl/intl.dart';

import 'package:path/path.dart' as p;

import 'package:path_provider/path_provider.dart';

import '../../domain/payment_proof.dart';

String _peso(int cents) => formatPeso(cents);

Future<PaymentProofInput?> showPaymentProofSheet(
  BuildContext context, {

  required int expectedCents,

  required Future<bool> Function(String normalizedReference) isReferenceUsed,
  String? expectedProvider,
}) {
  return showModalBottomSheet<PaymentProofInput>(
    context: context,

    isScrollControlled: true,

    useSafeArea: true,

    showDragHandle: true,

    builder: (_) => _PaymentProofSheet(
      expectedCents: expectedCents,
      isReferenceUsed: isReferenceUsed,
      expectedProvider: expectedProvider,
    ),
  );
}

class _PaymentProofSheet extends StatefulWidget {
  final int expectedCents;

  final Future<bool> Function(String) isReferenceUsed;
  final String? expectedProvider;

  const _PaymentProofSheet({
    required this.expectedCents,
    required this.isReferenceUsed,
    this.expectedProvider,
  });

  @override
  State<_PaymentProofSheet> createState() => _PaymentProofSheetState();
}

class _PaymentProofSheetState extends State<_PaymentProofSheet> {
  final _refCtrl = TextEditingController();

  final _amountCtrl = TextEditingController();

  final _picker = ImagePicker();

  String? _photoPath;

  DateTime? _paidAt;

  String? _provider;

  bool _scanning = false;

  bool _submitting = false;

  bool _ackMismatch = false;
  bool _ackWarnings = false;

  String? _note;

  String? _error;

  @override
  void dispose() {
    _refCtrl.dispose();

    _amountCtrl.dispose();

    super.dispose();
  }

  int? get _amountCents {
    final v = double.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));

    if (v == null || v <= 0) return null;

    return (v * 100).round();
  }

  String? get _normalizedRef =>
      PaymentProofInput.normalizeReference(_refCtrl.text);

  bool get _mismatch =>
      _amountCents != null && _amountCents != widget.expectedCents;

  /// "5 hours", "3 days", "16 months"...
  String _ago(Duration d) {
    if (d.inDays >= 60) return '${(d.inDays / 30).floor()} months';
    if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
    if (d.inHours >= 1) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    return '${d.inMinutes} minutes';
  }

  String? get _dateWarning {
    final d = _paidAt;
    if (d == null) return null;
    final now = DateTime.now();
    final shown = DateFormat('MMM d, yyyy · h:mm a').format(d);
    if (d.isAfter(now.add(const Duration(minutes: 10)))) {
      return 'The payment date ($shown) is in the future.';
    }
    final age = now.difference(d);
    if (age > const Duration(hours: 3)) {
      return 'The screenshot shows $shown, which is ${_ago(age)} ago. '
          'It may be an old screenshot.';
    }
    return null;
  }

  String? get _providerWarning {
    final expected = widget.expectedProvider?.toLowerCase();
    final seen = _provider?.toLowerCase();
    if (expected == null || seen == null) return null;
    if (expected.contains(seen) || seen.contains(expected)) return null;
    return 'The screenshot looks like $_provider but you selected '
        '${widget.expectedProvider}.';
  }

  bool get _hasWarnings => _dateWarning != null || _providerWarning != null;

  /// Why the confirm button is disabled (null = ready).

  String? get _blocker {
    if (_scanning) return 'Reading the image...';

    if (_photoPath == null) return 'Take or pick a photo of the payment first.';

    if (_normalizedRef == null) return 'Enter the reference no.';

    if (_amountCents == null) return 'Enter the amount paid.';

    if (_mismatch && !_ackMismatch) {
      return 'Tick the box above to continue with a different amount.';
    }
    final paid = _paidAt;
    if (paid != null && DateTime.now().difference(paid).inDays >= 2) {
      return 'This payment is more than 2 days old. Ask the customer for a '
          'new payment proof.';
    }
    if (_hasWarnings && !_ackWarnings) {
      return 'Check the warning above and tick the box to continue.';
    }

    return null;
  }

  bool get _canConfirm => _blocker == null && !_submitting;

  /// Picked/camera files can live in a temp dir the OS clears. Keep a copy.

  Future<String> _persist(String sourcePath) async {
    final docs = await getApplicationDocumentsDirectory();

    final dir = Directory(p.join(docs.path, 'payment_proofs'));

    if (!await dir.exists()) await dir.create(recursive: true);

    final name =
        'proof_${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath)}';

    final saved = await File(sourcePath).copy(p.join(dir.path, name));

    return saved.path;
  }

  /// Saves a copy of a freshly taken photo to the phone's gallery.

  /// Never throws — a failed gallery save must not block the payment.

  Future<bool> _saveToGallery(String path) async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) return false;
      }

      await Gal.putImage(path);

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _scan(ImageSource source) async {
    final XFile? picked;

    try {
      // Preserve source resolution. Small leading letters such as "IT" are
      // easy to lose when a screenshot is downscaled before OCR.
      picked = await _picker.pickImage(source: source, imageQuality: 100);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open the ${source.name}: $e');
      }
      return;
    }

    if (picked == null) return;

    setState(() {
      _scanning = true;
      _error = null;
      _note = null;
    });

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final saved = await _persist(picked.path);

      // Only photos taken with the camera are added to the gallery. A
      // screenshot picked from the gallery is already there.
      String? galleryMsg;
      if (source == ImageSource.camera) {
        galleryMsg = await _saveToGallery(saved)
            ? 'Saved to your gallery.'
            : 'Couldn\'t save to your gallery (permission denied?).';
      }

      // PASS 1 — OCR the original image.
      final primary = await recognizer.processImage(
        InputImage.fromFilePath(saved),
      );

      var combinedOcrText = primary.text;
      var parsed = PaymentProofParser.parse(combinedOcrText);

      // PASS 2 — render a larger, contrast-enhanced OCR image when the first
      // pass did not produce a reference. This is particularly useful for
      // small leading letters such as "IT" in references.
      if (parsed.referenceNo == null) {
        try {
          final enlargedPath = await _createOcrVariant(
            saved,
            scale: 2.0,
            maxDimension: 4096,
            enhanceContrast: true,
          );

          try {
            final enlarged = await recognizer.processImage(
              InputImage.fromFilePath(enlargedPath),
            );
            combinedOcrText = '$combinedOcrText\n${enlarged.text}';
          } finally {
            await _safeDelete(enlargedPath);
          }

          parsed = PaymentProofParser.parse(combinedOcrText);
        } catch (_) {
          // Enhanced OCR is a best-effort fallback. Keep the original OCR
          // result if image processing is unavailable on this device.
        }
      }

      // PASS 3 — use the first OCR result's line geometry to isolate the
      // Reference label and the nearby value. This prevents Trace ID,
      // account number, amount, etc. from competing with the reference.
      if (parsed.referenceNo == null) {
        final referenceRegion = _findReferenceRegion(primary);

        if (referenceRegion != null) {
          try {
            final focusedPath = await _createOcrVariant(
              saved,
              crop: referenceRegion,
              scale: 3.0,
              maxDimension: 2600,
              enhanceContrast: true,
            );

            try {
              final focused = await recognizer.processImage(
                InputImage.fromFilePath(focusedPath),
              );
              combinedOcrText = '$combinedOcrText\n${focused.text}';
            } finally {
              await _safeDelete(focusedPath);
            }
          } catch (_) {
            // Focused OCR is also best-effort; never block a cashier from
            // reviewing the fields manually if it cannot be performed.
          }
        }
      }

      // Final parse across all OCR passes. The parser is responsible for
      // choosing the Reference No. field over Trace ID and other numeric fields.
      parsed = PaymentProofParser.parse(combinedOcrText);

      if (!mounted) return;

      setState(() {
        _photoPath = saved;
        _ackMismatch = false;
        _ackWarnings = false;
        _refCtrl.text = parsed.referenceNo ?? '';
        _amountCtrl.text = parsed.amountCents == null
            ? ''
            : (parsed.amountCents! / 100).toStringAsFixed(2);
        _paidAt = parsed.paidAt;
        _provider = parsed.provider;

        final missing = [
          if (parsed.referenceNo == null) 'reference no.',
          if (parsed.amountCents == null) 'amount',
          if (parsed.paidAt == null) 'date/time',
        ];

        final scanNote = missing.isEmpty
            ? 'Scan finished. Check each field against the photo.'
            : 'Couldn\'t read: ${missing.join(', ')}. Please fill in.';

        _note = galleryMsg == null ? scanNote : '$scanNote $galleryMsg';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Scan failed: $e');
      }
    } finally {
      await recognizer.close();
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  /// Finds the line containing a reference label and includes the immediately
  /// following value line (plus one weaker nearby line). The actual image is
  /// still cropped dynamically from OCR coordinates; no provider-specific
  /// screen coordinates are hard-coded.
  ui.Rect? _findReferenceRegion(RecognizedText recognized) {
    final label = RegExp(
      r'\b(?:reference|ref)\b|payment\s+reference|transaction\s+reference',
      caseSensitive: false,
    );

    final excluded = RegExp(
      r'\b(?:trace|transaction\s*(?:id|no|number)|account|mobile|phone|otp|pin)\b',
      caseSensitive: false,
    );

    for (final block in recognized.blocks) {
      for (var i = 0; i < block.lines.length; i++) {
        final line = block.lines[i];
        if (!label.hasMatch(line.text)) continue;

        var rect = line.boundingBox;

        if (i + 1 < block.lines.length &&
            !excluded.hasMatch(block.lines[i + 1].text)) {
          rect = rect.expandToInclude(block.lines[i + 1].boundingBox);
        }

        if (i + 2 < block.lines.length &&
            !excluded.hasMatch(block.lines[i + 2].text)) {
          rect = rect.expandToInclude(block.lines[i + 2].boundingBox);
        }

        // Padding is intentionally generous because OCR boxes can be slightly
        // tighter than the actual printed field.
        return rect.inflate(32);
      }
    }

    return null;
  }

  /// Creates a temporary PNG for enhanced OCR. The original payment proof is
  /// never modified. [crop] uses OCR coordinates when a focused reference pass
  /// is requested.
  Future<String> _createOcrVariant(
    String sourcePath, {
    ui.Rect? crop,
    required double scale,
    required int maxDimension,
    bool enhanceContrast = false,
  }) async {
    final sourceBytes = await File(sourcePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(sourceBytes);

    try {
      final frame = await codec.getNextFrame();
      final sourceImage = frame.image;

      try {
        final bounds = ui.Rect.fromLTWH(
          0,
          0,
          sourceImage.width.toDouble(),
          sourceImage.height.toDouble(),
        );

        final sourceRect = (crop ?? bounds).intersect(bounds);
        if (sourceRect.isEmpty) {
          throw StateError('OCR crop region is empty.');
        }

        var targetWidth = (sourceRect.width * scale).round();
        var targetHeight = (sourceRect.height * scale).round();

        final longest = targetWidth > targetHeight ? targetWidth : targetHeight;

        if (longest > maxDimension) {
          final factor = maxDimension / longest;
          targetWidth = (targetWidth * factor).round();
          targetHeight = (targetHeight * factor).round();
        }

        targetWidth = targetWidth.clamp(1, maxDimension).toInt();
        targetHeight = targetHeight.clamp(1, maxDimension).toInt();

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final destination = ui.Rect.fromLTWH(
          0,
          0,
          targetWidth.toDouble(),
          targetHeight.toDouble(),
        );

        final paint = ui.Paint()
          ..filterQuality = ui.FilterQuality.high
          ..isAntiAlias = true;

        if (enhanceContrast) {
          // Mild contrast boost. Keep the transformation
          // deliberately conservative so thin letters such as I and T are
          // not destroyed by aggressive thresholding.
          paint.colorFilter = const ui.ColorFilter.matrix(<double>[
            1.25,
            0.0,
            0.0,
            0.0,
            -31.875,
            1.25,
            0.0,
            0.0,
            0.0,
            -31.875,
            1.25,
            0.0,
            0.0,
            0.0,
            -31.875,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
          ]);
        }

        canvas.drawImageRect(sourceImage, sourceRect, destination, paint);

        final picture = recorder.endRecording();
        final output = await picture.toImage(targetWidth, targetHeight);

        try {
          final data = await output.toByteData(format: ui.ImageByteFormat.png);

          if (data == null) {
            throw StateError('Could not encode OCR image.');
          }

          final tempDir = await getTemporaryDirectory();
          final outputPath = p.join(
            tempDir.path,
            'payment_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
          );

          await File(outputPath).writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );

          return outputPath;
        } finally {
          output.dispose();
        }
      } finally {
        sourceImage.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<void> _safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Disposable OCR files must never block payment-proof scanning.
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();

    final initial = _paidAt ?? now;

    final date = await showDatePicker(
      context: context,

      initialDate: initial,

      firstDate: DateTime(now.year - 1),

      lastDate: now.add(const Duration(days: 1)),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,

      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return;

    setState(
      () => _paidAt = DateTime(
        date.year,

        date.month,

        date.day,

        time.hour,

        time.minute,
      ),
    );
  }

  Future<void> _confirm() async {
    FocusScope.of(context).unfocus();

    final ref = _normalizedRef!;

    setState(() {
      _submitting = true;

      _error = null;
    });

    try {
      if (await widget.isReferenceUsed(ref)) {
        if (mounted) {
          setState(
            () => _error =
                'Reference $ref was already used on a previous sale. '
                'The same payment can\'t be counted twice.',
          );
        }

        return;
      }

      if (!mounted) return;

      Navigator.pop(
        context,

        PaymentProofInput(
          referenceNo: ref,

          amountCents: _amountCents!,

          paidAt: _paidAt,

          provider: _provider,

          photoPath: _photoPath,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final scheme = theme.colorScheme;

    final amount = _amountCents;

    final blocker = _blocker;

    return Padding(
      // Lifts the whole sheet (including the pinned button) above the keyboard.

      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),

      child: Column(
        mainAxisSize: MainAxisSize.min,

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [
          // ---------------- Header (fixed) ----------------

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),

            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        'Payment proof',

                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      Text(
                        'Order total ${_peso(widget.expectedCents)}',

                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  tooltip: 'Cancel',

                  onPressed: () => Navigator.pop(context),

                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          // ---------------- Scrollable form ----------------
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,

              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,

                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _scanning
                              ? null
                              : () => _scan(ImageSource.camera),

                          icon: const Icon(Icons.photo_camera_outlined),

                          label: Text(_photoPath == null ? 'Camera' : 'Retake'),
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _scanning
                              ? null
                              : () => _scan(ImageSource.gallery),

                          icon: const Icon(Icons.photo_library_outlined),

                          label: const Text('Screenshot'),
                        ),
                      ),
                    ],
                  ),

                  if (_scanning) ...[
                    const SizedBox(height: 12),

                    const LinearProgressIndicator(),
                  ],

                  if (_photoPath != null) ...[
                    const SizedBox(height: 12),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        GestureDetector(
                          onTap: () => showDialog<void>(
                            context: context,

                            builder: (_) => Dialog(
                              child: InteractiveViewer(
                                child: Image.file(File(_photoPath!)),
                              ),
                            ),
                          ),

                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),

                            child: Image.file(
                              File(_photoPath!),

                              width: 64,

                              height: 84,

                              fit: BoxFit.cover,

                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 64,

                                height: 84,

                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Text(
                            '${_note ?? ''}\nTap the photo to enlarge it.',

                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,

                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: _refCtrl,

                      onChanged: (_) => setState(() => _error = null),

                      textCapitalization: TextCapitalization.characters,

                      textInputAction: TextInputAction.next,

                      decoration: const InputDecoration(
                        labelText: 'Reference no.',

                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: _amountCtrl,

                      onChanged: (_) => setState(() {
                        _ackMismatch = false;

                        _error = null;
                      }),

                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),

                      textInputAction: TextInputAction.done,

                      decoration: const InputDecoration(
                        labelText: 'Amount paid',

                        prefixText: '₱ ',

                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    InkWell(
                      onTap: _pickDateTime,

                      borderRadius: BorderRadius.circular(4),

                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date & time paid (optional)',

                          border: OutlineInputBorder(),

                          suffixIcon: Icon(Icons.edit_calendar_outlined),
                        ),

                        child: Text(
                          _paidAt == null
                              ? 'Not set'
                              : DateFormat(
                                  'MMM d, yyyy · h:mm a',
                                ).format(_paidAt!),
                        ),
                      ),
                    ),

                    if (_hasWarnings) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_dateWarning != null)
                              Text(
                                _dateWarning!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            if (_providerWarning != null)
                              Text(
                                _providerWarning!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _ackWarnings,
                              onChanged: (v) =>
                                  setState(() => _ackWarnings = v ?? false),
                              title: Text(
                                'I checked this. Continue anyway',
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_mismatch && amount != null) ...[
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),

                        decoration: BoxDecoration(
                          color: scheme.errorContainer,

                          borderRadius: BorderRadius.circular(12),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              amount < widget.expectedCents
                                  ? 'Underpaid by ${_peso(widget.expectedCents - amount)}'
                                  : 'Overpaid by ${_peso(amount - widget.expectedCents)}',

                              style: TextStyle(
                                color: scheme.onErrorContainer,

                                fontWeight: FontWeight.w800,
                              ),
                            ),

                            const SizedBox(height: 2),

                            Text(
                              'Paid ${_peso(amount)} vs order total '
                              '${_peso(widget.expectedCents)}.',

                              style: TextStyle(
                                color: scheme.onErrorContainer,

                                fontSize: 12,
                              ),
                            ),

                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,

                              dense: true,

                              controlAffinity: ListTileControlAffinity.leading,

                              value: _ackMismatch,

                              onChanged: (v) =>
                                  setState(() => _ackMismatch = v ?? false),

                              title: Text(
                                'The amount differs — continue anyway',

                                style: TextStyle(
                                  color: scheme.onErrorContainer,

                                  fontSize: 13,

                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // ---------------- Pinned bottom bar ----------------
          Material(
            color: scheme.surface,

            elevation: 6,

            shadowColor: scheme.shadow.withValues(alpha: 0.25),

            child: SafeArea(
              top: false,

              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),

                child: Column(
                  mainAxisSize: MainAxisSize.min,

                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),

                        child: Text(
                          _error!,

                          style: TextStyle(
                            color: scheme.error,

                            fontSize: 12,

                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else if (blocker != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),

                        child: Text(
                          blocker,

                          style: TextStyle(
                            color: scheme.onSurfaceVariant,

                            fontSize: 12,
                          ),
                        ),
                      ),

                    FilledButton.icon(
                      onPressed: _canConfirm ? _confirm : null,

                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),

                      icon: _submitting
                          ? const SizedBox(
                              width: 18,

                              height: 18,

                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),

                      label: Text(
                        _submitting ? 'Checking...' : 'Use this proof',

                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
