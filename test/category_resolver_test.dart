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
    const merchantHist = {'starbucks': 20};

    test('item history wins over merchant and keyword', () {
      expect(
        resolveItemCategory(
          itemName: 'Latte',
          merchant: 'Starbucks',
          itemHistory: itemHist,
          merchantHistory: merchantHist,
          keywordFallback: 30,
        ),
        10,
      );
    });

    test('merchant history wins when item has no history', () {
      expect(
        resolveItemCategory(
          itemName: 'Croissant',
          merchant: 'Starbucks',
          itemHistory: itemHist,
          merchantHistory: merchantHist,
          keywordFallback: 30,
        ),
        20,
      );
    });

    test('keyword fallback when neither item nor merchant has history', () {
      expect(
        resolveItemCategory(
          itemName: 'Croissant',
          merchant: 'Unknown Cafe',
          itemHistory: itemHist,
          merchantHistory: merchantHist,
          keywordFallback: 30,
        ),
        30,
      );
    });

    test('falls through to keyword (e.g. other) when fallback is null', () {
      expect(
        resolveItemCategory(
          itemName: 'X',
          merchant: null,
          itemHistory: const {},
          merchantHistory: const {},
          keywordFallback: null,
        ),
        isNull,
      );
    });
  });

  group('resolveInvoiceCategory priority', () {
    test('merchant history wins over keyword', () {
      expect(
        resolveInvoiceCategory(
          merchant: 'Starbucks',
          merchantHistory: const {'starbucks': 20},
          keywordFallback: 30,
        ),
        20,
      );
    });

    test('keyword fallback when merchant has no history', () {
      expect(
        resolveInvoiceCategory(
          merchant: 'Unknown',
          merchantHistory: const {'starbucks': 20},
          keywordFallback: 30,
        ),
        30,
      );
    });
  });
}
