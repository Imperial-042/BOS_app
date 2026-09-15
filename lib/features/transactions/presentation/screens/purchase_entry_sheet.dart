// lib/features/supplies/presentation/widgets/purchase_entry_sheet.dart
//
// Replaces the old "Add Price" dialog in Supplies Price List. A
// purchase now captures: purchase unit (dropdown), how many base
// units are in one purchase unit (pack size), how many were bought,
// and the price per purchase unit. This is what lets Supplies Price
// List double as the raw-material input for the whole costing/
// recipe system — every purchase here updates stock AND recalculates
// weighted-average cost automatically.
//
// Redesigned for clarity: numbered steps, a dropdown instead of free
// text for the purchase unit, and a running plain-language summary
// ("You're buying 10 packs of 100 g each = 1,000 g total for ₱1,000")
// so the owner can sanity-check the math before saving.
//
// Drop this in alongside supplies_price_list_page.dart and call
// `showPurchaseEntrySheet(context, supply: mySupply)` wherever the
// old "Add Price" action used to live.

import 'package:bos_application/features/transactions/domain/costing_service.dart';
import 'package:bos_application/features/transactions/domain/unit_options.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;

final costingServiceProvider = Provider<CostingService>((ref) {
  return CostingService(ref.watch(databaseProvider));
});

Future<void> showPurchaseEntrySheet(
  BuildContext context, {
  required Supply supply,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PurchaseEntrySheet(supply: supply),
  );
}

class PurchaseEntrySheet extends ConsumerStatefulWidget {
  final Supply supply;
  const PurchaseEntrySheet({super.key, required this.supply});

  @override
  ConsumerState<PurchaseEntrySheet> createState() => _PurchaseEntrySheetState();
}

