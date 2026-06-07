import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/invoice.dart';

/// Quick time windows offered by the History time filter, plus a [custom]
/// sentinel that defers to [HistoryFilter.customRange].
enum TimePreset { all, thisMonth, last30Days, thisYear, custom }

/// Whether the category filter matches an invoice's own (header) category or
/// the categories of its line items — the two can diverge.
enum CategoryMatch { invoice, item }

/// Immutable snapshot of the History tab's active filters. An empty/`all`
/// filter matches everything.
class HistoryFilter {
  final String? kind; // null = all, else 'expense' | 'income'
  final Set<int> categoryIds; // empty = all categories
  final CategoryMatch categoryMatch; // how categoryIds are matched
  final TimePreset timePreset;
  final DateTimeRange? customRange; // set only when timePreset == custom

  const HistoryFilter({
    this.kind,
    this.categoryIds = const {},
    this.categoryMatch = CategoryMatch.invoice,
    this.timePreset = TimePreset.all,
    this.customRange,
  });

  bool get isActive =>
      kind != null || categoryIds.isNotEmpty || timePreset != TimePreset.all;

  HistoryFilter copyWith({
    String? kind,
    bool clearKind = false,
    Set<int>? categoryIds,
    CategoryMatch? categoryMatch,
    TimePreset? timePreset,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
  }) {
    return HistoryFilter(
      kind: clearKind ? null : (kind ?? this.kind),
      categoryIds: categoryIds ?? this.categoryIds,
      categoryMatch: categoryMatch ?? this.categoryMatch,
      timePreset: timePreset ?? this.timePreset,
      customRange: clearCustomRange ? null : (customRange ?? this.customRange),
    );
  }

  /// Resolves the active date window (or null = unbounded) relative to [now].
  DateTimeRange? resolveRange(DateTime now) => switch (timePreset) {
        TimePreset.all => null,
        TimePreset.thisMonth =>
          DateTimeRange(start: DateTime(now.year, now.month), end: now),
        TimePreset.last30Days =>
          DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
        TimePreset.thisYear => DateTimeRange(start: DateTime(now.year), end: now),
        TimePreset.custom => customRange,
      };

  /// Whether [inv] satisfies every active filter dimension.
  bool matches(Invoice inv, DateTime now) {
    if (kind != null && inv.kind != kind) return false;
    if (categoryIds.isNotEmpty) {
      final ok = switch (categoryMatch) {
        CategoryMatch.invoice =>
          inv.categoryId != null && categoryIds.contains(inv.categoryId),
        CategoryMatch.item => inv.items.any(
            (it) => it.categoryId != null && categoryIds.contains(it.categoryId)),
      };
      if (!ok) return false;
    }
    final range = resolveRange(now);
    if (range != null) {
      final d = inv.invoiceDate; // inclusive, date-only
      if (d.isBefore(DateUtils.dateOnly(range.start))) return false;
      if (d.isAfter(DateUtils.dateOnly(range.end))) return false;
    }
    return true;
  }
}

class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void setKind(String? k) =>
      state = k == null ? state.copyWith(clearKind: true) : state.copyWith(kind: k);

  void toggleCategory(int id) {
    final next = {...state.categoryIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(categoryIds: next);
  }

  void setCategories(Set<int> ids) => state = state.copyWith(categoryIds: ids);

  void setCategoryMatch(CategoryMatch m) =>
      state = state.copyWith(categoryMatch: m);

  void setTimePreset(TimePreset p) => state = p == TimePreset.custom
      ? state.copyWith(timePreset: p)
      : state.copyWith(timePreset: p, clearCustomRange: true);

  void setCustomRange(DateTimeRange r) =>
      state = state.copyWith(timePreset: TimePreset.custom, customRange: r);

  void clear() => state = const HistoryFilter();
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilter>(
        HistoryFilterNotifier.new);
