// lib/features/production/presentation/screens/pos_payment_sheet.dart
//
// Payment step of the POS. Opened from the order sheet's "Checkout" button.
//
//   * Phone  (< 720): a tall bottom sheet, one column. The order recap is a
//     collapsible card at the top.
//   * Tablet / wide (>= 720): a centred dialog. From ~820 it splits in two:
//     order recap on the left, payment form on the right.
//
// RULES (unchanged from before)
//   * Cash: enter the amount received -> change is calculated live.
//   * Split payment: add more than one payment row (e.g. Cash + GCash).
//     Only cash can overpay (that's what change is for).
//   * Nothing is posted to the journal here. Sales attach to the open shift
//     and are posted when the shift is closed.
//
// Returns true from [showPosPaymentSheet] when the sale was recorded.

import 'dart:math' as math;

import 'package:bos_application/core/auth/auth_providers.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/features/transactions/domain/pos_discount.dart';
import 'package:bos_application/features/transactions/domain/tender_calculator.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_credit.dart';
import 'package:bos_application/features/transactions/presentation/widgets/order_details_card.dart';
import 'package:bos_application/features/transactions/presentation/widgets/pos_customer_picker.dart';
import 'package:bos_application/features/transactions/presentation/widgets/pos_discount_sheet.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show ledgerVersionProvider, kCurrentBusinessId;
import '../../domain/payment_proof.dart';
import '../../domain/pos_session_service.dart';
import '../../domain/production_service.dart' show SaleLineInput;
import '../widgets/payment_proof_sheet.dart';
import '../widgets/payment_provider_picker.dart';
import 'pos_order_state.dart';
import 'products_page.dart'
    show producibilityProvider, productionServiceProvider;

String _peso(int cents) => formatPeso(cents);

/// Payment accounts the cashier may use at THIS branch: everything except
/// the cash drawers that belong to other branches.
final posPaymentAccountsProvider = FutureProvider<List<Account>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);
  final businessId = ref.watch(selectedBusinessIdProvider);
  final branchId = ref.watch(selectedBranchIdProvider);

  final branches = await (db.select(
    db.branches,
  )..where((b) => b.businessId.equals(businessId))).get();
  final otherDrawers = {
    for (final b in branches)
      if (b.id != branchId && b.cashAccountId != null) b.cashAccountId!,
  };

  final rows =
      await (db.select(db.accounts)..where(
            (a) =>
                a.businessId.equals(businessId) &
                a.isPaymentAccount.equals(true) &
                a.isActive.equals(true),
          ))
          .get();
  return [
    for (final a in rows)
      if (!otherDrawers.contains(a.id)) a,
  ];
});

/// Opens the payment step. Resolves to true when the sale was recorded.
Future<bool?> showPosPaymentSheet(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;

  if (width >= 720) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: const _PaymentSheet(dialog: true),
        ),
      ),
    );
  }

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PaymentSheet(),
  );
}

// ============================================================================
// PAYMENT ROW MODEL
// ============================================================================

enum _CustMode { none, existing, newCustomer }

class _Tender {
  String? accountId;
  String? provider;
  PaymentProofInput? proof;
  int? proofForCents;

  /// True until the cashier types a custom amount. While true (and this is
  /// the only payment row) the amount follows the order total.
  bool auto = true;

  /// True while the shown amount was filled in by the app. The next keypad
  /// digit then starts a new number instead of appending to it.
  bool fresh = true;

  final TextEditingController amountCtrl = TextEditingController();

  int get cents => parsePesoCents(amountCtrl.text) ?? 0;

  void dispose() => amountCtrl.dispose();
}

typedef _Calc = TenderCalc;

/// A payment choice that is not a real account: charge to a customer's tab.
class _CreditOption {
  final String id;
  final String name = 'On credit';
  const _CreditOption(this.id);
}

// ============================================================================
// PAYMENT SHEET
// ============================================================================

class _PaymentSheet extends ConsumerStatefulWidget {
  final bool dialog;
  const _PaymentSheet({this.dialog = false});

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final List<_Tender> _tenders = [_Tender()];
  final _notesCtrl = TextEditingController();

  /// One key per checkout attempt: pressing Complete twice saves one sale.
  final String _saleKey = const Uuid().v4();
  bool _stockOnly = false;
  PosDiscount? _discount;
  Customer? _customer;
  _CustMode _custMode = _CustMode.none;
  final _custName = TextEditingController();
  final _custAddress = TextEditingController();
  final _custTin = TextEditingController();
  bool _processing = false;
  String? _error;

  static const bool _requireProvider = true;

  @override
  void dispose() {
    for (final t in _tenders) {
      t.dispose();
    }
    _notesCtrl.dispose();
    _custName.dispose();
    _custAddress.dispose();
    _custTin.dispose();
    super.dispose();
  }

  // ---------- account helpers -------------------------------------------------

