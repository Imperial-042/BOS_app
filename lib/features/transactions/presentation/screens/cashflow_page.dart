import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column, Table;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

import '../../../transactions/presentation/screens/transaction_page.dart'
    show businessProfileProvider, ledgerVersionProvider, kCurrentBusinessId;

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
// PROVIDERS
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

// ============================================================
// ACCOUNT VISUALS
// ============================================================

const _gradients = <List<Color>>[
  [Color(0xFF5B5FEF), Color(0xFF7C4DFF)],
  [Color(0xFF00897B), Color(0xFF26A69A)],
  [Color(0xFFF57C00), Color(0xFFFFB300)],
  [Color(0xFFD84315), Color(0xFFF4511E)],
  [Color(0xFF1976D2), Color(0xFF29B6F6)],
  [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
];

List<Color> _gradientFor(String name) {
  final index =
      name.codeUnits.fold<int>(0, (a, b) => a + b) % _gradients.length;

  return _gradients[index];
}

IconData _iconFor(String name) {
  final lower = name.toLowerCase();

  if (lower.contains('bank')) {
    return Icons.account_balance_rounded;
  }

  if (lower.contains('cash')) {
    return Icons.payments_rounded;
  }

  if (lower.contains('gcash')) {
    return Icons.phone_android_rounded;
  }

  if (lower.contains('wallet')) {
    return Icons.account_balance_wallet_rounded;
  }

  return Icons.account_balance_wallet_outlined;
}

String _peso(int cents) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  ).format(cents / 100);
}

// ============================================================
// CASHFLOW PAGE
// ============================================================

