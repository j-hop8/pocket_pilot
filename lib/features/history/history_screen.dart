import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/categories.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/invoice.dart';
import '../../models/invoice_item.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/mascots.dart';
import 'history_filter.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s             = ref.watch(stringsProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final filter        = ref.watch(historyFilterProvider);
    final catMap        = ref.watch(categoriesByIdProvider).asData?.value ?? const {};

    return invoicesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: PocketColors.persimmon),
      ),
      error: (e, _) => Center(child: Text(s.failedToLoadError(e))),
      data: (invoices) {
        // No data at all → onboarding empty state (no filter bar).
        if (invoices.isEmpty) {
          return EmptyState(
            title: s.noHistory,
            subtitle: s.scanToStart,
            mascot: const ReceiptMascot(size: 72),
          );
        }

        final now = DateTime.now();
        final filtered =
            invoices.where((i) => filter.matches(i, now)).toList();
        final byItem = filter.categoryMatch == CategoryMatch.item;

        // In By-item mode the list is a flat stream of line items; the summary
        // counts items and sums their amounts. In By-invoice mode it's the
        // invoices themselves.
        final entries =
            byItem ? _itemEntries(filtered, filter) : const <_ItemEntry>[];
        final count = byItem ? entries.length : filtered.length;
        final total = byItem
            ? entries.fold<int>(0, (sum, e) => sum + e.item.amount)
            : filtered.fold<int>(0, (sum, i) => sum + i.totalAmount);
        final isEmpty = byItem ? entries.isEmpty : filtered.isEmpty;

        return Column(
          children: [
            _ViewModeToggle(filter: filter, s: s),
            _FilterBar(filter: filter, catMap: catMap, s: s),
            _SummaryRow(count: count, total: total, s: s),
            Expanded(
              child: isEmpty
                  ? Center(
                      child: Text(
                        s.noMatches,
                        style: GoogleFonts.spaceMono(
                          fontSize: 13,
                          color: PocketColors.inkSoft,
                        ),
                      ),
                    )
                  : byItem
                      ? _buildItemList(context, entries, catMap, s)
                      : _buildInvoiceList(context, ref, filtered, catMap, s),
            ),
          ],
        );
      },
    );
  }

  /// Flattens the matching invoices into individual line items, keeping each
  /// item's parent invoice for display (sign, merchant) and navigation. An
  /// active category filter narrows to items in the selected categories.
  List<_ItemEntry> _itemEntries(List<Invoice> invoices, HistoryFilter filter) {
    final cats = filter.categoryIds;
    final out = <_ItemEntry>[];
    for (final inv in invoices) {
      for (final item in inv.items) {
        if (cats.isNotEmpty &&
            !(item.categoryId != null && cats.contains(item.categoryId))) {
          continue;
        }
        out.add((inv: inv, item: item));
      }
    }
    return out;
  }

  Widget _buildInvoiceList(BuildContext context, WidgetRef ref,
      List<Invoice> invoices, Map<int, Category> catMap, AppStrings s) {
    final groups = <String, List<Invoice>>{};
    for (final inv in invoices) {
      final key = formatDate(inv.invoiceDate);
      (groups[key] ??= []).add(inv);
    }
    final dateKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final items = <_Item>[];
    for (final key in dateKeys) {
      final dayInvoices = groups[key]!;
      // Net for the day: income adds, expense subtracts.
      final dayNet = dayInvoices.fold<int>(
          0, (sum, i) => sum + (i.isIncome ? i.totalAmount : -i.totalAmount));
      items.add(_Header(date: key, net: dayNet));
      for (final inv in dayInvoices) {
        items.add(_InvoiceRow(invoice: inv, catMap: catMap));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        return switch (item) {
          _Header h => _DateHeader(header: h),
          _InvoiceRow r => _TransactionTile(
              invoice:  r.invoice,
              catMap:   r.catMap,
              s:        s,
              onTap:    () => context.push('/invoice/${r.invoice.id}'),
              // Long-press delete only for user-originated invoices; official
              // (synced) ones can't be deleted — see InvoiceDetailScreen.
              onDelete: r.invoice.canDelete
                  ? () => _confirmDelete(context, ref, r.invoice.id!, s)
                  : null,
            ),
          _ItemRow _ => const SizedBox.shrink(), // not used in invoice mode
        };
      },
    );
  }

  /// By-item layout: line items grouped by their invoice's date, with no
  /// per-invoice wrapper. Tapping an item opens its parent invoice's detail
  /// page — the same destination as tapping the invoice in By-invoice mode.
  Widget _buildItemList(BuildContext context, List<_ItemEntry> entries,
      Map<int, Category> catMap, AppStrings s) {
    final groups = <String, List<_ItemEntry>>{};
    for (final e in entries) {
      (groups[formatDate(e.inv.invoiceDate)] ??= []).add(e);
    }
    final dateKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final items = <_Item>[];
    for (final key in dateKeys) {
      final dayEntries = groups[key]!;
      final dayNet = dayEntries.fold<int>(
          0,
          (sum, e) =>
              sum + (e.inv.isIncome ? e.item.amount : -e.item.amount));
      items.add(_Header(date: key, net: dayNet));
      for (final e in dayEntries) {
        items.add(_ItemRow(entry: e, catMap: catMap));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        return switch (item) {
          _Header h => _DateHeader(header: h),
          _ItemRow r => _LineItemTile(
              entry:  r.entry,
              catMap: r.catMap,
              s:      s,
              onTap:  () => context.push('/invoice/${r.entry.inv.id}'),
            ),
          _InvoiceRow _ => const SizedBox.shrink(), // not used in item mode
        };
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String id, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTitle),
        content: Text(s.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(invoiceRepositoryProvider).delete(id);
      ref.invalidate(invoiceListProvider);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter bar + summary
// ─────────────────────────────────────────────────────────────────────────────

/// Top-level switch between the By-invoice and By-item layouts. Also drives how
/// the category filter is matched (header vs. line-item category). Rendered as a
/// compact two-segment control so the binary choice reads as one unit, distinct
/// from the filter pills below.
class _ViewModeToggle extends ConsumerWidget {
  final HistoryFilter filter;
  final AppStrings s;

  const _ViewModeToggle({required this.filter, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historyFilterProvider.notifier);
    final byItem = filter.categoryMatch == CategoryMatch.item;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: PocketColors.paper2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PocketColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              label: s.matchByInvoice,
              active: !byItem,
              onTap: () => notifier.setCategoryMatch(CategoryMatch.invoice),
            ),
            _Segment(
              label: s.matchByItem,
              active: byItem,
              onTap: () => notifier.setCategoryMatch(CategoryMatch.item),
            ),
          ],
        ),
      ),
    );
  }
}

