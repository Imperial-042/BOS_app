import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/supplies_price_list_page.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class _EditedAdjustment {
  final double quantity;
  final String notes;

  const _EditedAdjustment({required this.quantity, required this.notes});
}

class StockAdjustmentHistoryPage extends ConsumerWidget {
  final Supply supply;

  const StockAdjustmentHistoryPage({super.key, required this.supply});

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _deleteAdjustment(
    BuildContext context,
    WidgetRef ref,
    InventoryMovement movement,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete stock adjustment?'),
        content: Text(
          'Deleting this ${_formatQuantity(movement.quantity.abs())} ${supply.stockUnit} removal will restore that quantity to current stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      final db = ref.read(databaseProvider);
      final viewBranchId = ref.read(selectedBranchIdProvider);

      await db.transaction(() async {
        final currentSupply = await (db.select(
          db.supplies,
        )..where((s) => s.id.equals(supply.id))).getSingleOrNull();
        if (currentSupply == null) throw StateError('Supply no longer exists.');

        final movementBranch =
            movement.branchId ??
            AppDatabase.mainBranchId(currentSupply.businessId);
        if (movementBranch != viewBranchId) {
          throw StateError(
            'This adjustment belongs to another branch. Switch to that branch to delete it.',
          );
        }

        final qty = await StockService(
          db,
          viewBranchId: viewBranchId,
        ).supplyQty(viewBranchId, supply.id);
        if (qty - movement.quantity < -1e-9) {
          throw StateError('Deleting this would make stock negative.');
        }

        await (db.delete(
          db.inventoryMovements,
        )..where((m) => m.id.equals(movement.id))).go();

        await StockService.recompute(
          db,
          businessId: currentSupply.businessId,
          branchId: viewBranchId,
        );
      });

      ref.invalidate(stockAdjustmentHistoryProvider(supply.id));
      ref.invalidate(suppliesProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${_formatQuantity(movement.quantity.abs())} ${supply.stockUnit} restored to stock.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to delete adjustment: $error'),
        ),
      );
    }
  }

  Future<void> _editAdjustment(
    BuildContext context,
    WidgetRef ref,
    InventoryMovement movement,
  ) async {
    final notes = movement.notes?.trim() ?? '';
    final oldRemovedQuantity = movement.quantity.abs();

    final result = await showDialog<_EditedAdjustment>(
      context: context,
      builder: (_) => _EditAdjustmentDialog(
        initialQuantity: oldRemovedQuantity,
        initialNotes: notes,
        unit: supply.stockUnit,
      ),
    );

    if (result == null || !context.mounted) {
      return;
    }

    if (result.quantity <= 0) {
      return;
    }

    final newRemovedQuantity = result.quantity;

    // currentStock already reflects the old removal.
    // Smaller removal => restore the difference.
    // Larger removal => remove the difference.

    try {
      final db = ref.read(databaseProvider);
      final viewBranchId = ref.read(selectedBranchIdProvider);

      await db.transaction(() async {
        final currentSupply = await (db.select(
          db.supplies,
        )..where((s) => s.id.equals(supply.id))).getSingleOrNull();
        if (currentSupply == null) throw StateError('Supply no longer exists.');

        final movementBranch =
            movement.branchId ??
            AppDatabase.mainBranchId(currentSupply.businessId);
        if (movementBranch != viewBranchId) {
          throw StateError(
            'This adjustment belongs to another branch. Switch to that branch to edit it.',
          );
        }

        final qty = await StockService(
          db,
          viewBranchId: viewBranchId,
        ).supplyQty(viewBranchId, supply.id);
        final newMovementQty = -newRemovedQuantity;
        if (qty + (newMovementQty - movement.quantity) < -1e-9) {
          throw StateError('Adjustment would make stock negative.');
        }

        await (db.update(
          db.inventoryMovements,
        )..where((m) => m.id.equals(movement.id))).write(
          InventoryMovementsCompanion(
            quantity: Value(newMovementQty),
            notes: Value(
              result.notes.trim().isEmpty ? null : result.notes.trim(),
            ),
          ),
        );

        await StockService.recompute(
          db,
          businessId: currentSupply.businessId,
          branchId: viewBranchId,
        );
      });

      ref.invalidate(stockAdjustmentHistoryProvider(supply.id));
      ref.invalidate(suppliesProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Adjustment updated and stock recalculated.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Unable to update adjustment: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final historyAsync = ref.watch(stockAdjustmentHistoryProvider(supply.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Stock adjustment history',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Unable to load adjustment history.\n$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
        data: (movements) {
          if (movements.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 52,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No stock adjustments yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Damaged, expired, and correction entries will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        supply.name,
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${movements.length} record${movements.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ...movements.map(
                (movement) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StockAdjustmentHistoryCard(
                    movement: movement,
                    stockUnit: supply.stockUnit,
                    quantityFormatter: _formatQuantity,
                    onEdit: () => _editAdjustment(context, ref, movement),
                    onDelete: () => _deleteAdjustment(context, ref, movement),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StockAdjustmentHistoryCard extends StatelessWidget {
  final InventoryMovement movement;
  final String Function(double value) quantityFormatter;
  final String stockUnit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StockAdjustmentHistoryCard({
    required this.movement,
    required this.quantityFormatter,
    required this.stockUnit,
    required this.onEdit,
    required this.onDelete,
  });

  IconData _iconForReason(String notes) {
    final value = notes.toLowerCase();

    if (value.contains('damage')) {
      return Icons.broken_image_outlined;
    }

    if (value.contains('expir')) {
      return Icons.event_busy_outlined;
    }

    if (value.contains('count')) {
      return Icons.fact_check_outlined;
    }

    return Icons.remove_circle_outline;
  }

  Color _colorForReason(BuildContext context, String notes) {
    final value = notes.toLowerCase();

    if (value.contains('expir')) {
      return Colors.deepOrange;
    }

    if (value.contains('damage')) {
      return Colors.redAccent;
    }

    if (value.contains('count')) {
      return Colors.orange;
    }

    return Theme.of(context).colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = movement.notes?.trim() ?? '';
    final color = _colorForReason(context, notes);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_iconForReason(notes), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notes.isEmpty ? 'Stock adjustment' : notes,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '-${quantityFormatter(movement.quantity.abs())} $stockUnit',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat(
                    'MMM d, yyyy · h:mm a',
                  ).format(movement.movementDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit adjustment',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete adjustment',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _EditAdjustmentDialog extends StatefulWidget {
  final double initialQuantity;
  final String initialNotes;
  final String unit;

  const _EditAdjustmentDialog({
    required this.initialQuantity,
    required this.initialNotes,
    required this.unit,
  });

  @override
  State<_EditAdjustmentDialog> createState() => _EditAdjustmentDialogState();
}

class _EditAdjustmentDialogState extends State<_EditAdjustmentDialog> {
  late final TextEditingController _quantityController;
  late final TextEditingController _notesController;
  String? _error;

  @override
  void initState() {
    super.initState();

    _quantityController = TextEditingController(
      text: widget.initialQuantity == widget.initialQuantity.roundToDouble()
          ? widget.initialQuantity.toInt().toString()
          : widget.initialQuantity.toString(),
    );

    _notesController = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = double.tryParse(
      _quantityController.text.replaceAll(',', '').trim(),
    );

    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      setState(() {
        _error = 'Enter a valid quantity.';
      });
      return;
    }

    Navigator.pop(
      context,
      _EditedAdjustment(
        quantity: quantity,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit stock adjustment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _quantityController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Removed quantity',
                suffixText: widget.unit,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason / note',
                hintText: 'e.g. Damaged packaging',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Changing the quantity will automatically adjust the current inventory.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save changes')),
      ],
    );
  }
}