class CashflowPage extends ConsumerWidget {
  const CashflowPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(accountBalancesProvider);
    final pendingAsync = ref.watch(pendingCashflowProvider);
    final businessName = ref
        .watch(businessProfileProvider)
        .maybeWhen(data: (value) => value.name, orElse: () => null);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar.large(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerLowest,
            titleSpacing: 20,
            title: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Brand/accent mark
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [scheme.primary, scheme.primaryContainer],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.balance_rounded,
                            size: 23,
                            color: scheme.onPrimary,
                          ),
                        ),

                        const SizedBox(width: 14),

                        // Title hierarchy
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 5),
                              Text(
                                businessName == null || businessName.isEmpty
                                    ? 'Cashflow'
                                    : '$businessName cashflow',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.2,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your money, organized in one place',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.05,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ==================================================
          // HERO
          // ==================================================
          SliverToBoxAdapter(
            child: balancesAsync.when(
              data: (balances) {
                return _TotalBalanceHero(
                  balances: balances,
                  onTransfer: balances.length >= 2
                      ? () => _showTransferSheet(context, ref)
                      : null,
                );
              },
              loading: () => const _HeroSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          SliverToBoxAdapter(
            child: pendingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (items) => _PendingCashflowSection(items: items),
            ),
          ),

          // ==================================================
          // ACCOUNT SECTION
          // ==================================================
          balancesAsync.when(
            data: (balances) {
              if (balances.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyAccountsState(),
                );
              }

              return SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;

                  if (width >= 850) {
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _AccountCard(balance: balances[index]);
                        }, childCount: balances.length),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 470,
                              mainAxisExtent: 220,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    sliver: SliverList.separated(
                      itemCount: balances.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        return _AccountCard(balance: balances[index]);
                      },
                    ),
                  );
                },
              );
            },
            loading: () {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            error: (error, _) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _CashflowErrorState(
                  onRetry: () {
                    ref.invalidate(accountBalancesProvider);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showTransferSheet(BuildContext context, WidgetRef ref) {
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
}

class _PendingCashflowSection extends StatelessWidget {
  final List<PendingCashflowItem> items;

  const _PendingCashflowSection({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending receivables and payables',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    item.receivable
                        ? Icons.call_received_rounded
                        : Icons.call_made_rounded,
                    color: item.receivable ? Colors.green : scheme.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.receivable ? 'Receivable' : 'Payable',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _peso(item.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: item.receivable ? Colors.green : scheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

    final total = balances.fold<int>(0, (sum, item) => sum + item.balance);

    final positiveAccounts = balances.where((e) => e.balance >= 0).length;

    final negativeAccounts = balances.where((e) => e.balance < 0).length;

    final isNegative = total < 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;

          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1F2937), Color(0xFF111827)],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Decorative background orb.
                Positioned(
                  right: -70,
                  top: -85,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                ),

                Positioned(
                  right: 80,
                  bottom: -120,
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.secondary.withValues(alpha: 0.07),
                    ),
                  ),
                ),

                Padding(
                  padding: EdgeInsets.all(compact ? 22 : 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ----------------------------------------
                      // HEADER
                      // ----------------------------------------

                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.07),
                              ),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOTAL BALANCE',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Across all active accounts',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.40),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Text(
                              '${balances.length} ${balances.length == 1 ? 'account' : 'accounts'}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // ----------------------------------------
                      // MAIN BALANCE
                      // ----------------------------------------
                      Text(
                        'Available cash',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 5),

                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _peso(total),
                          maxLines: 1,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2.0,
                            height: 1,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ----------------------------------------
                      // STATUS
                      // ----------------------------------------
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isNegative
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.80),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              isNegative
                                  ? 'Net balance is below zero'
                                  : 'Your available funds are positive',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.80),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ----------------------------------------
                      // BOTTOM ROW
                      // ----------------------------------------
                      if (compact)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _HeroMetric(
                                    icon: Icons.check_circle_rounded,
                                    label: 'Healthy',
                                    value: '$positiveAccounts',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _HeroMetric(
                                    icon: Icons.warning_rounded,
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
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _HeroMetric(
                                icon: Icons.check_circle_rounded,
                                label: 'Healthy accounts',
                                value: '$positiveAccounts',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HeroMetric(
                                icon: Icons.warning_rounded,
                                label: 'Negative accounts',
                                value: '$negativeAccounts',
                              ),
                            ),
                            if (onTransfer != null) ...[
                              const SizedBox(width: 12),
                              _HeroTransferButton(onPressed: onTransfer!),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// HERO METRIC
// ============================================================

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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.70)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
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

// ============================================================
// HERO TRANSFER BUTTON
// ============================================================

class _HeroTransferButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _HeroTransferButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz_rounded, size: 19, color: scheme.primary),
              const SizedBox(width: 7),
              Text(
                'Transfer',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
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
        if (points.length < 2) {
          return 0;
        }

        return points.last.runningBalance -
            points[points.length - 2].runningBalance;
      },
      orElse: () => 0,
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AccountDetailPage(account: balance.account),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.20),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          balance.account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Payment account',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                            color: Colors.white.withValues(alpha: 0.68),
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
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trend != 0) _TrendBadge(value: trend),
                ],
              ),

              const SizedBox(height: 15),

              SizedBox(
                height: 42,
                width: double.infinity,
                child: historyAsync.when(
                  data: (points) {
                    return _Sparkline(points: points);
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
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
// TREND BADGE
// ============================================================

class _TrendBadge extends StatelessWidget {
  final int value;

  const _TrendBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    final positive = value > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
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

// ============================================================
// SPARKLINE
// ============================================================

class _Sparkline extends StatelessWidget {
  final List<BalancePoint> points;

  const _Sparkline({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Not enough history for a trend',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
          ),
        ),
      );
    }

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].runningBalance.toDouble()),
    ];

    return LineChart(
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
                  Colors.white.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
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

    return Scaffold(
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
          child: Text(
            'Unable to load account history.',
            style: Theme.of(context).textTheme.bodyLarge,
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

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _DetailHero(
                account: widget.account,
                balance: currentBalance,
                change: change,
                gradient: gradient,
              ),
              const SizedBox(height: 18),
              _PeriodSelector(
                selected: _period,
                onChanged: (period) {
                  setState(() {
                    _period = period;
                  });
                },
              ),
              const SizedBox(height: 18),
              _ChartCard(points: filtered, gradient: gradient),
              const SizedBox(height: 18),
              _DetailInsights(points: filtered, currentBalance: currentBalance),
            ],
          );
        },
      ),
    );
  }

  List<BalancePoint> _filterByPeriod(List<BalancePoint> points) {
    if (points.isEmpty) {
      return points;
    }

    final now = DateTime.now();

    final cutoff = switch (_period) {
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.threeMonths => now.subtract(const Duration(days: 90)),
    };

    final firstAfterCutoff = points.indexWhere((p) => !p.date.isBefore(cutoff));

    if (firstAfterCutoff <= 0) {
      return points;
    }

    final result = <BalancePoint>[
      points[firstAfterCutoff - 1],
      ...points.skip(firstAfterCutoff),
    ];

    return result.length >= 2 ? result : points;
  }
}

