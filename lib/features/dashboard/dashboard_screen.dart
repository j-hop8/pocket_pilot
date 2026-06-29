import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/categories.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../widgets/mascots.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s             = ref.watch(stringsProvider);
    final month         = ref.watch(selectedMonthProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final catMap        = ref.watch(categoriesByIdProvider).asData?.value ?? const {};
    final budgets       = ref.watch(budgetsByCategoryProvider).asData?.value ?? const {};

    return invoicesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: PocketColors.persimmon),
      ),
      error: (e, _) => Center(child: Text(s.failedToLoadError(e))),
      data: (all) {
        final monthInvoices = all
            .where((i) =>
                i.invoiceDate.year == month.year &&
                i.invoiceDate.month == month.month)
            .toList();
        final expenseInvoices =
            monthInvoices.where((i) => !i.isIncome).toList();
        final expenseTotal =
            expenseInvoices.fold<int>(0, (sum, i) => sum + i.totalAmount);
        final incomeTotal = monthInvoices
            .where((i) => i.isIncome)
            .fold<int>(0, (sum, i) => sum + i.totalAmount);
        final net = incomeTotal - expenseTotal;

        // Category breakdown is spending-only; income has its own categories.
        final byCategory = <int?, int>{};
        for (final inv in expenseInvoices) {
          byCategory.update(
            inv.categoryId,
            (v) => v + inv.totalAmount,
            ifAbsent: () => inv.totalAmount,
          );
        }
        final sorted = byCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
          children: [
            _MonthNavigator(
              month: month,
              s: s,
              onPrev: () => ref
                  .read(selectedMonthProvider.notifier)
                  .set(DateTime(month.year, month.month - 1)),
              onNext: () => ref
                  .read(selectedMonthProvider.notifier)
                  .set(DateTime(month.year, month.month + 1)),
            ),
            const SizedBox(height: 20),
            _HeroCard(
              expenseTotal: expenseTotal,
              incomeTotal: incomeTotal,
              net: net,
              month: month,
              count: monthInvoices.length,
              s: s,
            ),
            const SizedBox(height: 16),
            _BudgetCategoryCard(
              budgets: budgets,
              sorted: sorted,
              expenseTotal: expenseTotal,
              catMap: catMap,
              s: s,
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MonthNavigator extends StatelessWidget {
  final DateTime month;
  final AppStrings s;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthNavigator({
    required this.month,
    required this.s,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _NavButton(icon: Icons.chevron_left, onTap: onPrev),
        const SizedBox(width: 12),
        Text(
          s.formatMonthNav(month),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PocketColors.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 12),
        _NavButton(icon: Icons.chevron_right, onTap: onNext),
        const Spacer(),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: PocketColors.paper2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: PocketColors.inkSoft),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final int expenseTotal;
  final int incomeTotal;
  final int net;
  final DateTime month;
  final int count;
  final AppStrings s;

  const _HeroCard({
    required this.expenseTotal,
    required this.incomeTotal,
    required this.net,
    required this.month,
    required this.count,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: PocketColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.formatMonthHero(month),
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.1,
              color: PocketColors.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'NT\$',
                style: GoogleFonts.spaceMono(
                  fontSize: 13,
                  color: PocketColors.inkSoft,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                (expenseTotal ~/ 100).toString(),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: PocketColors.ink,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(
                label: s.incomeThisMonth,
                value: incomeTotal,
                signed: false,
                color: PocketColors.pine,
              ),
              const SizedBox(width: 28),
              _MiniStat(
                label: s.netLabel,
                value: net,
                signed: true,
                color: net >= 0 ? PocketColors.pine : PocketColors.ink,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const CoinMascot(size: 28),
              const SizedBox(width: 10),
              Text(
                count == 0 ? s.noSpendingThisMonth : s.spendingCount(count),
                style: const TextStyle(
                  fontSize: 13,
                  color: PocketColors.inkSoft,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small labelled figure (Income / Net) shown under the hero's big expense
/// number. [signed] prefixes the value with +/− (used for net, which can go
/// negative); income is always shown as a positive inflow.
class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final bool signed;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.signed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final magnitude = value.abs() ~/ 100;
    final prefix = signed ? (value >= 0 ? '+' : '−') : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceMono(
            fontSize: 9,
            letterSpacing: 0.1,
            color: PocketColors.inkSoft,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'NT\$$prefix$magnitude',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Progress of spending against a budget limit. [fraction] is clamped to 0..1
/// for the bar; [over] is true when spending has exceeded the limit. Pure and
/// side-effect-free so it can be unit-tested directly.
({double fraction, bool over}) budgetProgress(int spent, int limit) {
  if (limit <= 0) return (fraction: 0, over: false);
  return (fraction: (spent / limit).clamp(0.0, 1.0), over: spent > limit);
}

/// This month's spending and budgets in one card. The overall cap (if set) sits
/// on top, then budgeted expense categories (most-strained first) showing
/// spent/limit progress, then the remaining spending categories as plain bars
/// sized against the top spender. The pencil opens budget management; with no
/// budgets and no spending, a slim prompt links there too.
class _BudgetCategoryCard extends StatelessWidget {
  final Map<int?, Budget> budgets;
  final List<MapEntry<int?, int>> sorted; // categories by spend, desc
  final int expenseTotal;
  final Map<int, Category> catMap;
  final AppStrings s;

  const _BudgetCategoryCard({
    required this.budgets,
    required this.sorted,
    required this.expenseTotal,
    required this.catMap,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final overall = budgets[null];
    final spentById = {for (final e in sorted) e.key: e.value};
    final maxSpend = sorted.isEmpty ? 0 : sorted.first.value;

    // Budgeted expense categories, most-strained (closest to / over budget) first.
    final budgetedCats = budgets.entries
        .where((e) => e.key != null)
        .map((e) => e.value)
        .toList()
      ..sort((a, b) {
        final fa = a.amount == 0 ? 0.0 : (spentById[a.categoryId] ?? 0) / a.amount;
        final fb = b.amount == 0 ? 0.0 : (spentById[b.categoryId] ?? 0) / b.amount;
        return fb.compareTo(fa);
      });
    // Spending categories without a budget, already in spend-desc order.
    final nonBudgeted =
        sorted.where((e) => !budgets.containsKey(e.key)).toList();

    final hasAnyBudget = overall != null || budgetedCats.isNotEmpty;
    final hasSpending = sorted.isNotEmpty;

    // Per-category rows: budgeted ones (spent/limit) first, then plain spend bars.
    final catRows = <Widget>[
      for (final b in budgetedCats)
        _CategoryRow(
          label: s.catName(catMap[b.categoryId]),
          color: styleForCategory(catMap[b.categoryId]).color,
          spent: spentById[b.categoryId] ?? 0,
          limit: b.amount,
          maxSpend: maxSpend,
          s: s,
        ),
      for (final e in nonBudgeted)
        _CategoryRow(
          label: s.catName(e.key == null ? null : catMap[e.key]),
          color: styleForCategory(e.key == null ? null : catMap[e.key]).color,
          spent: e.value,
          limit: null,
          maxSpend: maxSpend,
          s: s,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: PocketColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                s.budgetSectionLabel.toUpperCase(),
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  letterSpacing: 0.14,
                  color: PocketColors.inkSoft,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push('/budgets'),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_outlined,
                      size: 18, color: PocketColors.inkSoft),
                ),
              ),
            ],
          ),
          if (!hasAnyBudget && !hasSpending)
            _SetBudgetPrompt(s: s)
          else ...[
            const SizedBox(height: 16),
            if (overall != null)
              _CategoryRow(
                label: s.overallBudgetLabel,
                color: PocketColors.ink,
                spent: expenseTotal,
                limit: overall.amount,
                maxSpend: maxSpend,
                s: s,
              ),
            // A line separating the overall (total) budget from the categories.
            if (overall != null && catRows.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child:
                    Divider(height: 1, thickness: 1, color: PocketColors.line),
              ),
            for (int i = 0; i < catRows.length; i++) ...[
              if (i != 0) const SizedBox(height: 14),
              catRows[i],
            ],
          ],
        ],
      ),
    );
  }
}

class _SetBudgetPrompt extends StatelessWidget {
  final AppStrings s;
  const _SetBudgetPrompt({required this.s});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/budgets'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const CoinMascot(size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.setABudgetCta,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PocketColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: PocketColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// One category line. With a [limit] it's a budget row: spent/limit text, a
/// progress bar that turns persimmon when over, and a remaining / over-by
/// footnote. With [limit] null it's a plain spend row: just the amount and a bar
/// sized as a fraction of [maxSpend] (the top-spending category).
class _CategoryRow extends StatelessWidget {
  final String label;
  final Color color;
  final int spent;
  final int? limit;
  final int maxSpend;
  final AppStrings s;

  const _CategoryRow({
    required this.label,
    required this.color,
    required this.spent,
    required this.limit,
    required this.maxSpend,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final lim = limit;
    final double fraction;
    final String trailing;
    String? footnote;
    Color footnoteColor = PocketColors.inkSoft;

    if (lim != null) {
      final p = budgetProgress(spent, lim);
      fraction = p.fraction;
      trailing = s.spentOfText(spent, lim);
      final remaining = lim - spent;
      // Percent of budget used — lets the user forecast before exceeding (e.g.
      // 85%) and see by how much they're over (>100%) once they do.
      final pct = lim > 0 ? (spent / lim * 100).round() : 0;
      final status =
          p.over ? s.overByText(-remaining) : s.remainingText(remaining);
      footnote = '$pct% · $status';
      // Keep the bar in the category colour even when over (a persimmon bar
      // reads as another category); the "over by" footnote signals the overage.
      footnoteColor = p.over ? PocketColors.persimmon : PocketColors.inkSoft;
    } else {
      fraction = maxSpend > 0 ? (spent / maxSpend).clamp(0.0, 1.0) : 0.0;
      trailing = (spent ~/ 100).toString();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: PocketColors.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              trailing,
              style: GoogleFonts.spaceMono(
                fontSize: 11,
                color: PocketColors.inkSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: PocketColors.paper2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
        if (footnote != null) ...[
          const SizedBox(height: 4),
          Text(
            footnote,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: footnoteColor,
            ),
          ),
        ],
      ],
    );
  }
}
