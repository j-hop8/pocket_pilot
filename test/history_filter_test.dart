import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketpilot/features/history/history_filter.dart';
import 'package:pocketpilot/models/invoice.dart';
import 'package:pocketpilot/models/invoice_item.dart';

Invoice _inv({
  required String kind,
  int? categoryId,
  List<int?> itemCategoryIds = const [],
  required DateTime date,
  int total = 10000,
}) {
  return Invoice(
    invoiceDate: date,
    totalAmount: total,
    source: 'manual',
    kind: kind,
    categoryId: categoryId,
    items: [
      for (var i = 0; i < itemCategoryIds.length; i++)
        InvoiceItem(name: 'item$i', amount: 100, categoryId: itemCategoryIds[i]),
    ],
  );
}

void main() {
  final now = DateTime(2026, 6, 7);

  group('HistoryFilter.kind', () {
    final expense = _inv(kind: 'expense', date: now);
    final income = _inv(kind: 'income', date: now);

    test('null matches both', () {
      const f = HistoryFilter();
      expect(f.matches(expense, now), isTrue);
      expect(f.matches(income, now), isTrue);
    });

    test('expense excludes income', () {
      const f = HistoryFilter(kind: 'expense');
      expect(f.matches(expense, now), isTrue);
      expect(f.matches(income, now), isFalse);
    });
  });

  group('HistoryFilter.category two modes', () {
    // Header category 1, but contains a line item categorized as 2.
    final inv = _inv(
        kind: 'expense', categoryId: 1, itemCategoryIds: [1, 2], date: now);

    test('by invoice matches on header category only', () {
      const byInv = HistoryFilter(categoryMatch: CategoryMatch.invoice);
      expect(byInv.copyWithCats({1}).matches(inv, now), isTrue);
      expect(byInv.copyWithCats({2}).matches(inv, now), isFalse);
    });

    test('by item matches when any line item category is selected', () {
      const byItem = HistoryFilter(categoryMatch: CategoryMatch.item);
      expect(byItem.copyWithCats({2}).matches(inv, now), isTrue);
      expect(byItem.copyWithCats({3}).matches(inv, now), isFalse);
    });
  });

  group('HistoryFilter.uncategorized', () {
    final uncatInv = _inv(kind: 'expense', categoryId: null, date: now);
    final catInv = _inv(kind: 'expense', categoryId: 1, date: now);

    test('a plain category filter excludes uncategorized records', () {
      const f = HistoryFilter(categoryIds: {1});
      expect(f.matches(catInv, now), isTrue);
      expect(f.matches(uncatInv, now), isFalse);
    });

    test('uncategorized flag matches null-category records', () {
      const f = HistoryFilter(uncategorized: true);
      expect(f.hasCategoryFilter, isTrue);
      expect(f.matches(uncatInv, now), isTrue);
      expect(f.matches(catInv, now), isFalse);
    });

    test('combines with picked categories as OR', () {
      const f = HistoryFilter(categoryIds: {1}, uncategorized: true);
      expect(f.matches(uncatInv, now), isTrue);
      expect(f.matches(catInv, now), isTrue);
    });

    test('by item mode matches items with no category', () {
      final inv = _inv(
          kind: 'expense', categoryId: 1, itemCategoryIds: [1, null], date: now);
      const byItem =
          HistoryFilter(uncategorized: true, categoryMatch: CategoryMatch.item);
      expect(byItem.matches(inv, now), isTrue);
    });
  });

  group('HistoryFilter.time', () {
    test('thisMonth excludes prior month', () {
      const f = HistoryFilter(timePreset: TimePreset.thisMonth);
      expect(f.matches(_inv(kind: 'expense', date: DateTime(2026, 6, 1)), now),
          isTrue);
      expect(f.matches(_inv(kind: 'expense', date: DateTime(2026, 5, 31)), now),
          isFalse);
    });

    test('custom range is inclusive on both ends', () {
      final f = HistoryFilter(
        timePreset: TimePreset.custom,
        customRange:
            DateTimeRange(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      );
      expect(f.matches(_inv(kind: 'expense', date: DateTime(2026, 6, 1)), now),
          isTrue);
      expect(f.matches(_inv(kind: 'expense', date: DateTime(2026, 6, 5)), now),
          isTrue);
      expect(f.matches(_inv(kind: 'expense', date: DateTime(2026, 6, 6)), now),
          isFalse);
    });
  });
}

extension on HistoryFilter {
  HistoryFilter copyWithCats(Set<int> ids) => copyWith(categoryIds: ids);
}
