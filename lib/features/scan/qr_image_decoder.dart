import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/big5.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'qr_pixels.dart';

/// Decodes every QR code found in an image's [bytes]. Pure Dart, so it works on
/// **web and mobile alike** (unlike `mobile_scanner.analyzeImage`, which throws
/// on web).
///
/// A 電子發票證明聯 carries two QR codes side by side, and a single ZXing pass only
/// returns one. So we decode the whole image *plus* its left and right halves
/// and return all distinct payloads — the caller's parser then sorts header vs.
/// overflow. Safe to run inside `compute()` (top-level, isolate-friendly args).
///
/// Optimisations: clamps to a 1600 px longest edge before zxing (a QR doesn't
/// need more resolution than that and the heavy `img.decodeImage` cost scales
/// with pixels), tries the half-image crop that's most likely missing first
/// (right half if we already saw a left-shaped payload, and vice versa), and
/// short-circuits the moment both an e-invoice header (no `**`) *and* its
/// overflow (`**…`) are in hand.
///
/// Note for the web photo-import path: prefer [decodeQrCodesFromImageWeb] — it
/// uses Skia's native JPEG decoder via `dart:ui` (an order of magnitude faster
/// than the pure-Dart `img.decodeImage`) and yields between zxing passes so the
/// browser can repaint and the mascot keeps animating.
List<String> decodeQrCodesFromImage(Uint8List bytes) {
  img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } catch (_) {
    return const []; // unrecognized / corrupt file
  }
  if (image == null) return const [];
  // Real phone photos carry EXIF orientation; `_clamp` only bakes it in when it
  // actually resizes (via `copyResize`), so an already-small image would stay
  // sideways and confuse the QR detector. Bake it unconditionally up front.
  image = img.bakeOrientation(image);
  image = _clamp(image, longestEdge: 1600);
  return _scanRegionsSync(image);
}

