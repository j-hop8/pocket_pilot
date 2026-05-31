import 'package:flutter_test/flutter_test.dart';
import 'package:pocketpilot/core/formatters.dart';
import 'package:pocketpilot/models/invoice.dart';

void main() {
  group('formatters', () {
    test('formatTwd converts cents to NT\$ dollars', () {
      expect(formatTwd(35000), 'NT\$350');
      expect(formatTwd(0), 'NT\$0');
      expect(formatTwd(123400), 'NT\$1,234');
    });

    test('dollarsToCents round-trips', () {
      expect(dollarsToCents(350), 35000);
      expect(centsToDollars(35000), 350);
    });
  });

  group('Invoice.fromJson', () {
    test('parses header + nested items, sorted by sort_order', () {
      final inv = Invoice.fromJson({
        'id': 'abc',
        'invoice_number': null,
        'invoice_date': '2026-05-15',
        'merchant_name': '全聯',
        'total_amount': 35000,
        'currency': 'TWD',
        'category_id': 1,
        'source': 'manual',
        'invoice_items': [
          {
            'id': 'i2',
            'name': 'second',
            'amount': 10000,
            'sort_order': 1,
          },
          {
            'id': 'i1',
            'name': 'first',
            'amount': 25000,
            'sort_order': 0,
          },
        ],
      });

      expect(inv.merchantName, '全聯');
      expect(inv.totalAmount, 35000);
      expect(inv.source, 'manual');
      expect(inv.items.length, 2);
      expect(inv.items.first.name, 'first');
      expect(inv.items.last.name, 'second');
    });
  });
}
