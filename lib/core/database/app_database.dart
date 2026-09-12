// lib/core/database/app_database.dart
//
// BOS local database, built with `drift`.
//
// Setup (add to pubspec.yaml):
//   dependencies:
//     drift: ^2.20.0
//     sqlite3_flutter_libs: ^0.5.0
//     path_provider: ^2.1.0
//     path: ^1.9.0
//   dev_dependencies:
//     drift_dev: ^2.20.0
//     build_runner: ^2.4.0
//
// After editing this file, generate the .g.dart part with:
//   dart run build_runner build --delete-conflicting-outputs

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ============================================================
// 0. TENANT ROOT
// ============================================================

class Businesses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get ownerName => text().nullable()();
  TextColumn get managerName => text().nullable()();
  TextColumn get businessCategory => text().nullable()();
  TextColumn get addressCountry => text().nullable()();
  TextColumn get addressProvince => text().nullable()();
  TextColumn get addressCity => text().nullable()();
  TextColumn get addressBarangay => text().nullable()();
  TextColumn get addressZipCode => text().nullable()();
  IntColumn get startingCapital => integer().withDefault(const Constant(0))();
  TextColumn get startingCapitalAccountId => text().nullable()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  TextColumn get currency => text().withDefault(const Constant('PHP'))();
  TextColumn get ownerUserId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 1. LEDGER CORE