  String? _nameOf(String? id) {
    final list = ref.read(posPaymentAccountsProvider).value;
    if (list == null || id == null) return null;
    for (final a in list) {
      if (a.id == id) return a.name;
    }
    return null;
  }

  bool _isCash(_Tender t) {
    final name = _nameOf(t.accountId);
    return name != null && isCashAccount(t.accountId!, name);
  }

  PaymentProviderKind? _kindOf(_Tender t) {
    final name = _nameOf(t.accountId);
    if (name == null) return null;
    return paymentKindOf(t.accountId!, name);
  }

  void _setAmount(_Tender t, int cents) {
    t.amountCtrl.text = (cents / 100).toStringAsFixed(2);
    t.fresh = true;
  }

  void _key(_Tender t, String k) {
    HapticFeedback.selectionClick();
    var s = t.amountCtrl.text;

    if (k == 'C') {
      s = '';
    } else if (k == '⌫') {
      s = t.fresh || s.isEmpty ? '' : s.substring(0, s.length - 1);
    } else {
      if (t.fresh) s = '';
      if (k == '.') {
        if (s.contains('.')) return;
        if (s.isEmpty) s = '0';
        s += '.';
      } else {
        final dot = s.indexOf('.');
        if (dot >= 0 && s.length - dot > 2) return; // 2 decimals max
        if (s.length >= 9) return;
        s = s == '0' ? k : s + k;
      }
    }
    t.fresh = false;
    setState(() {
      t.amountCtrl.text = s;
      t.auto = false;
      _error = null;
    });
  }

  /// What is still unpaid if every OTHER row is taken at face value.
  int _remainingFor(int index, int total) {
    var others = 0;
    for (var j = 0; j < _tenders.length; j++) {
      if (j != index && _tenders[j].accountId != null) {
        others += _tenders[j].cents;
      }
    }
    return math.max(0, total - others);
  }

  int _subtotal(List<POSLineItem> order) =>
      order.fold<int>(0, (sum, l) => sum + l.lineTotal);

  int _discountOf(int subtotal) =>
      _stockOnly ? 0 : (_discount?.amountFor(subtotal) ?? 0);

  int _orderTotal(List<POSLineItem> order) {
    final sub = _subtotal(order);
    return sub - _discountOf(sub);
  }

  /// Keeps a lone, untouched payment row equal to the order total when the
  /// total changes (for example after a discount).
  void _syncAuto(List<POSLineItem> order) {
    if (_tenders.length != 1) return;
    final t = _tenders.first;
    if (!t.auto || t.accountId == null) return;
    _setAmount(t, _orderTotal(order));
    if (mounted) setState(() {});
  }

  /// Applies (or clears, with null) the discount and keeps a lone,
  /// untouched payment row equal to the new total.
  void _setDiscount(PosDiscount? d) {
    setState(() {
      _discount = d;
      _error = null;
    });
    _syncAuto(ref.read(posOrderProvider));
  }

  Future<void> _pickCustomDiscount(int subtotal) async {
    final result = await showPosDiscountSheet(
      context,
      subtotalCents: subtotal,
      current: _discount,
    );
    if (result == null || !mounted) return;
    _setDiscount(result.discount);
  }

  _Calc _calc(int total) => TenderCalculator.calculate(
    total: total,
    lines: [
      for (final t in _tenders)
        if (t.accountId != null) TenderLine(isCash: _isCash(t), cents: t.cents),
    ],
  );

  // ---------- provider + proof ------------------------------------------------

  Future<void> _pickProvider(_Tender t, PaymentProviderKind kind) async {
    final picked = await showPaymentProviderPicker(
      context,
      kind: kind,
      selected: t.provider,
    );
    if (picked != null && mounted) {
      setState(() {
        t.provider = picked;
        _error = null;
      });
    }
  }

  Future<bool> _referenceUsedInDb(String reference) =>
      ref.read(posSessionServiceProvider).isReferenceUsed(reference);

  Future<void> _attachProof(_Tender t) async {
    final expected = t.cents;
    final proof = await showPaymentProofSheet(
      context,
      expectedCents: expected,
      expectedProvider: t.provider,
      isReferenceUsed: (reference) async {
        for (final other in _tenders) {
          if (!identical(other, t) && other.proof?.referenceNo == reference) {
            return true;
          }
        }
        return _referenceUsedInDb(reference);
      },
    );
    if (proof != null && mounted) {
      setState(() {
        t.proof = proof;
        t.proofForCents = expected;
        _error = null;
      });
    }
  }

  // ---------- validation + save -----------------------------------------------

