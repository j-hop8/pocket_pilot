// Exposes [decodeQrCodesInWorker]: the zxing-wasm module-Worker decoder on the
// web (runs off the UI thread so photo import stays smooth), and a stub
// elsewhere (only ever called behind `kIsWeb`).
export 'qr_worker_client_stub.dart'
    if (dart.library.js_interop) 'qr_worker_client_web.dart';
