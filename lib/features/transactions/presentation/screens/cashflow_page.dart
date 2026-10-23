import 'dart:math';

import 'package:bos_application/core/audit/audit_enums.dart';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/ledger/ledger_service.dart';
import '../../domain/capital_asset_liability_service.dart';

import '../../../transactions/presentation/screens/transaction_page.dart'
    show
        businessProfileProvider,
        ledgerVersionProvider,
        kCurrentBusinessId,
        paymentAccountsProvider;

// ============================================================
// MODELS
// ============================================================

class AccountBalance {
  final Account account;
  final int balance;

  const AccountBalance({required this.account, required this.balance});
}

class BalancePoint {
  final DateTime date;
  final int runningBalance;

  const BalancePoint({required this.date, required this.runningBalance});
}

class PendingCashflowItem {
  final String description;
  final int amount;
  final DateTime date;
  final bool receivable;

  const PendingCashflowItem({
    required this.description,
    required this.amount,
    required this.date,
    required this.receivable,
  });
}

// ============================================================
// PROVIDERS  (unchanged)
// ============================================================

final accountBalancesProvider = FutureProvider<List<AccountBalance>>((
  ref,
) async {
  ref.watch(ledgerVersionProvider);

  final db = ref.watch(databaseProvider);

  final accounts =
      await (db.select(db.accounts)..where(
            (a) =>
                a.businessId.equals(kCurrentBusinessId) &
                a.isPaymentAccount.equals(true) &
                a.isActive.equals(true),
          ))
          .get();

  final results = <AccountBalance>[];

  for (final account in accounts) {
    final rows = await db
        .customSelect(
          '''
          SELECT
            COALESCE(SUM(debit), 0) AS total_debit,
            COALESCE(SUM(credit), 0) AS total_credit
          FROM ledger_lines ll
          INNER JOIN journal_entries je
            ON je.id = ll.journal_entry_id
          WHERE ll.account_id = ?
          ''',
          variables: [Variable.withString(account.id)],
        )
        .getSingle();

    final debit = rows.read<int>('total_debit');
    final credit = rows.read<int>('total_credit');

    results.add(
      AccountBalance(
        account: account,
        balance: account.startingBalance + debit - credit,
      ),
    );
  }

  return results;
});

final accountBalanceHistoryProvider =
    FutureProvider.family<List<BalancePoint>, String>((ref, accountId) async {
      ref.watch(ledgerVersionProvider);

      final db = ref.watch(databaseProvider);

      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(accountId))).getSingle();

      final rows = await db
          .customSelect(
            '''
          SELECT
            je.entry_date AS entry_date,
            SUM(
              CASE
                WHEN ll.debit > 0 THEN ll.debit
                ELSE -ll.credit
              END
            ) OVER (
              ORDER BY je.entry_date, je.created_at
            ) AS running_delta
          FROM ledger_lines ll
          JOIN journal_entries je
            ON je.id = ll.journal_entry_id
          WHERE ll.account_id = ?
          ORDER BY je.entry_date, je.created_at
          ''',
            variables: [Variable.withString(accountId)],
          )
          .get();

      final points = <BalancePoint>[
        BalancePoint(
          date: account.createdAt,
          runningBalance: account.startingBalance,
        ),
      ];

      for (final row in rows) {
        final delta = row.read<int>('running_delta');
        final dateStr = row.read<String>('entry_date');

        points.add(
          BalancePoint(
            date: DateTime.parse(dateStr),
            runningBalance: account.startingBalance + delta,
          ),
        );
      }

      return points;
    });

final pendingCashflowProvider = FutureProvider<List<PendingCashflowItem>>((
  ref,
) async {
  ref.watch(ledgerVersionProvider);
  final db = ref.watch(databaseProvider);

  final pendingIncome =
      await (db.select(db.incomeTransactions)
            ..where(
              (income) =>
                  income.businessId.equals(kCurrentBusinessId) &
                  income.status.equals('pending'),
            )
            ..orderBy([(income) => OrderingTerm.desc(income.txnDate)]))
          .get();
  final pendingExpenses =
      await (db.select(db.expenses)
            ..where(
              (expense) =>
                  expense.businessId.equals(kCurrentBusinessId) &
                  expense.status.equals('pending'),
            )
            ..orderBy([(expense) => OrderingTerm.desc(expense.expenseDate)]))
          .get();

  return [
    ...pendingIncome.map(
      (income) => PendingCashflowItem(
        description: income.description ?? 'Pending receivable',
        amount: income.amount,
        date: income.txnDate,
        receivable: true,
      ),
    ),
    ...pendingExpenses.map(
      (expense) => PendingCashflowItem(
        description: expense.description ?? 'Pending payable',
        amount: expense.amount,
        date: expense.expenseDate,
        receivable: false,
      ),
    ),
  ]..sort((a, b) => b.date.compareTo(a.date));
});

final capitalAssetLiabilityServiceProvider =
    Provider<CapitalAssetLiabilityService>((ref) {
      return CapitalAssetLiabilityService(ref.watch(databaseProvider));
    });

final assetBalancesProvider = FutureProvider<List<AccountBalanceEntry>>((ref) {
  ref.watch(ledgerVersionProvider);
  return ref
      .watch(capitalAssetLiabilityServiceProvider)
      .assetBalances(kCurrentBusinessId);
});

final liabilityBalancesProvider = FutureProvider<List<AccountBalanceEntry>>((
  ref,
) {
  ref.watch(ledgerVersionProvider);
  return ref
      .watch(capitalAssetLiabilityServiceProvider)
      .liabilityBalances(kCurrentBusinessId);
});

final capitalBalanceProvider = FutureProvider<int>((ref) {
  ref.watch(ledgerVersionProvider);
  return ref
      .watch(capitalAssetLiabilityServiceProvider)
      .capitalBalance(kCurrentBusinessId);
});

final accountLedgerEntriesProvider =
    FutureProvider.family<List<LedgerEntryRow>, String>((ref, accountId) {
      ref.watch(ledgerVersionProvider);
      return ref
          .watch(capitalAssetLiabilityServiceProvider)
          .accountLedgerEntries(accountId);
    });

// ============================================================
// DESIGN TOKENS & HELPERS
// ============================================================

/// Widest the content ever gets. Beyond this, margins grow instead,
/// so tablets, desktop and web never stretch into unreadable rows.
const double _kMaxWidth = 1180;

