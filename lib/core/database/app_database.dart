// lib/core/database/app_database.dart
//
// BOS local database, built with `drift`.
//
// After editing this file, generate the .g.dart part with:
//   dart run build_runner build --delete-conflicting-outputs

import 'dart:io';

import 'package:bos_application/core/audit/audit_schema_guard.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_change_log.dart';

part 'app_database.g.dart';

// ============================================================
// 0. TENANT ROOT
// ============================================================

class Businesses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get legalName => text().nullable()();
  TextColumn get ownerName => text().nullable()();
  TextColumn get managerName => text().nullable()();

  /// Primary operating model: retailer|wholesaler|distributor|manufacturer|
  /// service_provider (extensible — new ids need no schema change).
  TextColumn get businessType => text().nullable()();

  /// Industry the business operates in (e.g. 'Grocery', 'Automotive repair').
  /// Separate from [businessType]: a Manufacturer can be in food, a Service
  /// provider in automotive. Kept distinct from the legacy
  /// [businessCategory] onboarding field; new code reads/writes both.
  TextColumn get industry => text().nullable()();
  TextColumn get businessCategory => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get addressCountry => text().nullable()();
  TextColumn get addressProvince => text().nullable()();
  TextColumn get addressCity => text().nullable()();
  TextColumn get addressBarangay => text().nullable()();
  TextColumn get addressZipCode => text().nullable()();
  IntColumn get startingCapital => integer().withDefault(const Constant(0))();
  TextColumn get startingCapitalAccountId => text().nullable()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  TextColumn get currency => text().withDefault(const Constant('PHP'))();

  /// IANA timezone name, e.g. 'Asia/Manila' — maps cleanly to timestamptz
  /// handling when this syncs to Supabase later.
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Manila'))();
  TextColumn get logoPath => text().nullable()();

  /// Archived businesses keep their history but can't be switched into.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get ownerUserId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-business on/off state for a BOS module (management, finance, pos…).
