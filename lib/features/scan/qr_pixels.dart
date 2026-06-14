// Exposes [decodeImagePixelsWeb] / [ImagePixels]: a browser-canvas pixel reader
// on the web, and a throwing stub elsewhere (only ever called behind `kIsWeb`).
export 'qr_pixels_stub.dart'
    if (dart.library.js_interop) 'qr_pixels_web.dart';
