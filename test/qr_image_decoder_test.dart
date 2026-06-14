import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pocketpilot/features/scan/qr_image_decoder.dart';
import 'package:pp_core/pp_core.dart';
import 'package:zxing2/qrcode.dart';

String _header({
  String number = 'BM18825967',
  String rocDate = '1150523',
  String random = '2683',
  String salesHex = '00000030',
  String totalHex = '00000032',
  String buyer = '00000000',
  String seller = '87589505',
  String aes = 'aBcDeFgHiJkLmNoPqRsTuVwX',
}) =>
    '$number$rocDate$random$salesHex$totalHex$buyer$seller$aes';

// Renders [content] as a QR image (white quiet zone, scaled modules).
img.Image _qrImage(String content, {int scale = 6, int quiet = 4}) {
  final qr = Encoder.encode(content, ErrorCorrectionLevel.m);
  final m = qr.matrix!;
  final w = (m.width + quiet * 2) * scale;
  final h = (m.height + quiet * 2) * scale;
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < m.height; y++) {
    for (var x = 0; x < m.width; x++) {
      if (m.get(x, y) == 1) {
        final px = (x + quiet) * scale;
        final py = (y + quiet) * scale;
        img.fillRect(image,
            x1: px,
            y1: py,
            x2: px + scale - 1,
            y2: py + scale - 1,
            color: img.ColorRgb8(0, 0, 0));
      }
    }
  }
  return image;
}

Uint8List _qrPng(String content) => img.encodePng(_qrImage(content));

// Two QR codes side by side, like a real 證明聯.
Uint8List _sideBySidePng(String left, String right) {
  final a = _qrImage(left);
  final b = _qrImage(right);
  final out = img.Image(width: a.width + b.width, height: max(a.height, b.height));
  img.fill(out, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(out, a, dstX: 0, dstY: 0);
  img.compositeImage(out, b, dstX: a.width, dstY: 0);
  return img.encodePng(out);
}

// A receipt photographed on a desk: the two side-by-side codes sit small and
// centred inside a large frame with wide margins all around, then the whole
// thing is downscaled like a real camera capture. This is the geometry that
// broke the old bare-halves crop (the centred codes straddle the midline), so
// it guards the overlapping-crops + centre-band region strategy.
Uint8List _receiptPhotoPng(String left, String right, {double resize = 0.75}) {
  final a = _qrImage(left);
  final b = _qrImage(right);
  const gap = 12;
  final codesW = a.width + b.width + gap;
  final codesH = max(a.height, b.height);
  final frame = img.Image(width: (codesW * 2.6).round(), height: codesH * 4);
  img.fill(frame, color: img.ColorRgb8(205, 200, 196)); // desk
  final ox = (frame.width - codesW) ~/ 2;
  final oy = (frame.height - codesH) ~/ 2;
  img.fillRect(frame, // white receipt patch behind the codes
      x1: ox - 10,
      y1: oy - 10,
      x2: ox + codesW + 10,
      y2: oy + codesH + 10,
      color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(frame, a, dstX: ox, dstY: oy);
  img.compositeImage(frame, b, dstX: ox + a.width + gap, dstY: oy);
  final photo = img.copyResize(frame,
      width: (frame.width * resize).round(),
      interpolation: img.Interpolation.average);
  return img.encodePng(photo);
}

void main() {
  group('decodeQrCodesFromImage (pure-Dart, the web photo-import path)', () {
    test('decodes a single QR payload', () {
      expect(decodeQrCodesFromImage(_qrPng('HELLO-123')), contains('HELLO-123'));
    });

    test('garbage bytes decode to nothing (no throw)', () {
      expect(decodeQrCodesFromImage(Uint8List.fromList([1, 2, 3, 4])), isEmpty);
    });

    test('an e-invoice left QR round-trips and parses', () {
      final codes = decodeQrCodesFromImage(_qrPng(_header()));
      final left = codes.firstWhere((c) => parseEinvoiceQr(left: c) != null);
      final inv = parseEinvoiceQr(left: left)!;
      expect(inv.invoiceNumber, 'BM18825967');
      expect(inv.totalDollars, 50);
    });

    test('decodes a down-scaled, blurred QR (gallery-thumbnail path)', () {
      // Mimics a real photo / gallery thumbnail: render large, then shrink and
      // blur so module edges soften and contrast drops. Covers the resize/blur
      // regime the recent-photos picker feeds in (originBytes can be reduced).
      final big = _qrImage(_header(), scale: 8);
      var photo = img.copyResize(big,
          width: (big.width * 0.42).round(),
          interpolation: img.Interpolation.average);
      photo = img.gaussianBlur(photo, radius: 1);
      final codes = decodeQrCodesFromImage(img.encodePng(photo));
      final left =
          codes.firstWhere((c) => parseEinvoiceQr(left: c) != null, orElse: () => '');
      expect(parseEinvoiceQr(left: left)?.invoiceNumber, 'BM18825967');
    });

    test('both QR codes are recovered from a side-by-side image', () {
      // ASCII item names: zxing2's encoder is Latin-1 only, so the test fixture
      // can't render Chinese — the runtime decoder handles UTF-8 fine.
      final left = '${_header()}:**********:3:1:0:ItemA:1:30';
      const right = '**ItemB:2:10:ItemC:1:5';
      final codes = decodeQrCodesFromImage(_sideBySidePng(left, right));
      expect(codes, contains(left));
      expect(codes, contains(right));

      // And the panel's classify-then-parse logic yields full items.
      final header = codes.firstWhere((c) => parseEinvoiceQr(left: c) != null);
      final overflow = codes.firstWhere((c) => c.startsWith('**'));
      final inv = parseEinvoiceQr(left: header, right: overflow)!;
      expect(inv.hasFullItems, isTrue);
      expect(inv.items.map((i) => i.name), ['ItemA', 'ItemB', 'ItemC']);
    });

    test('recovers both codes from a small, centred receipt with margins', () {
      final left = '${_header()}:**********:3:1:0:ItemA:1:30';
      const right = '**ItemB:2:10:ItemC:1:5';
      final codes = decodeQrCodesFromImage(_receiptPhotoPng(left, right));
      final header =
          codes.firstWhere((c) => parseEinvoiceQr(left: c) != null, orElse: () => '');
      final overflow = codes.firstWhere((c) => c.startsWith('**'), orElse: () => '');
      final inv = parseEinvoiceQr(left: header, right: overflow);
      expect(inv?.hasFullItems, isTrue);
      expect(inv?.items.map((i) => i.name), ['ItemA', 'ItemB', 'ItemC']);
    });
  });
}