/// One half of [_ViewModeToggle]. The active segment fills with ink; the
/// inactive one is transparent, letting the container's track show through.
class _Segment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Segment(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: active ? PocketColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? PocketColors.paper : PocketColors.inkSoft,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final HistoryFilter filter;
  final Map<int, Category> catMap;
  final AppStrings s;

  const _FilterBar({required this.filter, required this.catMap, required this.s});

  String get _kindLabel => switch (filter.kind) {
        'expense' => s.expenseLabel,
        'income' => s.incomeLabel,
        _ => s.filterAllKinds,
      };

  String _categoryLabel() {
    final ids = filter.categoryIds;
    if (ids.isEmpty) return s.filterCategoryLabel;
    if (ids.length == 1) return s.catName(catMap[ids.first]);
    return s.categoryCount(ids.length);
  }

  String _timeLabel() => switch (filter.timePreset) {
        TimePreset.all => s.filterTimeLabel,
        TimePreset.thisMonth => s.timeThisMonth,
        TimePreset.last30Days => s.timeLast30,
        TimePreset.thisYear => s.timeThisYear,
        TimePreset.custom => filter.customRange == null
            ? s.timeCustom
            : '${formatDate(filter.customRange!.start)} – '
                '${formatDate(filter.customRange!.end)}',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          _FilterChip(
            label: _kindLabel,
            active: filter.kind != null,
            onTap: () => _showSheet(context, const _KindSheet()),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            label: _categoryLabel(),
            active: filter.categoryIds.isNotEmpty,
            onTap: () => _showSheet(context, const _CategorySheet()),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            label: _timeLabel(),
            active: filter.timePreset != TimePreset.all,
            onTap: () => _showSheet(context, const _TimeSheet()),
          ),
          if (filter.isActive) ...[
            const SizedBox(width: 10),
            _ClearChip(
              label: s.clearFilters,
              onTap: () => ref.read(historyFilterProvider.notifier).clear(),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _showSheet(BuildContext context, Widget sheet) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PocketColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => sheet,
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int count;
  final int total;
  final AppStrings s;

  const _SummaryRow(
      {required this.count, required this.total, required this.s});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: Row(
        children: [
          Text(
            s.resultsCount(count),
            style: GoogleFonts.spaceMono(
              fontSize: 11,
              color: PocketColors.inkSoft,
            ),
          ),
          const Spacer(),
          Text(
            formatTwd(total),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: PocketColors.ink,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill that triggers a filter sheet. With [showCaret] it shows a dropdown
/// affordance; without it, it's a plain selectable toggle. Mirrors the category
/// screen's _KindChip.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(16, 9, 10, 9),
        decoration: BoxDecoration(
          color: active ? PocketColors.ink : PocketColors.paper2,
          borderRadius: BorderRadius.circular(999),
          border: active ? null : Border.all(color: PocketColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? PocketColors.paper : PocketColors.inkSoft,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 16,
              color: active ? PocketColors.paper : PocketColors.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ClearChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 16, 9),
        decoration: BoxDecoration(
          color: PocketColors.paper2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PocketColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close, size: 15, color: PocketColors.inkSoft),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PocketColors.inkSoft,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter sheets
// ─────────────────────────────────────────────────────────────────────────────

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: PocketColors.ink,
      ),
    );
  }
}

/// A tappable option row with a trailing check when [selected].
class _SheetOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SheetOption(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: PocketColors.ink,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 20, color: PocketColors.persimmon),
          ],
        ),
      ),
    );
  }
}

