// lib/features/transactions/presentation/screens/categories_page.dart
//
// Administration -> Categories. Income and expense categories mapped to
// their GL accounts. Custom categories can be created, renamed, linked to
// any same-type GL account, deactivated, or deleted when unused.

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/authorization_service.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import 'transaction_page.dart' show kCurrentBusinessId, ledgerVersionProvider;

class CategoryWithUsage {
  final Category category;
  final String ledgerAccountName;
  final int transactionCount;
  const CategoryWithUsage({
    required this.category,
    required this.ledgerAccountName,
    required this.transactionCount,
  });
}

final categoriesWithUsageProvider =
    FutureProvider.family<List<CategoryWithUsage>, String>((
      ref,
      txnType,
    ) async {
      ref.watch(ledgerVersionProvider);
      final db = ref.watch(databaseProvider);

      final categories =
          await (db.select(db.categories)
                ..where(
                  (c) =>
                      c.businessId.equals(kCurrentBusinessId) &
                      c.txnType.equals(txnType),
                )
                ..orderBy([(c) => OrderingTerm.asc(c.name)]))
              .get();

      final accounts = await (db.select(
        db.accounts,
      )..where((a) => a.businessId.equals(kCurrentBusinessId))).get();
      final accountNames = {for (final a in accounts) a.id: a.name};

      final results = <CategoryWithUsage>[];
      for (final category in categories) {
        final row = await db
            .customSelect(
              txnType == 'income'
                  ? 'SELECT COUNT(*) AS c FROM income_transactions WHERE category_id = ?'
                  : 'SELECT COUNT(*) AS c FROM expenses WHERE category_id = ?',
              variables: [Variable.withString(category.id)],
            )
            .getSingle();

        results.add(
          CategoryWithUsage(
            category: category,
            ledgerAccountName:
                accountNames[category.ledgerAccountId] ?? 'Unknown account',
            transactionCount: row.read<int>('c'),
          ),
        );
      }
      return results;
    });

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canProvider(BosPermission.financeEdit));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Income'),
              Tab(text: 'Expenses'),
            ],
          ),
          actions: [
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'New category',
                onPressed: () =>
                    _showCategoryEditor(context, ref, 'expense', null),
              ),
          ],
        ),
        body: TabBarView(
          children: [
            _CategoryList(txnType: 'income', canEdit: canEdit),
            _CategoryList(txnType: 'expense', canEdit: canEdit),
          ],
        ),
      ),
    );
  }

  void _showCategoryEditor(
    BuildContext context,
    WidgetRef ref,
    String txnType,
    CategoryWithUsage? existing,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _CategoryEditorSheet(txnType: txnType, existing: existing),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.txnType, required this.canEdit});

  final String txnType;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesWithUsageProvider(txnType));

    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const Center(child: Text('Unable to load categories.')),
      data: (categories) {
        final active = categories
            .where((entry) => entry.category.isActive)
            .toList();
        final inactive = categories
            .where((entry) => !entry.category.isActive)
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (active.isEmpty && inactive.isEmpty) const _EmptyCategories(),
            _CategorySection(
              title: 'Active',
              entries: active,
              canEdit: canEdit,
              txnType: txnType,
            ),
            if (inactive.isNotEmpty)
              _CategorySection(
                title: 'Archived',
                entries: inactive,
                canEdit: canEdit,
                txnType: txnType,
              ),
          ],
        );
      },
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No categories yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.entries,
    required this.canEdit,
    required this.txnType,
  });

  final String title;
  final List<CategoryWithUsage> entries;
  final bool canEdit;
  final String txnType;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '$title (${entries.length})'.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: CircleAvatar(
                      backgroundColor: entries[i].category.isCustom
                          ? theme.colorScheme.tertiaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        entries[i].category.isCustom
                            ? Icons.edit_note_rounded
                            : Icons.label_outline_rounded,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      entries[i].category.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Posts to ${entries[i].ledgerAccountName}'
                      ' · ${entries[i].transactionCount} txn',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: canEdit
                        ? const Icon(Icons.chevron_right_rounded)
                        : null,
                    onTap: canEdit
                        ? () {
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (_) => _CategoryEditorSheet(
                                txnType: txnType,
                                existing: entries[i],
                              ),
                            );
                          }
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryEditorSheet extends ConsumerStatefulWidget {
  const _CategoryEditorSheet({required this.txnType, this.existing});

  final String txnType;
  final CategoryWithUsage? existing;

  @override
  ConsumerState<_CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<_CategoryEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _ledgerAccountId;
  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.existing != null;
  bool get _hasUsage => (widget.existing?.transactionCount ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?.category.name ?? '',
    );
    _ledgerAccountId = widget.existing?.category.ledgerAccountId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ledgerAccountId == null) {
      setState(() => _error = 'Pick the account this category posts to.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final db = ref.read(databaseProvider);
    final audit = ref.read(auditLogServiceProvider);
    final name = _nameController.text.trim();

    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.financeEdit, businessId: kCurrentBusinessId);

      await db.transaction(() async {
        if (_isEditing) {
          final before = widget.existing!.category;
          await (db.update(
            db.categories,
          )..where((c) => c.id.equals(before.id))).write(
            CategoriesCompanion(
              name: Value(name),
              ledgerAccountId: Value(_ledgerAccountId!),
            ),
          );
          await audit.record(
            AuditEvent(
              businessId: kCurrentBusinessId,
              module: AuditModule.finance,
              actionType: AuditActionType.update,
              action: 'finance.category_updated',
              entityType: 'category',
              entityId: before.id,
              entityLabel: name,
              before: {
                'name': before.name,
                'ledgerAccountId': before.ledgerAccountId,
              },
              after: {'name': name, 'ledgerAccountId': _ledgerAccountId},
              details: {'txnType': widget.txnType},
            ),
          );
        } else {
          final id = const Uuid().v4();
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  id: id,
                  businessId: kCurrentBusinessId,
                  name: name,
                  txnType: widget.txnType,
                  ledgerAccountId: _ledgerAccountId!,
                  isCustom: const Value(true),
                ),
              );
          await audit.record(
            AuditEvent(
              businessId: kCurrentBusinessId,
              module: AuditModule.finance,
              actionType: AuditActionType.create,
              action: 'finance.category_created',
              entityType: 'category',
              entityId: id,
              entityLabel: name,
              after: {
                'name': name,
                'txnType': widget.txnType,
                'ledgerAccountId': _ledgerAccountId,
              },
            ),
          );
        }
      });

      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } on PermissionDeniedException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _archive() async {
    final db = ref.read(databaseProvider);
    final audit = ref.read(auditLogServiceProvider);
    final category = widget.existing!.category;

    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.financeEdit, businessId: kCurrentBusinessId);

      await db.transaction(() async {
        await (db.update(db.categories)..where((c) => c.id.equals(category.id)))
            .write(const CategoriesCompanion(isActive: Value(false)));
        await audit.record(
          AuditEvent(
            businessId: kCurrentBusinessId,
            module: AuditModule.finance,
            actionType: AuditActionType.delete,
            action: 'finance.category_archived',
            entityType: 'category',
            entityId: category.id,
            entityLabel: category.name,
            before: {'isActive': true},
            after: {'isActive': false},
          ),
        );
      });

      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } on PermissionDeniedException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete() async {
    final db = ref.read(databaseProvider);
    final audit = ref.read(auditLogServiceProvider);
    final category = widget.existing!.category;

    try {
      ref
          .read(authorizationServiceProvider)
          .require(BosPermission.financeEdit, businessId: kCurrentBusinessId);

      await db.transaction(() async {
        final used = await db
            .customSelect(
              widget.txnType == 'income'
                  ? 'SELECT COUNT(*) AS c FROM income_transactions WHERE category_id = ?'
                  : 'SELECT COUNT(*) AS c FROM expenses WHERE category_id = ?',
              variables: [Variable.withString(category.id)],
            )
            .getSingle();
        if (used.read<int>('c') > 0) {
          throw StateError(
            'This category is now used by transactions. Archive it instead.',
          );
        }

        await (db.delete(
          db.categories,
        )..where((c) => c.id.equals(category.id))).go();
        await audit.record(
          AuditEvent(
            businessId: kCurrentBusinessId,
            module: AuditModule.finance,
            actionType: AuditActionType.delete,
            action: 'finance.category_deleted',
            entityType: 'category',
            entityId: category.id,
            entityLabel: category.name,
            before: {
              'name': category.name,
              'txnType': category.txnType,
              'ledgerAccountId': category.ledgerAccountId,
            },
          ),
        );
      });

      ref.read(ledgerVersionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop();
    } on PermissionDeniedException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = ref.watch(databaseProvider);
    // A category can post to ANY active GL account (e.g. "Additional
    // Capital" is an income category posting to an equity account), so the
    // dropdown must not be filtered by the category's txn type — otherwise
    // the category's current account isn't in the list and the
    // DropdownButtonFormField assertion fails.
    final accountsFuture = db.select(db.accounts)
      ..where(
        (a) =>
            a.businessId.equals(kCurrentBusinessId) & a.isActive.equals(true),
      );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? 'Edit category' : 'New ${widget.txnType} category',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Category name',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a category name.'
                    : null,
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<Account>>(
                future: accountsFuture.get(),
                builder: (context, snapshot) {
                  final accounts = snapshot.data ?? const <Account>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _ledgerAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Posts to account',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _ledgerAccountId = value),
                    validator: (value) =>
                        value == null ? 'Pick an account.' : null,
                  );
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Text(_isEditing ? 'Save changes' : 'Create category'),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 8),
                if (_hasUsage)
                  OutlinedButton.icon(
                    onPressed: _archive,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive category'),
                  )
                else
                  TextButton.icon(
                    onPressed: _delete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      'Delete category',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
