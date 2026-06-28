import 'package:flutter_test/flutter_test.dart';
import 'package:pocketpilot/core/category_resolver.dart';

void main() {
  group('foldMostRecentCategory', () {
    test('keeps the most recent category per key', () {
      final map = foldMostRecentCategory([
        (key: 'Coffee', categoryId: 1, stamp: '2026-01-01|a'),
        (key: 'coffee', categoryId: 2, stamp: '2026-06-01|a'), // newer, wins
        (key: 'coffee', categoryId: 3, stamp: '2026-03-01|a'),
      ]);
      expect(map['coffee'], 2); // normalized key, latest stamp
    });

    test('same date falls back to created_at in the stamp', () {
      final map = foldMostRecentCategory([
        (key: 'tea', categoryId: 1, stamp: '2026-06-01|2026-06-01T08:00:00Z'),
        (key: 'tea', categoryId: 2, stamp: '2026-06-01|2026-06-01T09:00:00Z'),
      ]);
      expect(map['tea'], 2);
    });

    test('skips null category, null key, and blank key', () {
      final map = foldMostRecentCategory([
        (key: 'book', categoryId: null, stamp: '2026-06-01|a'),
        (key: null, categoryId: 5, stamp: '2026-06-01|a'),
        (key: '   ', categoryId: 6, stamp: '2026-06-01|a'),
        (key: 'book', categoryId: 7, stamp: '2026-05-01|a'),
      ]);
      expect(map['book'], 7);
      expect(map.containsKey(''), isFalse);
      expect(map.length, 1);
    });
  });

  group('resolveItemCategory priority', () {
    const itemHist = {'latte': 10};

    test('item history wins over keyword', () {
      expect(
        resolveItemCategory(
          itemName: 'Latte',
          itemHistory: itemHist,
          keywordFallback: 30,
        ),
        10,
      );
    });

    test('keyword fallback when the item has no history', () {
      expect(
        resolveItemCategory(
          itemName: 'Croissant',
          itemHistory: itemHist,
          keywordFallback: 30,
        ),
        30,
      );
    });

    test('null (uncategorized) when neither history nor keyword matches', () {
      expect(
        resolveItemCategory(
          itemName: 'X',
          itemHistory: const {},
          keywordFallback: null,
        ),
        isNull,
      );
    });
  });

  group('resolveInvoiceCategory priority', () {
    test('merchant history wins over keyword and item mode', () {
      expect(
        resolveInvoiceCategory(
          merchant: 'Starbucks',
          merchantHistory: const {'starbucks': 20},
          keywordFallback: 30,
          itemCategoryIds: const [40, 40],
        ),
        20,
      );
    });

    test('keyword fallback wins over item mode when merchant has no history', () {
      expect(
        resolveInvoiceCategory(
          merchant: 'Unknown',
          merchantHistory: const {'starbucks': 20},
          keywordFallback: 30,
          itemCategoryIds: const [40, 40],
        ),
        30,
      );
    });

    test('item mode fallback when neither merchant history nor keyword matches', () {
      expect(
        resolveInvoiceCategory(
          merchant: 'Unknown',
          merchantHistory: const {},
          keywordFallback: null,
          itemCategoryIds: const [40, 50, 40],
        ),
        40,
      );
    });

    test('null when nothing matches and items are all uncategorized', () {
      expect(
        resolveInvoiceCategory(
          merchant: 'Unknown',
          merchantHistory: const {},
          keywordFallback: null,
          itemCategoryIds: const [null, null],
        ),
        isNull,
      );
    });
  });

  group('modeCategory', () {
    test('returns the most frequent non-null id', () {
      expect(modeCategory(const [1, 2, 2, 3, 2]), 2);
    });

    test('ignores nulls', () {
      expect(modeCategory(const [null, 5, null, 5, 7]), 5);
    });

    test('ties are broken by first appearance', () {
      // 8 and 9 both appear twice; 8 is seen first.
      expect(modeCategory(const [8, 9, 9, 8]), 8);
    });

    test('null for empty or all-null input', () {
      expect(modeCategory(const []), isNull);
      expect(modeCategory(const [null, null]), isNull);
    });
  });
}