class _KindSheet extends ConsumerWidget {
  const _KindSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final kind = ref.watch(historyFilterProvider).kind;
    final notifier = ref.read(historyFilterProvider.notifier);

    void pick(String? k) {
      notifier.setKind(k);
      Navigator.pop(context);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle(s.filterKindTitle),
          const SizedBox(height: 8),
          _SheetOption(
            label: s.filterAllKinds,
            selected: kind == null,
            onTap: () => pick(null),
          ),
          _SheetOption(
            label: s.expenseLabel,
            selected: kind == 'expense',
            onTap: () => pick('expense'),
          ),
          _SheetOption(
            label: s.incomeLabel,
            selected: kind == 'income',
            onTap: () => pick('income'),
          ),
        ],
      ),
    );
  }
}

class _CategorySheet extends ConsumerWidget {
  const _CategorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final filter = ref.watch(historyFilterProvider);
    final notifier = ref.read(historyFilterProvider.notifier);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SheetTitle(s.filterCategoryLabel),
                const Spacer(),
                if (filter.categoryIds.isNotEmpty)
                  TextButton(
                    onPressed: () => notifier.setCategories({}),
                    child: Text(s.clearFilters),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            categoriesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(s.failedToLoadError(e)),
              data: (cats) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in cats)
                    _SelectableCategoryChip(
                      category: c,
                      label: s.catName(c),
                      selected: filter.categoryIds.contains(c.id),
                      onTap: () => notifier.toggleCategory(c.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableCategoryChip extends StatelessWidget {
  final Category category;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableCategoryChip({
    required this.category,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleForCategory(category);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? style.color : style.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check : style.icon,
              size: 15,
              color: selected ? Colors.white : style.color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : style.color,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSheet extends ConsumerWidget {
  const _TimeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final filter = ref.watch(historyFilterProvider);
    final notifier = ref.read(historyFilterProvider.notifier);

    void pickPreset(TimePreset p) {
      notifier.setTimePreset(p);
      Navigator.pop(context);
    }

    Future<void> pickCustom() async {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDateRange: filter.customRange,
      );
      if (range != null) notifier.setCustomRange(range);
      if (context.mounted) Navigator.pop(context);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle(s.filterTimeLabel),
          const SizedBox(height: 8),
          _SheetOption(
            label: s.timeAll,
            selected: filter.timePreset == TimePreset.all,
            onTap: () => pickPreset(TimePreset.all),
          ),
          _SheetOption(
            label: s.timeThisMonth,
            selected: filter.timePreset == TimePreset.thisMonth,
            onTap: () => pickPreset(TimePreset.thisMonth),
          ),
          _SheetOption(
            label: s.timeLast30,
            selected: filter.timePreset == TimePreset.last30Days,
            onTap: () => pickPreset(TimePreset.last30Days),
          ),
          _SheetOption(
            label: s.timeThisYear,
            selected: filter.timePreset == TimePreset.thisYear,
            onTap: () => pickPreset(TimePreset.thisYear),
          ),
          _SheetOption(
            label: filter.timePreset == TimePreset.custom &&
                    filter.customRange != null
                ? '${formatDate(filter.customRange!.start)} – '
                    '${formatDate(filter.customRange!.end)}'
                : s.timeCustom,
            selected: filter.timePreset == TimePreset.custom,
            onTap: pickCustom,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// A line item paired with the invoice it belongs to — the unit of the
/// By-item view.
typedef _ItemEntry = ({Invoice inv, InvoiceItem item});

sealed class _Item {}

class _Header extends _Item {
  final String date;
  final int net; // signed: positive = net income, negative = net spending
  _Header({required this.date, required this.net});
}

class _InvoiceRow extends _Item {
  final Invoice invoice;
  final Map<int, Category> catMap;
  _InvoiceRow({required this.invoice, required this.catMap});
}

class _ItemRow extends _Item {
  final _ItemEntry entry;
  final Map<int, Category> catMap;
  _ItemRow({required this.entry, required this.catMap});
}

// ─────────────────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final _Header header;
  const _DateHeader({required this.header});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(
        children: [
          Text(
            header.date,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.1,
              color: PocketColors.inkSoft,
            ),
          ),
          const Spacer(),
          Text(
            '${header.net >= 0 ? '+' : '−'}${header.net.abs() ~/ 100}',
            style: GoogleFonts.spaceMono(
              fontSize: 11,
              color: PocketColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Invoice invoice;
  final Map<int, Category> catMap;
  final AppStrings s;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _TransactionTile({
    required this.invoice,
    required this.catMap,
    required this.s,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cat      = invoice.categoryId == null ? null : catMap[invoice.categoryId];
    final style    = styleForCategory(cat);
    final merchant = invoice.merchantName?.isNotEmpty == true
        ? invoice.merchantName!
        : s.unknownMerchant;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PocketColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: PocketColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.catName(cat),
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      color: PocketColors.inkSoft,
                      letterSpacing: 0.04,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${invoice.isIncome ? '+' : '−'}${invoice.totalAmount ~/ 100}',
              style: GoogleFonts.spaceMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: invoice.isIncome ? PocketColors.pine : PocketColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single line item in the By-item view. The item name leads; the parent
/// merchant is the subtitle so the source invoice is clear. Tapping opens the
/// parent invoice's detail page.
class _LineItemTile extends StatelessWidget {
  final _ItemEntry entry;
  final Map<int, Category> catMap;
  final AppStrings s;
  final VoidCallback onTap;

  const _LineItemTile({
    required this.entry,
    required this.catMap,
    required this.s,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inv  = entry.inv;
    final item = entry.item;
    // Fall back to the invoice's category when the item itself is uncategorized.
    final catId = item.categoryId ?? inv.categoryId;
    final cat   = catId == null ? null : catMap[catId];
    final style = styleForCategory(cat);
    final merchant = inv.merchantName?.isNotEmpty == true
        ? inv.merchantName!
        : s.unknownMerchant;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PocketColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: PocketColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    merchant,
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      color: PocketColors.inkSoft,
                      letterSpacing: 0.04,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${inv.isIncome ? '+' : '−'}${item.amount ~/ 100}',
              style: GoogleFonts.spaceMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: inv.isIncome ? PocketColors.pine : PocketColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