  String? _validatePayments(int total) {
    if (_tenders.any((t) => t.accountId == null)) {
      return 'Choose a payment method for every payment, or turn on '
          '"Stock deduction only".';
    }
    if (total <= 0) {
      return 'The order total is ₱0.00. Set a sell price on the item(s), or '
          'turn on "Stock deduction only".';
    }

    final c = _calc(total);

    final customerProblem = _customerProblem();
    if (customerProblem != null) return customerProblem;

    for (final t in _tenders) {
      final name = _nameOf(t.accountId) ?? 'this account';
      if (t.cents <= 0) {
        return _isCash(t)
            ? 'Enter the cash received.'
            : 'Enter the amount paid via $name.';
      }
    }
    if (c.nonCashOver) {
      return 'Bank / e-wallet amounts add up to more than the order total. '
          'Only cash can give change.';
    }
    if (c.cashDue == 0 && c.cashReceived > 0) {
      return 'The other payments already cover the total — remove the cash '
          'payment.';
    }
    if (c.shortfall > 0) {
      return 'Payments are short by ${_peso(c.shortfall)}.';
    }

    for (final t in _tenders) {
      if (_isCash(t)) continue;
      final kind = _kindOf(t);
      if (_requireProvider && kind != null && t.provider == null) {
        return 'Select the ${kind.noun} used for the ${_nameOf(t.accountId)} '
            'payment.';
      }
      if (t.proof != null && t.proofForCents != t.cents) {
        return 'A payment amount changed after its proof was attached. '
            'Scan the proof again.';
      }
    }
    return null;
  }

  List<SaleTenderInput> _buildTenders(int total) {
    final c = _calc(total);
    var appliedLeft = c.cashApplied;
    final out = <SaleTenderInput>[];

    for (final t in _tenders) {
      if (_isCash(t)) {
        final applied = math.min(t.cents, appliedLeft);
        appliedLeft -= applied;
        out.add(
          SaleTenderInput(
            accountId: t.accountId!,
            amountCents: applied,
            tenderedCents: t.cents,
            changeCents: t.cents - applied,
          ),
        );
      } else {
        final p = t.proof;
        out.add(
          SaleTenderInput(
            accountId: t.accountId!,
            amountCents: t.cents,
            provider: t.provider ?? p?.provider,
            proof: p == null
                ? null
                : PaymentProofInput(
                    referenceNo: p.referenceNo,
                    amountCents: p.amountCents,
                    paidAt: p.paidAt,
                    provider: t.provider ?? p.provider,
                    photoPath: p.photoPath,
                  ),
          ),
        );
      }
    }
    return out;
  }

