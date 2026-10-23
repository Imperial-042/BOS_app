import 'package:flutter/material.dart';

import '../../domain/purchase_line_pricing.dart';
import '../../domain/purchase_unit_options.dart';

Future<PurchaseLinePricingResult?> showPurchaseLineEditorDialog(
  BuildContext context, {
  required String itemName,
  required String quantityLabel,
  required String unit,
  required double stockUnitsPerUnit,
  required List<PurchaseUnitOption> unitOptions,
  required double quantity,
  required bool isWeighted,
  required int unitPriceCents,
  required int grossTotalCents,
  required int finalTotalCents,
  required String discountType,
  required double discountValue,
  required int originalUnitPriceCents,
  required double originalStockUnitsPerUnit,
}) {
  return showDialog<PurchaseLinePricingResult>(
    context: context,
    builder: (_) => _PurchaseLineEditorDialog(
      itemName: itemName,
      quantityLabel: quantityLabel,
      unit: unit,
      stockUnitsPerUnit: stockUnitsPerUnit,
      unitOptions: unitOptions,
      quantity: quantity,
      isWeighted: isWeighted,
      unitPriceCents: unitPriceCents,
      grossTotalCents: grossTotalCents,
      finalTotalCents: finalTotalCents,
      discountType: discountType,
      discountValue: discountValue,
      originalUnitPriceCents: originalUnitPriceCents,
      originalStockUnitsPerUnit: originalStockUnitsPerUnit,
    ),
  );
}

class _PurchaseLineEditorDialog extends StatefulWidget {
  final String itemName;
  final String quantityLabel;
  final String unit;
  final double stockUnitsPerUnit;
  final List<PurchaseUnitOption> unitOptions;
  final double quantity;
  final bool isWeighted;
  final int unitPriceCents;
  final int grossTotalCents;
  final int finalTotalCents;
  final String discountType;
  final double discountValue;

  /// The original stored unit price (cents) and its conversion factor.
  /// Every unit switch re-derives the price from this anchor so switching
  /// back to the original unit restores the exact original price.
  final int originalUnitPriceCents;
  final double originalStockUnitsPerUnit;

  const _PurchaseLineEditorDialog({
    required this.itemName,
    required this.quantityLabel,
    required this.unit,
    required this.stockUnitsPerUnit,
    required this.unitOptions,
    required this.quantity,
    required this.isWeighted,
    required this.unitPriceCents,
    required this.grossTotalCents,
    required this.finalTotalCents,
    required this.discountType,
    required this.discountValue,
    required this.originalUnitPriceCents,
    required this.originalStockUnitsPerUnit,
  });

  @override
  State<_PurchaseLineEditorDialog> createState() =>
      _PurchaseLineEditorDialogState();
}

class _PurchaseLineEditorDialogState extends State<_PurchaseLineEditorDialog> {
  PurchaseUnitOption? _optionFor(String name) {
    for (final option in widget.unitOptions) {
      if (option.name.toLowerCase() == name.toLowerCase()) return option;
    }
    return null;
  }

  late String _selectedUnit = _optionFor(widget.unit)?.name ?? widget.unit;
  late double _stockUnitsPerUnit =
      _optionFor(widget.unit)?.stockUnitsPerUnit ?? widget.stockUnitsPerUnit;

  static bool _isValidFactor(double factor) => factor.isFinite && factor > 0;

  // Conversion anchor: the original stored price and the factor of the unit
  // that price is for. Unit switches convert FROM this anchor, never from
  // an already converted/rounded display price. The anchor only moves when
  // the user manually types a new price.
  late int _anchorPriceCents = widget.originalUnitPriceCents >= 0
      ? widget.originalUnitPriceCents
      : widget.unitPriceCents;
  late double _anchorFactor = _isValidFactor(widget.originalStockUnitsPerUnit)
      ? widget.originalStockUnitsPerUnit
      : (_isValidFactor(_stockUnitsPerUnit) ? _stockUnitsPerUnit : 1.0);
  late final _quantityController = TextEditingController(
    text: _formatQuantity(widget.quantity),
  );
  late final _directTotalController = TextEditingController(
    text: (widget.finalTotalCents / 100).toStringAsFixed(2),
  );
  late final _unitPriceController = TextEditingController(
    text: (widget.unitPriceCents / 100).toStringAsFixed(2),
  );
  late final _discountController = TextEditingController(
    text: widget.discountType == PurchaseLinePricing.fixedDiscount
        ? (widget.discountValue / 100).toStringAsFixed(2)
        : widget.discountValue.toString(),
  );

