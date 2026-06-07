import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/categories.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/mascots.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s             = ref.watch(stringsProvider);
    final month         = ref.watch(selectedMonthProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final catMap        = ref.watch(categoriesByIdProvider).asData?.value ?? const {};

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
            if (monthInvoices.isEmpty)
              SizedBox(
                height: 240,
                child: EmptyState(
                  title: s.noSpendingThisMonth,
                  subtitle: s.scanToStart,
                  mascot: const ReceiptMascot(size: 72),
                ),
              )
            else
              _CategoryCard(
                sorted: sorted,
                catMap: catMap,
                byCategoryLabel: s.byCategory,
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

class _CategoryCard extends StatelessWidget {
  final List<MapEntry<int?, int>> sorted;
  final Map<int, Category> catMap;
  final String byCategoryLabel;
  final AppStrings s;

  const _CategoryCard({
    required this.sorted,
    required this.catMap,
    required this.byCategoryLabel,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = sorted.isEmpty ? 1 : sorted.first.value;

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
          Text(
            byCategoryLabel.toUpperCase(),
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.14,
              color: PocketColors.inkSoft,
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.map((e) {
            final cat = e.key == null ? null : catMap[e.key];
            final style = styleForCategory(cat);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _CategoryRow(
                label: s.catName(cat),
                amount: e.value,
                color: style.color,
                fraction: maxVal > 0 ? e.value / maxVal : 0.0,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;
  final double fraction;

  const _CategoryRow({
    required this.label,
    required this.amount,
    required this.color,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: PocketColors.ink),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: PocketColors.paper2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(
            (amount ~/ 100).toString(),
            textAlign: TextAlign.right,
            style: GoogleFonts.spaceMono(
              fontSize: 11,
              color: PocketColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}
