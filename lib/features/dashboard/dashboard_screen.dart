import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/categories.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/mascots.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final catMap = ref.watch(categoriesByIdProvider).asData?.value ?? const {};

    return invoicesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: PocketColors.persimmon),
      ),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (all) {
        final monthInvoices = all
            .where((i) =>
                i.invoiceDate.year == month.year &&
                i.invoiceDate.month == month.month)
            .toList();
        final total =
            monthInvoices.fold<int>(0, (sum, i) => sum + i.totalAmount);

        final byCategory = <int?, int>{};
        for (final inv in monthInvoices) {
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
              onPrev: () => ref
                  .read(selectedMonthProvider.notifier)
                  .set(DateTime(month.year, month.month - 1)),
              onNext: () => ref
                  .read(selectedMonthProvider.notifier)
                  .set(DateTime(month.year, month.month + 1)),
            ),
            const SizedBox(height: 20),
            _HeroCard(
              total: total,
              month: month,
              count: monthInvoices.length,
            ),
            const SizedBox(height: 16),
            if (monthInvoices.isEmpty)
              SizedBox(
                height: 240,
                child: EmptyState(
                  title: '這個月還沒有消費',
                  subtitle: 'scan a receipt to get started.',
                  mascot: const ReceiptMascot(size: 72),
                ),
              )
            else
              _CategoryCard(
                sorted: sorted,
                catMap: catMap,
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _MonthNavigator extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthNavigator({
    required this.month,
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
          formatMonth(month),
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

// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final int total;
  final DateTime month;
  final int count;

  const _HeroCard({
    required this.total,
    required this.month,
    required this.count,
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
            formatMonthZh(month),
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
                (total ~/ 100).toString(),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: PocketColors.ink,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const CoinMascot(size: 28),
              const SizedBox(width: 10),
              Text(
                count == 0
                    ? '這個月還沒有消費'
                    : '$count 筆消費',
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

// ---------------------------------------------------------------------------

class _CategoryCard extends StatelessWidget {
  final List<MapEntry<int?, int>> sorted;
  final Map<int, Category> catMap;

  const _CategoryCard({required this.sorted, required this.catMap});

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
            'BY CATEGORY',
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.14,
              color: PocketColors.inkSoft,
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.map((e) {
            final cat = e.key == null ? null : catMap[e.key];
            final style = styleForKey(cat?.key);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _CategoryRow(
                label: cat?.label ?? 'Other',
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
            style: const TextStyle(
              fontSize: 13,
              color: PocketColors.ink,
            ),
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
