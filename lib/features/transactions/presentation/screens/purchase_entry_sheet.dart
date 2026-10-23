// lib/features/supplies/presentation/widgets/purchase_entry_sheet.dart
// (or lib/features/transactions/presentation/screens/purchase_entry_sheet.dart)

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/transactions/domain/production_service.dart'
    show UnitConverter;
import 'package:bos_application/features/transactions/domain/supply_catalog_service.dart';
import 'package:bos_application/features/transactions/domain/unit_options.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider;

const List<String> kWeightPurchaseUnitOptions = ['g', 'kg'];

/// Returned when a purchase record is saved so callers (e.g. the cart)
/// can update in-memory state immediately without waiting on streams.
class PurchaseEntryResult {
  final String supplyId;
  final int priceCents;
  final String name;
  final String? brand;
  final String purchaseUnit;
  final double unitsPerPurchase;
  final bool isSoldByWeight; // new

  const PurchaseEntryResult({
    required this.supplyId,
    required this.priceCents,
    required this.name,
    required this.brand,
    required this.purchaseUnit,
    required this.unitsPerPurchase,
    required this.isSoldByWeight, // new
  });
}

Future<PurchaseEntryResult?> showPurchaseEntrySheet(
  BuildContext context, {
  required Supply supply,
}) {
  return showModalBottomSheet<PurchaseEntryResult>(
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

class _AlternateUnitFields {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController unitsPerStockController = TextEditingController();

  void dispose() {
    nameController.dispose();
    unitsPerStockController.dispose();
  }
}

class _PurchaseEntrySheetState extends ConsumerState<PurchaseEntrySheet> {
  String? _purchaseUnit;
  String? _categoryId;
  List<ProductCategory> _categories = <ProductCategory>[];

  bool _saving = false;
  bool _loadingRecord = true;
  bool _loadingCategories = true;
  bool _hasPurchaseRecord = false;
  bool _loadingAlternateUnits = true;
  String? _error;
  final List<_AlternateUnitFields> _alternateUnits = [];

  final _customUnitController = TextEditingController();

  late final _nameController = TextEditingController(text: widget.supply.name);

  late final _brandController = TextEditingController(
    text: widget.supply.brand ?? '',
  );

  late final _unitsPerPurchaseController = TextEditingController(
    text: widget.supply.unitsPerPurchase > 0
        ? _trim(widget.supply.unitsPerPurchase)
        : '',
  );

  late final _priceController = TextEditingController(
    text: widget.supply.currentPrice > 0
        ? (widget.supply.currentPrice / 100).toStringAsFixed(2)
        : '',
  );

  late final _storeController = TextEditingController(
    text: widget.supply.lastStoreName ?? '',
  );

  late final _addressController = TextEditingController(
    text: widget.supply.lastStoreAddress ?? '',
  );

  late final _skuController = TextEditingController(
    text: widget.supply.sku ?? '',
  );

  late final _barcodeController = TextEditingController(
    text: widget.supply.barcode ?? '',
  );

  // These three fields are displayed in the user's purchase unit
  // (pack/sack/case/etc.), but are stored in the supply's base stock unit.
  late final _currentStockController = TextEditingController(
    text: _purchaseStockText(
      widget.supply.currentStock,
      widget.supply.unitsPerPurchase > 0 ? widget.supply.unitsPerPurchase : 1.0,
    ),
  );

  late final _minimumStockController = TextEditingController(
    text: widget.supply.minimumStock > 0
        ? _purchaseStockText(
            widget.supply.minimumStock,
            widget.supply.unitsPerPurchase > 0
                ? widget.supply.unitsPerPurchase
                : 1.0,
          )
        : '',
  );

  late final _maximumStockController = TextEditingController(
    text: widget.supply.maximumStock > 0
        ? _purchaseStockText(
            widget.supply.maximumStock,
            widget.supply.unitsPerPurchase > 0
                ? widget.supply.unitsPerPurchase
                : 1.0,
          )
        : '',
  );

  late double _stockDisplayUnitsPerPurchase;

  bool get _isWeightBased =>
      _purchaseUnit != null &&
      kWeightPurchaseUnitOptions.contains(_purchaseUnit);

  /// Weight units convert deterministically (1 kg is always 1000 g), so
  /// once the user picks one, we compute the "Contains" ratio for them
  /// instead of asking them to type it.
  void _autoFillWeightConversion() {
    if (!_isWeightBased) return;
    if (!UnitConverter.areCompatible(_purchaseUnit!, widget.supply.stockUnit)) {
      return; // incompatible dimension — leave field for the error banner to explain
    }
    final converted = UnitConverter.convert(
      1,
      _purchaseUnit!,
      widget.supply.stockUnit,
    );
    _unitsPerPurchaseController.text = converted == converted.roundToDouble()
        ? converted.toInt().toString()
        : converted.toString();
  }

  @override
  void initState() {
    super.initState();

    _stockDisplayUnitsPerPurchase = widget.supply.unitsPerPurchase > 0
        ? widget.supply.unitsPerPurchase
        : 1.0;

    final existingPurchaseUnit = widget.supply.purchaseUnit;

    if (existingPurchaseUnit != null &&
        existingPurchaseUnit.trim().isNotEmpty) {
      if (kPurchaseUnitOptions.contains(existingPurchaseUnit) ||
          kWeightPurchaseUnitOptions.contains(existingPurchaseUnit)) {
        _purchaseUnit = existingPurchaseUnit;
      } else {
        _purchaseUnit = kCustomUnitOption;
        _customUnitController.text = existingPurchaseUnit;
      }
    }

    _loadPurchaseRecordState();
    _loadCategories();
    _loadAlternateUnits();
  }

  @override
  void dispose() {
    _customUnitController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _unitsPerPurchaseController.dispose();
    _priceController.dispose();
    _storeController.dispose();
    _addressController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _currentStockController.dispose();
    _minimumStockController.dispose();
    _maximumStockController.dispose();
    for (final fields in _alternateUnits) {
      fields.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAlternateUnits() async {
    try {
      final rows =
          await (ref
                  .read(databaseProvider)
                  .select(ref.read(databaseProvider).supplyUnitConversions)
                ..where((row) => row.supplyId.equals(widget.supply.id)))
              .get();
      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          final fields = _AlternateUnitFields()
            ..nameController.text = row.unitName
            ..unitsPerStockController.text = _trim(row.unitsPerStockUnit);
          _alternateUnits.add(fields);
        }
        _loadingAlternateUnits = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingAlternateUnits = false;
        _error = 'Could not load alternate units: $error';
      });
    }
  }

  void _addAlternateUnit() {
    setState(() => _alternateUnits.add(_AlternateUnitFields()));
  }

  void _removeAlternateUnit(_AlternateUnitFields fields) {
    setState(() => _alternateUnits.remove(fields));
    fields.dispose();
  }

  static String _trim(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  static String _formatCents(double cents) {
    return '₱${(cents / 100).toStringAsFixed(2)}';
  }

  static double _safeUnitsPerPurchase(double value) {
    return value > 0 ? value : 1.0;
  }

  static String _purchaseStockText(double baseUnits, double unitsPerPurchase) {
    final factor = _safeUnitsPerPurchase(unitsPerPurchase);
    return _trim(baseUnits / factor);
  }

  static double? _parseNumber(String text) {
    final normalized = text.replaceAll(',', '').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String get _effectivePurchaseUnit {
    if (_purchaseUnit == kCustomUnitOption) {
      return _customUnitController.text.trim();
    }

    return _purchaseUnit ?? '';
  }

  String get _stockPurchaseUnitLabel {
    final purchaseUnit = _effectivePurchaseUnit.trim();

    if (purchaseUnit.isNotEmpty) {
      return purchaseUnit;
    }

    return widget.supply.stockUnit;
  }

  String get _stockConversionDescription {
    final purchaseUnit = _stockPurchaseUnitLabel;
    final units = _unitsPerPurchaseController.text.trim();

    if (units.isEmpty) {
      return 'Enter how many ${widget.supply.stockUnit} are in one $purchaseUnit.';
    }

    return '1 $purchaseUnit = $units ${widget.supply.stockUnit}';
  }

  String? get _selectedCategoryId {
    final exists = _categories.any((category) => category.id == _categoryId);

    return exists ? _categoryId : null;
  }

  double? get _calculatedCostPerBaseUnit {
    final normalizedPrice = _priceController.text.replaceAll(',', '').trim();
    final normalizedUnits = _unitsPerPurchaseController.text
        .replaceAll(',', '')
        .trim();

    final price = double.tryParse(normalizedPrice);
    final units = double.tryParse(normalizedUnits);

    if (price == null ||
        units == null ||
        !price.isFinite ||
        !units.isFinite ||
        price < 0 ||
        units <= 0) {
      return null;
    }

    return (price * 100) / units;
  }

  void _convertStockField(
    TextEditingController controller,
    double fromUnitsPerPurchase,
    double toUnitsPerPurchase,
  ) {
    final entered = _parseNumber(controller.text);

    if (entered == null ||
        fromUnitsPerPurchase <= 0 ||
        toUnitsPerPurchase <= 0) {
      return;
    }

    final baseUnits = entered * fromUnitsPerPurchase;
    final converted = baseUnits / toUnitsPerPurchase;

    controller.text = _trim(converted);
  }

  void _handleUnitsPerPurchaseChanged(String value) {
    final next = _parseNumber(value);

    if (next == null || !next.isFinite || next <= 0) {
      setState(() {});
      return;
    }

    final previous = _stockDisplayUnitsPerPurchase;

    _convertStockField(_currentStockController, previous, next);

    _convertStockField(_minimumStockController, previous, next);

    _convertStockField(_maximumStockController, previous, next);

    _stockDisplayUnitsPerPurchase = next;

    setState(() {});
  }

  Future<void> _loadCategories() async {
    try {
      final db = ref.read(databaseProvider);

      final categories =
          await (db.select(db.productCategories)
                ..where(
                  (category) =>
                      category.businessId.equals(widget.supply.businessId),
                )
                ..orderBy([
                  (category) => OrderingTerm.asc(category.sortOrder),
                  (category) => OrderingTerm.asc(category.name),
                ]))
              .get();

      if (!mounted) return;

      final existingCategoryId = widget.supply.categoryId;
      final categoryExists = categories.any(
        (category) => category.id == existingCategoryId,
      );

      setState(() {
        _categories = categories;
        _categoryId = categoryExists ? existingCategoryId : null;
        _loadingCategories = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _categories = <ProductCategory>[];
        _categoryId = null;
        _loadingCategories = false;
        _error = 'Unable to load categories: $error';
      });
    }
  }

  Future<void> _loadPurchaseRecordState() async {
    try {
      final db = ref.read(databaseProvider);

      final history =
          await (db.select(db.supplyPriceHistory)
                ..where((history) => history.supplyId.equals(widget.supply.id))
                ..orderBy([
                  (history) => OrderingTerm(
                    expression: history.recordedDate,
                    mode: OrderingMode.desc,
                  ),
                  (history) => OrderingTerm(
                    expression: history.id,
                    mode: OrderingMode.desc,
                  ),
                ])
                ..limit(20))
              .get();

      final hasRecord = history.any(
        (entry) =>
            entry.notes == 'purchase_record' ||
            entry.storeName.trim().toLowerCase() != 'initial price',
      );

      if (!mounted) return;

      setState(() {
        _hasPurchaseRecord = hasRecord;
        _loadingRecord = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loadingRecord = false;
        _error = 'Unable to load the existing purchase record: $error';
      });
    }
  }

  Future<void> _assertCodeIsAvailable({
    required AppDatabase db,
    required String? sku,
    required String? barcode,
  }) async {
    if (sku != null) {
      final row = await db
          .customSelect(
            '''
        SELECT name
        FROM supplies
        WHERE business_id = ?
          AND sku = ?
          AND id <> ?
          AND is_active = 1
        LIMIT 1
        ''',
            variables: [
              Variable.withString(widget.supply.businessId),
              Variable.withString(sku),
              Variable.withString(widget.supply.id),
            ],
          )
          .getSingleOrNull();

      if (row != null) {
        throw StateError(
          'SKU $sku is already used by ${row.read<String>('name')}.',
        );
      }
    }

    if (barcode != null) {
      final row = await db
          .customSelect(
            '''
        SELECT name
        FROM supplies
        WHERE business_id = ?
          AND barcode = ?
          AND id <> ?
          AND is_active = 1
        LIMIT 1
        ''',
            variables: [
              Variable.withString(widget.supply.businessId),
              Variable.withString(barcode),
              Variable.withString(widget.supply.id),
            ],
          )
          .getSingleOrNull();

      if (row != null) {
        throw StateError(
          'Barcode $barcode is already used by ${row.read<String>('name')}.',
        );
      }
    }
  }

  Future<void> _save() async {
    final purchaseUnit = _effectivePurchaseUnit;
    if (_isWeightBased &&
        !UnitConverter.areCompatible(purchaseUnit, widget.supply.stockUnit)) {
      setState(() {
        _error =
            'This supply\'s stock unit (${widget.supply.stockUnit}) isn\'t a '
            'weight unit, so it can\'t be purchased by weight. Pick a '
            'different purchase unit.';
      });
      return;
    }

    final normalizedContains = _unitsPerPurchaseController.text
        .replaceAll(',', '')
        .trim();
    final unitsPerPurchase = double.tryParse(normalizedContains);

    final normalizedPrice = _priceController.text.replaceAll(',', '').trim();
    final price = double.tryParse(normalizedPrice);

    final currentStockPurchaseUnits = _parseNumber(
      _currentStockController.text,
    );

    final minimumStockPurchaseUnits =
        _parseNumber(_minimumStockController.text) ?? 0.0;

    final maximumStockPurchaseUnits =
        _parseNumber(_maximumStockController.text) ?? 0.0;

    if (purchaseUnit.isEmpty) {
      setState(() {
        _error = 'Choose (or type) a purchase unit.';
      });
      return;
    }

    if (unitsPerPurchase == null ||
        !unitsPerPurchase.isFinite ||
        unitsPerPurchase <= 0) {
      setState(() {
        _error =
            'Enter how many ${widget.supply.stockUnit} are in one $purchaseUnit.';
      });
      return;
    }

    if (_loadingAlternateUnits) return;
    final alternateUnitValues = <({String name, double unitsPerStockUnit})>[];
    final knownUnits = <String>{
      purchaseUnit.toLowerCase(),
      widget.supply.stockUnit.trim().toLowerCase(),
    };
    for (final fields in _alternateUnits) {
      final name = fields.nameController.text.trim();
      final countText = fields.unitsPerStockController.text
          .replaceAll(',', '')
          .trim();
      if (name.isEmpty && countText.isEmpty) continue;
      final unitsPerStockUnit = double.tryParse(countText);
      if (name.isEmpty ||
          unitsPerStockUnit == null ||
          !unitsPerStockUnit.isFinite ||
          unitsPerStockUnit <= 0) {
        setState(() {
          _error =
              'Enter a unit and a positive quantity for each alternate unit.';
        });
        return;
      }
      if (!knownUnits.add(name.toLowerCase())) {
        setState(() => _error = 'Each purchase unit must be unique.');
        return;
      }
      alternateUnitValues.add((
        name: name,
        unitsPerStockUnit: unitsPerStockUnit,
      ));
    }

    if (price == null || !price.isFinite || price < 0) {
      setState(() {
        _error = 'Enter a valid price.';
      });
      return;
    }

    if (!_hasPurchaseRecord &&
        (currentStockPurchaseUnits == null ||
            !currentStockPurchaseUnits.isFinite ||
            currentStockPurchaseUnits < 0)) {
      setState(() {
        _error = 'Enter a valid current stock amount in $purchaseUnit.';
      });
      return;
    }

    if (!minimumStockPurchaseUnits.isFinite || minimumStockPurchaseUnits < 0) {
      setState(() {
        _error = 'Enter a valid minimum stock amount.';
      });
      return;
    }

    if (!maximumStockPurchaseUnits.isFinite || maximumStockPurchaseUnits < 0) {
      setState(() {
        _error = 'Enter a valid maximum stock amount.';
      });
      return;
    }

    if (maximumStockPurchaseUnits > 0 &&
        maximumStockPurchaseUnits < minimumStockPurchaseUnits) {
      setState(() {
        _error = 'Maximum stock cannot be lower than minimum stock.';
      });
      return;
    }

    final normalizedSku = SupplyCatalogService.normalizeSku(
      _skuController.text,
    );

    final normalizedBarcode = SupplyCatalogService.normalizeBarcode(
      _barcodeController.text,
    );

    final selectedCategoryId = _selectedCategoryId;
    final priceCents = (price * 100).round();
    final now = DateTime.now();
    final storeName = _storeController.text.trim();
    final storeAddress = _addressController.text.trim();
    final nameText = _nameController.text.trim();
    if (nameText.isEmpty) {
      setState(() {
        _error = 'Enter a product / item name.';
      });
      return;
    }

    final brandText = _brandController.text.trim();
    final brandValue = brandText.isEmpty ? null : brandText;

    // Convert the user's purchase-unit input into the base stock unit before
    // persisting. The rest of BOS continues to calculate inventory/costing in
    // base units.
    final currentStockBaseUnits = currentStockPurchaseUnits == null
        ? null
        : currentStockPurchaseUnits * unitsPerPurchase;

    final minimumStockBaseUnits = minimumStockPurchaseUnits * unitsPerPurchase;

    final maximumStockBaseUnits = maximumStockPurchaseUnits * unitsPerPurchase;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final audit = ref.read(auditLogServiceProvider);

      await _assertCodeIsAvailable(
        db: db,
        sku: normalizedSku,
        barcode: normalizedBarcode,
      );

      await db.transaction(() async {
        final currentSupply =
            await (db.select(db.supplies)
                  ..where((supply) => supply.id.equals(widget.supply.id)))
                .getSingleOrNull();

        if (currentSupply == null) {
          throw StateError('This supply no longer exists.');
        }

        final costPerBaseUnit = priceCents / unitsPerPurchase;

        await (db.update(
          db.supplies,
        )..where((supply) => supply.id.equals(widget.supply.id))).write(
          SuppliesCompanion(
            name: Value(nameText),
            brand: Value(brandValue),
            sku: Value(normalizedSku),
            barcode: Value(normalizedBarcode),
            categoryId: Value(selectedCategoryId),
            currentPrice: Value(priceCents),
            purchaseUnit: Value(purchaseUnit),
            unitsPerPurchase: Value(unitsPerPurchase),
            costPerBaseUnit: Value(costPerBaseUnit),
            minimumStock: Value(minimumStockBaseUnits),
            maximumStock: Value(maximumStockBaseUnits),
            lastStoreName: Value(storeName.isEmpty ? null : storeName),
            lastStoreAddress: Value(storeAddress.isEmpty ? null : storeAddress),
            updatedAt: Value(now),
            isSoldByWeight: Value(_isWeightBased),
          ),
        );

        if (!_hasPurchaseRecord && currentStockBaseUnits != null) {
          final branchId = ref.read(selectedBranchIdProvider);
          final stock = StockService(db, viewBranchId: branchId);
          final onHand = await stock.supplyQty(branchId, widget.supply.id);
          final diff = currentStockBaseUnits - onHand;
          if (diff.abs() > 1e-9) {
            await stock.moveSupply(
              branchId: branchId,
              supplyId: widget.supply.id,
              type: 'opening_balance',
              quantity: diff,
              unit: currentSupply.stockUnit,
              notes: 'Opening stock',
            );
          }
        }

        final settingOpeningStock = !_hasPurchaseRecord;
        await audit.record(
          AuditEvent(
            businessId: currentSupply.businessId,
            module: AuditModule.inventory,
            actionType: AuditActionType.update,
            action: _hasPurchaseRecord
                ? 'inventory.purchase_record_updated'
                : 'inventory.purchase_record_created',
            entityType: 'supplies',
            entityId: currentSupply.id,
            entityLabel: nameText,
            before: {
              'name': currentSupply.name,
              'brand': currentSupply.brand,
              'price': currentSupply.currentPrice,
              'purchaseUnit': currentSupply.purchaseUnit,
              'unitsPerPurchase': currentSupply.unitsPerPurchase,
              'minimumStock': currentSupply.minimumStock,
              'maximumStock': currentSupply.maximumStock,
              'stock': currentSupply.currentStock,
              'sku': currentSupply.sku,
              'barcode': currentSupply.barcode,
              'categoryId': currentSupply.categoryId,
            },
            after: {
              'name': nameText,
              'brand': brandValue,
              'price': priceCents,
              'purchaseUnit': purchaseUnit,
              'unitsPerPurchase': unitsPerPurchase,
              'minimumStock': minimumStockBaseUnits,
              'maximumStock': maximumStockBaseUnits,
              'stock': settingOpeningStock
                  ? currentStockBaseUnits
                  : currentSupply.currentStock,
              'sku': normalizedSku,
              'barcode': normalizedBarcode,
              'categoryId': selectedCategoryId,
            },
            details: {
              'openingStockSet': settingOpeningStock,
              'store': storeName,
            },
          ),
        );

        await (db.delete(
          db.supplyUnitConversions,
        )..where((row) => row.supplyId.equals(widget.supply.id))).go();
        for (final alternate in alternateUnitValues) {
          await db
              .into(db.supplyUnitConversions)
              .insert(
                SupplyUnitConversionsCompanion.insert(
                  supplyId: widget.supply.id,
                  unitName: alternate.name,
                  unitsPerStockUnit: alternate.unitsPerStockUnit,
                ),
              );
        }

        final shouldAddHistory =
            !_hasPurchaseRecord || currentSupply.currentPrice != priceCents;

        if (shouldAddHistory) {
          await db
              .into(db.supplyPriceHistory)
              .insert(
                SupplyPriceHistoryCompanion.insert(
                  id: const Uuid().v4(),
                  supplyId: widget.supply.id,
                  price: priceCents,
                  storeName: storeName.isEmpty ? '' : storeName,
                  storeAddress: Value(
                    storeAddress.isEmpty ? null : storeAddress,
                  ),
                  recordedDate: now,
                  notes: const Value('purchase_record'),
                ),
              );
        }
      });

      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) return;

      final wasFirstSave = !_hasPurchaseRecord;

      setState(() {
        _hasPurchaseRecord = true;
      });

      Navigator.of(context).pop(
        PurchaseEntryResult(
          supplyId: widget.supply.id,
          priceCents: priceCents,
          name: nameText,
          brand: brandValue,
          purchaseUnit: purchaseUnit,
          unitsPerPurchase: unitsPerPurchase,
          isSoldByWeight: _isWeightBased,
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            wasFirstSave
                ? '$nameText purchase record saved'
                : '$nameText purchase record updated',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || barcode == null || barcode.trim().isEmpty) return;
    _barcodeController.text =
        SupplyCatalogService.normalizeBarcode(barcode) ?? barcode.trim();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _hasPurchaseRecord ? 'Update Purchase' : 'Record Purchase';
    final actionLabel = _hasPurchaseRecord
        ? 'Update Purchase'
        : 'Save Purchase';

    final selectedCategoryId = _selectedCategoryId;

    final categoryItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Uncategorized'),
      ),
      for (final category in _categories)
        DropdownMenuItem<String?>(
          value: category.id,
          child: Text(
            category.name.trim().isEmpty
                ? 'Unnamed category'
                : category.name.trim(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    final calculatedCost = _calculatedCostPerBaseUnit;

    final currentPriceForDisplay = _parseNumber(_priceController.text) ?? 0.0;

    final currentStockPurchaseUnits = _parseNumber(
      _currentStockController.text,
    );

    final currentStockBaseUnits = currentStockPurchaseUnits == null
        ? null
        : currentStockPurchaseUnits *
              _safeUnitsPerPurchase(_stockDisplayUnitsPerPurchase);

    final totalStockWorthCents =
        calculatedCost != null &&
            currentStockBaseUnits != null &&
            currentStockBaseUnits.isFinite &&
            currentStockBaseUnits >= 0
        ? calculatedCost * currentStockBaseUnits
        : null;

    final purchaseUnit = _effectivePurchaseUnit;
    final stockUnit = widget.supply.stockUnit;

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),

                Text(
                  '${widget.supply.name} · current stock ${_purchaseStockText(widget.supply.currentStock, _stockDisplayUnitsPerPurchase)} $_stockPurchaseUnitLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 8),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stock is shown in $_stockPurchaseUnitLabel for easier entry, but BOS stores and calculates stock in $stockUnit. $_stockConversionDescription.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const _StepLabel(number: 1, text: 'Product identity'),
                const SizedBox(height: 8),

                TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Product / item name',
                    hintText: 'Required',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                ),

                const SizedBox(height: 10),

                TextField(
                  controller: _brandController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Product brand',
                    hintText: 'Optional',
                    prefixIcon: Icon(Icons.branding_watermark_outlined),
                  ),
                ),

                const SizedBox(height: 18),

                const _StepLabel(number: 2, text: 'What did you buy it in?'),
                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  initialValue: _purchaseUnit,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Purchase unit',
                    prefixIcon: Icon(Icons.shopping_bag_outlined),
                  ),
                  items: [
                    for (final unit in kPurchaseUnitOptions)
                      DropdownMenuItem<String>(value: unit, child: Text(unit)),
                    for (final unit in kWeightPurchaseUnitOptions)
                      DropdownMenuItem<String>(
                        value: unit,
                        child: Text(
                          '${kStockUnitLabels[unit] ?? unit} — by weight',
                        ),
                      ),
                    const DropdownMenuItem<String>(
                      value: kCustomUnitOption,
                      child: Text(kCustomUnitOption),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() {
                            _purchaseUnit = value;
                          });
                          _autoFillWeightConversion();
                        },
                ),

                if (_isWeightBased) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.scale_outlined,
                          size: 18,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            UnitConverter.areCompatible(
                                  _purchaseUnit!,
                                  widget.supply.stockUnit,
                                )
                                ? 'Priced by weight — the exact amount bought '
                                      '(e.g. 0.5 or 1.25 $_purchaseUnit) is entered per '
                                      'purchase in the shopping cart, not a fixed pack size.'
                                : 'This supply\'s stock unit (${widget.supply.stockUnit}) '
                                      'isn\'t a weight unit, so it can\'t be priced by weight.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_purchaseUnit == kCustomUnitOption) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customUnitController,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Type your own purchase unit',
                      hintText: 'e.g. drum, cylinder',
                    ),
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                ],

                const SizedBox(height: 18),

                _StepLabel(
                  number: 3,
                  text:
                      'How much is in one ${purchaseUnit.isEmpty ? 'purchase unit' : purchaseUnit}?',
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _unitsPerPurchaseController,
                  enabled: !_saving && !_isWeightBased,
                  readOnly: _isWeightBased,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Contains',
                    suffixText: stockUnit,
                    hintText: 'e.g. 25',
                    helperText: _isWeightBased
                        ? 'Auto-calculated — this purchase unit is a weight, so the conversion is fixed.'
                        : null,
                  ),
                  onChanged: _isWeightBased
                      ? null
                      : _handleUnitsPerPurchaseChanged,
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    purchaseUnit.isEmpty
                        ? 'Example: 1 pack = 25 kg'
                        : _stockConversionDescription,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Optional units for buying in another size',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Stock stays in ${widget.supply.stockUnit}. For example, add "piece" and 10 when 1 ${widget.supply.stockUnit} contains 10 pieces.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_loadingAlternateUnits)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  )
                else ...[
                  for (final fields in _alternateUnits)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: fields.nameController,
                              enabled: !_saving,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Alternate unit',
                                hintText: 'piece',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: fields.unitsPerStockController,
                              enabled: !_saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    'Units in 1 ${widget.supply.stockUnit}',
                                suffixText:
                                    fields.nameController.text.trim().isEmpty
                                    ? null
                                    : fields.nameController.text.trim(),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove alternate unit',
                            onPressed: _saving
                                ? null
                                : () => _removeAlternateUnit(fields),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _addAlternateUnit,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add unit option'),
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                const _StepLabel(number: 4, text: 'What is the current price?'),
                const SizedBox(height: 8),

                TextField(
                  controller: _priceController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Price per ${purchaseUnit.isEmpty ? 'unit' : purchaseUnit}',
                    prefixText: '₱ ',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                ),

                const SizedBox(height: 18),

                const _StepLabel(
                  number: 5,
                  text: 'Current stock & stock limits',
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _currentStockController,
                  enabled: !_saving,
                  readOnly: _hasPurchaseRecord,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Current available stock',
                    hintText: 'e.g. 10',
                    suffixText: _stockPurchaseUnitLabel,
                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                    helperText: _hasPurchaseRecord
                        ? 'Stored in $stockUnit, shown here in $_stockPurchaseUnitLabel.'
                        : 'Enter the current stock in $_stockPurchaseUnitLabel.',
                  ),
                ),

                const SizedBox(height: 10),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 500;

                    final minimumField = TextField(
                      controller: _minimumStockController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Minimum stock',
                        hintText: 'e.g. 2',
                        suffixText: _stockPurchaseUnitLabel,
                        prefixIcon: const Icon(Icons.arrow_downward_rounded),
                        helperText: 'Low-stock level',
                      ),
                    );

                    final maximumField = TextField(
                      controller: _maximumStockController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Maximum stock',
                        hintText: 'e.g. 20',
                        suffixText: _stockPurchaseUnitLabel,
                        prefixIcon: const Icon(Icons.arrow_upward_rounded),
                        helperText: '0 = no maximum',
                      ),
                    );

                    if (compact) {
                      return Column(
                        children: [
                          minimumField,
                          const SizedBox(height: 10),
                          maximumField,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: minimumField),
                        const SizedBox(width: 12),
                        Expanded(child: maximumField),
                      ],
                    );
                  },
                ),

                if (calculatedCost != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.calculate_outlined,
                          size: 18,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cost per $stockUnit',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_formatCents(calculatedCost)} per $stockUnit',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Current available stock',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentStockPurchaseUnits == null
                                    ? 'Not entered'
                                    : '${_trim(currentStockPurchaseUnits)} $_stockPurchaseUnitLabel (${_trim(currentStockBaseUnits ?? 0)} $stockUnit)',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                totalStockWorthCents == null
                                    ? 'Enter a valid current stock amount to calculate total stock worth.'
                                    : 'Total stock worth',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                totalStockWorthCents == null
                                    ? '—'
                                    : _formatCents(totalStockWorthCents),
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              if (totalStockWorthCents != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  '${_trim(currentStockPurchaseUnits ?? 0)} $_stockPurchaseUnitLabel × ₱${currentPriceForDisplay.toStringAsFixed(2)} per $_stockPurchaseUnitLabel',
                                  style: TextStyle(
                                    color: scheme.onPrimaryContainer.withValues(
                                      alpha: 0.72,
                                    ),
                                    fontSize: 11,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Choose a purchase unit and enter its contents to calculate the cost per $stockUnit.',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                const _StepLabel(number: 6, text: 'Where did you buy it?'),
                const SizedBox(height: 8),

                TextField(
                  controller: _storeController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Store / supplier',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),

                const SizedBox(height: 10),

                TextField(
                  controller: _addressController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),

                const SizedBox(height: 18),

                const _StepLabel(number: 7, text: 'Supply category'),
                const SizedBox(height: 8),

                DropdownButtonFormField<String?>(
                  initialValue: selectedCategoryId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    hintText: _loadingCategories
                        ? 'Loading categories...'
                        : 'Choose a category',
                    prefixIcon: const Icon(Icons.category_outlined),
                    suffixIcon: _loadingCategories
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  items: categoryItems,
                  onChanged: (_saving || _loadingCategories)
                      ? null
                      : (value) {
                          setState(() {
                            _categoryId = value;
                          });
                        },
                ),

                const SizedBox(height: 18),

                const _StepLabel(number: 8, text: 'Catalog identity'),
                const SizedBox(height: 8),

                TextField(
                  controller: _skuController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'SKU (optional)',
                    hintText: 'Leave blank to remove the SKU',
                    prefixIcon: Icon(Icons.sell_outlined),
                  ),
                ),

                const SizedBox(height: 10),

                TextField(
                  controller: _barcodeController,
                  enabled: !_saving,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'Barcode (optional)',
                    hintText: 'Leave blank to remove the barcode',
                    prefixIcon: const Icon(Icons.qr_code_2_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Scan barcode',
                      onPressed: _saving ? null : _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: (_saving || _loadingRecord || _loadingCategories)
                        ? null
                        : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            (_loadingRecord || _loadingCategories)
                                ? 'Loading...'
                                : actionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
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