// ============================================================

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get type => text().withLength(
    min: 1,
    max: 20,
  )(); // asset|liability|equity|income|expense
  BoolColumn get isPaymentAccount =>
      boolean().withDefault(const Constant(false))();
  IntColumn get startingBalance => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class JournalEntries extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get description => text().nullable()();
  TextColumn get sourceType => text()(); // 'income'|'expense'|'transfer'|...
  TextColumn get sourceId => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('completed'))(); // posted-equivalent
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class LedgerLines extends Table {
  TextColumn get id => text()();
  TextColumn get journalEntryId =>
      text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get debit => integer().withDefault(const Constant(0))();
  IntColumn get credit => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 2. CATEGORIES
// ============================================================

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get txnType => text()(); // 'income' | 'expense'
  TextColumn get ledgerAccountId => text().references(Accounts, #id)();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 3. CUSTOMERS & RECEIVABLES
// ============================================================

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class IncomeTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  DateTimeColumn get txnDate => dateTime()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get amount => integer()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get paymentAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('completed'))(); // pending|completed
  TextColumn get journalEntryId =>
      text().nullable().references(JournalEntries, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ReceivablePayments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get amount => integer()();
  TextColumn get paymentAccountId => text().references(Accounts, #id)();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 4. SUPPLIERS & PAYABLES
// ============================================================

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class SupplierPurchases extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  DateTimeColumn get purchaseDate => dateTime()();
  IntColumn get amount => integer()();
  BoolColumn get isOnCredit => boolean().withDefault(const Constant(false))();
  TextColumn get paymentAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class PayablePayments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  IntColumn get amount => integer()();
  TextColumn get paymentAccountId => text().references(Accounts, #id)();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 5. EXPENSES
// ============================================================

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  DateTimeColumn get expenseDate => dateTime()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get amount => integer()();
  TextColumn get paymentAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get receiptPhotoPath => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('completed'))(); // pending|completed
  TextColumn get journalEntryId =>
      text().nullable().references(JournalEntries, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 6. SUPPLIES PRICE LIST + SHOPPING CART
// ============================================================

class Supplies extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  RealColumn get unitQuantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get lastStoreName => text().nullable()();
  TextColumn get lastStoreAddress => text().nullable()();
  IntColumn get currentPrice => integer()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class SupplyPriceHistory extends Table {
  TextColumn get id => text()();
  TextColumn get supplyId =>
      text().references(Supplies, #id, onDelete: KeyAction.cascade)();
  IntColumn get price => integer()();
  TextColumn get storeName => text()();
  TextColumn get storeAddress => text().nullable()();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  DateTimeColumn get recordedDate => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ShoppingCarts extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  DateTimeColumn get cartDate => dateTime()();
  TextColumn get storeName => text().nullable()();
  TextColumn get storeAddress => text().nullable()();
  IntColumn get totalAmount => integer()();
  TextColumn get expenseId => text().nullable().references(Expenses, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ShoppingCartItems extends Table {
  TextColumn get id => text()();
  TextColumn get cartId =>
      text().references(ShoppingCarts, #id, onDelete: KeyAction.cascade)();
  TextColumn get supplyId => text().nullable().references(Supplies, #id)();
  TextColumn get itemName => text()();
  TextColumn get brand => text().nullable()();
  RealColumn get unitQuantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  IntColumn get unitPrice => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  IntColumn get lineTotal => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 7. ACCOUNT TRANSFERS
// ============================================================

class AccountTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get fromAccountId => text().references(Accounts, #id)();
  TextColumn get toAccountId => text().references(Accounts, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get transferDate => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// DATABASE CLASS
// ============================================================

@DriftDatabase(
  tables: [
    Businesses,
    Accounts,
    JournalEntries,
    LedgerLines,
    Categories,
    Customers,
    IncomeTransactions,
    ReceivablePayments,
    Suppliers,
    SupplierPurchases,
    PayablePayments,
    Expenses,
    Supplies,
    SupplyPriceHistory,
    ShoppingCarts,
    ShoppingCartItems,
    AccountTransfers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // NEW — for tests
  // AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(supplies, supplies.brand);
        await m.addColumn(supplies, supplies.unitQuantity);
        await m.addColumn(supplies, supplies.lastStoreName);
        await m.addColumn(supplies, supplies.lastStoreAddress);
        await m.addColumn(shoppingCartItems, shoppingCartItems.brand);
        await m.addColumn(shoppingCartItems, shoppingCartItems.unitQuantity);
        await m.addColumn(shoppingCartItems, shoppingCartItems.unit);
      }
      if (from < 3) {
        await m.addColumn(businesses, businesses.ownerName);
        await m.addColumn(businesses, businesses.businessCategory);
      }
      if (from < 4) {
        await m.addColumn(businesses, businesses.addressCountry);
        await m.addColumn(businesses, businesses.addressProvince);
        await m.addColumn(businesses, businesses.addressCity);
        await m.addColumn(businesses, businesses.addressZipCode);
        await m.addColumn(businesses, businesses.startingCapital);
        await m.addColumn(businesses, businesses.startingCapitalAccountId);
      }
      if (from < 5) {
        await m.addColumn(businesses, businesses.isCurrent);
      }
      if (from < 6) {
        await m.addColumn(businesses, businesses.managerName);
      }
      if (from < 7) {
        await m.addColumn(businesses, businesses.addressBarangay);
      }
    },
  );

  /// Seeds the default chart of accounts + starter categories for a newly
  /// created business. Call this once, right after inserting the Businesses row.
  Future<void> seedDefaultsForBusiness(String businessId) async {
    final defaultAccounts = <(String, String, String, bool)>[
      ('acc_cash_$businessId', 'Cash on Hand', 'asset', true),
      ('acc_bank_$businessId', 'Bank Account', 'asset', true),
      ('acc_ewallet_$businessId', 'E-Wallet', 'asset', true),
      ('acc_ar_$businessId', 'Accounts Receivable', 'asset', false),
      ('acc_ap_$businessId', 'Accounts Payable', 'liability', false),
      ('acc_equity_$businessId', "Owner's Equity", 'equity', false),
      ('acc_sales_$businessId', 'Sales Income', 'income', false),
      ('acc_other_inc_$businessId', 'Other Income', 'income', false),
      ('acc_inv_exp_$businessId', 'Inventory/Stock Expense', 'expense', false),
      ('acc_labor_exp_$businessId', 'Salary/Labor Expense', 'expense', false),
      ('acc_rent_exp_$businessId', 'Rent Expense', 'expense', false),
      ('acc_util_exp_$businessId', 'Utilities Expense', 'expense', false),
      (
        'acc_transport_exp_$businessId',
        'Transportation Expense',
        'expense',
        false,
      ),
      ('acc_supplies_exp_$businessId', 'Supplies Expense', 'expense', false),
      ('acc_other_exp_$businessId', 'Other Expense', 'expense', false),
    ];

    await batch((b) {
      b.insertAll(
        accounts,
        defaultAccounts
            .map(
              (a) => AccountsCompanion.insert(
                id: a.$1,
                businessId: businessId,
                name: a.$2,
                type: a.$3,
                isPaymentAccount: Value(a.$4),
              ),
            )
            .toList(),
      );
    });

    final defaultCategories = <(String, String, String)>[
      ('Sale', 'income', 'acc_sales_$businessId'),
      ('Service', 'income', 'acc_sales_$businessId'),
      ('Additional Capital', 'income', 'acc_equity_$businessId'),
      ('Other Income', 'income', 'acc_other_inc_$businessId'),
      ('Inventory', 'expense', 'acc_inv_exp_$businessId'),
      ('Supplies', 'expense', 'acc_supplies_exp_$businessId'),
      ('Labor', 'expense', 'acc_labor_exp_$businessId'),
      ('Transportation', 'expense', 'acc_transport_exp_$businessId'),
      ('Rent', 'expense', 'acc_rent_exp_$businessId'),
      ('Utilities', 'expense', 'acc_util_exp_$businessId'),
      ('Other', 'expense', 'acc_other_exp_$businessId'),
    ];

    await batch((b) {
      b.insertAll(
        categories,
        defaultCategories
            .map(
              (c) => CategoriesCompanion.insert(
                id: '${c.$1.toLowerCase().replaceAll(' ', '_')}_$businessId',
                businessId: businessId,
                name: c.$1,
                txnType: c.$2,
                ledgerAccountId: c.$3,
              ),
            )
            .toList(),
      );
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'bos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