/// Web **deep-fallback** decode, on the UI thread.
///
/// Only reached on browsers with no Worker support — the common web path goes
/// through `BarcodeDetector` or the zxing-wasm Worker (see `scan_decoder.dart`),
/// both off-thread. zxing here still yields between passes so the mascot ticks.
///
/// Pixels come from a **2D canvas** ([decodeImagePixelsWeb]: `createImageBitmap`
/// → `drawImage` → `getImageData`), not `ui.Image.toByteData` — the latter
/// returns an all-zero buffer on Flutter web's HTML/headless renderers, which
/// silently fed zxing a black image. The browser decodes **and** downscales to
/// 1600 px in one step (its resampler runs off the Dart isolate); we no longer
/// follow it with a second pure-Dart area-average resize — that was a wasteful,
/// UI-thread-blocking double downscale.
///
/// Falls back to the pure-Dart pipeline only if the canvas reader is
/// unavailable (older browser without `createImageBitmap`/`OffscreenCanvas`).
Future<List<String>> decodeQrCodesFromImageWeb(Uint8List bytes) async {
  final px = await decodeImagePixelsWeb(bytes, maxEdge: 1600);
  if (px == null) {
    if (kDebugMode) {
      debugPrint('[einvoice] web canvas pixels unavailable → pure-Dart');
    }
    return decodeQrCodesFromImage(bytes);
  }
  final image = img.Image.fromBytes(
    width: px.width,
    height: px.height,
    bytes: px.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  await _yieldFrame();
  return _scanRegionsAsync(image);
}

/// Hands the UI isolate back to the engine long enough to render exactly one
/// frame, then resumes. On web the decode runs on the same isolate as the UI, so
/// without these hand-backs the reading mascot would sit frozen for the whole
/// decode; sprinkling them between the heavy (un-chunkable) zxing passes lets it
/// keep blinking and breathing while the work grinds on. `endOfFrame` resolves
/// only after a frame is actually drawn, so each yield guarantees one mascot tick
/// — more reliable than a bare `Future.delayed(Duration.zero)`, which yields to
/// the event loop but doesn't promise a repaint landed before the next chunk.
Future<void> _yieldFrame() => SchedulerBinding.instance.endOfFrame;

/// Whole → missing-half → other-half decode loop. The sync version is used by
/// the mobile (compute-isolate) and test paths; the async version is used on
/// web and yields between regions so the UI thread can repaint.
List<String> _scanRegionsSync(img.Image image) {
  final acc = _Acc();
  acc.record(_decodeOne(image));
  if (acc.done) return acc.values;
  for (final region in _regions(image, acc.hasOverflow)) {
    acc.record(_decodeOne(region));
    if (acc.done) break;
  }
  return acc.values;
}

Future<List<String>> _scanRegionsAsync(img.Image image) async {
  final acc = _Acc();
  acc.record(await _decodeOneAsync(image));
  if (acc.done) return acc.values;
  for (final region in _regions(image, acc.hasOverflow)) {
    await _yieldFrame();
    acc.record(await _decodeOneAsync(region));
    if (acc.done) break;
  }
  return acc.values;
}

/// Candidate crops to try after the whole-image pass, in priority order.
///
/// A photographed receipt sits small and centred with wide margins, and the two
/// codes straddle the middle — so a bare 50/50 split can bisect a code and bare
/// halves leave each code tiny within a tall frame. We use **overlapping**
/// halves (so a midline code survives in at least one) plus a **centre band**
/// (zooms onto a centred receipt), and upscale any narrow crop so zxing keeps
/// enough pixels per module. The side we're still missing is tried first.
List<img.Image> _regions(img.Image image, bool hasOverflow) {
  final w = image.width;
  if (w <= 1) return const [];
  img.Image crop(double x0, double x1) {
    final x = (w * x0).round().clamp(0, w - 1);
    final cw = ((w * x1).round() - x).clamp(1, w - x);
    return _upscaleNarrow(
        img.copyCrop(image, x: x, y: 0, width: cw, height: image.height));
  }

  final left = crop(0.0, 0.55);
  final right = crop(0.45, 1.0);
  final band = crop(0.2, 0.8);
  return hasOverflow ? [left, right, band] : [right, left, band];
}

/// Upscales a crop whose width is below [minWidth] so a small QR's modules span
/// enough pixels for zxing's binarizer. Cubic keeps module edges crisp.
img.Image _upscaleNarrow(img.Image region, {int minWidth = 900}) {
  if (region.width >= minWidth) return region;
  final scale = minWidth / region.width;
  return img.copyResize(
    region,
    width: minWidth,
    height: (region.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
}

class _Acc {
  final found = <String>{};
  var hasHeader = false; // a non-`**` payload
  var hasOverflow = false; // a `**`-prefixed payload (e-invoice right QR)
  bool get done => hasHeader && hasOverflow;
  List<String> get values => found.toList();
  void record(String? text) {
    if (text == null || text.isEmpty) return;
    if (!found.add(text)) return;
    if (text.startsWith('**')) {
      hasOverflow = true;
    } else {
      hasHeader = true;
    }
  }
}

img.Image _clamp(img.Image image, {required int longestEdge}) {
  // 4032×3024 iPhone originals decode 5-10× slower than necessary — a QR's
  // 21-pixel module is well-served by ~1600 px on the long edge.
  final longest = image.width >= image.height ? image.width : image.height;
  if (longest <= longestEdge) return image;
  return image.width >= image.height
      ? img.copyResize(image,
          width: longestEdge, interpolation: img.Interpolation.average)
      : img.copyResize(image,
          height: longestEdge, interpolation: img.Interpolation.average);
}

String? _decodeOne(img.Image image) {
  final source = _luminanceSource(image);
  if (source == null) return null;
  final hints = _decodeHints();
  // HybridBinarizer suits photos (local thresholds); GlobalHistogramBinarizer is a
  // cheap fallback that can win on evenly-lit flat scans. Try both before giving up.
  for (final binarizer in _binarizers(source)) {
    final text = _decodeWith(binarizer, hints);
    if (text != null) return text;
  }
  return null; // nothing in this region
}

/// Frame-yielding twin of [_decodeOne] for the web path: hands a mascot frame
/// back between the two binarizer attempts (each a single un-chunkable zxing
/// call) so the animation keeps ticking through the slowest part of the decode.
Future<String?> _decodeOneAsync(img.Image image) async {
  final source = _luminanceSource(image);
  if (source == null) return null;
  final hints = _decodeHints();
  final binarizers = _binarizers(source);
  for (var i = 0; i < binarizers.length; i++) {
    final text = _decodeWith(binarizers[i], hints);
    if (text != null) return text;
    if (i < binarizers.length - 1) await _yieldFrame();
  }
  return null;
}

/// Builds zxing's luminance source from [image]'s pixels, or null if the pixel
/// copy fails.
///
/// zxing2's RGBLuminanceSource reads each int as 0xAARRGGBB (r from bits 16-23,
/// g from 8-15, b from 0-7). On a little-endian host the byte buffer must be laid
/// out B,G,R,A to form that int — i.e. ChannelOrder.bgra. (Using abgr scrambled the
/// channels and bled the opaque alpha into "blue", which still decoded clean
/// high-contrast images but lost too much contrast on real-world photos.)
RGBLuminanceSource? _luminanceSource(img.Image image) {
  final Int32List pixels;
  try {
    pixels = image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.bgra)
        .buffer
        .asInt32List();
  } catch (_) {
    return null;
  }
  return RGBLuminanceSource(image.width, image.height, pixels);
}

List<Binarizer> _binarizers(RGBLuminanceSource source) =>
    [HybridBinarizer(source), GlobalHistogramBinarizer(source)];

/// Decode byte segments losslessly as ISO-8859-1 (1 byte → 1 code unit) rather
/// than letting zxing guess: MOF e-invoice item names are byte-mode CJK with no
/// ECI, and a UTF-8 guess silently turns Big5 names into U+FFFD (the bytes are
/// then gone). We recover the real text from the preserved bytes in
/// [_recoverText]; the ASCII header/delimiters are invariant under this.
DecodeHints _decodeHints() => DecodeHints()
  ..put(DecodeHintType.tryHarder)
  ..put(DecodeHintType.characterSet, 'ISO-8859-1');

String? _decodeWith(Binarizer binarizer, DecodeHints hints) {
  try {
    return _recoverText(QRCodeReader().decode(BinaryBitmap(binarizer), hints: hints));
  } catch (_) {
    return null; // NotFoundException etc. — caller tries the next binarizer.
  }
}

const _big5Lenient = Big5Codec(allowInvalid: true);
final _einvoiceHeadRe = RegExp(r'^[A-Z]{2}\d{8}');

/// Recovers the real payload text, working around mis-encoded CJK item names.
///
/// MOF e-invoice item names are UTF-8 on compliant systems but **Big5** on many
/// Taiwan POS systems — and some wrongly tag the QR with a UTF-8 ECI, which
/// makes zxing decode the Big5 bytes into U+FFFD (the bytes are then lost in
/// [Result.text]). The QR is a single byte-mode segment though, so its raw
/// pre-charset bytes survive in `byteSegments`: when that segment reconstructs a
/// recognisable e-invoice we re-decode it ourselves via [recoverEinvoiceText].
String _recoverText(Result result) {
  final segs = result.resultMetadata[ResultMetadataType.byteSegments];
  if (segs is List<Int8List> && segs.length == 1) {
    final src = segs.first;
    final bytes = Uint8List(src.length);
    for (var i = 0; i < src.length; i++) {
      bytes[i] = src[i] & 0xff;
    }
    final recovered = recoverEinvoiceText(bytes);
    if (recovered != null) return recovered;
  }
  return result.text;
}

/// Re-decodes a QR's raw byte-mode segment [bytes] into the correct e-invoice
/// text, picking UTF-8 then Big5. ASCII — the whole header and every
/// delimiter/number — is invariant under both, so this never corrupts a header.
///
/// Returns null when [bytes] don't look like an e-invoice payload: only then is
/// it safe to trust them as the *whole* payload (otherwise they might be one
/// byte-run inside a mixed-mode QR and we'd drop the rest). Callers keep the
/// decoder's own text in that case. (Latin-1 is a lossless byte→char view for
/// the probe.)
///
/// Shared by the zxing2 path ([_recoverText]) and the web worker client, which
/// applies it to the raw `bytes` zxing-wasm returns per symbol.
String? recoverEinvoiceText(Uint8List bytes) {
  final probe = latin1.decode(bytes);
  if (probe.startsWith('**') || _einvoiceHeadRe.hasMatch(probe)) {
    try {
      return utf8.decode(bytes); // throws on non-UTF-8 (e.g. Big5)
    } catch (_) {
      return _big5Lenient.decode(bytes);
    }
  }
  return null;
}