/// Ink-navy used for the hero. Kept fixed so it reads the same in
/// light and dark themes.
const _inkTop = Color(0xFF101C30);
const _inkBottom = Color(0xFF0A1220);

/// Tabular figures keep columns of money aligned.
const _tabular = [FontFeature.tabularFigures()];

const _gradients = <List<Color>>[
  [Color(0xFF3F51D9), Color(0xFF6C5CE7)],
  [Color(0xFF00796B), Color(0xFF2BB5A0)],
  [Color(0xFFE65100), Color(0xFFF9A825)],
  [Color(0xFFC2410C), Color(0xFFEF6C45)],
  [Color(0xFF1565C0), Color(0xFF38B6F0)],
  [Color(0xFF8E24AA), Color(0xFFC265D6)],
];

List<Color> _gradientFor(String name) {
  final index =
      name.codeUnits.fold<int>(0, (a, b) => a + b) % _gradients.length;
  return _gradients[index];
}

IconData _iconFor(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('bank')) return Icons.account_balance_rounded;
  if (lower.contains('cash')) return Icons.payments_rounded;
  if (lower.contains('gcash') || lower.contains('maya')) {
    return Icons.phone_android_rounded;
  }
  if (lower.contains('wallet')) return Icons.account_balance_wallet_rounded;
  return Icons.account_balance_wallet_outlined;
}

String _peso(int cents) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  ).format(cents / 100);
}

String _compactPeso(double cents) {
  return NumberFormat.compactCurrency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  ).format(cents / 100);
}

/// Green that stays readable on both light and dark surfaces.
Color _positive(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF5FD3A0)
    : const Color(0xFF1F8F5F);

double _sidePad(double width) =>
    max(width >= 720 ? 28.0 : 16.0, (width - _kMaxWidth) / 2);

String _sourceTypeLabel(String sourceType) {
  switch (sourceType) {
    case 'capital':
      return 'Capital contribution';
    case 'asset':
      return 'Asset acquisition';
    case 'liability':
      return 'Liability incurred';
    case 'supplier_purchase':
      return 'Supplier purchase';
    case 'payable_payment':
      return 'Payment to supplier';
    case 'income':
      return 'Sale';
    case 'receivable_payment':
      return 'Payment from customer';
    case 'transfer':
      return 'Account transfer';
    default:
      return 'Transaction';
  }
}

/// Lays children out in as many equal-width columns as fit, so the
/// layout adapts from a 320dp phone to an ultrawide monitor and the
/// tiles are never a fixed height (safe with large text sizes).
class _AdaptiveWrap extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final int maxColumns;

  const _AdaptiveWrap({
    required this.children,
    required this.minTileWidth,
    this.spacing = 14,
    this.maxColumns = 4,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fit = ((width + spacing) / (minTileWidth + spacing)).floor();
        final columns = fit.clamp(1, max(1, maxColumns));
        final tileWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.subtitle}) : trailing = null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ============================================================
// CASHFLOW PAGE
// ============================================================

class CashflowPage extends ConsumerWidget {
  const CashflowPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(accountBalancesProvider);
    ref.invalidate(pendingCashflowProvider);
    ref.invalidate(assetBalancesProvider);
    ref.invalidate(liabilityBalancesProvider);
    await ref.read(accountBalancesProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessName = ref
        .watch(businessProfileProvider)
        .maybeWhen(data: (value) => value.name, orElse: () => null);
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    // Large accessibility text still fits; extreme scales are capped.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        body: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 76,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                backgroundColor: scheme.surfaceContainerLowest,
                centerTitle: false,
                titleSpacing: _sidePad(width),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      businessName == null || businessName.isEmpty
                          ? 'Accounts'
                          : '$businessName Accounts',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Where your money is right now',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pad = constraints.maxWidth >= 720 ? 28.0 : 16.0;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _kMaxWidth + pad * 2,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(pad, 4, pad, 120),
                          child: const _CashflowContent(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showTransferSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => const _TransferSheet(),
  );
}

class _CashflowContent extends ConsumerWidget {
  const _CashflowContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(accountBalancesProvider);
    final pendingAsync = ref.watch(pendingCashflowProvider);
    final assetsAsync = ref.watch(assetBalancesProvider);
    final liabilitiesAsync = ref.watch(liabilityBalancesProvider);

    final balances = balancesAsync.maybeWhen(
      data: (v) => v,
      orElse: () => null,
    );
    final assets = assetsAsync.maybeWhen(data: (v) => v, orElse: () => null);
    final liabilities = liabilitiesAsync.maybeWhen(
      data: (v) => v,
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------- HERO ----------------
        balancesAsync.when(
          data: (list) => _TotalBalanceHero(
            balances: list,
            onTransfer: list.length >= 2
                ? () => _showTransferSheet(context)
                : null,
          ),
          loading: () => const _HeroSkeleton(),
          error: (_, __) => _CashflowErrorState(
            onRetry: () => ref.invalidate(accountBalancesProvider),
          ),
        ),

        // ---------------- NET POSITION ----------------
        if (balances != null) ...[
          const SizedBox(height: 14),
          _PositionStrip(
            cash: balances.fold<int>(0, (s, b) => s + b.balance),
            assets: assets?.fold<int>(0, (s, a) => s + a.balance),
            liabilities: liabilities?.fold<int>(0, (s, a) => s + a.balance),
          ),
        ],

        // ---------------- PENDING ----------------
        pendingAsync.maybeWhen(
          data: (items) => _PendingCashflowSection(items: items),
          orElse: () => const SizedBox.shrink(),
        ),

        // ---------------- ACCOUNTS ----------------
        if (balances != null) ...[
          _SectionHeader(
            title: 'Payment accounts',
            subtitle: balances.isEmpty
                ? null
                : '${balances.length} active · tap one for its history',
          ),
          if (balances.isEmpty)
            const _EmptyAccountsState()
          else
            _AdaptiveWrap(
              minTileWidth: 330,
              maxColumns: 3,
              children: [for (final b in balances) _AccountCard(balance: b)],
            ),
        ],

        // ---------------- ASSETS & LIABILITIES ----------------
        const _SectionHeader(
          title: 'Balance sheet',
          subtitle: 'What the business owns and what it owes',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 760;

            final assetsWidget = assetsAsync.when(
              data: (a) => _AssetsSection(assets: a),
              loading: () => const _PanelSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
            );
            final liabilitiesWidget = liabilitiesAsync.when(
              data: (l) => _LiabilitiesSection(liabilities: l),
              loading: () => const _PanelSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
            );

            if (sideBySide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: assetsWidget),
                  const SizedBox(width: 14),
                  Expanded(child: liabilitiesWidget),
                ],
              );
            }
            return Column(
              children: [
                assetsWidget,
                const SizedBox(height: 14),
                liabilitiesWidget,
              ],
            );
          },
        ),
      ],
    );
  }
}