class _PurchaseEntrySheetState extends ConsumerState<PurchaseEntrySheet> {
  String?
  _purchaseUnit; // null while unset; kCustomUnitOption triggers free text
  final _customUnitController = TextEditingController();
  late final _unitsPerPurchaseController = TextEditingController(
    text: widget.supply.unitsPerPurchase > 0
        ? _trim(widget.supply.unitsPerPurchase)
        : '',
  );
  final _quantityController = TextEditingController(text: '1');
  late final _priceController = TextEditingController(
    text: widget.supply.currentPrice > 0
        ? (widget.supply.currentPrice / 100).toStringAsFixed(2)
        : '',
  );
  final _storeController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.supply.purchaseUnit;
    if (existing != null && existing.isNotEmpty) {
      if (kPurchaseUnitOptions.contains(existing)) {
        _purchaseUnit = existing;
      } else {
        _purchaseUnit = kCustomUnitOption;
        _customUnitController.text = existing;
      }
    }
    _prefillLastQuantity();
  }

  // The Supplies row only keeps the latest price/pack size, not the
  // latest quantity bought — pull that from the most recent price
  // history entry so re-stocking the usual amount doesn't require
  // retyping it every time.
  Future<void> _prefillLastQuantity() async {
    final db = ref.read(databaseProvider);
    final latest = await (db.select(db.supplyPriceHistory)
          ..where((h) => h.supplyId.equals(widget.supply.id))
          ..orderBy([
            (h) => OrderingTerm(
              expression: h.recordedDate,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();

    if (latest != null && mounted) {
      setState(() => _quantityController.text = _trim(latest.purchaseQuantity));
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _customUnitController.dispose();
    _unitsPerPurchaseController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _storeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String get _effectivePurchaseUnit => _purchaseUnit == kCustomUnitOption
      ? _customUnitController.text.trim()
      : (_purchaseUnit ?? '');

  double get _previewTotalBaseUnits {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    final perPurchase = double.tryParse(_unitsPerPurchaseController.text) ?? 0;
    return qty * perPurchase;
  }

  double get _previewTotalCost {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0;
    return qty * price;
  }

  double get _previewCostPerBaseUnit {
    final baseUnits = _previewTotalBaseUnits;
    if (baseUnits <= 0) return 0;
    return (_previewTotalCost * 100) / baseUnits; // pesos -> cents
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final qty = double.tryParse(_quantityController.text);
    final perPurchase = double.tryParse(_unitsPerPurchaseController.text);
    final price = double.tryParse(_priceController.text);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Record Purchase',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${widget.supply.name} · tracked in ${widget.supply.stockUnit} · currently ${_trim(widget.supply.currentStock)} ${widget.supply.stockUnit} in stock',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              _StepLabel(number: 1, text: 'What did you buy it in?'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _purchaseUnit,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Purchase unit',
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
                items: [
                  ...kPurchaseUnitOptions.map(
                    (u) => DropdownMenuItem(value: u, child: Text(u)),
                  ),
                  DropdownMenuItem(
                    value: kCustomUnitOption,
                    child: Text(kCustomUnitOption),
                  ),
                ],
                onChanged: (v) => setState(() => _purchaseUnit = v),
              ),
              if (_purchaseUnit == kCustomUnitOption) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customUnitController,
                  decoration: const InputDecoration(
                    labelText: 'Type your own purchase unit',
                    hintText: 'e.g. drum, cylinder',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 18),

              _StepLabel(
                number: 2,
                text:
                    'How much is in one ${_effectivePurchaseUnit.isEmpty ? "purchase unit" : _effectivePurchaseUnit}?',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _unitsPerPurchaseController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Contains',
                  suffixText: widget.supply.stockUnit,
                  hintText: 'e.g. 100',
                ),
                onChanged: (_) => setState(() {}),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _effectivePurchaseUnit.isEmpty ||
                          perPurchase == null ||
                          perPurchase <= 0
                      ? 'Example: "1 pack = 100 g" → contains: 100'
                      : '1 $_effectivePurchaseUnit = ${_trim(perPurchase)} ${widget.supply.stockUnit}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              _StepLabel(
                number: 3,
                text: 'How many did you buy, and for how much?',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        suffixText: _effectivePurchaseUnit.isEmpty
                            ? null
                            : _effectivePurchaseUnit,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'Price per ${_effectivePurchaseUnit.isEmpty ? "unit" : _effectivePurchaseUnit}',
                        prefixText: '₱ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (_previewTotalBaseUnits > 0 &&
                  price != null &&
                  price >= 0) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.summarize_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Summary',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_trim(qty ?? 0)} $_effectivePurchaseUnit${(qty ?? 0) == 1 ? '' : 's'} × ${_trim(perPurchase ?? 0)} ${widget.supply.stockUnit} '
                        '= ${_trim(_previewTotalBaseUnits)} ${widget.supply.stockUnit} received',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total cost: ₱${_previewTotalCost.toStringAsFixed(2)}  ·  '
                        '≈ ₱${(_previewCostPerBaseUnit / 100).toStringAsFixed(4)} per ${widget.supply.stockUnit}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'New stock after this purchase: ${_trim(widget.supply.currentStock + _previewTotalBaseUnits)} ${widget.supply.stockUnit}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              _StepLabel(number: 4, text: 'Where did you buy it?'),
              const SizedBox(height: 8),
              TextField(
                controller: _storeController,
                decoration: const InputDecoration(
                  labelText: 'Store / supplier',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Purchase',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final unitsPerPurchase = double.tryParse(_unitsPerPurchaseController.text);
    final quantity = double.tryParse(_quantityController.text);
    final price = double.tryParse(_priceController.text);
    final purchaseUnit = _effectivePurchaseUnit;

    if (purchaseUnit.isEmpty) {
      setState(() => _error = 'Choose (or type) a purchase unit.');
      return;
    }
    if (unitsPerPurchase == null || unitsPerPurchase <= 0) {
      setState(
        () => _error =
            'Enter how many ${widget.supply.stockUnit} are in one $purchaseUnit.',
      );
      return;
    }
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter a valid quantity bought.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(costingServiceProvider)
          .recordPurchase(
            supplyId: widget.supply.id,
            pricePerPurchaseUnitCents: (price * 100).round(),
            purchaseQuantity: quantity,
            unitsPerPurchase: unitsPerPurchase,
            purchaseUnit: purchaseUnit,
            storeName: _storeController.text.trim().isEmpty
                ? 'Unspecified'
                : _storeController.text.trim(),
            storeAddress: _addressController.text.trim().isEmpty
                ? null
                : _addressController.text.trim(),
            date: DateTime.now(),
          );
      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StepLabel extends StatelessWidget {
  final int number;
  final String text;
  const _StepLabel({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
