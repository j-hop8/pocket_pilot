import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categories.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../models/category.dart';
import '../../widgets/empty_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final catMap = ref.watch(categoriesByIdProvider).asData?.value ?? const {};

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MonthHeader(
              month: month,
              onPrev: () => ref
                  .read(selectedMonthProvider.notifier)
                  .set(DateTime(month.year, month.month - 1)),
              onNext: () => ref
                  .read(selectedMonthProvider.notifier)
                  .set(DateTime(month.year, month.month + 1)),
            ),
            const SizedBox(height: 16),
            _TotalCard(total: total),
            const SizedBox(height: 16),
            if (monthInvoices.isEmpty)
              const SizedBox(
                height: 280,
                child: EmptyState(
                  icon: Icons.savings_outlined,
                  title: 'No spending this month',
                  subtitle: 'Tap Add to record an invoice.',
                ),
              )
            else
              _BreakdownCard(byCategory: byCategory, catMap: catMap),
          ],
        );
      },
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Text(
          formatMonth(month),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final int total;
  const _TotalCard({required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total spend',
              style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 8),
            Text(
              formatTwd(total),
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final Map<int?, int> byCategory;
  final Map<int, Category> catMap;

  const _BreakdownCard({required this.byCategory, required this.catMap});

  @override
  Widget build(BuildContext context) {
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = entries.map((e) {
      final cat = e.key == null ? null : catMap[e.key];
      final style = styleForKey(cat?.key);
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: style.color,
        title: '',
        radius: 48,
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'By category',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...entries.map((e) {
              final cat = e.key == null ? null : catMap[e.key];
              final style = styleForKey(cat?.key);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: style.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(cat?.label ?? 'Uncategorized')),
                    Text(
                      formatTwd(e.value),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