// ============================================================
// TOTAL BALANCE HERO
// ============================================================

class _TotalBalanceHero extends StatelessWidget {
  final List<AccountBalance> balances;
  final VoidCallback? onTransfer;

  const _TotalBalanceHero({required this.balances, required this.onTransfer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final total = balances.fold<int>(0, (sum, item) => sum + item.balance);
    final positiveAccounts = balances.where((e) => e.balance >= 0).length;
    final negativeAccounts = balances.length - positiveAccounts;
    final isNegative = total < 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final pad = constraints.maxWidth < 420 ? 20.0 : 30.0;
        final amountSize = constraints.maxWidth < 420
            ? 38.0
            : (wide ? 56.0 : 48.0);

        final figure = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Cash on hand',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _HeroPill(
                  text:
                      '${balances.length} ${balances.length == 1 ? 'account' : 'accounts'}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: total.toDouble()),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _peso(value.round()),
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: amountSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.8,
                      height: 1.05,
                      fontFeatures: _tabular,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            _HeroPill(
              icon: isNegative
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
              text: isNegative
                  ? 'Total is below zero'
                  : 'Funds are in the green',
              tint: isNegative ? const Color(0xFFFFB4A8) : null,
            ),
          ],
        );

        final side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.trending_up_rounded,
                    label: 'Positive',
                    value: '$positiveAccounts',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.trending_down_rounded,
                    label: 'Negative',
                    value: '$negativeAccounts',
                  ),
                ),
              ],
            ),
            if (onTransfer != null) ...[
              const SizedBox(height: 10),
              _HeroTransferButton(onPressed: onTransfer!),
            ],
          ],
        );

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_inkTop, _inkBottom],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -80,
                top: -100,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.22),
                  ),
                ),
              ),
              Positioned(
                left: -60,
                bottom: -120,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.tertiary.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(pad),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 6, child: figure),
                          SizedBox(width: pad),
                          Expanded(flex: 4, child: side),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          figure,
                          SizedBox(height: pad - 4),
                          side,
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? tint;

  const _HeroPill({required this.text, this.icon, this.tint});

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Colors.white.withValues(alpha: 0.82);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTransferButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _HeroTransferButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _inkTop,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
        label: const Text(
          'Transfer between accounts',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

// ============================================================
// NET POSITION STRIP
// ============================================================

class _PositionStrip extends StatelessWidget {
  final int cash;
  final int? assets;
  final int? liabilities;

  const _PositionStrip({
    required this.cash,
    required this.assets,
    required this.liabilities,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = cash + (assets ?? 0) - (liabilities ?? 0);

    return _AdaptiveWrap(
      minTileWidth: 150,
      spacing: 10,
      maxColumns: 4,
      children: [
        _StatTile(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Cash',
          value: _peso(cash),
          color: scheme.primary,
        ),
        _StatTile(
          icon: Icons.inventory_2_outlined,
          label: 'Other assets',
          value: assets == null ? '—' : _peso(assets!),
          color: _positive(context),
        ),
        _StatTile(
          icon: Icons.request_quote_outlined,
          label: 'Liabilities',
          value: liabilities == null ? '—' : _peso(liabilities!),
          color: scheme.error,
        ),
        _StatTile(
          icon: Icons.stacked_line_chart_rounded,
          label: 'Net position',
          value: _peso(net),
          color: net >= 0 ? _positive(context) : scheme.error,
          emphasized: true,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool emphasized;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: emphasized ? color.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: emphasized
              ? color.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PENDING RECEIVABLES / PAYABLES
// ============================================================

class _PendingCashflowSection extends StatelessWidget {
  final List<PendingCashflowItem> items;

  const _PendingCashflowSection({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final receivables = items.where((i) => i.receivable).toList();
    final payables = items.where((i) => !i.receivable).toList();

    final panels = <Widget>[
      if (receivables.isNotEmpty)
        _PendingPanel(
          title: 'Money coming in',
          items: receivables,
          receivable: true,
        ),
      if (payables.isNotEmpty)
        _PendingPanel(
          title: 'Money going out',
          items: payables,
          receivable: false,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          title: 'Pending',
          subtitle: 'Not yet in your accounts',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 760 && panels.length == 2) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: panels[0]),
                  const SizedBox(width: 14),
                  Expanded(child: panels[1]),
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < panels.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  panels[i],
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PendingPanel extends StatefulWidget {
  final String title;
  final List<PendingCashflowItem> items;
  final bool receivable;

  const _PendingPanel({
    required this.title,
    required this.items,
    required this.receivable,
  });

  @override
  State<_PendingPanel> createState() => _PendingPanelState();
}

class _PendingPanelState extends State<_PendingPanel> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = widget.receivable ? _positive(context) : scheme.error;
    final total = widget.items.fold<int>(0, (s, i) => s + i.amount);
    final visible = _expanded
        ? widget.items
        : widget.items.take(_collapsedCount).toList();
    final hidden = widget.items.length - visible.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.receivable
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _peso(total),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          DateFormat('MMM d, yyyy').format(item.date),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _peso(item.amount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.items.length > _collapsedCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show $hidden more'),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// ACCOUNT CARD
// ============================================================

class _AccountCard extends ConsumerWidget {
  final AccountBalance balance;

  const _AccountCard({required this.balance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _gradientFor(balance.account.name);
    final historyAsync = ref.watch(
      accountBalanceHistoryProvider(balance.account.id),
    );

    final trend = historyAsync.maybeWhen(
      data: (points) {
        if (points.length < 2) return 0;
        return points.last.runningBalance -
            points[points.length - 2].runningBalance;
      },
      orElse: () => 0,
    );

    final overdrawn = balance.balance < 0;

    return Semantics(
      button: true,
      label:
          '${balance.account.name}, balance ${_peso(balance.balance)}. Opens history.',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountDetailPage(account: balance.account),
              ),
            );
          },
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _iconFor(balance.account.name),
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        balance.account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (overdrawn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Text(
                          'Overdrawn',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.arrow_outward_rounded,
                        color: Colors.white70,
                        size: 19,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available balance',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _peso(balance.balance),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                                fontFeatures: _tabular,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trend != 0) ...[
                      const SizedBox(width: 8),
                      _TrendBadge(value: trend),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: historyAsync.when(
                    data: (points) => _Sparkline(points: points),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final int value;

  const _TrendBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    final positive = value > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            _peso(value.abs()),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<BalancePoint> points;

  const _Sparkline({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Trend appears after your first entry',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      );
    }

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].runningBalance.toDouble()),
    ];

    return IgnorePointer(
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: max(1, (spots.length - 1).toDouble()),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.28,
              color: Colors.white,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ACCOUNT DETAIL
// ============================================================

enum _Period { week, month, threeMonths }

class AccountDetailPage extends ConsumerStatefulWidget {
  final Account account;

  const AccountDetailPage({super.key, required this.account});

  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends ConsumerState<AccountDetailPage> {
  _Period _period = _Period.month;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(
      accountBalanceHistoryProvider(widget.account.id),
    );
    final gradient = _gradientFor(widget.account.name);

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text(
            widget.account.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: _CashflowErrorState(
              message: 'Couldn’t load this account’s history',
              onRetry: () => ref.invalidate(
                accountBalanceHistoryProvider(widget.account.id),
              ),
            ),
          ),
          data: (points) {
            final filtered = _filterByPeriod(points);
            final currentBalance = points.isNotEmpty
                ? points.last.runningBalance
                : 0;
            final previousBalance = points.length > 1
                ? points[points.length - 2].runningBalance
                : currentBalance;
            final change = currentBalance - previousBalance;

            return LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final wide = w >= 900;
                final pad = w >= 720 ? 28.0 : 16.0;

                final hero = _DetailHero(
                  account: widget.account,
                  balance: currentBalance,
                  change: change,
                  gradient: gradient,
                );
                final insights = _DetailInsights(
                  points: filtered,
                  currentBalance: currentBalance,
                );
                final chart = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PeriodSelector(
                      selected: _period,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                    const SizedBox(height: 14),
                    _ChartCard(
                      points: filtered,
                      gradient: gradient,
                      height: wide ? 300 : (w >= 600 ? 260 : 220),
                    ),
                  ],
                );
                final activity = _ActivitySection(account: widget.account);

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _kMaxWidth),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 400,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      hero,
                                      const SizedBox(height: 14),
                                      insights,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [chart, activity],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                hero,
                                const SizedBox(height: 16),
                                chart,
                                const SizedBox(height: 14),
                                insights,
                                activity,
                              ],
                            ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<BalancePoint> _filterByPeriod(List<BalancePoint> points) {
    if (points.isEmpty) return points;

    final now = DateTime.now();
    final cutoff = switch (_period) {
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.threeMonths => now.subtract(const Duration(days: 90)),
    };

    final firstAfterCutoff = points.indexWhere((p) => !p.date.isBefore(cutoff));
    if (firstAfterCutoff <= 0) return points;

    final result = <BalancePoint>[
      points[firstAfterCutoff - 1],
      ...points.skip(firstAfterCutoff),
    ];
    return result.length >= 2 ? result : points;
  }
}

class _DetailHero extends StatelessWidget {
  final Account account;
  final int balance;
  final int change;
  final List<Color> gradient;

  const _DetailHero({
    required this.account,
    required this.balance,
    required this.change,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final positive = change >= 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_iconFor(account.name), color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Current balance',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              _peso(balance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
                fontFeatures: _tabular,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  positive
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${positive ? '+' : '-'}${_peso(change.abs())} since last entry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final _Period selected;
  final ValueChanged<_Period> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Period>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _Period.week, label: Text('7 days')),
        ButtonSegment(value: _Period.month, label: Text('30 days')),
        ButtonSegment(value: _Period.threeMonths, label: Text('3 months')),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final List<BalancePoint> points;
  final List<Color> gradient;
  final double height;

  const _ChartCard({
    required this.points,
    required this.gradient,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 18, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balance history',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Touch the line to see a day’s balance',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: height,
            child: _DetailChart(points: points, gradient: gradient),
          ),
        ],
      ),
    );
  }
}

class _DetailChart extends StatelessWidget {
  final List<BalancePoint> points;
  final List<Color> gradient;

  const _DetailChart({required this.points, required this.gradient});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (points.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart_rounded, size: 34, color: colors.outline),
            const SizedBox(height: 8),
            Text(
              'Not enough history yet',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].runningBalance.toDouble()),
    ];

    final values = spots.map((s) => s.y).toList();
    var minValue = values.reduce(min);
    var maxValue = values.reduce(max);

    if (minValue == maxValue) {
      final flatPad = max(maxValue.abs() * 0.10, 100.0);
      minValue -= flatPad;
      maxValue += flatPad;
    }

    final range = maxValue - minValue;
    final padding = max(range * 0.12, 100.0);
    final minY = minValue - padding;
    final maxY = maxValue + padding;
    final horizontalInterval = max(range / 4, 1).toDouble();
    final bottomInterval = max((spots.length / 4).ceil(), 1).toDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: max(1, (spots.length - 1).toDouble()),
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: horizontalInterval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: colors.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: horizontalInterval,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    _compactPeso(value),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: bottomInterval,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DateFormat('MMM d').format(points[index].date),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => colors.inverseSurface,
            getTooltipItems: (touched) {
              return touched.map((spot) {
                final index = spot.x.toInt();
                final date = index >= 0 && index < points.length
                    ? points[index].date
                    : null;

                return LineTooltipItem(
                  '${_peso(spot.y.toInt())}\n',
                  TextStyle(
                    color: colors.onInverseSurface,
                    fontWeight: FontWeight.w800,
                  ),
                  children: [
                    if (date != null)
                      TextSpan(
                        text: DateFormat('MMM d, yyyy').format(date),
                        style: TextStyle(
                          color: colors.onInverseSurface.withValues(
                            alpha: 0.70,
                          ),
                          fontSize: 10,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            gradient: LinearGradient(colors: gradient),
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  gradient.first.withValues(alpha: 0.2),
                  gradient.last.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailInsights extends StatelessWidget {
  final List<BalancePoint> points;
  final int currentBalance;

  const _DetailInsights({required this.points, required this.currentBalance});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (points.length < 2) return const SizedBox.shrink();

    final first = points.first.runningBalance;
    final change = currentBalance - first;
    final highest = points.map((p) => p.runningBalance).reduce(max);
    final lowest = points.map((p) => p.runningBalance).reduce(min);

    return _AdaptiveWrap(
      minTileWidth: 125,
      spacing: 10,
      maxColumns: 3,
      children: [
        _InsightCard(
          icon: Icons.swap_vert_rounded,
          label: 'Period change',
          value: '${change >= 0 ? '+' : '-'}${_peso(change.abs())}',
          color: change >= 0 ? _positive(context) : colors.error,
        ),
        _InsightCard(
          icon: Icons.arrow_upward_rounded,
          label: 'Highest',
          value: _peso(highest),
          color: colors.primary,
        ),
        _InsightCard(
          icon: Icons.arrow_downward_rounded,
          label: 'Lowest',
          value: _peso(lowest),
          color: colors.secondary,
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InsightCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 9),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Latest ledger activity for a payment account, shown under the chart.
class _ActivitySection extends ConsumerWidget {
  final Account account;

  const _ActivitySection({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final entriesAsync = ref.watch(accountLedgerEntriesProvider(account.id));

    return entriesAsync.maybeWhen(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        final recent = entries.toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final shown = recent.take(8).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(title: 'Recent activity'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    _LedgerEntryTile(
                      entry: shown[i],
                      accountType: account.type,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _LedgerEntryTile extends StatelessWidget {
  final LedgerEntryRow entry;
  final String accountType;

  const _LedgerEntryTile({required this.entry, required this.accountType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final isIncrease = entry.debit > 0
        ? accountType == 'asset'
        : accountType != 'asset';
    final amount = entry.debit > 0 ? entry.debit : entry.credit;
    final color = isIncrease ? _positive(context) : scheme.error;
    final title = entry.description?.trim().isNotEmpty == true
        ? entry.description!.trim()
        : _sourceTypeLabel(entry.sourceType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIncrease ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 17,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_sourceTypeLabel(entry.sourceType)} · ${DateFormat('MMM d, yyyy').format(entry.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${isIncrease ? '+' : '-'}${_peso(amount)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EMPTY / ERROR / SKELETONS
// ============================================================

class _EmptyAccountsState extends StatelessWidget {
  const _EmptyAccountsState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              size: 34,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No payment accounts yet',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Record a transaction and pick a payment account. It will show up here with its balance and history.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashflowErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;

  const _CashflowErrorState({
    required this.onRetry,
    this.message = 'Couldn’t load your accounts',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: colors.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
      ),
    );
  }
}

class _PanelSkeleton extends StatelessWidget {
  const _PanelSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

// ============================================================
// TRANSFER SHEET
// ============================================================

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  String? _fromId;
  String? _toId;
  String? _error;

  final _amountController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(
    ColorScheme colors, {
    required String label,
    required IconData icon,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  void _swap() {
    setState(() {
      final tmp = _fromId;
      _fromId = _toId;
      _toId = tmp;
    });
  }

  void _setAmountCents(int cents) {
    setState(() {
      _amountController.text = (cents / 100).toStringAsFixed(2);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final balancesAsync = ref.watch(accountBalancesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: balancesAsync.when(
        loading: () => const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Couldn’t load your accounts. Close this and try again.'),
        ),
        data: (balances) {
          if (balances.length < 2) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'You need at least two payment accounts to make a transfer.',
                textAlign: TextAlign.center,
              ),
            );
          }

          AccountBalance? find(String? id) => id == null
              ? null
              : balances.where((b) => b.account.id == id).firstOrNull;

          final fromAccount = find(_fromId);
          final toAccount = find(_toId);

          final entered = double.tryParse(
            _amountController.text.replaceAll(',', '').trim(),
          );
          final enteredCents = entered == null ? null : (entered * 100).round();
          final exceeds =
              fromAccount != null &&
              enteredCents != null &&
              enteredCents > fromAccount.balance;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transfer money',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Move money between your accounts.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // FROM / swap / TO
                DropdownButtonFormField<String>(
                  key: ValueKey('from-$_fromId'),
                  initialValue: _fromId,
                  isExpanded: true,
                  decoration: _decoration(
                    colors,
                    label: 'From account',
                    icon: Icons.north_east_rounded,
                  ),
                  items: balances
                      .map(
                        (b) => DropdownMenuItem(
                          value: b.account.id,
                          child: Text(
                            b.account.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _fromId = value;
                    if (_toId == value) _toId = null;
                    _error = null;
                  }),
                ),
                if (fromAccount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 16),
                    child: Text(
                      'Available: ${_peso(fromAccount.balance)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.center,
                  child: IconButton.filledTonal(
                    tooltip: 'Swap accounts',
                    onPressed: (_fromId != null || _toId != null)
                        ? _swap
                        : null,
                    icon: const Icon(Icons.swap_vert_rounded),
                  ),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('to-$_toId-$_fromId'),
                  initialValue: _toId,
                  isExpanded: true,
                  decoration: _decoration(
                    colors,
                    label: 'To account',
                    icon: Icons.south_west_rounded,
                  ),
                  items: balances
                      .where((b) => b.account.id != _fromId)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b.account.id,
                          child: Text(
                            b.account.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _toId = value;
                    _error = null;
                  }),
                ),
                if (toAccount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 16),
                    child: Text(
                      'Current balance: ${_peso(toAccount.balance)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // AMOUNT
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: _decoration(
                    colors,
                    label: 'Amount',
                    icon: Icons.payments_outlined,
                    prefixText: '₱ ',
                  ),
                ),
                if (fromAccount != null && fromAccount.balance > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('25%'),
                        onPressed: () => _setAmountCents(
                          (fromAccount.balance * 0.25).round(),
                        ),
                      ),
                      ActionChip(
                        label: const Text('50%'),
                        onPressed: () => _setAmountCents(
                          (fromAccount.balance * 0.5).round(),
                        ),
                      ),
                      ActionChip(
                        label: const Text('All'),
                        onPressed: () => _setAmountCents(fromAccount.balance),
                      ),
                    ],
                  ),
                ],
                if (exceeds)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: colors.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${fromAccount.account.name} will go below zero.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 4),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.swap_horiz_rounded),
                    label: Text(_saving ? 'Transferring…' : 'Transfer money'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (_fromId == null || _toId == null) {
      setState(() => _error = 'Choose both accounts.');
      return;
    }
    if (_fromId == _toId) {
      setState(() => _error = 'Pick two different accounts.');
      return;
    }

    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );

    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final audit = ref.read(auditLogServiceProvider);

      final amountCents = (amount * 100).round();
      final transferDate = DateTime.now();

      await db.transaction(() async {
        final ledger = LedgerService(db);
        final from = await ledger.requirePaymentAccount(
          _fromId!,
          kCurrentBusinessId,
        );
        final to = await ledger.requirePaymentAccount(
          _toId!,
          kCurrentBusinessId,
        );

        final transferId = const Uuid().v4();
        final entryId = const Uuid().v4();

        await db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: entryId,
                businessId: kCurrentBusinessId,
                entryDate: transferDate,
                sourceType: 'transfer',
                sourceId: Value(transferId),
                description: const Value('Account transfer'),
              ),
            );

        await db
            .into(db.ledgerLines)
            .insert(
              LedgerLinesCompanion.insert(
                id: const Uuid().v4(),
                journalEntryId: entryId,
                accountId: to.id,
                debit: Value(amountCents),
              ),
            );

        await db
            .into(db.ledgerLines)
            .insert(
              LedgerLinesCompanion.insert(
                id: const Uuid().v4(),
                journalEntryId: entryId,
                accountId: from.id,
                credit: Value(amountCents),
              ),
            );

        await db
            .into(db.accountTransfers)
            .insert(
              AccountTransfersCompanion.insert(
                id: transferId,
                businessId: kCurrentBusinessId,
                fromAccountId: from.id,
                toAccountId: to.id,
                amount: amountCents,
                transferDate: transferDate,
              ),
            );

        await audit.record(
          AuditEvent(
            businessId: kCurrentBusinessId,
            module: AuditModule.finance,
            actionType: AuditActionType.create,
            action: 'finance.transfer_recorded',
            entityType: 'account_transfers',
            entityId: transferId,
            entityLabel: '${from.name} → ${to.name}',
            after: {
              'amount': amountCents,
              'fromAccountId': from.id,
              'toAccountId': to.id,
              'date': transferDate,
            },
            details: {'journalEntryId': entryId},
          ),
        );
      });

      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Transferred ${_peso(amountCents)}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Transfer failed: $error';
      });
    }
  }
}

// ============================================================
// ASSETS & LIABILITIES SECTIONS
// ============================================================

const _assetSubtypeLabels = {
  'current_asset': 'Current assets',
  'non_current_asset': 'Non-current assets',
};

const _liabilitySubtypeLabels = {
  'trade_payable': 'Trade payables',
  'loan_payable': 'Loans payable',
  'other_payable': 'Other payables',
};

class _BalancePanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final int total;
  final String emptyText;
  final Map<String, List<AccountBalanceEntry>> grouped;

  const _BalancePanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.total,
    required this.emptyText,
    required this.grouped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _peso(total),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (grouped.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                emptyText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final group in grouped.entries) ...[
              const SizedBox(height: 16),
              Text(
                group.key,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final item in group.value)
                _BalanceRow(account: item.account, amount: item.balance),
              const Divider(height: 14),
              _SubtotalRow(
                amount: group.value.fold<int>(0, (sum, e) => sum + e.balance),
              ),
            ],
        ],
      ),
    );
  }
}

class _AssetsSection extends StatelessWidget {
  final List<AccountBalanceEntry> assets;
  const _AssetsSection({required this.assets});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<AccountBalanceEntry>>{};
    for (final entry in assets) {
      final label =
          _assetSubtypeLabels[entry.account.subtype] ?? 'Other assets';
      grouped.putIfAbsent(label, () => []).add(entry);
    }

    return _BalancePanel(
      title: 'Assets',
      icon: Icons.inventory_2_outlined,
      color: _positive(context),
      total: assets.fold<int>(0, (sum, a) => sum + a.balance),
      emptyText:
          'No non-cash assets yet. Add equipment, a vehicle or stock from the Journal Entry page.',
      grouped: grouped,
    );
  }
}

class _LiabilitiesSection extends StatelessWidget {
  final List<AccountBalanceEntry> liabilities;
  const _LiabilitiesSection({required this.liabilities});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<AccountBalanceEntry>>{};
    for (final entry in liabilities) {
      final label =
          _liabilitySubtypeLabels[entry.account.subtype] ?? 'Other liabilities';
      grouped.putIfAbsent(label, () => []).add(entry);
    }

    return _BalancePanel(
      title: 'Liabilities',
      icon: Icons.request_quote_outlined,
      color: Theme.of(context).colorScheme.error,
      total: liabilities.fold<int>(0, (sum, a) => sum + a.balance),
      emptyText: 'Nothing owed right now. Payables and loans will show here.',
      grouped: grouped,
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final Account account;
  final int amount;
  const _BalanceRow({required this.account, required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AccountLedgerPage(account: account, balance: amount),
        ),
      ),
      child: ConstrainedBox(
        // 48dp minimum touch target.
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  account.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _peso(amount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tabular,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtotalRow extends StatelessWidget {
  final int amount;
  const _SubtotalRow({required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Subtotal',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          _peso(amount),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ACCOUNT LEDGER PAGE — read-only, dated history for an
// asset/liability account, grouped by month.
// New entries are only recorded via the Journal Entry page or
// through Suppliers/Customers.
// ============================================================

class AccountLedgerPage extends ConsumerWidget {
  final Account account;
  final int balance;

  const AccountLedgerPage({
    super.key,
    required this.account,
    required this.balance,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entriesAsync = ref.watch(accountLedgerEntriesProvider(account.id));
    final isAsset = account.type == 'asset';
    final accent = isAsset ? _positive(context) : scheme.error;

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text(
            account.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final pad = constraints.maxWidth >= 720 ? 28.0 : 16.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAsset ? 'Current value' : 'Amount owed',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _peso(balance),
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.2,
                                color: scheme.onSurface,
                                fontFeatures: _tabular,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    entriesAsync.when(
                      data: (entries) {
                        if (entries.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Text(
                                'No transactions recorded yet.',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }

                        final sorted = entries.toList()
                          ..sort((a, b) => b.date.compareTo(a.date));
                        final byMonth = <String, List<LedgerEntryRow>>{};
                        for (final e in sorted) {
                          byMonth
                              .putIfAbsent(
                                DateFormat('MMMM yyyy').format(e.date),
                                () => [],
                              )
                              .add(e);
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final month in byMonth.entries) ...[
                              _SectionHeader(title: month.key),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < month.value.length;
                                      i++
                                    ) ...[
                                      if (i > 0)
                                        Divider(
                                          height: 1,
                                          color: scheme.outlineVariant
                                              .withValues(alpha: 0.4),
                                        ),
                                      _LedgerEntryTile(
                                        entry: month.value[i],
                                        accountType: account.type,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: _CashflowErrorState(
                          message: 'Couldn’t load transactions',
                          onRetry: () => ref.invalidate(
                            accountLedgerEntriesProvider(account.id),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// ADD CAPITAL / ASSET / LIABILITY SHEETS — preserved from the original file
// ============================================================

class AddCapitalWithdrawalSheet extends ConsumerStatefulWidget {
  /// When set, edits this existing withdrawal journal entry instead
  /// of recording a new one.
  final String? journalEntryId;

  const AddCapitalWithdrawalSheet({super.key, this.journalEntryId});

  @override
  ConsumerState<AddCapitalWithdrawalSheet> createState() =>
      _AddCapitalWithdrawalSheetState();
}

class _AddCapitalWithdrawalSheetState
    extends ConsumerState<AddCapitalWithdrawalSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _paymentAccountId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _loading = false;
  int? _availableCapital;

  bool get _isEditing => widget.journalEntryId != null;

  @override
  void initState() {
    super.initState();
    _loadAvailableCapital();
    if (_isEditing) _loadExisting();
  }

  Future<void> _loadAvailableCapital() async {
    final balance = await ref.read(capitalBalanceProvider.future);
    if (!mounted) return;
    setState(() => _availableCapital = balance);
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final detail = await ref
        .read(capitalAssetLiabilityServiceProvider)
        .getCapitalWithdrawalDetail(widget.journalEntryId!);
    if (!mounted) return;
    setState(() {
      _amountController.text = (detail.amount / 100).toStringAsFixed(2);
      _noteController.text = detail.description ?? '';
      _paymentAccountId = detail.paymentAccountId;
      _date = detail.date;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );

    if (amount == null || amount <= 0 || _paymentAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount and choose an account.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final service = ref.read(capitalAssetLiabilityServiceProvider);
      final description = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (_isEditing) {
        await service.updateCapitalWithdrawal(
          journalEntryId: widget.journalEntryId!,
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          paymentAccountId: _paymentAccountId!,
          description: description,
        );
      } else {
        await service.recordCapitalWithdrawal(
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          paymentAccountId: _paymentAccountId!,
          description: description,
        );
      }

      ref.invalidate(capitalBalanceProvider);
      ref.invalidate(accountBalancesProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    final enteredAmount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );
    final remaining = (_availableCapital != null && enteredAmount != null)
        ? _availableCapital! - (enteredAmount * 100).round()
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isEditing
                                ? 'Edit Capital Withdrawal'
                                : 'Capital Withdrawal',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Money the owner takes out of the business.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_availableCapital != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Current capital: ${_peso(_availableCapital!)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₱ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (remaining != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              (remaining < 0
                                      ? Colors.redAccent
                                      : scheme.primary)
                                  .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          remaining < 0
                              ? 'This is more than the recorded capital.'
                              : 'Capital remaining after this: ${_peso(remaining)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: remaining < 0
                                ? Colors.redAccent
                                : scheme.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    accountsAsync.when(
                      data: (accounts) => DropdownButtonFormField<String>(
                        initialValue: _paymentAccountId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Taken from',
                        ),
                        items: accounts
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  a.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _paymentAccountId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Unable to load accounts'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepOrange.shade700,
                        ),
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isEditing
                                    ? 'Save Changes'
                                    : 'Withdraw Capital',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ============================================================
// ADD CAPITAL SHEET — shared by the Cashflow page and the Journal
// Entry page's "add" menu.
// ============================================================

class AddCapitalSheet extends ConsumerStatefulWidget {
  /// When set, edits this existing capital journal entry instead of
  /// recording a new one.
  final String? journalEntryId;

  const AddCapitalSheet({super.key, this.journalEntryId});

  @override
  ConsumerState<AddCapitalSheet> createState() => _AddCapitalSheetState();
}

class _AddCapitalSheetState extends ConsumerState<AddCapitalSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _paymentAccountId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _loading = false;

  bool get _isEditing => widget.journalEntryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final detail = await ref
        .read(capitalAssetLiabilityServiceProvider)
        .getCapitalDetail(widget.journalEntryId!);
    if (!mounted) return;
    setState(() {
      _amountController.text = (detail.amount / 100).toStringAsFixed(2);
      _noteController.text = detail.description ?? '';
      _paymentAccountId = detail.paymentAccountId;
      _date = detail.date;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );

    if (amount == null || amount <= 0 || _paymentAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount and choose an account.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final service = ref.read(capitalAssetLiabilityServiceProvider);
      final description = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (_isEditing) {
        await service.updateCapital(
          journalEntryId: widget.journalEntryId!,
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          paymentAccountId: _paymentAccountId!,
          description: description,
        );
      } else {
        await service.recordCapital(
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          paymentAccountId: _paymentAccountId!,
          description: description,
        );
      }

      ref.invalidate(capitalBalanceProvider);
      ref.invalidate(accountBalancesProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isEditing ? 'Edit Capital' : 'Add Capital',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Money the owner puts into the business.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₱ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    accountsAsync.when(
                      data: (accounts) => DropdownButtonFormField<String>(
                        initialValue: _paymentAccountId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Goes into',
                        ),
                        items: accounts
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  a.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _paymentAccountId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Unable to load accounts'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isEditing ? 'Save Changes' : 'Add Capital'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ============================================================
// ADD ASSET SHEET
// ============================================================

class AddAssetSheet extends ConsumerStatefulWidget {
  /// When set, edits this existing asset journal entry instead of
  /// recording a new one.
  final String? journalEntryId;

  const AddAssetSheet({super.key, this.journalEntryId});

  @override
  ConsumerState<AddAssetSheet> createState() => _AddAssetSheetState();
}

class _AddAssetSheetState extends ConsumerState<AddAssetSheet> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isCurrentAsset = true;
  bool _onCredit = false;
  String? _paymentAccountId;
  DateTime _date = DateTime.now();
  String? _assetAccountId;
  bool _saving = false;
  bool _loading = false;

  bool get _isEditing => widget.journalEntryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final detail = await ref
        .read(capitalAssetLiabilityServiceProvider)
        .getAssetDetail(widget.journalEntryId!);
    if (!mounted) return;
    final onCredit = detail.isOnCredit;
    setState(() {
      _nameController.text = detail.accountName;
      _amountController.text = (detail.amount / 100).toStringAsFixed(2);
      _noteController.text = detail.description ?? '';
      _isCurrentAsset = detail.subtype != 'non_current_asset';
      _onCredit = onCredit;
      _paymentAccountId = onCredit ? null : detail.paymentAccountId;
      _date = detail.date;
      _assetAccountId = detail.accountId;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );

    if (name.isEmpty ||
        amount == null ||
        amount <= 0 ||
        (!_onCredit && _paymentAccountId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a name, a valid amount, and how it was paid.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final service = ref.read(capitalAssetLiabilityServiceProvider);
      final description = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (_isEditing) {
        await service.updateAsset(
          journalEntryId: widget.journalEntryId!,
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          assetAccountId: _assetAccountId!,
          assetAccountName: name,
          isCurrentAsset: _isCurrentAsset,
          paymentAccountId: _onCredit ? null : _paymentAccountId,
          description: description,
        );
      } else {
        final account = await service.addAssetAccount(
          businessId: kCurrentBusinessId,
          name: name,
          isCurrentAsset: _isCurrentAsset,
        );

        await service.recordAsset(
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          assetAccountId: account.id,
          paymentAccountId: _onCredit ? null : _paymentAccountId,
          description: description,
        );
      }

      ref.invalidate(assetBalancesProvider);
      ref.invalidate(liabilityBalancesProvider);
      ref.invalidate(accountBalancesProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isEditing ? 'Edit Asset' : 'Add Asset',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Something the business now owns — equipment, a vehicle, etc.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Asset name',
                        hintText: 'e.g. Espresso Machine',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Current'),
                          icon: Icon(Icons.schedule_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Non-current'),
                          icon: Icon(Icons.apartment_rounded, size: 16),
                        ),
                      ],
                      selected: {_isCurrentAsset},
                      onSelectionChanged: (s) =>
                          setState(() => _isCurrentAsset = s.first),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _isCurrentAsset
                            ? 'Expected to be used or converted to cash within a year.'
                            : 'Longer-term — equipment, property, and the like.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₱ ',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bought on credit'),
                      subtitle: const Text(
                        'Adds to Accounts Payable instead of a payment account',
                      ),
                      value: _onCredit,
                      onChanged: (v) => setState(() {
                        _onCredit = v;
                        if (v) _paymentAccountId = null;
                      }),
                    ),
                    if (!_onCredit)
                      accountsAsync.when(
                        data: (accounts) => DropdownButtonFormField<String>(
                          initialValue: _paymentAccountId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Paid from',
                          ),
                          items: accounts
                              .map(
                                (a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text(
                                    a.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _paymentAccountId = v),
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const Text('Unable to load accounts'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isEditing ? 'Save Changes' : 'Add Asset'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ============================================================
// ADD LIABILITY SHEET
// ============================================================

const _liabilitySubtypeOptions = {
  'trade_payable': 'Trade Payable',
  'loan_payable': 'Loan Payable',
  'other_payable': 'Other Payable',
};

class AddLiabilitySheet extends ConsumerStatefulWidget {
  /// When set, edits this existing liability journal entry instead of
  /// recording a new one.
  final String? journalEntryId;

  const AddLiabilitySheet({super.key, this.journalEntryId});

  @override
  ConsumerState<AddLiabilitySheet> createState() => _AddLiabilitySheetState();
}

class _AddLiabilitySheetState extends ConsumerState<AddLiabilitySheet> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _subtype = 'trade_payable';
  String? _paymentAccountId;
  DateTime _date = DateTime.now();
  String? _liabilityAccountId;
  bool _saving = false;
  bool _loading = false;

  bool get _isEditing => widget.journalEntryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final detail = await ref
        .read(capitalAssetLiabilityServiceProvider)
        .getLiabilityDetail(widget.journalEntryId!);
    if (!mounted) return;
    setState(() {
      _nameController.text = detail.accountName;
      _amountController.text = (detail.amount / 100).toStringAsFixed(2);
      _noteController.text = detail.description ?? '';
      _subtype = detail.subtype ?? 'trade_payable';
      _paymentAccountId = detail.paymentAccountId;
      _date = detail.date;
      _liabilityAccountId = detail.accountId;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );

    if (name.isEmpty ||
        amount == null ||
        amount <= 0 ||
        _paymentAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a name, a valid amount, and where the money went.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final service = ref.read(capitalAssetLiabilityServiceProvider);
      final description = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (_isEditing) {
        await service.updateLiability(
          journalEntryId: widget.journalEntryId!,
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          liabilityAccountId: _liabilityAccountId!,
          liabilityAccountName: name,
          subtype: _subtype,
          paymentAccountId: _paymentAccountId!,
          description: description,
        );
      } else {
        final account = await service.addLiabilityAccount(
          businessId: kCurrentBusinessId,
          name: name,
          subtype: _subtype,
        );

        await service.recordLiability(
          businessId: kCurrentBusinessId,
          date: _date,
          amount: (amount * 100).round(),
          liabilityAccountId: account.id,
          paymentAccountId: _paymentAccountId!,
          description: description,
        );
      }

      ref.invalidate(liabilityBalancesProvider);
      ref.invalidate(accountBalancesProvider);
      ref.read(ledgerVersionProvider.notifier).state++;

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isEditing ? 'Edit Liability' : 'Add Liability',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Something the business now owes — a payable, a loan, etc.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Liability name',
                        hintText: 'e.g. Bank Loan',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _subtype,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: _liabilitySubtypeOptions.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _subtype = v ?? _subtype),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₱ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    accountsAsync.when(
                      data: (accounts) => DropdownButtonFormField<String>(
                        initialValue: _paymentAccountId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Money received into',
                        ),
                        items: accounts
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  a.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _paymentAccountId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Unable to load accounts'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isEditing ? 'Save Changes' : 'Add Liability',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
