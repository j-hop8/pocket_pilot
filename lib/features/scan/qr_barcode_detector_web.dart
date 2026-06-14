import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browser-native QR detection via the [`BarcodeDetector`][bd] API.
///
/// [bd]: https://developer.mozilla.org/en-US/docs/Web/API/BarcodeDetector
///
/// This is the **smooth web fast path**: detection runs natively off the main
/// thread, so the UI (and the reading mascot) never freezes — unlike the
/// pure-Dart zxing pipeline, which seizes the one web isolate. A single
/// `detect()` returns *every* QR in the frame, so both QRs of a 電子發票證明聯 come
/// back in one shot.
///
/// Returns:
/// - `null` when the API is unavailable (Firefox, desktop Safari, older
///   browsers) or any step throws — the caller escalates to the worker.
/// - the list of raw QR payloads otherwise (possibly empty if the photo had no
///   readable QR, in which case the caller still escalates to the worker, whose
///   aggressive crops can catch codes BarcodeDetector missed).
///
/// Big5 caveat: `rawValue` is browser-decoded as UTF-8, so the ASCII header QR
/// is exact (invoice no., date, amounts, tax IDs — all the caller needs), while
/// the overflow QR's CJK item names may be garbled. The worker path recovers
/// those losslessly from raw bytes.
Future<List<String>?> detectQrCodesWeb(Uint8List bytes) async {
  if (!web.window.has('BarcodeDetector')) return null;
  web.ImageBitmap? bitmap;
  web.ImageBitmap? scaled;
  try {
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS);
    // `from-image` bakes EXIF rotation in so portrait phone photos arrive
    // upright for the detector.
    bitmap = await web.window
        .createImageBitmap(
          blob,
          web.ImageBitmapOptions(imageOrientation: 'from-image'),
        )
        .toDart;
    // Cap the longest edge before detecting. A full-res phone photo (e.g.
    // 4032 px) makes `detect()` scan millions of extra pixels — seconds of work.
    // We resize the *already-decoded* bitmap (not the blob), so the browser only
    // rescales, no second JPEG decode, and it all stays off the main thread.
    final source = await _clampBitmap(bitmap);
    scaled = identical(source, bitmap) ? null : source;
    final detector = _BarcodeDetector(
      _BarcodeDetectorOptions(formats: <JSString>['qr_code'.toJS].toJS),
    );
    final results = (await detector.detect(source).toDart).toDart;
    final codes = <String>[];
    for (final r in results) {
      final v = r.rawValue;
      if (v.isNotEmpty) codes.add(v);
    }
    return codes;
  } catch (_) {
    return null; // treat any failure as "unavailable" → escalate to worker
  } finally {
    scaled?.close();
    bitmap?.close();
  }
}

/// A QR's modules are well-served by ~1600 px on the long edge, matching the
/// zxing-wasm worker path; anything larger just slows `detect()` down.
const int _maxEdge = 1600;

/// Returns [bitmap] downscaled so its longest edge is at most [_maxEdge], or
/// [bitmap] itself when it's already small enough. The resize runs off the main
/// thread (browser-side, source is the decoded bitmap — no re-decode).
Future<web.ImageBitmap> _clampBitmap(web.ImageBitmap bitmap) async {
  final w = bitmap.width;
  final h = bitmap.height;
  final longest = w >= h ? w : h;
  if (longest <= _maxEdge) return bitmap;
  final scale = _maxEdge / longest;
  return web.window
      .createImageBitmap(
        bitmap,
        web.ImageBitmapOptions(
          resizeWidth: (w * scale).round(),
          resizeHeight: (h * scale).round(),
          resizeQuality: 'high',
        ),
      )
      .toDart;
}

@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external _BarcodeDetector(_BarcodeDetectorOptions options);
  external JSPromise<JSArray<_DetectedBarcode>> detect(JSAny image);
}

extension type _BarcodeDetectorOptions._(JSObject _) implements JSObject {
  external factory _BarcodeDetectorOptions({JSArray<JSString> formats});
}

extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external String get rawValue;
}