  late bool _discountEnabled =
      widget.discountType != PurchaseLinePricing.noDiscount &&
      widget.discountValue > 0;
  late String _discountType =
      widget.discountType == PurchaseLinePricing.percentageDiscount
      ? PurchaseLinePricing.percentageDiscount
      : PurchaseLinePricing.fixedDiscount;
  String? _error;
  bool _totalEdited = false;

  static String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  @override
  void dispose() {
    _quantityController.dispose();
    _directTotalController.dispose();
    _unitPriceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  double? _parseNumber(String value) =>
      double.tryParse(value.replaceAll(',', '').trim());

  String _money(int cents) => '₱${(cents / 100).toStringAsFixed(2)}';

  /// Converts the anchor price to [toFactor]'s unit. Throws [ArgumentError]
  /// when the conversion data is missing or invalid.
  ConvertedUnitPrice _convertFromAnchor(double toFactor) {
    return PurchaseLinePricing.priceForUnit(
      originalPriceCents: _anchorPriceCents,
      originalStockUnitsPerUnit: _anchorFactor,
      selectedStockUnitsPerUnit: toFactor,
    );
  }

  /// Same as [_convertFromAnchor], but returns null instead of throwing.
  ConvertedUnitPrice? _tryConvertFromAnchor(double toFactor) {
    try {
      return _convertFromAnchor(toFactor);
    } on ArgumentError {
      return null;
    }
  }

  /// A manually typed unit price becomes the new conversion anchor.
  void _onUnitPriceEdited(String value) {
    final parsed = _parseNumber(value);
    if (parsed != null && parsed.isFinite && parsed >= 0) {
      _anchorPriceCents = (parsed * 100).round();
      _anchorFactor = _stockUnitsPerUnit;
    }
    setState(() => _error = null);
  }

  /// A manually typed line total becomes the new conversion anchor (stored
  /// per unit so unit switches still convert correctly).
  void _onDirectTotalEdited(String value) {
    _totalEdited = true;
    final parsed = _parseNumber(value);
    final quantity = _parseNumber(_quantityController.text) ?? widget.quantity;
    if (parsed != null && parsed.isFinite && parsed >= 0 && quantity > 0) {
      _anchorPriceCents = ((parsed * 100) / quantity).round();
      _anchorFactor = _stockUnitsPerUnit;
    }
    setState(() => _error = null);
  }

  void _onQuantityEdited(String _) {
    final quantity = _parseNumber(_quantityController.text);
    if (quantity != null && quantity > 0) {
      if (_totalEdited) {
        // The user fixed the total by hand, so keep it and re-derive the anchor.
        final total = _parseNumber(_directTotalController.text);
        if (total != null && total >= 0) {
          _anchorPriceCents = ((total * 100) / quantity).round();
          _anchorFactor = _stockUnitsPerUnit;
        }
      } else {
        // Otherwise the total follows the anchor price.
        final c = _tryConvertFromAnchor(_stockUnitsPerUnit);
        if (c == null) {
          setState(() => _error = 'Missing or invalid unit conversion factor');
          return;
        }
        _directTotalController.text =
            (((c.preciseUnitPriceCents * quantity).round()) / 100)
                .toStringAsFixed(2);
      }
    }
    setState(() => _error = null);
  }

  void _submit() {
    final quantity = _parseNumber(_quantityController.text);
    final expectedQuantity = widget.isWeighted
        ? quantity
        : quantity?.toInt().toDouble();
    if (expectedQuantity == null || expectedQuantity <= 0) {
      setState(
        () => _error = 'Enter a valid ${widget.quantityLabel.toLowerCase()}',
      );
      return;
    }

    if (!_discountEnabled) {
      final int totalCents;
      if (_totalEdited) {
        final totalPesos = _parseNumber(_directTotalController.text);
        if (totalPesos == null || totalPesos < 0) {
          setState(() => _error = 'Enter a valid total purchase price');
          return;
        }
        totalCents = (totalPesos * 100).round();
      } else {
        final c = _tryConvertFromAnchor(_stockUnitsPerUnit);
        if (c == null) {
          setState(() => _error = 'Missing or invalid unit conversion factor');
          return;
        }
        totalCents = (c.preciseUnitPriceCents * expectedQuantity).round();
      }
      Navigator.pop(
        context,
        PurchaseLinePricingResult(
          quantity: expectedQuantity,
          unitPriceCents: expectedQuantity > 0
              ? (totalCents / expectedQuantity).round()
              : 0,
          grossTotalCents: totalCents,
          discountType: PurchaseLinePricing.noDiscount,
          discountValue: 0,
          discountAmountCents: 0,
          finalTotalCents: totalCents,
          unitName: _selectedUnit,
          stockUnitsPerUnit: _stockUnitsPerUnit,
          originalUnitPriceCents: _anchorPriceCents,
          originalStockUnitsPerUnit: _anchorFactor,
        ),
      );
      return;
    }

    final unitPricePesos = _parseNumber(_unitPriceController.text);
    final discountInput = _parseNumber(_discountController.text);
    if (unitPricePesos == null || unitPricePesos < 0) {
      setState(() => _error = 'Enter a valid unit price');
      return;
    }
    if (discountInput == null || discountInput < 0) {
      setState(() => _error = 'Enter a valid discount');
      return;
    }
    if (_discountType == PurchaseLinePricing.percentageDiscount &&
        discountInput > 100) {
      setState(() => _error = 'Discount percentage must be between 0 and 100');
      return;
    }

    final unitPriceCents = (unitPricePesos * 100).round();
    final grossTotalCents = (expectedQuantity * unitPriceCents).round();
    final discountValue = _discountType == PurchaseLinePricing.fixedDiscount
        ? (discountInput * 100).roundToDouble()
        : discountInput;
    if (_discountType == PurchaseLinePricing.fixedDiscount &&
        discountValue > grossTotalCents) {
      setState(() => _error = 'Discount cannot exceed the gross amount');
      return;
    }
    final converted = _tryConvertFromAnchor(_stockUnitsPerUnit);
    if (converted == null) {
      setState(() => _error = 'Missing or invalid unit conversion factor');
      return;
    }
    final pricing = PurchaseLinePricing.calculate(
      quantity: expectedQuantity,
      unitPriceCents: unitPriceCents,
      discountType: _discountType,
      discountValue: discountValue,
      unitName: _selectedUnit,
      stockUnitsPerUnit: _stockUnitsPerUnit,
      preciseUnitPriceCents: converted.preciseUnitPriceCents,
      originalUnitPriceCents: _anchorPriceCents,
      originalStockUnitsPerUnit: _anchorFactor,
    );
    Navigator.pop(context, pricing);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quantity = _parseNumber(_quantityController.text) ?? widget.quantity;
    final showDiscount = _discountEnabled;
    final unitPricePesos = _parseNumber(_unitPriceController.text) ?? 0;
    final unitPriceCents = (unitPricePesos * 100).round();
    final discountInput = _parseNumber(_discountController.text) ?? 0;
    final discountValue = _discountType == PurchaseLinePricing.fixedDiscount
        ? (discountInput * 100).roundToDouble()
        : discountInput;
    final previewPreciseUnitPrice = _tryConvertFromAnchor(
      _stockUnitsPerUnit,
    )?.preciseUnitPriceCents;
    final pricing = showDiscount
        ? PurchaseLinePricing.calculate(
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            discountType: _discountType,
            discountValue: discountValue,
            unitName: _selectedUnit,
            stockUnitsPerUnit: _stockUnitsPerUnit,
            preciseUnitPriceCents: previewPreciseUnitPrice,
          )
        : null;
    final currentFinalTotalCents =
        pricing?.finalTotalCents ??
        ((_parseNumber(_directTotalController.text) ?? 0) * 100).round();
    final effectiveUnitCost = quantity > 0
        ? (currentFinalTotalCents / quantity).round()
        : 0;

    return AlertDialog(
      title: const Text('Update purchase line'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.itemName, style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              if (widget.unitOptions.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'Purchase unit'),
                  items: [
                    for (final option in widget.unitOptions)
                      DropdownMenuItem(
                        value: option.name,
                        child: Text(option.name),
                      ),
                  ],
                  onChanged: (unit) {
                    if (unit == null) return;
                    final option = widget.unitOptions.firstWhere(
                      (item) => item.name == unit,
                    );
                    final currentQty =
                        _parseNumber(_quantityController.text) ??
                        widget.quantity;

                    // Keep the same amount of stock: qty * oldFactor / newFactor.
                    final convertedQty =
                        currentQty *
                        _stockUnitsPerUnit /
                        option.stockUnitsPerUnit;
                    final isWhole =
                        (convertedQty - convertedQty.roundToDouble()).abs() <
                        1e-9;
                    // Counted lines can't hold fractions (_submit truncates with toInt()),
                    // so only convert when the result is whole or the line is weighted.
                    final nextQty = (widget.isWeighted || isWhole)
                        ? double.parse(convertedQty.toStringAsFixed(6))
                        : currentQty;

                    final converted = _tryConvertFromAnchor(
                      option.stockUnitsPerUnit,
                    );
                    if (converted == null) {
                      setState(
                        () => _error =
                            'Cannot convert ${widget.itemName} to ${option.name}: '
                            'missing or invalid conversion factor.',
                      );
                      return;
                    }

                    setState(() {
                      _selectedUnit = option.name;
                      _stockUnitsPerUnit = option.stockUnitsPerUnit;
                      _quantityController.text = _formatQuantity(nextQty);
                      _unitPriceController.text =
                          (converted.unitPriceCents / 100).toStringAsFixed(2);
                      _directTotalController.text =
                          (((converted.preciseUnitPriceCents * nextQty)
                                      .round()) /
                                  100)
                              .toStringAsFixed(2);
                      _totalEdited = false;
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _quantityController,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.isWeighted,
                ),
                onChanged: _onQuantityEdited,
                decoration: InputDecoration(
                  labelText: widget.quantityLabel,
                  suffixText: _selectedUnit.isEmpty ? null : _selectedUnit,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Total price')),
                  ButtonSegment(value: true, label: Text('Discount')),
                ],
                selected: {_discountEnabled},
                onSelectionChanged: (selection) => setState(() {
                  _discountEnabled = selection.first;
                  _error = null;
                  _totalEdited = false;
                  if (!_discountEnabled) {
                    final c = _tryConvertFromAnchor(_stockUnitsPerUnit);
                    if (c == null) {
                      _error = 'Missing or invalid unit conversion factor';
                    } else {
                      final q =
                          _parseNumber(_quantityController.text) ??
                          widget.quantity;
                      _directTotalController.text =
                          (((c.preciseUnitPriceCents * q).round()) / 100)
                              .toStringAsFixed(2);
                    }
                  }
                }),
              ),
              const SizedBox(height: 12),
              if (!_discountEnabled)
                TextField(
                  controller: _directTotalController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _onDirectTotalEdited,
                  decoration: const InputDecoration(
                    labelText: 'Total Purchase Price',
                    prefixText: '₱ ',
                  ),
                )
              else ...[
                TextField(
                  controller: _unitPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _onUnitPriceEdited,
                  decoration: const InputDecoration(
                    labelText: 'Unit Price',
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: PurchaseLinePricing.fixedDiscount,
                      label: Text('Fixed'),
                    ),
                    ButtonSegment(
                      value: PurchaseLinePricing.percentageDiscount,
                      label: Text('Percent'),
                    ),
                  ],
                  selected: {_discountType},
                  onSelectionChanged: (selection) => setState(() {
                    _discountType = selection.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText:
                        _discountType == PurchaseLinePricing.fixedDiscount
                        ? 'Discount Amount'
                        : 'Discount %',
                    prefixText:
                        _discountType == PurchaseLinePricing.fixedDiscount
                        ? '₱ '
                        : null,
                    suffixText:
                        _discountType == PurchaseLinePricing.percentageDiscount
                        ? '%'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                _SummaryRow(
                  label: 'Gross',
                  value: _money(pricing?.grossTotalCents ?? 0),
                ),
                _SummaryRow(
                  label: 'Discount',
                  value: '-${_money(pricing?.discountAmountCents ?? 0)}',
                ),
                const Divider(height: 20),
                _SummaryRow(
                  label: 'Final Total',
                  value: _money(pricing?.finalTotalCents ?? 0),
                  emphasize: true,
                ),
              ],
              const SizedBox(height: 10),
              _SummaryRow(
                label: 'Effective Unit Cost',
                value:
                    '${_money(effectiveUnitCost)}${_selectedUnit.isEmpty ? '' : ' / $_selectedUnit'}',
                emphasize: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save Changes')),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
