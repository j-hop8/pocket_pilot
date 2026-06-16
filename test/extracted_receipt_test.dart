import 'package:flutter_test/flutter_test.dart';
import 'package:pocketpilot/features/scan/extracted_receipt.dart';

void main() {
  test('parses a full receipt JSON', () {
    final r = ExtractedReceipt.fromJson({
      'merchantName': '  星巴克  ',
      'date': '2026-06-01',
      'total': 250,
      'salesAmount': 238,
      'sellerTaxId': '12345678',
      'invoiceNumber': 'ab-12345678',
      'kind': 'expense',
      'currency': 'TWD',
      'items': [
        {'name': '拿鐵', 'quantity': 2, 'unitPrice': 100, 'amount': 200},
        {'name': '蛋糕', 'amount': 50},
      ],
    });

    expect(r.merchantName, '星巴克'); // trimmed
    expect(r.date, DateTime(2026, 6, 1));
    expect(r.totalDollars, 250);
    expect(r.salesDollars, 238);
    expect(r.sellerTaxId, '12345678');
    expect(r.invoiceNumber, 'AB12345678'); // normalised: upper, dash stripped
    expect(r.kind, 'expense');
    expect(r.items, hasLength(2));
    expect(r.items.first.name, '拿鐵');
    expect(r.items.first.quantity, 2);
    expect(r.items.first.unitPriceDollars, 100);
    expect(r.items.first.amountDollars, 200);
    // unitPrice falls back to amount when the model omits it.
    expect(r.items[1].unitPriceDollars, 50);
    expect(r.items[1].quantity, 1);
  });

  test('falls back to today when the date is missing/unparseable', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    expect(ExtractedReceipt.fromJson({'total': 10}).date, today);
    expect(
      ExtractedReceipt.fromJson({'total': 10, 'date': 'not-a-date'}).date,
      today,
    );
  });

  test('empty / missing items yield an empty list (no invented lines)', () {
    expect(ExtractedReceipt.fromJson({'total': 10}).items, isEmpty);
    expect(
      ExtractedReceipt.fromJson({'total': 10, 'items': []}).items,
      isEmpty,
    );
  });

  test('drops a tax id / invoice number that is the wrong shape', () {
    final r = ExtractedReceipt.fromJson({
      'total': 10,
      'sellerTaxId': '1234', // not 8 digits
      'invoiceNumber': '12345678', // missing the two-letter prefix
    });
    expect(r.sellerTaxId, isNull);
    expect(r.invoiceNumber, isNull);
  });

  test('defaults kind to expense for anything but "income"', () {
    expect(ExtractedReceipt.fromJson({'total': 10}).kind, 'expense');
    expect(
      ExtractedReceipt.fromJson({'total': 10, 'kind': 'income'}).kind,
      'income',
    );
  });

  test('coerces string amounts with separators', () {
    final r = ExtractedReceipt.fromJson({'total': '1,250'});
    expect(r.totalDollars, 1250);
  });
}
