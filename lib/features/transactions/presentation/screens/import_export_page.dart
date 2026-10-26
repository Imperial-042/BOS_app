// lib/features/transactions/presentation/screens/import_export_page.dart
//
// Administration -> Import / Export. Every dataset exports as a business-
// scoped CSV via share_plus. Customers and suppliers can be imported from
// a simple CSV (name, phone, notes); financial ledgers deliberately have
// no import — hand-entered journals keep the books auditable.

import 'dart:convert';

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import 'package:uuid/uuid.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/authorization_service.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/sync/backup_service.dart';
import 'transaction_page.dart' show kCurrentBusinessId, ledgerVersionProvider;

/// A CSV cell: quote anything containing commas, quotes, or newlines.
String _csvCell(String value) {
  if (RegExp(r'[",\r\n]').hasMatch(value)) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Stops spreadsheet apps from treating text like "=SUM(A1)" as a formula.
String _safeText(String value) =>
    value.isNotEmpty && '=+-@'.contains(value[0]) ? "'$value" : value;

String _csv(List<List<String>> rows) => rows
    .map((row) => row.map((cell) => _csvCell(_safeText(cell))).join(','))
    .join('\n');

class _Dataset {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Future<String> Function(AppDatabase db) build;
  final String filename;

  const _Dataset({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.build,
    required this.filename,
  });
}

class ImportExportPage extends ConsumerWidget {
  const ImportExportPage({super.key});

  List<_Dataset> get _datasets => [
    _Dataset(
      id: 'accounts',
      title: 'Chart of Accounts',
      description:
          'Every account with type, classification, and starting balance.',
      icon: Icons.account_tree_outlined,
      filename: 'chart_of_accounts',
      build: _buildAccountsCsv,
    ),
    _Dataset(
      id: 'categories',
      title: 'Categories',
      description: 'Income and expense categories and their GL account.',
      icon: Icons.category_outlined,
      filename: 'categories',
      build: _buildCategoriesCsv,
    ),
    _Dataset(
      id: 'customers',
      title: 'Customers',
      description: 'Names, phone numbers, and notes.',
      icon: Icons.people_outline_rounded,
      filename: 'customers',
      build: _buildCustomersCsv,
    ),
    _Dataset(
      id: 'suppliers',
      title: 'Suppliers',
      description: 'Names, phone numbers, and notes.',
      icon: Icons.local_shipping_outlined,
      filename: 'suppliers',
      build: _buildSuppliersCsv,
    ),
    _Dataset(
      id: 'income',
      title: 'Income transactions',
      description:
          'All income rows with customer, account, amount, and status.',
      icon: Icons.trending_up_rounded,
      filename: 'income',
      build: _buildIncomeCsv,
    ),
    _Dataset(
      id: 'expenses',
      title: 'Expenses',
      description: 'All expense rows with account, amount, and status.',
      icon: Icons.trending_down_rounded,
      filename: 'expenses',
      build: _buildExpensesCsv,
    ),
    _Dataset(
      id: 'supplies',
      title: 'Supplies & stock',
      description: 'Inventory items with current stock, unit, and cost.',
      icon: Icons.inventory_2_outlined,
      filename: 'supplies',
      build: _buildSuppliesCsv,
    ),
    _Dataset(
      id: 'journal',
      title: 'Journal entries',
      description: 'Full ledger: every entry with its debit and credit lines.',
      icon: Icons.receipt_long_outlined,
      filename: 'journal_entries',
      build: _buildJournalCsv,
    ),
  ];

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    _Dataset dataset,
  ) async {
    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.reportsView, businessId: kCurrentBusinessId);
      final csv = await dataset.build(ref.read(databaseProvider));
      final dataRows = _parseCsv(csv).length - 1;
      await ref
          .read(auditLogServiceProvider)
          .record(
            AuditEvent(
              businessId: kCurrentBusinessId,
              module: AuditModule.administration,
              actionType: AuditActionType.export,
              action: 'data.exported',
              entityType: 'export',
              entityLabel: dataset.title,
              details: {
                'dataset': dataset.id,
                'rows': dataRows < 0 ? 0 : dataRows,
              },
            ),
          );

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final name = '${dataset.filename}_${kCurrentBusinessId}_$timestamp.csv';
      await Share.shareXFiles(
        [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: name)],
        fileNameOverrides: [name],
        subject: name,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(auditLogServiceProvider)
          .record(
            AuditEvent(
              businessId: kCurrentBusinessId,
              module: AuditModule.administration,
              actionType: AuditActionType.export,
              action: 'data.backup_created',
              entityType: 'backup',
              entityLabel: 'Full business backup',
            ),
          );
      await ref.read(backupServiceProvider).backupBusiness(kCurrentBusinessId);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      ref
          .read(authorizationServiceProvider)
          .require(
            BosPermission.businessSettings,
            businessId: kCurrentBusinessId,
          );
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final file = result?.files.firstOrNull;
      if (file == null || !context.mounted) return;

      final bytes = file.bytes;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file.')),
        );
        return;
      }

      final restored = await ref
          .read(backupServiceProvider)
          .restoreBusiness(kCurrentBusinessId, utf8.decode(bytes));
      await ref
          .read(auditLogServiceProvider)
          .tryRecord(
            AuditEvent(
              businessId: kCurrentBusinessId,
              module: AuditModule.administration,
              actionType: AuditActionType.update,
              action: 'data.restored',
              entityType: 'backup',
              entityLabel: file.name,
              details: {'records': restored, 'file': file.name},
            ),
          );
      ref.read(ledgerVersionProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored $restored record${restored == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on PermissionDeniedException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on BackupException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref, String kind) async {
    try {
      final permission = switch (kind) {
        'customer' => BosPermission.customersCreate,
        'supplier' => BosPermission.suppliersCreate,
        _ => throw ArgumentError.value(kind, 'kind'),
      };
      ref
          .read(authorizationServiceProvider)
          .require(permission, businessId: kCurrentBusinessId);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      final file = result?.files.firstOrNull;
      if (file == null || !context.mounted) return;

      final bytes = file.bytes;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file.')),
        );
        return;
      }

      final csv = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      final records = _parseCsv(csv);
      if (records.length < 2) {
        throw const FormatException(
          'That file has no data rows (only a header).',
        );
      }

      final header = records.first;
      final nameIndex = header.indexWhere(
        (cell) => cell.trim().toLowerCase() == 'name',
      );
      final phoneIndex = header.indexWhere(
        (cell) => cell.trim().toLowerCase() == 'phone',
      );
      final notesIndex = header.indexWhere(
        (cell) => cell.trim().toLowerCase() == 'notes',
      );
      if (nameIndex < 0) {
        throw const FormatException(
          'The file needs a "name" column in its header.',
        );
      }

      final db = ref.read(databaseProvider);
      final audit = ref.read(auditLogServiceProvider);
      var imported = 0;
      var skipped = 0;

      await db.transaction(() async {
        for (final cells in records.skip(1)) {
          final name = nameIndex < cells.length ? cells[nameIndex].trim() : '';
          if (name.isEmpty) {
            skipped++;
            continue;
          }
          final phone = phoneIndex >= 0 && phoneIndex < cells.length
              ? cells[phoneIndex].trim()
              : '';
          final notes = notesIndex >= 0 && notesIndex < cells.length
              ? cells[notesIndex].trim()
              : '';

          final exists = kind == 'customer'
              ? await (db.select(db.customers)..where(
                      (c) =>
                          c.businessId.equals(kCurrentBusinessId) &
                          c.name.equals(name),
                    ))
                    .getSingleOrNull()
              : await (db.select(db.suppliers)..where(
                      (s) =>
                          s.businessId.equals(kCurrentBusinessId) &
                          s.name.equals(name),
                    ))
                    .getSingleOrNull();
          if (exists != null) {
            skipped++;
            continue;
          }

          if (kind == 'customer') {
            await db
                .into(db.customers)
                .insert(
                  CustomersCompanion.insert(
                    id: const Uuid().v4(),
                    businessId: kCurrentBusinessId,
                    name: name,
                    phone: Value(phone.isEmpty ? null : phone),
                    notes: Value(notes.isEmpty ? null : notes),
                  ),
                );
          } else {
            await db
                .into(db.suppliers)
                .insert(
                  SuppliersCompanion.insert(
                    id: const Uuid().v4(),
                    businessId: kCurrentBusinessId,
                    name: name,
                    phone: Value(phone.isEmpty ? null : phone),
                    notes: Value(notes.isEmpty ? null : notes),
                  ),
                );
          }
          imported++;
        }
        if (imported > 0) {
          await audit.record(
            AuditEvent(
              businessId: kCurrentBusinessId,
              module: AuditModule.administration,
              actionType: AuditActionType.create,
              action: kind == 'customer'
                  ? 'data.customers_imported'
                  : 'data.suppliers_imported',
              entityType: kind == 'customer' ? 'customers' : 'suppliers',
              entityLabel: file.name,
              details: {
                'imported': imported,
                'skipped': skipped,
                'file': file.name,
              },
            ),
          );
        }
      });

      ref.read(ledgerVersionProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported $imported ${kind == 'customer' ? 'customer' : 'supplier'}'
            '${imported == 1 ? '' : 's'}'
            '${skipped > 0 ? ', skipped $skipped duplicate${skipped == 1 ? '' : 's'}' : ''}.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid CSV: ${error.message}')));
    } on PermissionDeniedException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var closedQuote = false;
    void finishField() {
      row.add(buffer.toString());
      buffer.clear();
      closedQuote = false;
    }

    void finishRow() {
      finishField();
      if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') {
        if (inQuotes && i + 1 < input.length && input[i + 1] == '"') {
          buffer.write('"');
          i++;
          continue;
        }
        if (inQuotes) {
          inQuotes = false;
          closedQuote = true;
        } else if (buffer.isEmpty && !closedQuote) {
          inQuotes = true;
        } else {
          throw const FormatException('Unexpected quote in a CSV field.');
        }
      } else if (char == ',' && !inQuotes) {
        finishField();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        finishRow();
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
          i++;
        }
      } else {
        if (closedQuote) {
          throw const FormatException(
            'Unexpected text after a quoted CSV field.',
          );
        }
        buffer.write(char);
      }
    }
    if (inQuotes) {
      throw const FormatException('A quoted CSV field was not closed.');
    }
    if (buffer.isNotEmpty || row.isNotEmpty) finishRow();
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canExport = ref.watch(canProvider(BosPermission.reportsView));
    final canImportCustomers = ref.watch(
      canProvider(BosPermission.customersCreate),
    );
    final canImportSuppliers = ref.watch(
      canProvider(BosPermission.suppliersCreate),
    );
    final canRestore = ref.watch(canProvider(BosPermission.businessSettings));

    return Scaffold(
      appBar: AppBar(title: const Text('Import / Export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'EXPORT',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Download a CSV of any dataset for this business.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final dataset in _datasets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: Icon(
                      dataset.icon,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    dataset.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(dataset.description),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: canExport
                      ? () => _export(context, ref, dataset)
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'BACKUP & RESTORE',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Save a complete copy of this business, or restore one. Restore '
            'never overwrites existing records.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.save_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Back up',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Export everything'),
                    onTap: canExport ? () => _backup(context, ref) : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.restore_rounded,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Restore',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('From a backup'),
                    onTap: canRestore ? () => _restore(context, ref) : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'IMPORT',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bulk-add customers or suppliers from a CSV with name, phone, '
            'and notes columns. Duplicates by name are skipped. Financial '
            'ledgers are never imported — they stay auditable.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.people_outline_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              title: Text(
                'Customers',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('Import a customer list from CSV.'),
              trailing: const Icon(Icons.upload_outlined),
              onTap: canImportCustomers
                  ? () => _import(context, ref, 'customer')
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              title: Text(
                'Suppliers',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('Import a supplier list from CSV.'),
              trailing: const Icon(Icons.upload_outlined),
              onTap: canImportSuppliers
                  ? () => _import(context, ref, 'supplier')
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CSV BUILDERS — one per dataset, all scoped to the current business.
// ============================================================================

Future<String> _buildAccountsCsv(AppDatabase db) async {
  final accounts =
      await (db.select(db.accounts)
            ..where((a) => a.businessId.equals(kCurrentBusinessId))
            ..orderBy([(a) => OrderingTerm.asc(a.name)]))
          .get();

  return _csv([
    [
      'name',
      'type',
      'subtype',
      'payment_account',
      'starting_balance',
      'active',
    ],
    for (final a in accounts)
      [
        a.name,
        a.type,
        a.subtype ?? '',
        a.isPaymentAccount ? 'yes' : 'no',
        (a.startingBalance / 100).toStringAsFixed(2),
        a.isActive ? 'yes' : 'no',
      ],
  ]);
}

Future<String> _buildCategoriesCsv(AppDatabase db) async {
  final categories =
      await (db.select(db.categories)
            ..where((c) => c.businessId.equals(kCurrentBusinessId))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();
  final accounts = await (db.select(
    db.accounts,
  )..where((a) => a.businessId.equals(kCurrentBusinessId))).get();
  final accountNames = {for (final a in accounts) a.id: a.name};

  return _csv([
    ['name', 'type', 'posts_to', 'custom', 'active'],
    for (final c in categories)
      [
        c.name,
        c.txnType,
        accountNames[c.ledgerAccountId] ?? '',
        c.isCustom ? 'yes' : 'no',
        c.isActive ? 'yes' : 'no',
      ],
  ]);
}

Future<String> _buildCustomersCsv(AppDatabase db) async {
  final customers =
      await (db.select(db.customers)
            ..where((c) => c.businessId.equals(kCurrentBusinessId))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  return _csv([
    ['name', 'phone', 'notes', 'active'],
    for (final c in customers)
      [c.name, c.phone ?? '', c.notes ?? '', c.isActive ? 'yes' : 'no'],
  ]);
}

Future<String> _buildSuppliersCsv(AppDatabase db) async {
  final suppliers =
      await (db.select(db.suppliers)
            ..where((s) => s.businessId.equals(kCurrentBusinessId))
            ..orderBy([(s) => OrderingTerm.asc(s.name)]))
          .get();

  return _csv([
    ['name', 'phone', 'notes', 'active'],
    for (final s in suppliers)
      [s.name, s.phone ?? '', s.notes ?? '', s.isActive ? 'yes' : 'no'],
  ]);
}

Future<String> _buildIncomeCsv(AppDatabase db) async {
  final rows = await db
      .customSelect(
        '''
    SELECT
      i.txn_date, i.amount, i.status, i.description, i.notes, i.reference,
      cat.name AS category, c.name AS customer, a.name AS account
    FROM income_transactions i
    LEFT JOIN categories cat ON cat.id = i.category_id
    LEFT JOIN customers c ON c.id = i.customer_id
    LEFT JOIN accounts a ON a.id = i.payment_account_id
    WHERE i.business_id = ?
    ORDER BY i.txn_date DESC
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
        readsFrom: {
          db.incomeTransactions,
          db.categories,
          db.customers,
          db.accounts,
        },
      )
      .get();

  return _csv([
    [
      'date',
      'category',
      'customer',
      'account',
      'amount',
      'status',
      'reference',
      'description',
      'notes',
    ],
    for (final r in rows)
      [
        r.read<DateTime>('txn_date').toIso8601String(),
        r.read<String?>('category') ?? '',
        r.read<String?>('customer') ?? '',
        r.read<String?>('account') ?? '',
        (r.read<int>('amount') / 100).toStringAsFixed(2),
        r.read<String>('status'),
        r.read<String?>('reference') ?? '',
        r.read<String?>('description') ?? '',
        r.read<String?>('notes') ?? '',
      ],
  ]);
}

Future<String> _buildExpensesCsv(AppDatabase db) async {
  final rows = await db
      .customSelect(
        '''
    SELECT
      e.expense_date, e.amount, e.status, e.description, e.notes, e.reference,
      cat.name AS category, a.name AS account
    FROM expenses e
    LEFT JOIN categories cat ON cat.id = e.category_id
    LEFT JOIN accounts a ON a.id = e.payment_account_id
    WHERE e.business_id = ?
    ORDER BY e.expense_date DESC
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
        readsFrom: {db.expenses, db.categories, db.accounts},
      )
      .get();

  return _csv([
    [
      'date',
      'category',
      'account',
      'amount',
      'status',
      'reference',
      'description',
      'notes',
    ],
    for (final r in rows)
      [
        r.read<DateTime>('expense_date').toIso8601String(),
        r.read<String?>('category') ?? '',
        r.read<String?>('account') ?? '',
        (r.read<int>('amount') / 100).toStringAsFixed(2),
        r.read<String>('status'),
        r.read<String?>('reference') ?? '',
        r.read<String?>('description') ?? '',
        r.read<String?>('notes') ?? '',
      ],
  ]);
}

Future<String> _buildSuppliesCsv(AppDatabase db) async {
  final supplies =
      await (db.select(db.supplies)
            ..where((s) => s.businessId.equals(kCurrentBusinessId))
            ..orderBy([(s) => OrderingTerm.asc(s.name)]))
          .get();

  return _csv([
    [
      'name',
      'sku',
      'barcode',
      'current_stock',
      'stock_unit',
      'cost_per_base_unit',
      'current_price',
      'active',
    ],
    for (final s in supplies)
      [
        s.name,
        s.sku ?? '',
        s.barcode ?? '',
        s.currentStock.toString(),
        s.stockUnit,
        (s.costPerBaseUnit / 100).toStringAsFixed(4),
        (s.currentPrice / 100).toStringAsFixed(2),
        s.isActive ? 'yes' : 'no',
      ],
  ]);
}

Future<String> _buildJournalCsv(AppDatabase db) async {
  final rows = await db
      .customSelect(
        '''
    SELECT
      j.entry_date, j.source_type, j.source_id, j.description,
      l.account_id, a.name AS account_name, l.debit, l.credit
    FROM journal_entries j
    INNER JOIN ledger_lines l ON l.journal_entry_id = j.id
    INNER JOIN accounts a ON a.id = l.account_id
    WHERE j.business_id = ?
    ORDER BY j.entry_date DESC, j.id, l.debit DESC
    ''',
        variables: [Variable.withString(kCurrentBusinessId)],
        readsFrom: {db.journalEntries, db.ledgerLines, db.accounts},
      )
      .get();

  return _csv([
    [
      'date',
      'source_type',
      'source_id',
      'description',
      'account',
      'debit',
      'credit',
    ],
    for (final r in rows)
      [
        r.read<DateTime>('entry_date').toIso8601String(),
        r.read<String>('source_type'),
        r.read<String?>('source_id') ?? '',
        r.read<String?>('description') ?? '',
        r.read<String>('account_name'),
        (r.read<int>('debit') / 100).toStringAsFixed(2),
        (r.read<int>('credit') / 100).toStringAsFixed(2),
      ],
  ]);
}