// ============================================================
// DETAIL HERO
// ============================================================

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
            color: gradient.first.withValues(alpha: 0.18),
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
                  color: Colors.white.withValues(alpha: 0.15),
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
              color: Colors.white.withValues(alpha: 0.70),
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
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
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
                const SizedBox(width: 5),
                Text(
                  '${positive ? '+' : '-'}${_peso(change.abs())} since last entry',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

// ============================================================
// PERIOD SELECTOR
// ============================================================

class _PeriodSelector extends StatelessWidget {
  final _Period selected;
  final ValueChanged<_Period> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Period>(
      segments: const [
        ButtonSegment(value: _Period.week, label: Text('7 days')),
        ButtonSegment(value: _Period.month, label: Text('30 days')),
        ButtonSegment(value: _Period.threeMonths, label: Text('3 months')),
      ],
      selected: {selected},
      onSelectionChanged: (value) {
        onChanged(value.first);
      },
    );
  }
}

// ============================================================
// CHART CARD
// ============================================================

class _ChartCard extends StatelessWidget {
  final List<BalancePoint> points;
  final List<Color> gradient;

  const _ChartCard({required this.points, required this.gradient});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balance history',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'How your account balance changed',
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
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: _DetailChart(points: points, gradient: gradient),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DETAIL CHART
// ============================================================

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
      final padding = max(maxValue.abs() * 0.10, 100.0);

