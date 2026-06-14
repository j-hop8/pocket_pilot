import 'package:flutter_test/flutter_test.dart';
import 'package:pp_core/pp_core.dart';

// Builds a 77-char left-QR header from its fixed-width fields.
String _header({
  String number = 'BM18825967',
  String rocDate = '1150523',
  String random = '2683',
  String salesHex = '00000030', // 48
  String totalHex = '00000032', // 50
  String buyer = '00000000',
  String seller = '87589505',
  String aes = 'aBcDeFgHiJkLmNoPqRsTuVwX', // 24 chars
}) =>
    '$number$rocDate$random$salesHex$totalHex$buyer$seller$aes';

void main() {
  group('parseEinvoiceQr — header (matches the sample 欣泰安 receipt)', () {
    final inv = parseEinvoiceQr(left: _header())!;

    test('header is exactly 77 chars', () {
      expect(_header().length, 77);
    });

    test('invoice number', () => expect(inv.invoiceNumber, 'BM18825967'));

    test('ROC date 1150523 → 2026-05-23 (+1911)', () {
      expect(inv.date, DateTime(2026, 5, 23));
    });

    test('random code', () => expect(inv.randomCode, '2683'));

    test('amounts decode from hex (48 pre-tax / 50 total)', () {
      expect(inv.salesAmountDollars, 48);
      expect(inv.totalDollars, 50);
    });

    test('seller tax id kept, buyer 00000000 → null (B2C)', () {
      expect(inv.sellerTaxId, '87589505');
      expect(inv.buyerTaxId, isNull);
    });

    test('no tail → header-only (no full items)', () {
      expect(inv.items, isEmpty);
      expect(inv.hasFullItems, isFalse);
      expect(inv.rawLeft, _header());
    });
  });

  group('parseEinvoiceQr — full items', () {
    // Real tail layout after the 77-char header (NO reserved field):
    // <sellerCustom>:<totalCount>:<thisQrCount>:<encoding>:<name>:<qty>:<price>…
    test('items entirely in the left QR', () {
      final left = '${_header()}:**********:2:2:0:商品A:1:30:商品B:2:10';
      final inv = parseEinvoiceQr(left: left)!;
      expect(inv.declaredItemCount, 2);
      expect(inv.hasFullItems, isTrue);
      expect(inv.items.map((i) => i.name), ['商品A', '商品B']);
      expect(inv.items[0].amount, 30); // qty 1 × 30
      expect(inv.items[1].amount, 20); // qty 2 × 10
    });

    test('items spanning left + right QR are merged', () {
      final left = '${_header()}:**********:3:1:0:商品A:1:30';
      const right = '**商品B:2:10:商品C:1:5';
      final inv = parseEinvoiceQr(left: left, right: right)!;
      expect(inv.declaredItemCount, 3);
      expect(inv.hasFullItems, isTrue);
      expect(inv.items.map((i) => i.name), ['商品A', '商品B', '商品C']);
    });

    test('all items on the right QR (left declares 0 on this page)', () {
      final left = '${_header()}:**********:2:0:0';
      const right = '**商品B:2:10:商品C:1:5';
      final inv = parseEinvoiceQr(left: left, right: right)!;
      expect(inv.declaredItemCount, 2);
      expect(inv.hasFullItems, isTrue);
      expect(inv.items.map((i) => i.name), ['商品B', '商品C']);
    });

    test('flipped scan order (right passed as left) is tolerated', () {
      final left = '${_header()}:**********:3:1:0:商品A:1:30';
      const right = '**商品B:2:10:商品C:1:5';
      final inv = parseEinvoiceQr(left: right, right: left)!;
      expect(inv.invoiceNumber, 'BM18825967');
      expect(inv.hasFullItems, isTrue);
    });
  });

  group('parseEinvoiceQr — graceful fallback', () {
    test('Big5 encoding flag → skip items, stay header-only', () {
      final left = '${_header()}:**********:1:1:1:??:1:30'; // encoding 1
      final inv = parseEinvoiceQr(left: left)!;
      expect(inv.declaredItemCount, 1);
      expect(inv.items, isEmpty);
      expect(inv.hasFullItems, isFalse);
    });

    test('count mismatch → not full (no fabricated items)', () {
      // Declares 5 but only one triple present.
      final left = '${_header()}:**********:5:5:0:商品A:1:30';
      final inv = parseEinvoiceQr(left: left)!;
      expect(inv.hasFullItems, isFalse);
      expect(inv.items.length, lessThan(5));
    });
  });

  group('parseEinvoiceQr — invalid input', () {
    test('too short → null', () {
      expect(parseEinvoiceQr(left: 'BM18825967'), isNull);
    });

    test('bad invoice number → null', () {
      expect(parseEinvoiceQr(left: _header(number: '12345678AB')), isNull);
    });

    test('non-hex amount → null', () {
      expect(parseEinvoiceQr(left: _header(totalHex: 'ZZZZZZZZ')), isNull);
    });

    test('impossible date → null', () {
      expect(parseEinvoiceQr(left: _header(rocDate: '1151399')), isNull);
    });
  });
}
