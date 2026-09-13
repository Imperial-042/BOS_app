// lib/features/supplies/presentation/widgets/purchase_entry_sheet.dart
//
// Replaces the old "Add Price" dialog in Supplies Price List. A
// purchase now captures: purchase unit (pack/sack/case/bottle...),
// how many base units are in one purchase unit (pack size), how
// many were bought, and the price per purchase unit. This is what
// lets Supplies Price List double as the raw-material input for
// the whole costing/recipe system — every purchase here updates
// stock AND recalculates weighted-average cost automatically.
//
// Drop this in alongside supplies_price_list_page.dart and call
// `showPurchaseEntrySheet(context, supply: mySupply)` wherever the
// old "Add Price" action used to live.

import 'package:bos_application/features/transactions/domain/costing_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

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
  late final _purchaseUnitController = TextEditingController(
    text: widget.supply.purchaseUnit ?? '',
  );
  late final _unitsPerPurchaseController = TextEditingController(
    text: widget.supply.unitsPerPurchase > 0
        ? _trim(widget.supply.unitsPerPurchase)
        : '',
  );
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _storeController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saving = false;
  String? _error;

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _purchaseUnitController.dispose();
    _unitsPerPurchaseController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _storeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  double get _previewTotalBaseUnits {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    final perPurchase = double.tryParse(_unitsPerPurchaseController.text) ?? 0;
    return qty * perPurchase;
  }

  double get _previewCostPerBaseUnit {
    final price = double.tryParse(_priceController.text) ?? 0;
    final baseUnits = _previewTotalBaseUnits;
    if (baseUnits <= 0) return 0;
    return (price * 100) / baseUnits; // price entered in pesos -> cents
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                      'Record Purchase — ${widget.supply.name}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'Base unit tracked: ${widget.supply.stockUnit} · Current stock: ${_trim(widget.supply.currentStock)} ${widget.supply.stockUnit}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              _SectionLabel('How you bought it'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _purchaseUnitController,
                      decoration: const InputDecoration(
                        labelText: 'Purchase unit',
                        hintText: 'e.g. pack, sack, case',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _unitsPerPurchaseController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '= how many ${widget.supply.stockUnit}?',
                        hintText: 'e.g. 100',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'e.g. "1 pack = 100 g" → purchase unit: pack, conversion: 100',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              _SectionLabel('This purchase'),
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
                        labelText: 'Quantity bought',
                        suffixText: _purchaseUnitController.text.isEmpty
                            ? null
                            : _purchaseUnitController.text,
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
                      decoration: const InputDecoration(
                        labelText: 'Price per unit',
                        prefixText: '₱ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_previewTotalBaseUnits > 0) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You\'ll receive: ${_trim(_previewTotalBaseUnits)} ${widget.supply.stockUnit}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                      if (_previewCostPerBaseUnit > 0)
                        Text(
                          '≈ ₱${(_previewCostPerBaseUnit / 100).toStringAsFixed(4)} per ${widget.supply.stockUnit} (this purchase)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              _SectionLabel('Where'),
              const SizedBox(height: 8),
              TextField(
                controller: _storeController,
                decoration: const InputDecoration(
                  labelText: 'Store / supplier',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
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

    if (_purchaseUnitController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a purchase unit (e.g. pack, sack).');
      return;
    }
    if (unitsPerPurchase == null || unitsPerPurchase <= 0) {
      setState(
        () => _error =
            'Enter how many ${widget.supply.stockUnit} are in one purchase unit.',
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
            purchaseUnit: _purchaseUnitController.text.trim(),
            storeName: _storeController.text.trim().isEmpty
                ? 'Unspecified'
                : _storeController.text.trim(),
            storeAddress: _addressController.text.trim().isEmpty
                ? null
                : _addressController.text.trim(),
            date: DateTime.now(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.primary,
      ),
    );
  }
}
