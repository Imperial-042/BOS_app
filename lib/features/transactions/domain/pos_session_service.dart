// lib/features/production/domain/pos_session_service.dart
//
// Shifts ("sessions"), split-payment tenders, and void / restore.
//
// LEDGER RULE
//   Selling does not write to the journal. Sales are stored against the
//   open shift. When the shift is CLOSED, one ledger entry (+ one income
//   transaction) per payment account is posted for the shift's non-void
//   sales, through LedgerService.postEntry (same path saveIncome() uses).
//
// VOID RULE
//   A receipt can be voided / restored only while its shift is still open.
//   Voiding puts the consumed supplies back; restoring consumes them again
//   (and is refused if stock is no longer enough).

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_writer.dart';
import 'package:bos_application/core/auth/approval_service.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/ledger/ledger_service.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../transactions/presentation/screens/transaction_page.dart'
    show ledgerServiceProvider;
import 'payment_proof.dart';

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

/// "1,250.50" -> 125050. Null when empty / invalid / negative.
int? parsePesoCents(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', ''));
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

/// Cash drawer accounts (the only kind that can give change).
bool isCashAccount(String id, String name) {
  final i = id.toLowerCase();
  if (i.startsWith('acc_cash_')) return true;
  if (i.startsWith('acc_bank_') || i.startsWith('acc_ewallet_')) return false;
  return name.toLowerCase().contains('cash');
}

String friendlyError(Object e) =>
    e is StateError ? e.message : e.toString().replaceFirst('Exception: ', '');

// ---------------------------------------------------------------------------
// Inputs / outputs
// ---------------------------------------------------------------------------

/// One payment part of a sale. A normal sale has one; a split sale has many.
class SaleTenderInput {
  final String accountId;

  /// Portion of the bill this tender settles (change already excluded).
  final int amountCents;

  /// Cash handed over (cash only) — may exceed [amountCents].
  final int? tenderedCents;
  final int changeCents;
  final String? provider;
  final PaymentProofInput? proof;

  const SaleTenderInput({
    required this.accountId,
    required this.amountCents,
    this.tenderedCents,
    this.changeCents = 0,
    this.provider,
    this.proof,
  });
}

class CashierStat {
  final String name;
  final int count;
  final int cents;
  const CashierStat(this.name, this.count, this.cents);
}

class VoidedSaleInfo {
  final String code;
  final int cents;
  final String reason;
  final String cashier;
  final DateTime? voidedAt;
  final bool stockOnly;
  const VoidedSaleInfo({
    required this.code,
    required this.cents,
    required this.reason,
    required this.cashier,
    required this.voidedAt,
    required this.stockOnly,
  });
}

class ShiftSummary {
  final int salesCount;
  final int voidedCount;
  final int stockOnlyCount;
  final int grossCents;

  /// Money applied per payment account (change excluded).
  final Map<String, int> byAccountId;
  final Map<String, String> accountNames;
  final int cashSalesCents;
  final int expectedCashCents;

  // ---- new ----
  /// Total value of voided (non stock-only) receipts.
  final int voidedCents;

  /// Amount sold on credit (Accounts Receivable tender).
  final int creditCents;

  /// Cash physically handed over by customers, and the change returned.
  final int cashTenderedCents;
  final int changeGivenCents;

  /// Discounts given. sale.totalAmount is stored NET of discount, so this is
  /// 0 until the discount amount is persisted per sale (see notes in the
  /// reply). The UI hides the row while it is 0.
  final int discountCents;

  final DateTime? firstSaleAt;
  final DateTime? lastSaleAt;
  final List<CashierStat> cashiers;
  final List<VoidedSaleInfo> voids;

  const ShiftSummary({
    required this.salesCount,
    required this.voidedCount,
    required this.stockOnlyCount,
    required this.grossCents,
    required this.byAccountId,
    required this.accountNames,
    required this.cashSalesCents,
    required this.expectedCashCents,
    this.voidedCents = 0,
    this.creditCents = 0,
    this.cashTenderedCents = 0,
    this.changeGivenCents = 0,
    this.discountCents = 0,
    this.firstSaleAt,
    this.lastSaleAt,
    this.cashiers = const [],
    this.voids = const [],
  });
}

class CloseResult {
  final int journalEntries;
  final int postedCents;
  final int varianceCents; // counted - expected

  const CloseResult(this.journalEntries, this.postedCents, this.varianceCents);
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final posSessionServiceProvider = Provider<PosSessionService>(
  (ref) => PosSessionService(
    ref.watch(databaseProvider),
    ref.watch(ledgerServiceProvider),
    auth: ref.watch(authorizationServiceProvider),
    viewBranchId: ref.watch(selectedBranchIdProvider),
  ),
);

/// The currently open shift, or null when the register is closed.
final currentPosSessionProvider = StreamProvider<PosSession?>((ref) {
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final branchId = ref.watch(selectedBranchIdProvider);
  return (db.select(db.posSessions)
        ..where(
          (s) =>
              s.businessId.equals(businessId) &
              s.branchId.equals(branchId) &
              s.status.equals('open'),
        )
        ..limit(1))
      .watch()
      .map((rows) => rows.isEmpty ? null : rows.first);
});
// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class PosSessionService {
  final AppDatabase db;
  final LedgerService ledgerService;
  final AuthorizationService? auth;
  final String? viewBranchId;
  late final StockService _stock = StockService(db, viewBranchId: viewBranchId);

  PosSessionService(
    this.db,
    this.ledgerService, {
    this.auth,
    this.viewBranchId,
  });

  Future<String?> _branchCashAccountId(
    String businessId,
    String? branchId,
  ) async {
    if (branchId == null) return null;
    final b = await (db.select(
      db.branches,
    )..where((x) => x.id.equals(branchId))).getSingleOrNull();
    return b?.cashAccountId;
  }

  /// True when [normalizedReference] already belongs to a NON-voided sale.
  /// (A voided sale releases its payment reference.)
  Future<bool> isReferenceUsed(String normalizedReference) =>
      referenceInUse(db, normalizedReference);

  /// Static so ProductionService.recordSale can use the exact same rule.
  static Future<bool> referenceInUse(
    AppDatabase db,
    String normalizedReference,
  ) async {
    final tenderQuery = db.select(db.posSaleTenders)
      ..where(
        (t) =>
            t.referenceNo.equals(normalizedReference) &
            t.isVoided.equals(false),
      )
      ..limit(1);
    if ((await tenderQuery.get()).isNotEmpty) return true;

    final paymentQuery =
        db.select(db.posSalePayments).join([
            innerJoin(
              db.posSales,
              db.posSales.id.equalsExp(db.posSalePayments.saleId),
            ),
          ])
          ..where(
            db.posSalePayments.referenceNo.equals(normalizedReference) &
                db.posSales.isVoided.equals(false),
          )
          ..limit(1);
    return (await paymentQuery.get()).isNotEmpty;
  }
  // ----- Tenders (called from ProductionService.recordSale) ----------------

  static Future<void> insertTenders(
    AppDatabase db,
    String saleId,
    List<SaleTenderInput> tenders,
  ) async {
    for (final t in tenders) {
      await db
          .into(db.posSaleTenders)
          .insert(
            PosSaleTendersCompanion.insert(
              id: _uuid.v4(),
              saleId: saleId,
              accountId: t.accountId,
              amount: t.amountCents,
              tendered: Value(t.tenderedCents),
              changeGiven: Value(t.changeCents),
              referenceNo: Value(t.proof?.referenceNo),
              paidAt: Value(t.proof?.paidAt),
              provider: Value(t.provider ?? t.proof?.provider),
              photoPath: Value(t.proof?.photoPath),
            ),
          );
    }
  }

  // ----- Open ---------------------------------------------------------------

  Future<PosSession> openSession({
    required String businessId,
    required String branchId,
    required int openingCashCents,
    String? notes,
    String? userId,
  }) {
    return db.transaction(() async {
      final branch = await (db.select(db.branches)..where(
            (b) =>
                b.id.equals(branchId) &
                b.businessId.equals(businessId) &
                b.isActive.equals(true),
          ))
          .getSingleOrNull();
      if (branch == null) {
        throw StateError('Choose an active branch in this business.');
      }

      final open =
          await (db.select(db.posSessions)..where(
                (s) =>
                    s.businessId.equals(businessId) &
                    s.branchId.equals(branchId) &
                    s.status.equals('open'),
              ))
              .get();
      if (open.isNotEmpty) throw StateError('A shift is already open.');

      final id = _uuid.v4();
      await db
          .into(db.posSessions)
          .insert(
            PosSessionsCompanion.insert(
              id: id,
              businessId: businessId,
              openingCash: Value(openingCashCents),
              branchId: Value(branchId),
              notes: Value(notes),
            ),
          );

      await AuditWriter.write(
        db,
        businessId: businessId,
        userId: userId,
        action: 'sales.shift_opened',
        module: AuditModule.sales,
        actionType: AuditActionType.create,
        entityType: 'pos_sessions',
        entityId: id,
        entityLabel: 'Shift #${id.substring(0, 6).toUpperCase()}',
        after: {'openingCash': openingCashCents},
        details: {'notes': notes},
      );
      return (db.select(
        db.posSessions,
      )..where((s) => s.id.equals(id))).getSingle();
    });
  }

  // ----- Summary ------------------------------------------------------------

  Future<ShiftSummary> summarize(PosSession session) async {
    final sales = await (db.select(
      db.posSales,
    )..where((s) => s.sessionId.equals(session.id))).get();

    final live = sales.where((s) => !s.isVoided).toList();
    final paid = live.where((s) => !s.isStockOnly).toList();
    final voided = sales.where((s) => s.isVoided).toList();

    final tenders = paid.isEmpty
        ? <PosSaleTender>[]
        : await (db.select(
            db.posSaleTenders,
          )..where((t) => t.saleId.isIn(paid.map((s) => s.id).toList()))).get();

    final accounts = await (db.select(
      db.accounts,
    )..where((a) => a.businessId.equals(session.businessId))).get();
    final names = {for (final a in accounts) a.id: a.name};

    final branchCashId = await _branchCashAccountId(
      session.businessId,
      session.branchId,
    );
    bool isBranchCash(String id) => branchCashId != null
        ? id == branchCashId
        : isCashAccount(id, names[id] ?? '');

    String? arId;
    try {
      arId = (await ledgerService.receivableAccount(session.businessId)).id;
    } on LedgerException {
      arId = null;
    }

    final byAccount = <String, int>{};
    var cash = 0;
    var cashTendered = 0;
    var changeGiven = 0;
    var credit = 0;
    for (final t in tenders) {
      byAccount[t.accountId] = (byAccount[t.accountId] ?? 0) + t.amount;
      if (arId != null && t.accountId == arId) credit += t.amount;
      if (isBranchCash(t.accountId)) {
        cash += t.amount;
        cashTendered += t.tendered ?? t.amount;
        changeGiven += t.changeGiven;
      }
    }

    final cashierCount = <String, int>{};
    final cashierCents = <String, int>{};
    DateTime? first;
    DateTime? last;
    for (final s in paid) {
      final raw = (s.cashierName ?? '').trim();
      final name = raw.isEmpty ? 'Unassigned' : raw;
      cashierCount[name] = (cashierCount[name] ?? 0) + 1;
      cashierCents[name] = (cashierCents[name] ?? 0) + s.totalAmount;
      if (first == null || s.saleDate.isBefore(first)) first = s.saleDate;
      if (last == null || s.saleDate.isAfter(last)) last = s.saleDate;
    }
    final cashiers = [
      for (final e in cashierCents.entries)
        CashierStat(e.key, cashierCount[e.key] ?? 0, e.value),
    ]..sort((a, b) => b.cents.compareTo(a.cents));

    final voidList =
        [
          for (final v in voided)
            VoidedSaleInfo(
              code: v.id.substring(0, 8).toUpperCase(),
              cents: v.totalAmount,
              reason: (v.voidReason ?? '').trim(),
              cashier: (v.cashierName ?? '').trim().isEmpty
                  ? 'Unassigned'
                  : v.cashierName!.trim(),
              voidedAt: v.voidedAt,
              stockOnly: v.isStockOnly,
            ),
        ]..sort(
          (a, b) =>
              (b.voidedAt ?? DateTime(0)).compareTo(a.voidedAt ?? DateTime(0)),
        );
    return ShiftSummary(
      salesCount: paid.length,
      voidedCount: voided.length,
      stockOnlyCount: live.where((s) => s.isStockOnly).length,
      grossCents: paid.fold<int>(0, (sum, s) => sum + s.totalAmount),
      byAccountId: byAccount,
      accountNames: names,
      cashSalesCents: cash,
      expectedCashCents: session.openingCash + cash,
      voidedCents: voided
          .where((v) => !v.isStockOnly)
          .fold<int>(0, (sum, v) => sum + v.totalAmount),
      creditCents: credit,
      cashTenderedCents: cashTendered,
      changeGivenCents: changeGiven,
      firstSaleAt: first,
      lastSaleAt: last,
      cashiers: cashiers,
      voids: voidList,
    );
  }

  /// Money per (sale day, payment account) for the shift's real sales. Credit
  /// (Accounts Receivable) amounts are also split per customer.
  Future<List<_PostingBucket>> _postingBuckets(
    String sessionId,
    String? arId,
  ) async {
    final sales =
        await (db.select(db.posSales)..where(
              (x) =>
                  x.sessionId.equals(sessionId) &
                  x.isVoided.equals(false) &
                  x.isStockOnly.equals(false),
            ))
            .get();
    if (sales.isEmpty) return const [];

    final saleById = {for (final s in sales) s.id: s};
    final tenders = await (db.select(
      db.posSaleTenders,
    )..where((t) => t.saleId.isIn(saleById.keys.toList()))).get();

    final map = <String, _PostingBucket>{};
    for (final t in tenders) {
      final sale = saleById[t.saleId]!;
      final d = sale.saleDate;
      final day = DateTime(d.year, d.month, d.day);
      final credit = arId != null && t.accountId == arId;
      final customerId = credit ? sale.customerId : null;
      if (credit && customerId == null) {
        throw StateError(
          'A credit sale in this shift has no customer, so it can\'t be '
          'posted. Void that receipt and ring it up again.',
        );
      }
      final bucket = map.putIfAbsent(
        '${day.toIso8601String()}|${t.accountId}|${customerId ?? ''}',
        () => _PostingBucket(
          day: day,
          accountId: t.accountId,
          customerId: customerId,
          isCredit: credit,
        ),
      );
      bucket.cents += t.amount;
      if (d.isAfter(bucket.latest)) bucket.latest = d;
    }
    final out = map.values.toList()..sort((a, b) => a.day.compareTo(b.day));
    return out;
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ----- Close (this is where the ledger gets written) ---------------------

  Future<CloseResult> closeSession({
    required String sessionId,
    required int countedCashCents,
    String? notes,
    String? userId,
  }) {
    return db.transaction(() async {
      final s = await (db.select(
        db.posSessions,
      )..where((x) => x.id.equals(sessionId))).getSingle();
      if (s.status != 'open') throw StateError('This shift is already closed.');

      final summary = await summarize(s);
      final biz = s.businessId;
      final now = DateTime.now();
      final short = s.id.substring(0, 6).toUpperCase();

      final cats =
          await (db.select(db.categories)..where(
                (c) =>
                    c.businessId.equals(biz) &
                    c.txnType.equals('income') &
                    c.name.equals('Sale') &
                    c.isActive.equals(true),
              ))
              .get();
      if (cats.isEmpty && summary.byAccountId.isNotEmpty) {
        throw StateError('No "Sale" income category found for this business.');
      }
      final categoryId = cats.isEmpty ? '' : cats.first.id;

      var entries = 0;
      var posted = 0;

      String? arId;
      try {
        arId = (await ledgerService.receivableAccount(biz)).id;
      } on LedgerException {
        arId = null;
      }

      final buckets = await _postingBuckets(sessionId, arId);
      final multiDay = buckets.map((b) => b.day).toSet().length > 1;

      for (final bk in buckets) {
        if (bk.cents <= 0) continue;

        final txnId = _uuid.v4();
        final base = bk.isCredit
            ? 'POS credit sales — shift #$short'
            : 'POS sales — shift #$short';
        final desc = multiDay ? '$base (${_ymd(bk.day)})' : base;

        // Credit: paymentAccountId is the Accounts Receivable account, which
        // makes postEntry debit AR and credit Sales Income.
        final journalEntryId = await ledgerService.postEntry(
          businessId: biz,
          categoryId: categoryId,
          amount: bk.cents,
          paymentAccountId: bk.accountId,
          sourceType: 'income',
          sourceId: txnId,
          description: desc,
          date: bk.latest,
          branchId: s.branchId,
        );

        await db
            .into(db.incomeTransactions)
            .insert(
              IncomeTransactionsCompanion.insert(
                id: txnId,
                businessId: biz,
                txnDate: bk.latest,
                categoryId: categoryId,
                amount: bk.cents,
                description: Value(desc),
                // A credit sale has a customer and NO payment account: that
                // is exactly what the Customers/Receivables balance counts.
                customerId: Value(bk.customerId),
                paymentAccountId: Value(bk.isCredit ? null : bk.accountId),
                reference: Value('POS-$short'),
                status: const Value('completed'),
                journalEntryId: Value(journalEntryId),
                branchId: Value(s.branchId),
              ),
            );

        entries++;
        posted += bk.cents;
      }

      await _postCashVariance(
        biz: biz,
        summary: summary,
        variance: countedCashCents - summary.expectedCashCents,
        sessionId: sessionId,
        short: short,
        branchId: s.branchId,
      );

      await (db.update(
        db.posSessions,
      )..where((x) => x.id.equals(sessionId))).write(
        PosSessionsCompanion(
          status: const Value('closed'),
          closedAt: Value(now),
          countedCash: Value(countedCashCents),
          expectedCash: Value(summary.expectedCashCents),
          notes: notes == null ? const Value.absent() : Value(notes),
        ),
      );
      await AuditWriter.write(
        db,
        businessId: biz,
        userId: userId,
        action: 'sales.shift_closed',
        module: AuditModule.sales,
        actionType: AuditActionType.update,
        entityType: 'pos_sessions',
        entityId: sessionId,
        entityLabel: 'Shift #$short',
        before: {'status': 'open'},
        after: {
          'status': 'closed',
          'countedCash': countedCashCents,
          'expectedCash': summary.expectedCashCents,
          'variance': countedCashCents - summary.expectedCashCents,
        },
        details: {
          'openingCash': s.openingCash,
          'salesCount': summary.salesCount,
          'voidedCount': summary.voidedCount,
          'stockOnlyCount': summary.stockOnlyCount,
          'gross': summary.grossCents,
          'posted': posted,
          'journalEntries': entries,
          'notes': notes,
        },
      );
      return CloseResult(
        entries,
        posted,
        countedCashCents - summary.expectedCashCents,
      );
    });
  }

  /// Books a drawer difference so the books match the cash that is really
  /// there. Short: Dr "Cash Over/Short", Cr cash. Over: Dr cash, Cr over/short.
  /// If the cash account can't be found the shift still closes; the variance
  /// stays recorded on the shift and in the audit log.
  Future<void> _postCashVariance({
    required String biz,
    required ShiftSummary summary,
    required int variance,
    required String sessionId,
    required String short,
    String? branchId,
  }) async {
    if (variance == 0) return;

    String? cashId = await _branchCashAccountId(biz, branchId);
    if (cashId == null) {
      for (final id in summary.byAccountId.keys) {
        if (isCashAccount(id, summary.accountNames[id] ?? '')) {
          cashId = id;
          break;
        }
      }
    }
    cashId ??= AppDatabase.cloudCompatibleDefaultId(
      'accounts',
      'acc_cash_$biz',
    );

    final overShortId = AppDatabase.cloudCompatibleDefaultId(
      'accounts',
      'acc_cash_over_short_$biz',
    );

    try {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: overShortId,
              businessId: biz,
              name: 'Cash Over/Short',
              type: 'expense',
              isPaymentAccount: const Value(false),
            ),
            mode: InsertMode.insertOrIgnore,
          );

      final isShort = variance < 0;
      await ledgerService.postSimpleEntry(
        businessId: biz,
        date: DateTime.now(),
        amount: variance.abs(),
        debitAccountId: isShort ? overShortId : cashId,
        creditAccountId: isShort ? cashId : overShortId,
        sourceType: 'cash_variance',
        sourceId: sessionId,
        description: 'Cash ${isShort ? 'short' : 'over'} — shift #$short',
        branchId: branchId,
      );
    } on LedgerException {
      // Cash account missing or renamed: don't block closing the shift.
    }
  }

  // ----- Void / restore -----------------------------------------------------

  Future<void> voidSale(
    String saleId, {
    String? reason,
    String? userId,
    String? approvedByUserId,
    String? approvedByName,
  }) async {
    // A void must say why (AuditActionType.voided.requiresReason).
    final cleanReason = reason?.trim() ?? '';
    if (cleanReason.isEmpty) {
      throw StateError('A reason is required to void a receipt.');
    }

    await db.transaction(() async {
      final sale = await _sale(saleId);
      await _requireApproval(sale.businessId, approvedByUserId);
      if (sale.isVoided) throw StateError('This receipt is already void.');
      await _requireOpenShift(sale);

      await _moveStock(sale, restoring: false);
      await (db.update(db.posSaleTenders)
            ..where((t) => t.saleId.equals(saleId)))
          .write(const PosSaleTendersCompanion(isVoided: Value(true)));

      await (db.update(db.posSales)..where((s) => s.id.equals(saleId))).write(
        PosSalesCompanion(
          isVoided: const Value(true),
          voidedAt: Value(DateTime.now()),
          voidReason: Value(cleanReason),
        ),
      );

      await AuditWriter.write(
        db,
        businessId: sale.businessId,
        userId: userId,
        action: 'sales.sale_voided',
        module: AuditModule.sales,
        actionType: AuditActionType.voided,
        entityType: 'pos_sales',
        entityId: saleId,
        entityLabel: 'Sale ${saleId.substring(0, 8).toUpperCase()}',
        reason: cleanReason,
        before: {'isVoided': false},
        after: {'isVoided': true},
        details: {
          'total': sale.totalAmount,
          'stockOnly': sale.isStockOnly,
          'cashier': sale.cashierName,
          'sessionId': sale.sessionId,
          'approvedByUserId': approvedByUserId,
          'approvedByName': approvedByName,
        },
      );
    });
  }

  Future<void> restoreSale(
    String saleId, {
    String? userId,
    String? approvedByUserId,
    String? approvedByName,
  }) async {
    await db.transaction(() async {
      final sale = await _sale(saleId);
      await _requireApproval(sale.businessId, approvedByUserId);
      if (!sale.isVoided) throw StateError('This receipt is not void.');
      await _requireOpenShift(sale);

      // Its payment reference may have been used again since the void.
      final tendersToRestore = await (db.select(
        db.posSaleTenders,
      )..where((t) => t.saleId.equals(saleId))).get();
      for (final t in tendersToRestore) {
        final reference = t.referenceNo;
        if (reference != null && await referenceInUse(db, reference)) {
          throw StateError(
            'Payment reference $reference was already used on another sale, '
            'so this receipt can\'t be restored.',
          );
        }
      }

      await _moveStock(sale, restoring: true);
      await (db.update(db.posSaleTenders)
            ..where((t) => t.saleId.equals(saleId)))
          .write(const PosSaleTendersCompanion(isVoided: Value(false)));

      await (db.update(db.posSales)..where((s) => s.id.equals(saleId))).write(
        const PosSalesCompanion(
          isVoided: Value(false),
          voidedAt: Value(null),
          voidReason: Value(null),
        ),
      );

      await AuditWriter.write(
        db,
        businessId: sale.businessId,
        userId: userId,
        action: 'sales.sale_restored',
        module: AuditModule.sales,
        actionType: AuditActionType.update,
        entityType: 'pos_sales',
        entityId: saleId,
        entityLabel: 'Sale ${saleId.substring(0, 8).toUpperCase()}',
        before: {'isVoided': true, 'voidReason': sale.voidReason},
        after: {'isVoided': false},
        details: {
          'total': sale.totalAmount,
          'sessionId': sale.sessionId,
          'approvedByUserId': approvedByUserId,
          'approvedByName': approvedByName,
        },
      );
    });
  }

  Future<PosSale> _sale(String id) =>
      (db.select(db.posSales)..where((s) => s.id.equals(id))).getSingle();

  Future<void> _requireOpenShift(PosSale sale) async {
    if (sale.sessionId == null) {
      throw StateError(
        'This sale was recorded before shifts existed and is already in the '
        'journal, so it can\'t be voided here.',
      );
    }
    final s = await (db.select(
      db.posSessions,
    )..where((x) => x.id.equals(sale.sessionId!))).getSingleOrNull();
    if (s == null || s.status != 'open') {
      throw StateError(
        'This shift is closed and its sales are already posted to the '
        'journal, so the receipt can no longer be changed.',
      );
    }
  }

  Future<void> _moveStockedProducts(
    PosSale sale, {
    required bool restoring,
  }) async {
    final branchId = sale.branchId ?? AppDatabase.mainBranchId(sale.businessId);
    final items = await (db.select(
      db.posSaleItems,
    )..where((i) => i.saleId.equals(sale.id))).get();
    for (final item in items) {
      final pid = item.productId;
      if (pid == null) continue;
      final p = await (db.select(
        db.products,
      )..where((x) => x.id.equals(pid))).getSingleOrNull();
      if (p == null || p.trackingType != 'stocked') continue;
      if (restoring &&
          await _stock.productQty(branchId, pid) + 1e-9 < item.quantity) {
        throw StateError(
          'Not enough ${p.name} in stock to restore this receipt.',
        );
      }
      await _stock.moveProduct(
        branchId: branchId,
        productId: pid,
        businessId: sale.businessId,
        type: restoring ? 'pos_restore' : 'pos_void',
        quantity: restoring ? -item.quantity : item.quantity,
        referenceType: 'pos_sale',
        referenceId: sale.id,
      );
    }
  }

  Future<void> _moveStock(PosSale sale, {required bool restoring}) async {
    await _moveStockedProducts(sale, restoring: restoring);
    final fallback = sale.branchId ?? AppDatabase.mainBranchId(sale.businessId);
    final moves =
        await (db.select(db.inventoryMovements)..where(
              (m) =>
                  m.referenceId.equals(sale.id) &
                  m.movementType.equals('production_consumption'),
            ))
            .get();
    if (moves.isEmpty) return;

    if (restoring) {
      final need = <String, double>{};
      for (final m in moves) {
        final k = '${m.branchId ?? fallback}|${m.supplyId}';
        need[k] = (need[k] ?? 0) + m.quantity.abs();
      }
      for (final e in need.entries) {
        final p = e.key.split('|');
        if (await _stock.supplyQty(p[0], p[1]) + 1e-9 < e.value) {
          throw StateError('Not enough stock to restore this receipt.');
        }
      }
    }

    for (final m in moves) {
      await _stock.moveSupply(
        branchId: m.branchId ?? fallback,
        supplyId: m.supplyId,
        type: 'manual_adjustment',
        unit: m.unit,
        quantity: restoring ? m.quantity : -m.quantity,
        referenceType: restoring ? 'pos_restore' : 'pos_void',
        referenceId: sale.id,
        notes: restoring ? 'Receipt restored' : 'Receipt voided',
      );
    }
  }

  /// With approval PINs set up, void / restore need an owner or manager PIN
  /// (checked on screen, which hands us the approver's id). Until any PIN
  /// exists, the signed-in user just needs the void permission.
  Future<void> _requireApproval(
    String businessId,
    String? approvedByUserId,
  ) async {
    if (approvedByUserId != null) return;
    if (await ApprovalService.anyPinSet(db, businessId)) {
      throw StateError('Manager approval is required for this action.');
    }
    auth?.require(BosPermission.salesVoid, businessId: businessId);
  }
}

class _PostingBucket {
  final DateTime day;
  final String accountId;
  final String? customerId;
  final bool isCredit;
  int cents = 0;
  DateTime latest;

  _PostingBucket({
    required this.day,
    required this.accountId,
    this.customerId,
    this.isCredit = false,
  }) : latest = day;
}