/// No row = the module uses its default (enabled). Separate from user
/// permissions: a module can be enabled for the business while a given
/// member still can't open it because of their role.
class BusinessModuleConfigs extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get moduleId => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get configVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

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
  TextColumn get branchId => text().nullable()();
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
// 2. CATEGORIES (transaction categories — income/expense)
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
  TextColumn get address => text().nullable()();

  /// Tax Identification Number (optional), stored as 000-000-000-000.
  TextColumn get tin => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class IncomeTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();
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
  TextColumn get branchId => text().nullable()();
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
  RealColumn get minimumStock => real().withDefault(const Constant(0))();

  RealColumn get maximumStock => real().withDefault(const Constant(0))();
  RealColumn get lowStockThreshold => real().nullable()();
  TextColumn get stockUnit =>
      text().withDefault(const Constant('piece'))(); // g, kg, ml, L, piece...
  TextColumn get purchaseUnit => text().nullable()(); // "pack", "sack", ...
  RealColumn get unitsPerPurchase => real().withDefault(const Constant(1))();
  RealColumn get costPerBaseUnit =>
      real().withDefault(const Constant(0))(); // weighted-average, cents

  /// Internal item code / SKU. Normalised to upper-case by
  /// SupplyCatalogService. Unique per business when present.
  TextColumn get sku => text().nullable()();

  /// Scanned barcode (EAN/UPC/QR payload). Unique per business when
  /// present.
  TextColumn get barcode => text().nullable()();

  /// Reuses the same per-business category list as products, so a
  /// category like "Dairy" works for both a raw supply and a
  /// finished item without maintaining two separate lists.
  TextColumn get categoryId =>
      text().nullable().references(ProductCategories, #id)();

  /// True when this supply is priced by variable weight (produce, meat,
  /// bulk bins) — the purchase unit itself IS a weight unit (g/kg), so
  /// the amount bought is a free-form decimal entered per purchase
  /// (0.5 kg, 1.25 kg), not a fixed pack size.
  BoolColumn get isSoldByWeight =>
      boolean().withDefault(const Constant(false))();

  /// Local file path for the item photo — reference only, not bytes.
  TextColumn get imagePath => text().nullable()();

  /// Manual display order in the price catalog.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

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
  RealColumn get purchaseQuantity => real().withDefault(const Constant(1))();
  RealColumn get unitsPerPurchaseAtTime =>
      real().withDefault(const Constant(1))();

  /// THE FIX: previously, reversing a checkout matched rows by
  /// supplyId + price + quantity + date, which collides whenever the
  /// same supply is bought twice in one day at the same price and
  /// quantity — deleting one checkout could reverse the wrong row.
  /// Matching by this exact ID instead makes reversal unambiguous.
  TextColumn get shoppingCartItemId => text().nullable().references(
    ShoppingCartItems,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @override
  Set<Column> get primaryKey => {id};
}

class ShoppingCarts extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();
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

  TextColumn get supplyId => text().nullable().references(
    Supplies,
    #id,
    onDelete: KeyAction.setNull,
  )();

  TextColumn get itemName => text()();
  TextColumn get brand => text().nullable()();
  RealColumn get unitQuantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  IntColumn get unitPrice => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  BoolColumn get isWeighted => boolean().withDefault(const Constant(false))();
  RealColumn get weightQuantity => real().nullable()();
  RealColumn get stockUnitsPerUnit => real().withDefault(const Constant(1))();
  IntColumn get grossLineTotal => integer().withDefault(const Constant(0))();
  TextColumn get discountType => text().withDefault(const Constant('none'))();
  RealColumn get discountValue => real().withDefault(const Constant(0))();
  IntColumn get discountAmount => integer().withDefault(const Constant(0))();
  IntColumn get lineTotal => integer()();

  /// Original stored unit price (cents) this line's price derives from.
  /// Null for rows written before v31 — falls back to [unitPrice].
  IntColumn get originalUnitPrice => integer().nullable()();

  /// Conversion factor of the unit [originalUnitPrice] is for, in stock
  /// units per unit. Null falls back to [stockUnitsPerUnit].
  RealColumn get originalStockUnitsPerUnit => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SupplyUnitConversions extends Table {
  TextColumn get supplyId =>
      text().references(Supplies, #id, onDelete: KeyAction.cascade)();
  TextColumn get unitName => text()();

  /// Number of this unit in one stock unit. For example, 10 pieces per case.
  RealColumn get unitsPerStockUnit => real()();

  @override
  Set<Column> get primaryKey => {supplyId, unitName};
}

// ============================================================
// 7. ACCOUNT TRANSFERS
// ============================================================

class AccountTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();

  /// The account money leaves. The [ReferenceName] disambiguates the two
  /// back-references that would otherwise both be named `accountTransfersRefs`
  /// on `$AccountsTable`, causing a build-time warning.
  @ReferenceName('transfersFrom')
  TextColumn get fromAccountId => text().references(Accounts, #id)();

  @ReferenceName('transfersTo')
  TextColumn get toAccountId => text().references(Accounts, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get transferDate => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 8. PRODUCT MASTER
// ============================================================

/// Reusable, per-business product categories ("Drinks", "Pastries",
/// "Merchandise"). Kept separate from [Categories], which classifies
/// ledger transactions, not sellable items.
class ProductCategories extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// Optional "#RRGGBB" tint so the catalog can colour-code chips.
  TextColumn get colorHex => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();

  /// Internal product code / SKU. Normalised to upper-case by
  /// ProductCatalogService. Unique per business when present —
  /// enforced by a partial unique index (NULLs stay distinct).
  TextColumn get sku => text().nullable()();

  /// Scanned barcode (EAN/UPC/QR payload). Unique per business when
  /// present, same partial-index treatment as [sku].
  TextColumn get barcode => text().nullable()();

  TextColumn get categoryId =>
      text().nullable().references(ProductCategories, #id)();

  /// Longer description / prep notes shown on the product detail page.
  TextColumn get description => text().nullable()();

  /// Local file path or asset reference for the product photo. Stored
  /// as a reference only — the bytes live on disk, not in SQLite.
  TextColumn get imagePath => text().nullable()();

  /// 'finished' | 'intermediate' | 'merchandise' | 'service'
  TextColumn get productType =>
      text().withDefault(const Constant('finished'))();

  /// 'recipe' | 'stocked' | 'non_stocked'
  TextColumn get trackingType => text().withDefault(const Constant('recipe'))();

  /// The unit this product is produced/sold in — "cup", "serving",
  /// "piece", "bottle", etc. This is what recipe yields and sale
  /// quantities are expressed in.
  TextColumn get unit => text()();
  IntColumn get sellPrice => integer().nullable()(); // cents, optional

  /// On-hand quantity for trackingType == 'stocked' (merchandise you
  /// buy and resell as-is). Ignored for recipe/non-stocked products,
  /// whose availability is derived from supply stock instead.
  RealColumn get currentStock => real().withDefault(const Constant(0))();
  RealColumn get lowStockThreshold => real().nullable()();

  /// False for intermediate-only components (e.g. "Espresso Base")
  /// that exist purely to be used inside other recipes and are never
  /// sold directly to a customer. Preserved as-is: every existing
  /// query on isSellable keeps working.
  BoolColumn get isSellable => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Manual display order inside the catalog / POS grid.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Recipes extends Table {
  TextColumn get id => text()();

  /// The product this recipe produces. One product has at most one
  /// active recipe in this design.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// How many units of `productId` ONE batch of this recipe yields.
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

  /// 'supply' | 'product'
  TextColumn get componentType => text()();
  TextColumn get supplyId => text().nullable().references(Supplies, #id)();
  TextColumn get componentProductId =>
      text().nullable().references(Products, #id)();
  RealColumn get quantityRequired => real()();
  TextColumn get unit => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class InventoryMovements extends Table {
  TextColumn get id => text()();
  TextColumn get supplyId => text().references(Supplies, #id)();
  TextColumn get branchId => text().nullable()();

  /// 'production_consumption' | 'manual_adjustment' | 'restock'
  TextColumn get movementType => text()();
  TextColumn get unit => text()();
  RealColumn get quantity => real()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  DateTimeColumn get movementDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();

  /// Same purpose as SupplyPriceHistory.shoppingCartItemId — lets a
  /// checkout deletion find and remove the exact 'restock' movement it
  /// created, instead of matching by value (which can collide).
  TextColumn get shoppingCartItemId => text().nullable().references(
    ShoppingCartItems,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================
// 9. POS SALES (checkout receipts — real sales AND stock-only)
// ============================================================

class PosSales extends Table {
  TextColumn get id => text()();

  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();

  DateTimeColumn get saleDate => dateTime().withDefault(currentDateAndTime)();

  IntColumn get totalAmount => integer().withDefault(const Constant(0))();

  BoolColumn get isStockOnly => boolean().withDefault(const Constant(false))();

  TextColumn get paymentAccountId =>
      text().nullable().references(Accounts, #id)();

  TextColumn get notes => text().nullable()();

  // POS shift/session that owns this receipt.
  TextColumn get sessionId => text().nullable().references(PosSessions, #id)();

  // Receipt-level void state.
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();

  DateTimeColumn get voidedAt => dateTime().nullable()();

  TextColumn get voidReason => text().nullable()();

  TextColumn get cashierUserId => text().nullable()();

  TextColumn get cashierName => text().nullable()();

  /// Discount in centavos. totalAmount is stored NET of this.
  IntColumn get discountAmount => integer().withDefault(const Constant(0))();
  TextColumn get discountLabel => text().nullable()();

  /// Human receipt number, e.g. "A1B2-007" (shift code + running number).
  TextColumn get receiptNo => text().nullable()();

  /// Customer a credit sale was charged to (null for ordinary sales).
  TextColumn get customerId => text().nullable()();

  /// Dine in / Take out / GrabFood... A text snapshot, so renaming a type
  /// later never changes old receipts.
  TextColumn get orderType => text().nullable()();

  /// Platform / online order number (GrabFood, Foodpanda, Shopee...).
  TextColumn get orderRef => text().nullable()();
  TextColumn get contactName => text().nullable()();
  TextColumn get contactPhone => text().nullable()();
  TextColumn get deliveryAddress => text().nullable()();

  /// Table name at the time of the sale (a snapshot, like orderType).
  TextColumn get tableLabel => text().nullable()();
  IntColumn get guests => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class PosSaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId =>
      text().references(PosSales, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().nullable().references(
    Products,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  IntColumn get unitPrice => integer()();
  RealColumn get quantity => real()();
  IntColumn get lineTotal => integer()();

  /// Cost of one unit when it was sold (cents), for profit reports.
  IntColumn get unitCost => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Payment proof (GCash/GoTyme/etc. screenshot data) attached to a sale.
/// At most one row per sale. Money is in cents.
class PosSalePayments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId =>
      text().references(PosSales, #id, onDelete: KeyAction.cascade)();

  /// Normalized (no spaces, upper-case). Unique when present — see
  /// _createPaymentIndexes.
  TextColumn get referenceNo => text().nullable()();
  IntColumn get amountPaid => integer()();
  DateTimeColumn get paidAt => dateTime().nullable()();
  TextColumn get provider => text().nullable()();
  TextColumn get photoPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class PaymentProviders extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();

  /// 'bank' | 'ewallet'
  TextColumn get kind => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Customizable POS order types (Dine in, Take out, GrabFood, ...).
class PosOrderTypes extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// dine_in | takeout | pickup | delivery | online | other
  TextColumn get kind => text().withDefault(const Constant('other'))();
  BoolColumn get requiresTable =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get requiresCustomer =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get requiresAddress =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get requiresReference =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Restaurant tables / seating spots.
class PosTables extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get seats => integer().withDefault(const Constant(4))();
  TextColumn get section => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A register shift. Sales attach to the open shift; the journal is written
/// only when the shift is closed.
class PosSessions extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get openingCash => integer().withDefault(const Constant(0))();
  IntColumn get countedCash => integer().nullable()();
  IntColumn get expectedCash => integer().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('open'))(); // open|closed
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per payment part of a sale (split payments = several rows).
class PosSaleTenders extends Table {
  TextColumn get id => text()();
  TextColumn get saleId =>
      text().references(PosSales, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get amount => integer()(); // applied to the bill (change excluded)
  IntColumn get tendered => integer().nullable()(); // cash handed over
  IntColumn get changeGiven => integer().withDefault(const Constant(0))();
  TextColumn get referenceNo => text().nullable()();
  DateTimeColumn get paidAt => dateTime().nullable()();
  TextColumn get provider => text().nullable()();
  TextColumn get photoPath => text().nullable()();

  /// Mirrors the sale's void state so the unique reference rule can ignore
  /// voided payments.
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local login credentials. One row per person who can sign in to BOS on
/// this device. [BusinessMembers.userId] refers to [Users.id].
@DataClassName('AppUser')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get passwordHash => text()();
  TextColumn get passwordSalt => text()();
  TextColumn get displayName => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();

  /// Salted hash of the owner/manager approval PIN. Device-local; never synced.
  TextColumn get approvalPinHash => text().nullable()();
  TextColumn get approvalPinSalt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class BusinessMembers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get userId => text()();

  /// Stable role id: owner|manager|accountant|cashier|inventory|employee
  TextColumn get role => text()();

  /// invited | active | suspended | removed
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get invitedBy => text().nullable()();
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();
  TextColumn get userId => text()();
  TextColumn get action => text()(); // e.g. 'user.role_changed'
  TextColumn get entityType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get details => text().nullable()(); // JSON
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get module => text().nullable()();

  /// create|update|delete|void|refund|adjustment|permission|export|security
  TextColumn get actionType => text().nullable()();
  TextColumn get entityLabel => text().nullable()();
  TextColumn get actorName => text().nullable()();
  TextColumn get actorRole => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get source =>
      text().withDefault(const Constant('client_reported'))();
  TextColumn get reason => text().nullable()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-business customization of a role's permissions, layered on top of
/// [RolePermissions.of]'s defaults (core/auth/bos_access.dart). A role with
/// no rows here just uses the defaults; [granted] explicitly adds or
/// removes a single permission for that role in that business.
class RolePermissionOverrides extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get role => text()();
  TextColumn get permission => text()();
  BoolColumn get granted => boolean()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A short code that lets someone without an account yet join a business at
/// a chosen (non-owner) role, redeemed once during registration. Solves
/// onboarding offline: there's no server to email/push an invite through,
/// so the code itself — shared by the inviter out-of-band — is the proof.
@DataClassName('BusinessInvite')
class BusinessInvites extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get code => text()();
  TextColumn get role => text()();

  /// pending | used | revoked
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get usedByUserId => text().nullable()();
  DateTimeColumn get usedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Centralized change-tracking outbox for future Supabase synchronization.
/// One row per local mutation of a sync-relevant entity. Business logic
/// writes to this table inside the SAME database transaction as the actual
/// change, so a mutation can never succeed without being tracked (or fail
/// while leaving a phantom outbox row). No network code touches this yet —
/// it only makes local mutations inspectable and replayable.
///
/// `status` lifecycle: pending -> syncing -> (synced | failed).
/// Idempotency comes from [entityId] being the entity's own stable UUID, so
/// a repeat upload of the same change is recognized as the same record.
class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();

  /// Stable table name, e.g. 'customers', 'journal_entries'.
  TextColumn get entityType => text()();

  /// The entity's own stable id (its primary key). Repeating an operation
  /// for the same entity never needs a new id.
  TextColumn get entityId => text()();

  /// create | update | delete
  TextColumn get operation => text()();

  /// pending | syncing | synced | failed | conflict
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  /// When the next retry is allowed (exponential backoff). Null = try now.
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get error => text().nullable()();

  /// Globally unique, stable id for THIS logical change. Never regenerated
  /// on retry — the server uses it to recognize a repeated upload of the
  /// same mutation instead of duplicating it.
  TextColumn get mutationId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Durable per-business sync checkpoint: how far the pull cursor has
/// advanced. Advances only AFTER the corresponding local transaction
/// commits, so an interrupted pull resumes from the last safe point.
class SyncCheckpoints extends Table {
  TextColumn get businessId => text().references(Businesses, #id)();

  /// Server-authoritative high-water mark (the change-feed sequence we've
  /// fully applied locally). 0 = nothing pulled yet.
  IntColumn get lastServerCursor => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSuccessfulSyncAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {businessId};
}

// ============================================================
// 10. HR (attendance, schedules, leave, payroll) — device-local for now
// ============================================================

class ScheduleShifts extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();
  TextColumn get userId => text()();
  DateTimeColumn get shiftDate => dateTime()(); // local midnight
  IntColumn get startMinutes => integer()(); // minutes from midnight
  IntColumn get endMinutes => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class AttendanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().nullable()();
  TextColumn get userId => text()();
  DateTimeColumn get workDate => dateTime()();
  DateTimeColumn get clockIn => dateTime()();
  DateTimeColumn get clockOut => dateTime().nullable()();
  IntColumn get breakMinutes => integer().withDefault(const Constant(0))();

  /// 'clock' | 'manual'
  TextColumn get source => text().withDefault(const Constant('clock'))();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class LeaveRequests extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get userId => text()();

  /// vacation | sick | emergency | unpaid | other
  TextColumn get leaveType => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  RealColumn get days => real().withDefault(const Constant(1))();
  TextColumn get reason => text().nullable()();

  /// pending | approved | rejected | cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get decidedBy => text().nullable()();
  DateTimeColumn get decidedAt => dateTime().nullable()();
  TextColumn get decisionNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class PayrollProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get userId => text()();

  /// daily | hourly | fixed (fixed = one amount per pay period)
  TextColumn get payType => text()();
  IntColumn get rate => integer()(); // cents
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class PayrollRuns extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();

  /// draft | finalized
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get totalNet => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get finalizedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PayrollItems extends Table {
  TextColumn get id => text()();
  TextColumn get runId =>
      text().references(PayrollRuns, #id, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get userName => text()(); // snapshot
  TextColumn get payType => text()();
  IntColumn get rate => integer()();
  RealColumn get daysWorked => real().withDefault(const Constant(0))();
  RealColumn get hoursWorked => real().withDefault(const Constant(0))();
  RealColumn get paidLeaveDays => real().withDefault(const Constant(0))();
  IntColumn get grossPay => integer().withDefault(const Constant(0))();
  IntColumn get additions => integer().withDefault(const Constant(0))();
  IntColumn get deductions => integer().withDefault(const Constant(0))();
  IntColumn get netPay => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Owner-chosen display names for the custom role slots.
class RoleLabels extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get role => text()();
  TextColumn get label => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Roles the owner defines. A member holds it as the role id `c_<id>`.
class CustomRoles extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();

  /// Built-in role whose permissions this role starts with.
  TextColumn get baseRole => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Branch')
class Branches extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get code => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();

  /// This branch's own cash drawer account (a normal row in `accounts`).
  TextColumn get cashAccountId => text().nullable()();
  BoolColumn get isHeadquarters =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Who works in which branch. A user with NO active row here can work in every
/// branch (the owner always can).
class BranchMembers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().references(Branches, #id)();
  TextColumn get userId => text()();
  TextColumn get role => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only stock ledger for resale products (trackingType 'stocked').
/// Quantity is signed. Stock at a branch = SUM(quantity).
class ProductStockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().references(Branches, #id)();
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// opening_balance | pos_sale | pos_void | pos_restore | manual_adjustment |
  /// restock | transfer_out | transfer_in | transfer_cancel
  TextColumn get movementType => text()();
  RealColumn get quantity => real()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get movementDate =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StockTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  @ReferenceName('stockOut')
  TextColumn get fromBranchId => text().references(Branches, #id)();
  @ReferenceName('stockIn')
  TextColumn get toBranchId => text().references(Branches, #id)();

  /// in_transit | received | cancelled
  TextColumn get status => text().withDefault(const Constant('in_transit'))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get receivedBy => text().nullable()();
  DateTimeColumn get shippedAt => dateTime().nullable()();
  DateTimeColumn get receivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StockTransferItems extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get transferId =>
      text().references(StockTransfers, #id, onDelete: KeyAction.cascade)();

  /// 'supply' | 'product'
  TextColumn get itemType => text()();
  TextColumn get itemId => text()();
  TextColumn get itemName => text()(); // snapshot
  TextColumn get unit => text().withDefault(const Constant(''))();
  RealColumn get quantity => real()();
  RealColumn get receivedQuantity => real().nullable()();

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
    SupplyUnitConversions,
    SupplyPriceHistory,
    ShoppingCarts,
    ShoppingCartItems,
    AccountTransfers,
    ProductCategories,
    Products,
    Recipes,
    RecipeComponents,
    InventoryMovements,
    PosSales,
    PosSaleItems,
    PosSalePayments,
    PaymentProviders,
    PosOrderTypes,
    PosTables,
    PosSessions,
    PosSaleTenders,
    BusinessMembers,
    AuditLogs,
    Users,
    RolePermissionOverrides,
    BusinessInvites,
    BusinessModuleConfigs,
    SyncOutbox,
    SyncCheckpoints,
    ScheduleShifts,
    AttendanceRecords,
    LeaveRequests,
    PayrollProfiles,
    PayrollRuns,
    PayrollItems,
    RoleLabels,
    CustomRoles,
    Branches,
    BranchMembers,
    ProductStockMovements,
    StockTransfers,
    StockTransferItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 47;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createSyncOutboxOwners();
      await _createProductIndexes();
      await _createSupplyIndexes();
      await _createPaymentIndexes();
      await _createTenderIndexes();
      await _createMembershipIndexes();
      await _backfillOwnerMemberships();
      await _createUserIndexes();
      await _createPermissionOverrideIndexes();
      await _createInviteIndexes();
      await _createModuleConfigIndexes();
      await _createSyncOutboxIndexes();
      await _createBranchIndexes();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');

      // Self-heal: make sure the approval PIN columns exist even if this
      // device already recorded schema v38 before they were added.
      final userCols = await customSelect('PRAGMA table_info(users)').get();
      final userColNames = userCols.map((r) => r.read<String>('name')).toSet();
      if (!userColNames.contains('approval_pin_hash')) {
        await customStatement(
          'ALTER TABLE users ADD COLUMN approval_pin_hash TEXT',
        );
      }
      if (!userColNames.contains('approval_pin_salt')) {
        await customStatement(
          'ALTER TABLE users ADD COLUMN approval_pin_salt TEXT',
        );
      }
      // Cheap and idempotent — guarantees the catalog/POS lookup indexes
      // exist even for databases created before this code shipped.
      await _createProductIndexes();
      await _createSupplyIndexes();
      await _createMembershipIndexes();
      await _backfillOwnerMemberships();
      await _createPaymentIndexes();
      await _createTenderIndexes();
      await _createUserIndexes();
      await _createPermissionOverrideIndexes();
      await _createInviteIndexes();
      await _createModuleConfigIndexes();
      await _createSyncOutboxIndexes();
      await _createBranchIndexes();
      await _createPosReturnTables();
      await SyncChangeLog.install(this);
      await AuditSchemaGuard.install(this);
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
      }
      if (from < 11) {
        await m.addColumn(accounts, accounts.subtype);
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
      if (from < 13) {
        // ---- PRODUCT MASTER -------------------------------------------
        await m.createTable(productCategories);

        await m.addColumn(products, products.sku);
        await m.addColumn(products, products.barcode);
        await m.addColumn(products, products.categoryId);
        await m.addColumn(products, products.description);
        await m.addColumn(products, products.imagePath);
        await m.addColumn(products, products.productType);
        await m.addColumn(products, products.trackingType);
        await m.addColumn(products, products.currentStock);
        await m.addColumn(products, products.lowStockThreshold);
        await m.addColumn(products, products.sortOrder);
        await m.addColumn(products, products.updatedAt);

        // Classify what already exists, using isSellable (the only signal
        // the old schema had) plus whether a recipe is attached.
        await customStatement(
          "UPDATE products SET product_type = "
          "CASE WHEN is_sellable = 0 THEN 'intermediate' ELSE 'finished' END",
        );
        await customStatement(
          "UPDATE products SET tracking_type = "
          "CASE WHEN id IN (SELECT product_id FROM recipes) "
          "THEN 'recipe' ELSE 'non_stocked' END",
        );
        await customStatement('UPDATE products SET updated_at = created_at');

        // Give existing businesses the starter category set so the new
        // catalog filters aren't empty on first open.
        final existing = await customSelect('SELECT id FROM businesses').get();
        for (final row in existing) {
          await seedDefaultProductCategories(row.read<String>('id'));
        }

        await _createProductIndexes();
      }
      if (from < 14) {
        // ---- SUPPLY CATALOG IDENTITY -----------------------------------
        await m.addColumn(supplies, supplies.sku);
        await m.addColumn(supplies, supplies.barcode);
        await m.addColumn(supplies, supplies.categoryId);
        await m.addColumn(supplies, supplies.imagePath);
        await m.addColumn(supplies, supplies.sortOrder);
        await _createSupplyIndexes();
      }
      if (from < 15) {
        // ---- CHECKOUT REVERSAL LINKING ----------------------------------
        // THE FIX: give price-history and inventory-movement rows a real
        // foreign key back to the ShoppingCartItem that created them, so
        // deleting a checkout finds the exact rows to reverse instead of
        // matching by supplyId+price+quantity+date (which can collide when
        // the same item is bought twice in one day at the same price/qty).
        await m.addColumn(
          supplyPriceHistory,
          supplyPriceHistory.shoppingCartItemId,
        );
        await m.addColumn(
          inventoryMovements,
          inventoryMovements.shoppingCartItemId,
        );
      }
      if (from < 16) {
        // ---- SUPPLY MIN/MAX STOCK ----------------------------------------
        await m.addColumn(supplies, supplies.minimumStock);
        await m.addColumn(supplies, supplies.maximumStock);
      }

      if (from < 17) {
        await m.createTable(posSales);
        await m.createTable(posSaleItems);
      }
      if (from < 18) {
        await m.addColumn(supplies, supplies.isSoldByWeight);
        await m.addColumn(shoppingCartItems, shoppingCartItems.isWeighted);
        await m.addColumn(shoppingCartItems, shoppingCartItems.weightQuantity);
      }
      if (from < 19) {
        await m.createTable(posSalePayments);
        await _createPaymentIndexes();
      }
      if (from < 20) {
        await m.createTable(paymentProviders);
      }
      if (from < 21) {
        await m.createTable(posSessions);
        await m.createTable(posSaleTenders);

        await m.addColumn(posSales, posSales.sessionId);
        await m.addColumn(posSales, posSales.isVoided);
        await m.addColumn(posSales, posSales.voidedAt);
        await m.addColumn(posSales, posSales.voidReason);

        await _createPaymentIndexes();
      }
      if (from < 22) {
        await m.createTable(businessMembers);
        await m.createTable(auditLogs);
        await _createMembershipIndexes();
        await _backfillOwnerMemberships();
      }
      if (from < 23) {
        await m.addColumn(shoppingCartItems, shoppingCartItems.grossLineTotal);
        await m.addColumn(shoppingCartItems, shoppingCartItems.discountType);
        await m.addColumn(shoppingCartItems, shoppingCartItems.discountValue);
        await m.addColumn(shoppingCartItems, shoppingCartItems.discountAmount);
        await customStatement(
          'UPDATE shopping_cart_items '
          'SET gross_line_total = line_total '
          'WHERE gross_line_total = 0',
        );
      }
      if (from < 24) {
        await m.addColumn(
          shoppingCartItems,
          shoppingCartItems.stockUnitsPerUnit,
        );
        await m.createTable(supplyUnitConversions);
        await customStatement('''
          UPDATE shopping_cart_items
          SET stock_units_per_unit = COALESCE((
            SELECT CASE
              WHEN LOWER(TRIM(COALESCE(shopping_cart_items.unit, ''))) =
                   LOWER(TRIM(supplies.stock_unit)) THEN 1.0
              WHEN LOWER(TRIM(COALESCE(shopping_cart_items.unit, ''))) =
                   LOWER(TRIM(COALESCE(supplies.purchase_unit, '')))
                THEN supplies.units_per_purchase
              ELSE supplies.units_per_purchase
            END
            FROM supplies
            WHERE supplies.id = shopping_cart_items.supply_id
          ), 1.0)
          WHERE shopping_cart_items.supply_id IS NOT NULL
        ''');
      }
      if (from < 25) {
        await m.createTable(users);
        await _createUserIndexes();
      }
      if (from < 26) {
        await m.createTable(rolePermissionOverrides);
        await _createPermissionOverrideIndexes();
      }
      if (from < 27) {
        await m.createTable(businessInvites);
        await _createInviteIndexes();
      }
      if (from < 28) {
        await _addColumnIfMissing(m, businesses, businesses.legalName);
        await _addColumnIfMissing(m, businesses, businesses.businessType);
        await _addColumnIfMissing(m, businesses, businesses.industry);
        await _addColumnIfMissing(m, businesses, businesses.description);
        await _addColumnIfMissing(m, businesses, businesses.email);
        await _addColumnIfMissing(m, businesses, businesses.phone);
        await _addColumnIfMissing(m, businesses, businesses.timezone);
        await _addColumnIfMissing(m, businesses, businesses.logoPath);
        await _addColumnIfMissing(m, businesses, businesses.isActive);
        // businesses.updatedAt has a non-constant default (CURRENT_TIMESTAMP
        // via strftime), which SQLite forbids in ALTER TABLE ADD COLUMN. Add
        // it nullable, then backfill existing rows.
        try {
          await customStatement(
            'ALTER TABLE "businesses" ADD COLUMN "updated_at" INTEGER NULL;',
          );
        } catch (_) {
          // Column already exists on partially-upgraded device DBs.
        }
        await customStatement(
          "UPDATE businesses SET updated_at = CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER) "
          'WHERE updated_at IS NULL',
        );
        try {
          await m.createTable(businessModuleConfigs);
        } catch (_) {
          // Table already exists on partially-upgraded device DBs.
        }
        await _createModuleConfigIndexes();
        // The old onboarding category doubles as the industry for existing
        // businesses; business_type stays null until the owner picks one.
        await customStatement(
          'UPDATE businesses SET industry = business_category '
          'WHERE industry IS NULL AND business_category IS NOT NULL',
        );
      }
      if (from < 29) {
        try {
          await m.createTable(syncOutbox);
        } catch (_) {
          // Table already exists on partially-upgraded device DBs.
        }
        await _createSyncOutboxIndexes();
      }
      if (from < 30) {
        await _addColumnIfMissing(m, syncOutbox, syncOutbox.nextAttemptAt);
        await _addColumnIfMissing(m, syncOutbox, syncOutbox.mutationId);
        try {
          await m.createTable(syncCheckpoints);
        } catch (_) {
          // Table already exists on partially-upgraded device DBs.
        }
        await _createSyncCheckpointIndexes();
        // Backfill existing outbox rows with a stable mutation id.
        await customStatement(
          "UPDATE sync_outbox SET mutation_id = id WHERE mutation_id = ''",
        );
      }
      if (from < 31) {
        // ---- CART PRICE ANCHORS -------------------------------------------
        // Nullable on purpose: rows written before v31 fall back to the
        // line's own unitPrice/stockUnitsPerUnit as the conversion anchor.
        await _addColumnIfMissing(
          m,
          shoppingCartItems,
          shoppingCartItems.originalUnitPrice,
        );
        await _addColumnIfMissing(
          m,
          shoppingCartItems,
          shoppingCartItems.originalStockUnitsPerUnit,
        );
      }
      if (from < 32) {
        await _migrateLegacyIdsToUuid();
      }
      if (from < 33) {
        // Existing rows stay unattributed and are held for explicit recovery;
        // never silently upload legacy work under a different account.
        await _createSyncOutboxOwners();
      }
      if (from < 34) {
        await _addColumnIfMissing(m, posSales, posSales.cashierUserId);
        await _addColumnIfMissing(m, posSales, posSales.cashierName);
      }
      if (from < 35) {
        await _addColumnIfMissing(m, auditLogs, auditLogs.module);
        await _addColumnIfMissing(m, auditLogs, auditLogs.actionType);
        await _addColumnIfMissing(m, auditLogs, auditLogs.entityLabel);
        await _addColumnIfMissing(m, auditLogs, auditLogs.actorName);
        await _addColumnIfMissing(m, auditLogs, auditLogs.actorRole);
        await _addColumnIfMissing(m, auditLogs, auditLogs.deviceId);
        await _addColumnIfMissing(m, auditLogs, auditLogs.reason);
        await _addColumnIfMissing(m, auditLogs, auditLogs.beforeJson);
        await _addColumnIfMissing(m, auditLogs, auditLogs.afterJson);
      }
      if (from < 36) {
        await _addColumnIfMissing(m, posSales, posSales.discountAmount);
        await _addColumnIfMissing(m, posSales, posSales.discountLabel);
        await _addColumnIfMissing(m, posSales, posSales.receiptNo);
        await _addColumnIfMissing(m, posSaleItems, posSaleItems.unitCost);
        await _addColumnIfMissing(m, posSaleTenders, posSaleTenders.isVoided);
        await customStatement(
          'UPDATE pos_sale_tenders SET is_voided = 1 WHERE sale_id IN '
          '(SELECT id FROM pos_sales WHERE is_voided = 1)',
        );
        await _createTenderIndexes();
      }
      if (from < 37) {
        await _addColumnIfMissing(m, posSales, posSales.customerId);
      }
      if (from < 38) {
        await _addColumnIfMissing(m, users, users.approvalPinHash);
        await _addColumnIfMissing(m, users, users.approvalPinSalt);
      }
      if (from < 39) {
        Future<void> create(TableInfo t) async {
          try {
            await m.createTable(t);
          } catch (_) {
            // Table already exists on partially-upgraded device DBs.
          }
        }

        await create(scheduleShifts);
        await create(attendanceRecords);
        await create(leaveRequests);
        await create(payrollProfiles);
        await create(payrollRuns);
        await create(payrollItems);
      }

      if (from < 40) {
        try {
          await m.createTable(roleLabels);
        } catch (_) {
          // Table already exists on partially-upgraded device DBs.
        }
      }

      if (from < 41) {
        try {
          await m.createTable(customRoles);
        } catch (_) {
          // Table already exists on partially-upgraded device DBs.
        }
      }
      if (from < 42) {
        await _addColumnIfMissing(m, customers, customers.address);
        await _addColumnIfMissing(m, customers, customers.tin);
      }
      if (from < 43) {
        await _addColumnIfMissing(m, posSales, posSales.orderType);
        try {
          await m.createTable(posOrderTypes);
        } catch (_) {
          // Table already exists on partially-upgraded device DBs.
        }
      }
      if (from < 44) {
        await _addColumnIfMissing(m, posSales, posSales.orderRef);
        await _addColumnIfMissing(m, posSales, posSales.contactName);
        await _addColumnIfMissing(m, posSales, posSales.contactPhone);
        await _addColumnIfMissing(m, posSales, posSales.deliveryAddress);
        await _addColumnIfMissing(m, posSales, posSales.tableLabel);
        await _addColumnIfMissing(m, posSales, posSales.guests);
        await _addColumnIfMissing(m, posOrderTypes, posOrderTypes.kind);
        await _addColumnIfMissing(
          m,
          posOrderTypes,
          posOrderTypes.requiresTable,
        );
        await _addColumnIfMissing(
          m,
          posOrderTypes,
          posOrderTypes.requiresCustomer,
        );
        await _addColumnIfMissing(
          m,
          posOrderTypes,
          posOrderTypes.requiresAddress,
        );
        await _addColumnIfMissing(
          m,
          posOrderTypes,
          posOrderTypes.requiresReference,
        );
        try {
          await m.createTable(posTables);
        } catch (_) {
          // Table already exists on partially-upgraded device DBs.
        }
        // Give the old default types their behavior.
        await customStatement(
          "UPDATE pos_order_types SET kind = 'dine_in', requires_table = 1 "
          "WHERE kind = 'other' AND lower(name) LIKE 'dine%'",
        );
        await customStatement(
          "UPDATE pos_order_types SET kind = 'takeout' "
          "WHERE kind = 'other' AND lower(name) LIKE 'take%'",
        );
        await customStatement(
          "UPDATE pos_order_types SET kind = 'online', requires_reference = 1 "
          "WHERE kind = 'other' AND lower(name) IN "
          "('grabfood', 'foodpanda', 'maxim')",
        );
      }
      if (from < 45) {
        for (final create in <Future<void> Function()>[
          () => m.createTable(branches),
          () => m.createTable(branchMembers),
          () => m.createTable(productStockMovements),
          () => m.createTable(stockTransfers),
          () => m.createTable(stockTransferItems),
        ]) {
          try {
            await create();
          } catch (_) {
            // Table may already exist on a partially upgraded database.
          }
        }

        for (final tableName in _branchScopedTables) {
          try {
            await customStatement(
              'ALTER TABLE "$tableName" ADD COLUMN branch_id TEXT',
            );
          } catch (error) {
            if (!error.toString().contains('duplicate column name')) rethrow;
          }
        }

        await _enableBranches();
        await _createBranchIndexes();
      }
      if (from < 46) {
        await _addColumnIfMissing(m, auditLogs, auditLogs.source);
      }
      if (from < 47) {
        await _createPosReturnTables();
      }
    },
  );

  Future<void> _createSyncOutboxOwners() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_outbox_owners (
        outbox_id TEXT PRIMARY KEY NOT NULL
          REFERENCES sync_outbox(id) ON DELETE CASCADE,
        owner_user_id TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_sync_outbox_owners_user '
      'ON sync_outbox_owners (owner_user_id, outbox_id)',
    );
  }

  Future<void> _createPosReturnTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS pos_returns (
        id TEXT NOT NULL PRIMARY KEY,
        business_id TEXT NOT NULL REFERENCES businesses(id),
        sale_id TEXT NOT NULL REFERENCES pos_sales(id),
        refund_account_id TEXT NOT NULL REFERENCES accounts(id),
        reason TEXT NOT NULL,
        created_by TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS pos_return_items (
        id TEXT NOT NULL PRIMARY KEY,
        return_id TEXT NOT NULL
          REFERENCES pos_returns(id) ON DELETE RESTRICT,
        sale_item_id TEXT NOT NULL REFERENCES pos_sale_items(id),
        quantity REAL NOT NULL CHECK (quantity > 0),
        refund_amount INTEGER NOT NULL CHECK (refund_amount >= 0)
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pos_returns_business_created_idx '
      'ON pos_returns (business_id, created_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pos_returns_sale_idx '
      'ON pos_returns (sale_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pos_return_items_return_idx '
      'ON pos_return_items (return_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pos_return_items_sale_item_idx '
      'ON pos_return_items (sale_item_id)',
    );
  }

  String _cloudCompatibleDefaultId(String entityType, String legacyIdentity) =>
      cloudCompatibleDefaultId(entityType, legacyIdentity);

  /// Deterministic UUID for a seeded default row, derived from its legacy
  /// text id (e.g. `acc_sales_<businessId>`). Lets code that still holds a
  /// legacy key find the row seeded under its cloud-compatible id.
  static String cloudCompatibleDefaultId(
    String entityType,
    String legacyIdentity,
  ) {
    return const Uuid().v5(
      Uuid.NAMESPACE_URL,
      'bos:$entityType:$legacyIdentity',
    );
  }

  Future<void> _migrateLegacyIdsToUuid() async {
    // SQLite foreign keys are normally immediate. Deferring them lets us
    // update foreign-key columns and their parent primary keys within the
    // same migration transaction.
    await customStatement('PRAGMA defer_foreign_keys = ON');

    final uuid = const Uuid();

    bool isUuid(String value) {
      return RegExp(
        r'^[0-9a-fA-F]{8}-'
        r'[0-9a-fA-F]{4}-'
        r'[1-5][0-9a-fA-F]{3}-'
        r'[89abAB][0-9a-fA-F]{3}-'
        r'[0-9a-fA-F]{12}$',
      ).hasMatch(value);
    }

    String mappedId(String entityType, String oldId) {
      // UUID v5 gives us a deterministic UUID from the legacy ID.
      //
      // Therefore:
      //   accounts + acc_cash_businessX
      // will ALWAYS produce the same UUID.
      return uuid.v5(Uuid.NAMESPACE_URL, 'bos:$entityType:$oldId');
    }

    final accountMap = <String, String>{};
    final categoryMap = <String, String>{};
    final productCategoryMap = <String, String>{};

    // --------------------------------------------------------------------------
    // 1. Build account mapping
    // --------------------------------------------------------------------------

    final accountRows = await customSelect('SELECT id FROM accounts').get();

    for (final row in accountRows) {
      final oldId = row.read<String>('id');

      if (!isUuid(oldId)) {
        accountMap[oldId] = mappedId('accounts', oldId);
      }
    }

    // --------------------------------------------------------------------------
    // 2. Build transaction-category mapping
    // --------------------------------------------------------------------------

    final categoryRows = await customSelect('SELECT id FROM categories').get();

    for (final row in categoryRows) {
      final oldId = row.read<String>('id');

      if (!isUuid(oldId)) {
        categoryMap[oldId] = mappedId('categories', oldId);
      }
    }

    // --------------------------------------------------------------------------
    // 3. Build product-category mapping
    // --------------------------------------------------------------------------

    final productCategoryRows = await customSelect(
      'SELECT id FROM product_categories',
    ).get();

    for (final row in productCategoryRows) {
      final oldId = row.read<String>('id');

      if (!isUuid(oldId)) {
        productCategoryMap[oldId] = mappedId('product_categories', oldId);
      }
    }

    // --------------------------------------------------------------------------
    // 4. Update account foreign keys FIRST
    // --------------------------------------------------------------------------

    for (final entry in accountMap.entries) {
      final oldId = entry.key;
      final newId = entry.value;

      await customStatement(
        '''
    UPDATE businesses
    SET starting_capital_account_id = ?
    WHERE starting_capital_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE categories
    SET ledger_account_id = ?
    WHERE ledger_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE ledger_lines
    SET account_id = ?
    WHERE account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE income_transactions
    SET payment_account_id = ?
    WHERE payment_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE receivable_payments
    SET payment_account_id = ?
    WHERE payment_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE supplier_purchases
    SET payment_account_id = ?
    WHERE payment_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE payable_payments
    SET payment_account_id = ?
    WHERE payment_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE expenses
    SET payment_account_id = ?
    WHERE payment_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE account_transfers
    SET from_account_id = ?
    WHERE from_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE account_transfers
    SET to_account_id = ?
    WHERE to_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE pos_sales
    SET payment_account_id = ?
    WHERE payment_account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE pos_sale_tenders
    SET account_id = ?
    WHERE account_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE sync_outbox
    SET entity_id = ?
    WHERE entity_type = 'accounts'
      AND entity_id = ?
    ''',
        [newId, oldId],
      );
    }

    // --------------------------------------------------------------------------
    // 5. Update category foreign keys
    // --------------------------------------------------------------------------

    for (final entry in categoryMap.entries) {
      final oldId = entry.key;
      final newId = entry.value;

      await customStatement(
        '''
    UPDATE income_transactions
    SET category_id = ?
    WHERE category_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE expenses
    SET category_id = ?
    WHERE category_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE sync_outbox
    SET entity_id = ?
    WHERE entity_type = 'categories'
      AND entity_id = ?
    ''',
        [newId, oldId],
      );
    }

    // --------------------------------------------------------------------------
    // 6. Update product-category foreign keys
    // --------------------------------------------------------------------------

    for (final entry in productCategoryMap.entries) {
      final oldId = entry.key;
      final newId = entry.value;

      await customStatement(
        '''
    UPDATE supplies
    SET category_id = ?
    WHERE category_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE products
    SET category_id = ?
    WHERE category_id = ?
    ''',
        [newId, oldId],
      );

      await customStatement(
        '''
    UPDATE sync_outbox
    SET entity_id = ?
    WHERE entity_type = 'product_categories'
      AND entity_id = ?
    ''',
        [newId, oldId],
      );
    }

    // --------------------------------------------------------------------------
    // 7. Finally change the primary keys themselves
    // --------------------------------------------------------------------------

    for (final entry in accountMap.entries) {
      await customStatement(
        '''
    UPDATE accounts
    SET id = ?
    WHERE id = ?
    ''',
        [entry.value, entry.key],
      );
    }

    for (final entry in categoryMap.entries) {
      await customStatement(
        '''
    UPDATE categories
    SET id = ?
    WHERE id = ?
    ''',
        [entry.value, entry.key],
      );
    }

    for (final entry in productCategoryMap.entries) {
      await customStatement(
        '''
    UPDATE product_categories
    SET id = ?
    WHERE id = ?
    ''',
        [entry.value, entry.key],
      );
    }

    await customStatement('PRAGMA defer_foreign_keys = OFF');
  }

  // Tables with optional branch attribution. Null remains valid for rows
  // created before branch tracking and for business-wide accounting entries.
  static const _branchScopedTables = [
    'pos_sessions',
    'pos_sales',
    'pos_tables',
    'inventory_movements',
    'journal_entries',
    'income_transactions',
    'expenses',
    'shopping_carts',
    'audit_logs',
    'schedule_shifts',
    'attendance_records',
  ];

  /// Deterministic Main Branch ID shared by local devices and the server.
  static String mainBranchId(String businessId) =>
      cloudCompatibleDefaultId('branches', 'branch_main_$businessId');

  Future<void> _setSuppress(bool on) async {
    try {
      await customStatement('UPDATE sync_context SET suppress = ${on ? 1 : 0}');
    } catch (_) {
      // sync_context may not exist yet on very old installs.
    }
  }

  /// Creates a Main Branch for every existing business and attributes
  /// existing POS, inventory, shopping-cart, schedule, and attendance rows.
  /// Opening movements preserve the old supply/product stock quantities.
  Future<void> _enableBranches() async {
    await _setSuppress(true);
    try {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final businesses = await customSelect('SELECT id FROM businesses').get();

      for (final row in businesses) {
        final businessId = row.read<String>('id');
        final branchId = mainBranchId(businessId);
        final cashAccountId = cloudCompatibleDefaultId(
          'accounts',
          'acc_cash_$businessId',
        );

        final cashAccountExists = (await customSelect(
          'SELECT 1 FROM accounts WHERE id = ?',
          variables: [Variable.withString(cashAccountId)],
        ).get()).isNotEmpty;

        await customStatement(
          'INSERT OR IGNORE INTO branches '
          '(id, business_id, name, code, cash_account_id, is_headquarters, is_active) '
          "VALUES (?, ?, 'Main Branch', 'MAIN', ?, 1, 1)",
          [branchId, businessId, cashAccountExists ? cashAccountId : null],
        );

        for (final tableName in const [
          'pos_sessions',
          'pos_sales',
          'pos_tables',
          'shopping_carts',
          'schedule_shifts',
          'attendance_records',
        ]) {
          await customStatement(
            'UPDATE "$tableName" SET branch_id = ? '
            'WHERE branch_id IS NULL AND business_id = ?',
            [branchId, businessId],
          );
        }

        await customStatement(
          'UPDATE inventory_movements SET branch_id = ? '
          'WHERE branch_id IS NULL AND supply_id IN '
          '(SELECT id FROM supplies WHERE business_id = ?)',
          [branchId, businessId],
        );

        // Bring legacy supply stock into the append-only movement ledger.
        final supplies = await customSelect(
          'SELECT s.id AS id, s.stock_unit AS unit, '
          's.current_stock AS current_quantity, '
          'COALESCE((SELECT SUM(m.quantity) FROM inventory_movements m '
          'WHERE m.supply_id = s.id), 0) AS moved_quantity '
          'FROM supplies s WHERE s.business_id = ?',
          variables: [Variable.withString(businessId)],
        ).get();

        for (final supply in supplies) {
          final current = (supply.data['current_quantity'] as num).toDouble();
          final moved = (supply.data['moved_quantity'] as num).toDouble();
          final difference = current - moved;
          if (difference.abs() < 1e-9) continue;

          final supplyId = supply.read<String>('id');
          await customStatement(
            'INSERT OR IGNORE INTO inventory_movements '
            '(id, supply_id, movement_type, unit, quantity, reference_type, '
            'notes, movement_date, branch_id) '
            "VALUES (?, ?, 'opening_balance', ?, ?, 'migration', "
            "'Opening balance when branches were enabled', ?, ?)",
            [
              cloudCompatibleDefaultId(
                'inventory_movements',
                'opening_$supplyId',
              ),
              supplyId,
              supply.read<String>('unit'),
              difference,
              nowSec,
              branchId,
            ],
          );
        }

        // Seed starting stock for stocked/resale products.
        final products = await customSelect(
          'SELECT id, current_stock AS current_quantity FROM products '
          "WHERE business_id = ? AND tracking_type = 'stocked' "
          'AND current_stock <> 0',
          variables: [Variable.withString(businessId)],
        ).get();

        for (final product in products) {
          final productId = product.read<String>('id');
          await customStatement(
            'INSERT OR IGNORE INTO product_stock_movements '
            '(id, business_id, branch_id, product_id, movement_type, quantity, '
            'reference_type, notes, movement_date, created_at) '
            "VALUES (?, ?, ?, ?, 'opening_balance', ?, 'migration', "
            "'Opening balance when branches were enabled', ?, ?)",
            [
              cloudCompatibleDefaultId(
                'product_stock_movements',
                'opening_$productId',
              ),
              businessId,
              branchId,
              productId,
              (product.data['current_quantity'] as num).toDouble(),
              nowSec,
              nowSec,
            ],
          );
        }
      }
    } finally {
      await _setSuppress(false);
    }
  }

  Future<void> _createBranchIndexes() async {
    const statements = [
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_branches_one_hq '
          'ON branches (business_id) WHERE is_headquarters = 1',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_branches_code '
          'ON branches (business_id, code) WHERE code IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_branch_members '
          'ON branch_members (branch_id, user_id)',
      'CREATE INDEX IF NOT EXISTS ix_inv_mov_branch_supply '
          'ON inventory_movements (branch_id, supply_id)',
      'CREATE INDEX IF NOT EXISTS ix_psm_branch_product '
          'ON product_stock_movements (branch_id, product_id)',
      'CREATE INDEX IF NOT EXISTS ix_pos_sessions_branch '
          'ON pos_sessions (branch_id, status)',
      "CREATE UNIQUE INDEX IF NOT EXISTS ux_pos_sessions_one_open "
          "ON pos_sessions (branch_id) WHERE status = 'open'",
    ];

    for (final statement in statements) {
      try {
        await customStatement(statement);
      } catch (_) {
        // Do not prevent startup if an index cannot be built yet.
      }
    }
  }

  /// Adds a column only when it isn't already present. Some device
  /// databases were created by newer builds before their schema version
  /// was recorded, so a plain addColumn can crash with "duplicate column".
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    try {
      await m.addColumn(table, column);
    } catch (error) {
      // SQLite has no IF NOT EXISTS for ADD COLUMN; tolerate the
      // duplicate-column error so device DBs that already contain the
      // column can keep upgrading instead of crashing at startup.
      if (!error.toString().contains('duplicate column name')) rethrow;
    }
  }

  /// `WHERE ... IS NOT NULL` clause keeps the index small, so many
  /// products can share "no SKU" / "no barcode" while any real value
  /// stays unique within the business.
  Future<void> _createProductIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_products_business_sku '
      'ON products (business_id, sku) WHERE sku IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_products_business_barcode '
      'ON products (business_id, barcode) WHERE barcode IS NOT NULL',
    );
    // POS scanning path: barcode alone, so the scan resolves with a single
    // index seek before the business filter is applied in Dart.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_products_barcode '
      'ON products (barcode) WHERE barcode IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_products_business_category '
      'ON products (business_id, category_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_products_business_active_name '
      'ON products (business_id, is_active, name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_product_categories_business '
      'ON product_categories (business_id, is_active, sort_order)',
    );
  }

  /// Partial-unique + lookup indexes for the supply catalog. Same
  /// NULL-is-distinct trick as products: many supplies can have no
  /// SKU, but any real code is unique within the business.
  Future<void> _createSupplyIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_supplies_business_sku '
      'ON supplies (business_id, sku) WHERE sku IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_supplies_business_barcode '
      'ON supplies (business_id, barcode) WHERE barcode IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_supplies_barcode '
      'ON supplies (barcode) WHERE barcode IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_supplies_business_category '
      'ON supplies (business_id, category_id)',
    );
  }

  Future<void> _createPaymentIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_pos_sale_payments_reference '
      'ON pos_sale_payments (reference_no) WHERE reference_no IS NOT NULL',
    );
  }

  Future<void> _createTenderIndexes() async {
    // The old rule blocked a reference forever, even after a void.
    await customStatement('DROP INDEX IF EXISTS ux_pos_sale_tenders_reference');
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_pos_sale_tenders_reference_live '
      'ON pos_sale_tenders (reference_no) '
      'WHERE reference_no IS NOT NULL AND is_voided = 0',
    );
  }

  /// Starter product categories for a new business. Safe to call twice —
  /// IDs are deterministic and inserts use "insert or ignore".
  Future<void> seedDefaultProductCategories(String businessId) async {
    const defaults = <String>[
      'Drinks',
      'Food',
      'Pastries',
      'Merchandise',
      'Services',
      'Uncategorized',
    ];

    await batch((b) {
      b.insertAll(productCategories, [
        for (var i = 0; i < defaults.length; i++)
          ProductCategoriesCompanion.insert(
            id: _cloudCompatibleDefaultId(
              'product_categories',
              'pcat_${defaults[i].toLowerCase()}_$businessId',
            ),
            businessId: businessId,
            name: defaults[i],
            sortOrder: Value(i),
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  /// Starter order types for a new business. Safe to call twice.
  Future<void> seedDefaultOrderTypes(String businessId) async {
    // name, kind, needs table, needs customer, needs address, needs order no.
    const defaults = <(String, String, bool, bool, bool, bool)>[
      ('Dine in', 'dine_in', true, false, false, false),
      ('Take out', 'takeout', false, false, false, false),
      ('GrabFood', 'online', false, false, false, true),
      ('Foodpanda', 'online', false, false, false, true),
      ('Maxim', 'online', false, false, false, true),
    ];
    await batch((b) {
      b.insertAll(posOrderTypes, [
        for (var i = 0; i < defaults.length; i++)
          PosOrderTypesCompanion.insert(
            id: _cloudCompatibleDefaultId(
              'pos_order_types',
              'otype_${defaults[i].$1.toLowerCase().replaceAll(' ', '_')}_$businessId',
            ),
            businessId: businessId,
            name: defaults[i].$1,
            sortOrder: Value(i),
            kind: Value(defaults[i].$2),
            requiresTable: Value(defaults[i].$3),
            requiresCustomer: Value(defaults[i].$4),
            requiresAddress: Value(defaults[i].$5),
            requiresReference: Value(defaults[i].$6),
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  Future<void> _createMembershipIndexes() async {
    // One row per user per business.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_business_members_business_user '
      'ON business_members (business_id, user_id)',
    );
    // Single-owner model: at most one live owner row per business.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_business_members_one_owner '
      "ON business_members (business_id) "
      "WHERE role = 'owner' AND status <> 'removed'",
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_business_members_user '
      'ON business_members (user_id, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_audit_logs_business_time '
      'ON audit_logs (business_id, created_at)',
    );
  }

  /// Case-insensitive unique login identity.
  Future<void> _createUserIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_users_email '
      'ON users (email COLLATE NOCASE)',
    );
  }

  /// At most one override per (business, role, permission) — the latest
  /// write wins via upsert.
  Future<void> _createPermissionOverrideIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_role_permission_overrides '
      'ON role_permission_overrides (business_id, role, permission)',
    );
  }

  /// Codes are short and human-typed, so they must be globally unique
  /// regardless of case.
  Future<void> _createInviteIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_business_invites_code '
      'ON business_invites (code COLLATE NOCASE)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_business_invites_business_status '
      'ON business_invites (business_id, status)',
    );
  }

  /// One config row per (business, module).
  Future<void> _createModuleConfigIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_module_configs_business_module '
      'ON business_module_configs (business_id, module_id)',
    );
  }

  /// Fast outbox scans: pending work per business, and one logical change
  /// per (entity, operation) so a repeat write can be deduplicated.
  Future<void> _createSyncOutboxIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_sync_outbox_pending '
      "ON sync_outbox (business_id, status, created_at)",
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_sync_outbox_entity '
      'ON sync_outbox (entity_type, entity_id)',
    );
  }

  /// Checkpoint + outbox-mutation lookups.
  Future<void> _createSyncCheckpointIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ix_sync_outbox_mutation '
      'ON sync_outbox (mutation_id)',
    );
  }

  /// Every existing business's ownerUserId becomes an Owner membership.
  /// INSERT OR IGNORE + deterministic id => safe to run on every open.
  Future<void> _backfillOwnerMemberships() async {
    await customStatement(
      "INSERT OR IGNORE INTO business_members "
      "(id, business_id, user_id, role, status) "
      "SELECT 'mem_owner_' || id, id, owner_user_id, 'owner', 'active' "
      "FROM businesses "
      "WHERE owner_user_id IS NOT NULL AND owner_user_id <> ''",
    );
  }

  /// Seeds the default chart of accounts + starter categories for a newly
  /// created business. Call this once, right after inserting the Businesses row.
  Future<void> seedDefaultsForBusiness(String businessId) async {
    // ============================================================
    // DEFAULT ACCOUNT IDS
    // ============================================================

    final cashAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_cash_$businessId',
    );

    final bankAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_bank_$businessId',
    );

    final ewalletAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_ewallet_$businessId',
    );

    final receivableAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_ar_$businessId',
    );

    final payableAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_ap_$businessId',
    );

    final equityAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_equity_$businessId',
    );

    final salesAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_sales_$businessId',
    );

    final otherIncomeAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_other_inc_$businessId',
    );

    final inventoryExpenseAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_inv_exp_$businessId',
    );

    final laborExpenseAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_labor_exp_$businessId',
    );

    final rentExpenseAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_rent_exp_$businessId',
    );

    final utilitiesExpenseAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_util_exp_$businessId',
    );

    final transportExpenseAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_transport_exp_$businessId',
    );

    final suppliesExpenseAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_supplies_exp_$businessId',
    );

    final otherExpenseAccountId = _cloudCompatibleDefaultId(
      'accounts',
      'acc_other_exp_$businessId',
    );

    // ============================================================
    // DEFAULT ACCOUNTS
    // ============================================================

    final defaultAccounts = <AccountsCompanion>[
      AccountsCompanion.insert(
        id: cashAccountId,
        businessId: businessId,
        name: 'Cash on Hand',
        type: 'asset',
        isPaymentAccount: const Value(true),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: bankAccountId,
        businessId: businessId,
        name: 'Bank Account',
        type: 'asset',
        isPaymentAccount: const Value(true),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: ewalletAccountId,
        businessId: businessId,
        name: 'E-Wallet',
        type: 'asset',
        isPaymentAccount: const Value(true),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: receivableAccountId,
        businessId: businessId,
        name: 'Accounts Receivable',
        type: 'asset',
        isPaymentAccount: const Value(false),
        subtype: const Value('current_asset'),
      ),

      AccountsCompanion.insert(
        id: payableAccountId,
        businessId: businessId,
        name: 'Accounts Payable',
        type: 'liability',
        isPaymentAccount: const Value(false),
        subtype: const Value('trade_payable'),
      ),

      AccountsCompanion.insert(
        id: equityAccountId,
        businessId: businessId,
        name: "Owner's Equity",
        type: 'equity',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: salesAccountId,
        businessId: businessId,
        name: 'Sales Income',
        type: 'income',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: otherIncomeAccountId,
        businessId: businessId,
        name: 'Other Income',
        type: 'income',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: inventoryExpenseAccountId,
        businessId: businessId,
        name: 'Inventory/Stock Expense',
        type: 'expense',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: laborExpenseAccountId,
        businessId: businessId,
        name: 'Salary/Labor Expense',
        type: 'expense',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: rentExpenseAccountId,
        businessId: businessId,
        name: 'Rent Expense',
        type: 'expense',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: utilitiesExpenseAccountId,
        businessId: businessId,
        name: 'Utilities Expense',
        type: 'expense',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: transportExpenseAccountId,
        businessId: businessId,
        name: 'Transportation Expense',
        type: 'expense',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: suppliesExpenseAccountId,
        businessId: businessId,
        name: 'Supplies Expense',
        type: 'expense',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),

      AccountsCompanion.insert(
        id: otherExpenseAccountId,
        businessId: businessId,
        name: 'Other Expense',
        type: 'expense',
        isPaymentAccount: const Value(false),
        subtype: const Value(null),
      ),
    ];

    await batch((b) {
      b.insertAll(accounts, defaultAccounts, mode: InsertMode.insertOrIgnore);
    });

    // Every business starts with a deterministic Main Branch. The branch's
    // cash drawer points to this business's default Cash on Hand account.
    await into(branches).insert(
      BranchesCompanion.insert(
        id: mainBranchId(businessId),
        businessId: businessId,
        name: 'Main Branch',
        code: const Value('MAIN'),
        cashAccountId: Value(cashAccountId),
        isHeadquarters: const Value(true),
      ),
      mode: InsertMode.insertOrIgnore,
    );

    // ============================================================
    // DEFAULT CATEGORY IDS
    // ============================================================

    final saleCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Sale_$businessId',
    );

    final serviceCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Service_$businessId',
    );

    final additionalCapitalCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Additional Capital_$businessId',
    );

    final otherIncomeCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Other Income_$businessId',
    );

    final inventoryCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Inventory_$businessId',
    );

    final suppliesCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Supplies_$businessId',
    );

    final laborCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Labor_$businessId',
    );

    final transportationCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Transportation_$businessId',
    );

    final rentCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Rent_$businessId',
    );

    final utilitiesCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Utilities_$businessId',
    );

    final otherExpenseCategoryId = _cloudCompatibleDefaultId(
      'categories',
      'Other_$businessId',
    );

    // ============================================================
    // DEFAULT CATEGORIES
    // IMPORTANT:
    // ledgerAccountId MUST use the actual account IDs above.
    // ============================================================

    final defaultCategories = <CategoriesCompanion>[
      CategoriesCompanion.insert(
        id: saleCategoryId,
        businessId: businessId,
        name: 'Sale',
        txnType: 'income',
        ledgerAccountId: salesAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: serviceCategoryId,
        businessId: businessId,
        name: 'Service',
        txnType: 'income',
        ledgerAccountId: salesAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: additionalCapitalCategoryId,
        businessId: businessId,
        name: 'Additional Capital',
        txnType: 'income',
        ledgerAccountId: equityAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: otherIncomeCategoryId,
        businessId: businessId,
        name: 'Other Income',
        txnType: 'income',
        ledgerAccountId: otherIncomeAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: inventoryCategoryId,
        businessId: businessId,
        name: 'Inventory',
        txnType: 'expense',
        ledgerAccountId: inventoryExpenseAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: suppliesCategoryId,
        businessId: businessId,
        name: 'Supplies',
        txnType: 'expense',
        ledgerAccountId: suppliesExpenseAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: laborCategoryId,
        businessId: businessId,
        name: 'Labor',
        txnType: 'expense',
        ledgerAccountId: laborExpenseAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: transportationCategoryId,
        businessId: businessId,
        name: 'Transportation',
        txnType: 'expense',
        ledgerAccountId: transportExpenseAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: rentCategoryId,
        businessId: businessId,
        name: 'Rent',
        txnType: 'expense',
        ledgerAccountId: rentExpenseAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: utilitiesCategoryId,
        businessId: businessId,
        name: 'Utilities',
        txnType: 'expense',
        ledgerAccountId: utilitiesExpenseAccountId,
        isCustom: const Value(false),
      ),

      CategoriesCompanion.insert(
        id: otherExpenseCategoryId,
        businessId: businessId,
        name: 'Other',
        txnType: 'expense',
        ledgerAccountId: otherExpenseAccountId,
        isCustom: const Value(false),
      ),
    ];

    await batch((b) {
      b.insertAll(
        categories,
        defaultCategories,
        mode: InsertMode.insertOrIgnore,
      );
    });

    // ============================================================
    // DEFAULT PRODUCT CATEGORIES
    // ============================================================

    await seedDefaultProductCategories(businessId);
    await seedDefaultOrderTypes(businessId);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'bos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