  Future<void> _completeSale() async {
    if (_processing) return;
    final order = ref.read(posOrderProvider);
    if (order.isEmpty) return;

    final session = ref.read(currentPosSessionProvider).value;
    if (session == null) {
      setState(() => _error = 'The shift is closed. Open a shift to sell.');
      return;
    }

    final subtotal = _subtotal(order);
    final discountCents = _discountOf(subtotal);
    final total = subtotal - discountCents;

    final auth = ref.read(authorizationServiceProvider);
    if (_stockOnly && !auth.can(BosPermission.salesStockOnly)) {
      setState(() => _error = 'Your role can\'t record stock-only deductions.');
      return;
    }
    if (_discount != null && !auth.can(BosPermission.salesDiscount)) {
      setState(() => _error = 'Your role can\'t give discounts.');
      return;
    }

    final noteText = _notesCtrl.text.trim();
    if (_stockOnly && noteText.isEmpty) {
      setState(
        () => _error =
            'Enter the reason for this stock deduction (free sample, staff '
            'meal, spoilage...).',
      );
      return;
    }

    List<SaleTenderInput> tenders = const [];
    if (!_stockOnly) {
      final err = _validatePayments(total);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      tenders = _buildTenders(total);
    }
    final change = _stockOnly ? 0 : _calc(total).change;

    setState(() {
      _processing = true;
      _error = null;
    });
    final service = ref.read(productionServiceProvider);

    final cashierId = ref.read(authenticatedUserIdProvider);
    final cashierUser = ref.read(currentUserProvider).value;
    final cashierDisplay = (cashierUser?.displayName ?? '').trim();
    final lines = order
        .map(
          (l) => SaleLineInput(
            productId: l.productId,
            productName: l.name,
            unit: l.unit,
            unitPriceCents: l.unitPriceCents,
            quantity: l.quantity.toDouble(),
          ),
        )
        .toList();

    try {
      // 1) Deleted / archived since it was added?
      final db = ref.read(databaseProvider);
      final live =
          await (db.select(db.products)..where(
                (p) =>
                    p.id.isIn(order.map((l) => l.productId).toList()) &
                    p.isActive.equals(true),
              ))
              .get();
      final liveIds = {for (final p in live) p.id};
      final gone = [
        for (final l in order)
          if (!liveIds.contains(l.productId)) l.name,
      ];
      if (gone.isNotEmpty) {
        if (!mounted) return;
        setState(
          () => _error =
              '${gone.join(', ')} ${gone.length == 1 ? 'is' : 'are'} no longer '
              'available. Close this and remove '
              '${gone.length == 1 ? 'it' : 'them'} from the order.',
        );
        return;
      }
      // 2) Fresh check of the whole order.
      final problems = await service.checkOrder(lines);
      if (problems.isNotEmpty) {
        if (!mounted) return;
        setState(() => _error = problems.join('\n'));
        return;
      }

      // 3) One atomic save. recordSale does not touch the journal.
      final saleId = await service.recordSale(
        businessId: kCurrentBusinessId,
        lines: lines,
        stockOnly: _stockOnly,
        sessionId: session.id,
        tenders: tenders,
        notes: noteText.isEmpty ? null : noteText,
        idempotencyKey: _saleKey,
        discountCents: discountCents,
        discountLabel: _discount?.label,
        customerId: (!_stockOnly && _custMode == _CustMode.existing)
            ? _customer?.id
            : null,
        newCustomerName: (!_stockOnly && _custMode == _CustMode.newCustomer)
            ? _custName.text.trim()
            : null,
        newCustomerAddress: (!_stockOnly && _custMode == _CustMode.newCustomer)
            ? _custAddress.text.trim()
            : null,
        newCustomerTin: (!_stockOnly && _custMode == _CustMode.newCustomer)
            ? _formatTin(_custTin.text)
            : null,
        cashierUserId: cashierId,
        cashierName: cashierDisplay.isNotEmpty
            ? cashierDisplay
            : cashierUser?.email,
        orderType: ref.read(posOrderTypeProvider),
      );

      await attachOrderDetailsToSale(ref, saleId);

      ref.read(posOrderProvider.notifier).clear();
      ref.invalidate(producibilityProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      Navigator.pop(context, true);
      if (_stockOnly) {
        messenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Order recorded — stock deducted, no income logged.'),
          ),
        );
      } else {
        showDialog<void>(
          context: rootContext,
          builder: (_) => _SaleDoneDialog(total: total, change: change),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  bool _isCredit(_Tender t) {
    final creditId = ref.read(posReceivableAccountIdProvider).value;
    return creditId != null && t.accountId == creditId;
  }

  String? _tinProblem(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (!RegExp(r'^[0-9\- ]+$').hasMatch(t)) {
      return 'TIN can only have numbers and dashes.';
    }
    final d = t.replaceAll(RegExp(r'\D'), '');
    if (d.length != 9 && d.length != 12) {
      return 'A TIN has 9 or 12 digits (000-000-000-000).';
    }
    return null;
  }

  String? _formatTin(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    final parts = <String>[];
    for (var i = 0; i < d.length; i += 3) {
      parts.add(d.substring(i, math.min(i + 3, d.length)));
    }
    return parts.join('-');
  }

  /// Null when the customer choice is fine.
  String? _customerProblem() {
    switch (_custMode) {
      case _CustMode.existing:
        if (_customer == null) {
          return 'Choose the customer from your Customers list, or pick '
              'Walk-in.';
        }
      case _CustMode.newCustomer:
        if (_custName.text.trim().isEmpty) {
          return 'Enter the customer name, or pick Walk-in.';
        }
        final tin = _tinProblem(_custTin.text);
        if (tin != null) return tin;
      case _CustMode.none:
        if (_tenders.any(_isCredit)) {
          return 'Credit needs a customer. Choose Existing or New above.';
        }
    }
    return null;
  }

  // ---------- UI: customer ----------------------------------------------------

  Widget _customerSection(ColorScheme scheme) {
    final c = _customer;

    return _SectionCard(
      icon: Icons.person_outline_rounded,
      title: 'Customer (optional)',
      children: [
        Builder(
          builder: (context) {
            final narrow = MediaQuery.sizeOf(context).width < 460;

            Widget label(String text) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text, maxLines: 1, softWrap: false),
            );

            return SizedBox(
              width: double.infinity,
              child: SegmentedButton<_CustMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.standard,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                ),
                segments: [
                  ButtonSegment(
                    value: _CustMode.none,
                    icon: narrow
                        ? null
                        : const Icon(Icons.directions_walk_rounded, size: 18),
                    label: label('Walk-in'),
                  ),
                  ButtonSegment(
                    value: _CustMode.existing,
                    icon: narrow
                        ? null
                        : const Icon(Icons.people_alt_outlined, size: 18),
                    label: label('Existing'),
                  ),
                  ButtonSegment(
                    value: _CustMode.newCustomer,
                    icon: narrow
                        ? null
                        : const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: label('New'),
                  ),
                ],
                selected: {_custMode},
                onSelectionChanged: (s) => setState(() {
                  _custMode = s.first;
                  _error = null;
                }),
              ),
            );
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_custMode == _CustMode.existing) ...[
                const SizedBox(height: 12),
                _customerField(scheme),
                if (c != null &&
                    ((c.address ?? '').isNotEmpty || (c.tin ?? '').isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      [
                        if ((c.address ?? '').isNotEmpty) c.address!,
                        if ((c.tin ?? '').isNotEmpty) 'TIN ${c.tin}',
                      ].join(' · '),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              if (_custMode == _CustMode.newCustomer) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _custName,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(
                    labelText: 'Customer name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _custAddress,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _custTin,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(
                    labelText: 'TIN (optional)',
                    hintText: '000-000-000-000',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved to Customers when the sale is completed.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _customerField(ColorScheme scheme) {
    final c = _customer;
    return InkWell(
      onTap: () async {
        final picked = await showPosCustomerPicker(
          context,
          selectedId: _customer?.id,
        );
        if (picked != null && mounted) {
          setState(() {
            _customer = picked;
            _error = null;
          });
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Select from Customers',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outline_rounded),
          suffixIcon: Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          c?.name ?? 'Select customer',
          style: TextStyle(
            fontWeight: c == null ? FontWeight.w500 : FontWeight.w800,
            color: c == null ? scheme.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }

  // ---------- UI: payment rows ------------------------------------------------

  Widget _tenderCard(
    int i,
    List<dynamic> accounts,
    int total,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    final t = _tenders[i];
    final split = _tenders.length > 1;
    final cash = _isCash(t);
    final kind = _kindOf(t);
    final remaining = _remainingFor(i, total);

    final usedElsewhere = <String>{
      for (var j = 0; j < _tenders.length; j++)
        if (j != i && _tenders[j].accountId != null) _tenders[j].accountId!,
    };

    final quick = <int>[
      for (final d in const [50, 100, 200, 500, 1000])
        if (d * 100 >= remaining) d,
    ];

    IconData iconFor(dynamic a) {
      if (a is _CreditOption) return Icons.receipt_long_rounded;
      return isCashAccount(a.id as String, a.name as String)
          ? Icons.payments_rounded
          : Icons.account_balance_wallet_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  split ? 'Payment ${i + 1}' : 'Paid via',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (split)
                IconButton(
                  tooltip: 'Remove this payment',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _tenders.removeAt(i).dispose();
                    if (_tenders.length == 1) _tenders.first.auto = true;
                    _error = null;
                  }),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
          _paidViaDropdown(
            t: t,
            accounts: accounts,
            usedElsewhere: usedElsewhere,
            remaining: remaining,
            iconFor: iconFor,
          ),
          if (t.accountId != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: t.amountCtrl,
              readOnly: cash, // cash uses the keypad below
              showCursor: !cash,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              onChanged: (_) => setState(() {
                t.auto = false;
                _error = null;
              }),
              decoration: InputDecoration(
                labelText: cash ? 'Cash received' : 'Amount',
                prefixText: '₱ ',
                border: const OutlineInputBorder(),
              ),
            ),
            if (cash) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ActionChip(
                    label: const Text('Exact'),
                    onPressed: () => setState(() {
                      t.auto = _tenders.length == 1;
                      _setAmount(t, remaining);
                    }),
                  ),
                  for (final d in quick.take(4))
                    ActionChip(
                      label: Text('₱$d'),
                      onPressed: () => setState(() {
                        t.auto = false;
                        _setAmount(t, d * 100);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _CashKeypad(onKey: (k) => _key(t, k)),
            ] else if (_isCredit(t)) ...[
              const SizedBox(height: 12),
              Text(
                'Credit needs a customer. Choose one in the Customer box above.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ] else ...[
              if (kind != null) ...[
                const SizedBox(height: 12),
                _providerField(t, kind, scheme),
              ],
              const SizedBox(height: 12),
              _proofSection(t, scheme),
            ],
          ],
        ],
      ),
    );
  }

  /// "Paid via" as big tiles. Accounts already used by another payment row
  /// are left out.
  Widget _paidViaDropdown({
    required _Tender t,
    required List<dynamic> accounts,
    required Set<String> usedElsewhere,
    required int remaining,
    required IconData Function(dynamic) iconFor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final options = [
      for (final a in accounts)
        if (!usedElsewhere.contains(a.id as String)) a,
    ];

    if (options.isEmpty) {
      return Text(
        'No other payment methods are available.',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
      );
    }

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Payment method',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: t.accountId,
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(Icons.arrow_drop_down_rounded),
          hint: Text(
            'Choose payment method',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          items: [
            for (final a in options)
              DropdownMenuItem<String>(
                value: a.id as String,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        iconFor(a),
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        a.name as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            HapticFeedback.selectionClick();
            setState(() {
              if (t.accountId != id) {
                t.provider = null;
                t.proof = null;
                t.proofForCents = null;
              }
              t.accountId = id;
              t.auto = _tenders.length == 1;
              _setAmount(t, remaining);
              _error = null;
            });
          },
        ),
      ),
    );
  }

  Widget _providerField(
    _Tender t,
    PaymentProviderKind kind,
    ColorScheme scheme,
  ) {
    final chosen = t.provider;
    return InkWell(
      onTap: () => _pickProvider(t, kind),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: kind.label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(kind.icon),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          chosen ?? 'Select ${kind.noun}',
          style: TextStyle(
            fontWeight: chosen == null ? FontWeight.w500 : FontWeight.w800,
            color: chosen == null ? scheme.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }

  Widget _proofSection(_Tender t, ColorScheme scheme) {
    final proof = t.proof;
    if (proof == null) {
      return OutlinedButton.icon(
        onPressed: t.cents <= 0 ? null : () => _attachProof(t),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan payment proof'),
      );
    }

    final stale = t.proofForCents != t.cents;
    final matches = proof.amountCents == t.cents;
    final ok = !stale && matches;
    final color = ok ? Colors.green.shade700 : scheme.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ref ${proof.referenceNo ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  stale
                      ? 'Amount changed — scan the proof again'
                      : '${_peso(proof.amountCents)} paid'
                            '${matches ? '' : ' (differs from amount)'}',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove proof',
            onPressed: () => setState(() => t.proof = null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _paymentSummary(int total, _Calc c, ThemeData theme) {
    final scheme = theme.colorScheme;
    final received = c.nonCash + c.cashReceived;
    final progress = total <= 0 ? 0.0 : (received / total).clamp(0.0, 1.0);
    final paidInFull = total > 0 && received >= total && !c.nonCashOver;

    final Color accent;
    final IconData icon;
    final String label;
    final String value;
    if (c.nonCashOver) {
      accent = scheme.error;
      icon = Icons.warning_amber_rounded;
      label = 'Over by';
      value = _peso(c.nonCash - total);
    } else if (c.change > 0) {
      accent = Colors.green.shade700;
      icon = Icons.change_circle_outlined;
      label = 'Change to give';
      value = _peso(c.change);
    } else if (paidInFull) {
      accent = Colors.green.shade700;
      icon = Icons.check_circle_rounded;
      label = 'Paid in full';
      value = '✓';
    } else if (received > 0) {
      accent = Colors.orange.shade800;
      icon = Icons.hourglass_bottom_rounded;
      label = 'Remaining';
      value = _peso(c.shortfall);
    } else {
      accent = scheme.primary;
      icon = Icons.payments_outlined;
      label = 'Waiting for payment';
      value = _peso(total);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Received',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${_peso(received)} / ${_peso(total)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final order = ref.watch(posOrderProvider);
    final accountsAsync = ref.watch(posPaymentAccountsProvider);

    final canDiscount = ref.watch(canProvider(BosPermission.salesDiscount));
    final canCredit = ref.watch(canProvider(BosPermission.salesOnCredit));
    final creditId = ref.watch(posReceivableAccountIdProvider).value;
    final canStockOnly = ref.watch(canProvider(BosPermission.salesStockOnly));

    final subtotal = _subtotal(order);
    final discountCents = _discountOf(subtotal);
    final total = subtotal - discountCents;
    final calc = _calc(total);
    final itemCount = order.fold<int>(0, (s, l) => s + l.quantity);

    // Two panes only in the tablet/wide dialog.
    final split = widget.dialog && size.width >= 820;

    // ---- the payment form (shared by both layouts) ----
    final formChildren = <Widget>[
      if (!_stockOnly)
        _AmountHero(
          total: total,
          itemCount: itemCount,
          discount: discountCents,
          calc: calc,
        ),
      _SectionCard(
        icon: Icons.tune_rounded,
        title: 'Options',
        children: [
          if (canStockOnly)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Stock deduction only',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Skip recording income — for free samples or staff use',
              ),
              value: _stockOnly,
              onChanged: (v) => setState(() {
                _stockOnly = v;
                _error = null;
              }),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: _stockOnly ? 'Reason (required)' : 'Note (optional)',
              hintText: _stockOnly
                  ? 'Free sample, staff meal, spoilage...'
                  : null,
              prefixIcon: const Icon(Icons.sticky_note_2_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      if (!_stockOnly)
        _SectionCard(
          icon: Icons.sell_outlined,
          title: 'Discount',
          children: [
            if (!canDiscount)
              Text(
                'Your role can\'t give discounts.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('None'),
                    selected: _discount == null,
                    onSelected: (_) => _setDiscount(null),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.badge_outlined, size: 18),
                    label: Text(PosDiscount.seniorPwd.label),
                    selected: _discount?.label == PosDiscount.seniorPwd.label,
                    onSelected: (_) => _setDiscount(PosDiscount.seniorPwd),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      _discount != null &&
                              _discount!.label != PosDiscount.seniorPwd.label
                          ? _discount!.label
                          : 'Custom...',
                    ),
                    selected:
                        _discount != null &&
                        _discount!.label != PosDiscount.seniorPwd.label,
                    onSelected: (_) => _pickCustomDiscount(subtotal),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: discountCents > 0
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.savings_outlined,
                              size: 18,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Customer saves ${_peso(discountCents)}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      if (!_stockOnly) _customerSection(scheme),
      if (!_stockOnly)
        _SectionCard(
          icon: Icons.payments_outlined,
          title: 'Payment',
          children: [
            accountsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(
                'Unable to load payment accounts.',
                style: TextStyle(color: scheme.error),
              ),
              data: (accounts) {
                if (accounts.isEmpty) {
                  return Text(
                    'Add at least one active Cash, Bank, or E-Wallet '
                    'account before checkout.',
                    style: TextStyle(color: scheme.error),
                  );
                }
                final options = <dynamic>[
                  ...accounts,
                  if (creditId != null && canCredit) _CreditOption(creditId),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _tenders.length; i++)
                      _tenderCard(i, options, total, theme),
                    if (_tenders.length < options.length)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() {
                            _tenders.first.auto = false;
                            _tenders.add(_Tender()..auto = false);
                            _error = null;
                          }),
                          icon: const Icon(Icons.call_split_rounded, size: 18),
                          label: const Text(
                            'Split payment',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            _paymentSummary(total, calc, theme),
          ],
        ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(children: [if (_error != null) _ErrorBox(_error!)]),
      ),
    ];

    final recapLines = _RecapLines(order: order);

    Widget body;
    if (split) {
      body = SizedBox(
        height: math.min(size.height * 0.88, 760),
        child: Column(
          children: [
            _PaymentHeader(
              itemCount: itemCount,
              total: total,
              busy: _processing,
              onClose: () => Navigator.pop(context, false),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- left: order recap ----
                  Expanded(
                    flex: 5,
                    child: Container(
                      color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text(
                            'ORDER SUMMARY',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          recapLines,
                          const Divider(height: 28),
                          _totalLine('Subtotal', _peso(subtotal), scheme),
                          if (discountCents > 0)
                            _totalLine(
                              _discount?.label ?? 'Discount',
                              '−${_peso(discountCents)}',
                              scheme,
                              color: Colors.green.shade700,
                            ),
                        ],
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  // ---- right: payment form ----
                  Expanded(
                    flex: 6,
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(20),
                      children: formChildren,
                    ),
                  ),
                ],
              ),
            ),
            _PayBar(
              subtotal: subtotal,
              discount: discountCents,
              total: total,
              stockOnly: _stockOnly,
              processing: _processing,
              onComplete: _completeSale,
            ),
          ],
        ),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PaymentHeader(
            itemCount: itemCount,
            total: total,
            busy: _processing,
            onClose: () => Navigator.pop(context, false),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                // collapsible recap
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      shape: const RoundedRectangleBorder(),
                      collapsedShape: const RoundedRectangleBorder(),
                      leading: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 17,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        'Order summary',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: Text(
                        '$itemCount item${itemCount == 1 ? '' : 's'} · '
                        '${_peso(subtotal)}',
                      ),
                      children: [
                        recapLines,
                        if (discountCents > 0)
                          _totalLine(
                            _discount?.label ?? 'Discount',
                            '−${_peso(discountCents)}',
                            scheme,
                            color: Colors.green.shade700,
                          ),
                      ],
                    ),
                  ),
                ),
                ...formChildren,
              ],
            ),
          ),
          _PayBar(
            subtotal: subtotal,
            discount: discountCents,
            total: total,
            stockOnly: _stockOnly,
            processing: _processing,
            onComplete: _completeSale,
          ),
        ],
      );
    }

    return PopScope(
      // No dismissing while the sale is being saved.
      canPop: !_processing,
      child: Material(
        color: scheme.surface,
        borderRadius: widget.dialog
            ? null
            : const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            // The dialog already makes room for the keyboard.
            padding: EdgeInsets.only(
              bottom: widget.dialog
                  ? 0
                  : MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _totalLine(
    String label,
    String value,
    ColorScheme scheme, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color ?? scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SMALL WIDGETS
// ============================================================================

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled card that groups one part of the payment.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// Read-only list of what is being paid for.
class _RecapLines extends StatelessWidget {
  final List<POSLineItem> order;
  const _RecapLines({required this.order});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final l in order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '×${l.quantity}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _peso(l.lineTotal),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Header: gradient badge, title, running total, close button.
class _PaymentHeader extends StatelessWidget {
  final int itemCount;
  final int total;
  final bool busy;
  final VoidCallback onClose;

  const _PaymentHeader({
    required this.itemCount,
    required this.total,
    required this.busy,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.55),
            scheme.surface,
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.payments_rounded,
              color: scheme.onPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '$itemCount item${itemCount == 1 ? '' : 's'} · '
                  '${_peso(total)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Back to order',
            onPressed: busy ? null : onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar: totals that count up smoothly + a full-width action button.
class _PayBar extends StatelessWidget {
  final int subtotal;
  final int discount;
  final int total;
  final bool stockOnly;
  final bool processing;
  final VoidCallback onComplete;

  const _PayBar({
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.stockOnly,
    required this.processing,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: total.toDouble()),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                  _peso(v.round()),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (discount > 0 && !stockOnly)
                Text(
                  'saved ${_peso(discount)}',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: processing ? null : onComplete,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: processing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        stockOnly
                            ? Icons.inventory_2_outlined
                            : Icons.check_circle_outline_rounded,
                      ),
                label: Text(
                  processing
                      ? 'Processing...'
                      : stockOnly
                      ? 'Deduct stock'
                      : 'Complete Sale',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================================
// CHECKOUT PIECES (Loyverse-style)
// ============================================================================

/// Big "amount due" card with a live status line.
class _AmountHero extends StatelessWidget {
  final int total;
  final int itemCount;
  final int discount;
  final _Calc calc;

  const _AmountHero({
    required this.total,
    required this.itemCount,
    required this.discount,
    required this.calc,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final received = calc.nonCash + calc.cashReceived;

    String status;
    if (calc.nonCashOver) {
      status = 'Over by ${_peso(calc.nonCash - total)}';
    } else if (calc.change > 0) {
      status = 'Change ${_peso(calc.change)}';
    } else if (received >= total && total > 0) {
      status = 'Paid in full ✓';
    } else if (received > 0) {
      status = 'Remaining ${_peso(calc.shortfall)}';
    } else {
      status = 'Choose how the customer pays';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.3)!,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.32),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AMOUNT DUE',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Text(
                '$itemCount item${itemCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(end: total.toDouble()),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _peso(v.round()),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _HeroChip(status),
              if (discount > 0) _HeroChip('Saved ${_peso(discount)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String text;
  const _HeroChip(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
      ),
    ),
  );
}

// /// One payment method (Cash, GCash, On credit...).
// class _MethodTile extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final bool selected;
//   final VoidCallback onTap;

//   const _MethodTile({
//     required this.icon,
//     required this.label,
//     required this.selected,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final scheme = Theme.of(context).colorScheme;
//     final fg = selected ? scheme.onPrimary : scheme.onSurface;

//     return AnimatedContainer(
//       duration: const Duration(milliseconds: 180),
//       curve: Curves.easeOutCubic,
//       constraints: const BoxConstraints(minWidth: 104),
//       decoration: BoxDecoration(
//         gradient: selected
//             ? LinearGradient(
//                 colors: [
//                   scheme.primary,
//                   Color.lerp(scheme.primary, Colors.black, 0.22)!,
//                 ],
//               )
//             : null,
//         color: selected ? null : scheme.surfaceContainerLow,
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(
//           color: selected
//               ? Colors.transparent
//               : scheme.outlineVariant.withValues(alpha: 0.6),
//         ),
//         boxShadow: selected
//             ? [
//                 BoxShadow(
//                   color: scheme.primary.withValues(alpha: 0.3),
//                   blurRadius: 12,
//                   offset: const Offset(0, 5),
//                 ),
//               ]
//             : null,
//       ),
//       child: Material(
//         type: MaterialType.transparency,
//         child: InkWell(
//           borderRadius: BorderRadius.circular(18),
//           onTap: onTap,
//           child: Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(icon, size: 24, color: fg),
//                 const SizedBox(height: 6),
//                 Text(
//                   label,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     color: fg,
//                     fontWeight: FontWeight.w800,
//                     fontSize: 13,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

/// 3x4 numeric keypad for the cash received. Long-press ⌫ clears.
class _CashKeypad extends StatelessWidget {
  final ValueChanged<String> onKey;
  const _CashKeypad({required this.onKey});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const keys = ['7', '8', '9', '4', '5', '6', '1', '2', '3', '.', '0', '⌫'];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.3,
      children: [
        for (final k in keys)
          Material(
            color: k == '⌫'
                ? scheme.errorContainer.withValues(alpha: 0.6)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onKey(k),
              onLongPress: k == '⌫' ? () => onKey('C') : null,
              child: Center(
                child: k == '⌫'
                    ? Icon(
                        Icons.backspace_outlined,
                        size: 22,
                        color: scheme.onErrorContainer,
                      )
                    : Text(
                        k,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shown after a sale is saved: big change figure and a New sale button.
class _SaleDoneDialog extends StatelessWidget {
  final int total;
  final int change;
  const _SaleDoneDialog({required this.total, required this.change});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final green = Colors.green.shade700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, size: 46, color: green),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sale complete',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            if (change > 0) ...[
              Text(
                'CHANGE',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              FittedBox(
                child: Text(
                  _peso(change),
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    color: green,
                    letterSpacing: -1.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Total ${_peso(total)}',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Posts to the journal when the shift closes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'New sale',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
