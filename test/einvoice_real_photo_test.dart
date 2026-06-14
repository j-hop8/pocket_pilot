import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketpilot/features/scan/qr_image_decoder.dart';
import 'package:pp_core/pp_core.dart';

// Regression test against a REAL photographed 電子發票證明聯 (布朗嘞義大利麵A9店,
// BP-61934238, total 280) that previously failed to scan on the Android/Web
// pure-Dart path. Exercises the exact decode + parse pipeline that runs on
// device, including: dual side-by-side QR recovery from a margined photo, the
// '**'-prefixed right QR, and Big5 item names mis-flagged as UTF-8.
void main() {
  test('real receipt photo decodes both QRs, header, and Big5 items', () {
    final bytes =
        File('test/fixtures/einvoice_real_bp61934238.jpg').readAsBytesSync();
    final codes = decodeQrCodesFromImage(bytes);

    String? left;
    String? right;
    for (final v in codes) {
      if (v.startsWith('**')) {
        right ??= v;
      } else if (parseEinvoiceQr(left: v) != null) {
        left ??= v;
      }
    }
    expect(left, isNotNull, reason: 'header/left QR must decode from the photo');
    expect(right, isNotNull, reason: 'overflow/right QR must decode too');

    final inv = parseEinvoiceQr(left: left!, right: right)!;
    expect(inv.invoiceNumber, 'BP61934238');
    expect(inv.totalDollars, 280);
    expect(inv.sellerTaxId, '87320938');
    expect(inv.declaredItemCount, 2);
    expect(inv.hasFullItems, isTrue);

    expect(inv.items.map((i) => i.name), [
      '青醬培根',
      '套餐C(培根玉米濃湯、香蒜麵包(2片)、雞米花)',
    ]);
    expect(inv.items[0].amount, 180);
    expect(inv.items[1].amount, 100);
    // Items sum to the header total — the recovered itemisation is complete.
    expect(
      inv.items.fold<int>(0, (sum, i) => sum + i.amount),
      inv.totalDollars,
    );
  });

  // decodeQrCodesFromImageWeb's real browser path (canvas getImageData) can't
  // run under the VM, so here it exercises the non-web fallback (the canvas
  // reader's stub returns null → pure-Dart pipeline). The real-browser canvas
  // path is verified separately via `flutter test --platform chrome`.
  test('decodeQrCodesFromImageWeb returns the full result (non-web fallback)',
      () async {
    final bytes =
        File('test/fixtures/einvoice_real_bp61934238.jpg').readAsBytesSync();
    final codes = await decodeQrCodesFromImageWeb(bytes);

    final left = codes.firstWhere((c) => parseEinvoiceQr(left: c) != null,
        orElse: () => '');
    final right = codes.firstWhere((c) => c.startsWith('**'), orElse: () => '');
    expect(left, isNotEmpty, reason: 'web path: header QR must decode');
    expect(right, isNotEmpty, reason: 'web path: overflow QR must decode');

    final inv = parseEinvoiceQr(left: left, right: right)!;
    expect(inv.invoiceNumber, 'BP61934238');
    expect(inv.totalDollars, 280);
    expect(inv.items.map((i) => i.name), [
      '青醬培根',
      '套餐C(培根玉米濃湯、香蒜麵包(2片)、雞米花)',
    ]);
  });
}
