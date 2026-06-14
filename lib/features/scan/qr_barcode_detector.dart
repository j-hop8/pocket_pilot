// Exposes [detectQrCodesWeb]: the browser-native `BarcodeDetector` fast path on
// the web, and a null-returning stub elsewhere (only ever called behind
// `kIsWeb`). `BarcodeDetector` runs detection off the main thread internally, so
// it's the smooth web fast path; callers fall back to the worker when it returns
// null (API unavailable) or no valid invoice.
export 'qr_barcode_detector_stub.dart'
    if (dart.library.js_interop) 'qr_barcode_detector_web.dart';
