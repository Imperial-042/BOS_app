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

  /// Finer-grained classification, mainly for asset/liability accounts so
  /// the Cashflow "balance sheet" view can total and separate them:
  /// 'current_asset'|'non_current_asset' for assets, and
  /// 'trade_payable'|'loan_payable'|'other_payable' for liabilities.
  /// Null for cash/payment accounts, income, expense, and equity.
  TextColumn get subtype => text().nullable()();
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

  /// Null when [isOnCredit] is true — a pending payment the business
  /// hasn't actually received into a cash/bank/e-wallet account yet.
  TextColumn get paymentAccountId =>
      text().nullable().references(Accounts, #id)();

  /// True when the customer's payment is only a pending promise (a
  /// credit they still owe), not yet received into a real account.
  BoolColumn get isOnCredit => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().withDefault(const Constant('completed'))();
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

  /// Null when [isOnCredit] is true — a pending payment the business
  /// hasn't actually paid out of a cash/bank/e-wallet account yet.
  TextColumn get paymentAccountId =>
      text().nullable().references(Accounts, #id)();

  /// True when this payment is only a pending promise to pay (e.g. a
  /// credit the supplier is extending), not yet paid from a real account.
  BoolColumn get isOnCredit => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().withDefault(const Constant('completed'))();
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
  RealColumn get currentStock =>
      real().withDefault(const Constant(0))(); // in stockUnit
  RealColumn get lowStockThreshold => real().nullable()();
  TextColumn get stockUnit =>
      text().withDefault(const Constant('piece'))(); // g, kg, ml, L, piece...
  TextColumn get purchaseUnit => text().nullable()(); // "pack", "sack",
  // "case", "bottle"
  RealColumn get unitsPerPurchase => real().withDefault(
    const Constant(1),
  )(); // e.g. 1 pack =      // 100 (grams)
  RealColumn get costPerBaseUnit =>
      real().withDefault(const Constant(0))(); // weighted-average
  // cost, in CENTS,
  // per stockUnit

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
  RealColumn get purchaseQuantity => // how many purchase
      real().withDefault(const Constant(1))(); // units bought
  // (e.g. 10 packs)
  RealColumn get unitsPerPurchaseAtTime => // snapshot of the
      real().withDefault(const Constant(1))(); // conversion used

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

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();

  /// The unit this product is produced/sold in — "cup", "serving",
  /// "piece", "bottle", etc. This is what recipe yields and sale
  /// quantities are expressed in.
  TextColumn get unit => text()();
  IntColumn get sellPrice => integer().nullable()(); // cents, optional
  /// False for intermediate-only components (e.g. "Espresso Base")
  /// that exist purely to be used inside other recipes and are never
  /// sold directly to a customer.
  BoolColumn get isSellable => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Recipes extends Table {
  TextColumn get id => text()();

  /// The product this recipe produces. One product has at most one
  /// active recipe in this design — if you need recipe versioning
  /// later, add a `version`/`isActive` pair here.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// How many units of `productId` ONE batch of this recipe yields.
  /// E.g. a batch that makes 4 cups of syrup at once = 4.
  RealColumn get yieldQuantity => real().withDefault(const Constant(1))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class RecipeComponents extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();

  /// 'supply' | 'product' — a leaf raw material, or a nested
  /// sub-recipe (e.g. Espresso Base used inside Spanish Latte).
  TextColumn get componentType => text()();
  TextColumn get supplyId => text().nullable().references(Supplies, #id)();
  TextColumn get componentProductId =>
      text().nullable().references(Products, #id)();

  /// Quantity of this component needed per `yieldQuantity` of the
  /// recipe's output (NOT per single output unit — divide by
  /// yieldQuantity to get the per-unit requirement).
  RealColumn get quantityRequired => real()();

  /// The unit quantityRequired is expressed in — can differ from the
  /// supply's stockUnit (e.g. recipe says "18 g", stock is tracked
  /// in "kg") as long as they're the same dimension (mass/volume/count).
  TextColumn get unit => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class InventoryMovements extends Table {
  TextColumn get id => text()();
  TextColumn get supplyId => text().references(Supplies, #id)();

  /// 'production_consumption' | 'manual_adjustment' | 'restock'
  TextColumn get movementType => text()();
  TextColumn get unit => text()();

  /// Negative = consumed, positive = added. Stored in the supply's
  /// stockUnit at the time of the movement.
  RealColumn get quantity => real()();
  TextColumn get referenceType => text().nullable()(); // e.g. 'product_sale'
  TextColumn get referenceId => text().nullable()();
  DateTimeColumn get movementDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();

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
    Products,
    Recipes,
    RecipeComponents,
    InventoryMovements,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // NEW — for tests
  // AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 12;

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
      if (from < 8) {
        await m.addColumn(supplies, supplies.currentStock);
        await m.addColumn(supplies, supplies.stockUnit);

        await m.createTable(products);
        await m.createTable(recipes);
        await m.createTable(recipeComponents);
        await m.createTable(inventoryMovements);
      }
      if (from < 9) {
        await m.addColumn(inventoryMovements, inventoryMovements.unit);
      }
      if (from < 10) {
        // currentStock changes type (Int -> Real) — safest path is a
        // rename + recreate rather than an in-place type change:
        await m.addColumn(supplies, supplies.costPerBaseUnit);
        await m.addColumn(supplies, supplies.purchaseUnit);
        await m.addColumn(supplies, supplies.unitsPerPurchase);
        await m.addColumn(
          supplyPriceHistory,
          supplyPriceHistory.purchaseQuantity,
        );
        await m.addColumn(
          supplyPriceHistory,
          supplyPriceHistory.unitsPerPurchaseAtTime,
        );
        // currentStock's Int->Real change: if you're early in development
        // (no real user data to preserve), simplest is to bump schemaVersion
        // and let onCreate rebuild fresh. If you have real data, write an
        // explicit column-copy migration instead — ask if you need that.
      }
      if (from < 11) {
        await m.addColumn(accounts, accounts.subtype);
        // Backfill subtype on the accounts seeded before this column existed,
        // so existing businesses' Cashflow Assets/Liabilities sections group
        // correctly instead of everything landing under "Other".
        await customStatement(
          "UPDATE accounts SET subtype = 'current_asset' "
          "WHERE type = 'asset' AND subtype IS NULL AND "
          "(id LIKE 'acc_cash_%' OR id LIKE 'acc_bank_%' OR "
          "id LIKE 'acc_ewallet_%' OR id LIKE 'acc_ar_%')",
        );
        await customStatement(
          "UPDATE accounts SET subtype = 'trade_payable' "
          "WHERE type = 'liability' AND subtype IS NULL AND id LIKE 'acc_ap_%'",
        );
      }
      if (from < 12) {
        // payment_account_id needs to become nullable (an on-credit/pending
        // payment has no real account yet) — SQLite can't relax a NOT NULL
        // constraint in place, so recreate each table from the current
        // Dart definition and copy the existing rows across.
        await customStatement(
          'ALTER TABLE payable_payments RENAME TO payable_payments_old',
        );
        await m.createTable(payablePayments);
        await customStatement('''
          INSERT INTO payable_payments
            (id, business_id, supplier_id, amount, payment_account_id,
             is_on_credit, status, payment_date, notes, created_at)
          SELECT id, business_id, supplier_id, amount, payment_account_id,
                 0, 'completed', payment_date, notes, created_at
          FROM payable_payments_old
        ''');
        await customStatement('DROP TABLE payable_payments_old');

        await customStatement(
          'ALTER TABLE receivable_payments RENAME TO receivable_payments_old',
        );
        await m.createTable(receivablePayments);
        await customStatement('''
          INSERT INTO receivable_payments
            (id, business_id, customer_id, amount, payment_account_id,
             is_on_credit, status, payment_date, notes, created_at)
          SELECT id, business_id, customer_id, amount, payment_account_id,
                 0, 'completed', payment_date, notes, created_at
          FROM receivable_payments_old
        ''');
        await customStatement('DROP TABLE receivable_payments_old');
      }
    },
  );

  /// Seeds the default chart of accounts + starter categories for a newly
  /// created business. Call this once, right after inserting the Businesses row.
  Future<void> seedDefaultsForBusiness(String businessId) async {
    final defaultAccounts = <(String, String, String, bool, String?)>[
      ('acc_cash_$businessId', 'Cash on Hand', 'asset', true, null),
      ('acc_bank_$businessId', 'Bank Account', 'asset', true, null),
      ('acc_ewallet_$businessId', 'E-Wallet', 'asset', true, null),
      (
        'acc_ar_$businessId',
        'Accounts Receivable',
        'asset',
        false,
        'current_asset',
      ),
      (
        'acc_ap_$businessId',
        'Accounts Payable',
        'liability',
        false,
        'trade_payable',
      ),
      ('acc_equity_$businessId', "Owner's Equity", 'equity', false, null),
      ('acc_sales_$businessId', 'Sales Income', 'income', false, null),
      ('acc_other_inc_$businessId', 'Other Income', 'income', false, null),
      (
        'acc_inv_exp_$businessId',
        'Inventory/Stock Expense',
        'expense',
        false,
        null,
      ),
      (
        'acc_labor_exp_$businessId',
        'Salary/Labor Expense',
        'expense',
        false,
        null,
      ),
      ('acc_rent_exp_$businessId', 'Rent Expense', 'expense', false, null),
      ('acc_util_exp_$businessId', 'Utilities Expense', 'expense', false, null),
      (
        'acc_transport_exp_$businessId',
        'Transportation Expense',
        'expense',
        false,
        null,
      ),
      (
        'acc_supplies_exp_$businessId',
        'Supplies Expense',
        'expense',
        false,
        null,
      ),
      ('acc_other_exp_$businessId', 'Other Expense', 'expense', false, null),
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
                subtype: Value(a.$5),
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