      minValue -= padding;
      maxValue += padding;
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
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: colors.outlineVariant.withValues(alpha: 0.55),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
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
            getTooltipItems: (spots) {
              return spots.map((spot) {
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
                  gradient.first.withValues(alpha: 0.18),
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

// ============================================================
// DETAIL INSIGHTS
// ============================================================

class _DetailInsights extends StatelessWidget {
  final List<BalancePoint> points;
  final int currentBalance;

  const _DetailInsights({required this.points, required this.currentBalance});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (points.length < 2) {
      return const SizedBox.shrink();
    }

    final first = points.first.runningBalance;
    final change = currentBalance - first;

    final highest = points.map((p) => p.runningBalance).reduce(max);

    final lowest = points.map((p) => p.runningBalance).reduce(min);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _InsightCard(
                      icon: Icons.trending_up_rounded,
                      label: 'Period change',
                      value: '${change >= 0 ? '+' : '-'}${_peso(change.abs())}',
                      color: change >= 0 ? Colors.green.shade700 : colors.error,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InsightCard(
                      icon: Icons.arrow_upward_rounded,
                      label: 'Highest',
                      value: _peso(highest),
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InsightCard(
                icon: Icons.arrow_downward_rounded,
                label: 'Lowest',
                value: _peso(lowest),
                color: colors.secondary,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _InsightCard(
                icon: Icons.trending_up_rounded,
                label: 'Period change',
                value: '${change >= 0 ? '+' : '-'}${_peso(change.abs())}',
                color: change >= 0 ? Colors.green.shade700 : colors.error,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InsightCard(
                icon: Icons.arrow_upward_rounded,
                label: 'Highest',
                value: _peso(highest),
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InsightCard(
                icon: Icons.arrow_downward_rounded,
                label: 'Lowest',
                value: _peso(lowest),
                color: colors.secondary,
              ),
            ),
          ],
        );
      },
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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EMPTY STATE
// ============================================================

class _EmptyAccountsState extends StatelessWidget {
  const _EmptyAccountsState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: 40,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'No payment accounts yet',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a transaction and choose a payment account to start tracking your cash.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ERROR STATE
// ============================================================

class _CashflowErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _CashflowErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: colors.error),
            const SizedBox(height: 14),
            Text(
              'Couldn’t load cashflow',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HERO SKELETON
// ============================================================

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 340,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(30),
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

  final _amountController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final balancesAsync = ref.watch(accountBalancesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: balancesAsync.when(
        loading: () => const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Unable to load accounts.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
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

          final fromAccount = _fromId == null
              ? null
              : balances.firstWhere(
                  (b) => b.account.id == _fromId,
                  orElse: () => balances.first,
                );

          final toAccount = _toId == null
              ? null
              : balances.firstWhere(
                  (b) => b.account.id == _toId,
                  orElse: () => balances.first,
                );

          return Column(
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
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Move money between your accounts.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ------------------------------------------
              // FROM
              // ------------------------------------------
              DropdownButtonFormField<String>(
                initialValue: _fromId,
                decoration: InputDecoration(
                  labelText: 'From account',
                  prefixIcon: const Icon(Icons.north_east_rounded),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
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
                onChanged: (value) {
                  setState(() {
                    _fromId = value;

                    if (_toId == value) {
                      _toId = null;
                    }
                  });
                },
              ),

              if (fromAccount != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    'Available: ${_peso(fromAccount.balance)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // ------------------------------------------
              // TO
              // ------------------------------------------
              DropdownButtonFormField<String>(
                initialValue: _toId,
                decoration: InputDecoration(
                  labelText: 'To account',
                  prefixIcon: const Icon(Icons.south_west_rounded),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
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
                onChanged: (value) {
                  setState(() {
                    _toId = value;
                  });
                },
              ),

              if (toAccount != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    'Current balance: ${_peso(toAccount.balance)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // ------------------------------------------
              // AMOUNT
              // ------------------------------------------
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------
              // SUBMIT
              // ------------------------------------------
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
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (_fromId == null || _toId == null || _fromId == _toId) {
      return;
    }

    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );

    if (amount == null || amount <= 0) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = ref.read(databaseProvider);

      final amountCents = (amount * 100).round();

      await db.transaction(() async {
        final entryId = _generateId();

        await db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: entryId,
                businessId: kCurrentBusinessId,
                entryDate: DateTime.now(),
                sourceType: 'transfer',
                description: const Value('Account transfer'),
              ),
            );

        await db
            .into(db.ledgerLines)
            .insert(
              LedgerLinesCompanion.insert(
                id: _generateId(),
                journalEntryId: entryId,
                accountId: _toId!,
                debit: Value(amountCents),
              ),
            );

        await db
            .into(db.ledgerLines)
            .insert(
              LedgerLinesCompanion.insert(
                id: _generateId(),
                journalEntryId: entryId,
                accountId: _fromId!,
                credit: Value(amountCents),
              ),
            );

        await db
            .into(db.accountTransfers)
            .insert(
              AccountTransfersCompanion.insert(
                id: _generateId(),
                businessId: kCurrentBusinessId,
                fromAccountId: _fromId!,
                toAccountId: _toId!,
                amount: amountCents,
                transferDate: DateTime.now(),
              ),
            );
      });

      ref.read(ledgerVersionProvider.notifier).state++;

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Transfer completed'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Transfer failed: $error'),
        ),
      );
    }
  }

  String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toString() +
        Random().nextInt(9999).toString();
  }
}
