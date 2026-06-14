import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'qr_image_decoder.dart' show recoverEinvoiceText;

/// Decodes e-invoice QR payloads from image [bytes] on a **real background
/// thread** via [`web/zxing/qr_worker.js`] (zxing-wasm in a module Worker).
///
/// This is the smooth web fallback for browsers without `BarcodeDetector`
/// (Firefox, desktop Safari): the heavy JPEG-decode + QR-scan never touch the
/// UI isolate, so the page stays responsive. Returns the recovered raw payloads
/// (Big5-aware via [recoverEinvoiceText]), or an empty list if the worker is
/// unavailable, errors, or times out — callers then drop to the deep fallback.
/// Whether this browser can run the zxing-wasm Worker at all (essentially every
/// evergreen browser). When false, callers drop straight to the pure-Dart deep
/// fallback instead of paying a doomed Worker round-trip.
bool workerDecodeSupported() => web.window.has('Worker');

Future<List<String>> decodeQrCodesInWorker(Uint8List bytes) {
  final web.Worker worker;
  try {
    worker = _ensureWorker();
  } catch (_) {
    return Future.value(const []); // no Worker support → caller falls back
  }
  final id = _nextId++;
  final completer = Completer<List<String>>();
  _pending[id] = completer;

  // Copy into a fresh buffer so the transfer length is exact (the source may be
  // a view into a larger buffer) and we never detach bytes the caller still uses.
  final buffer = Uint8List.fromList(bytes).buffer.toJS;
  final message = JSObject()
    ..setProperty('id'.toJS, id.toJS)
    ..setProperty('bytes'.toJS, buffer);
  worker.postMessage(message, <JSAny>[buffer].toJS);

  return completer.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      _pending.remove(id);
      return const [];
    },
  );
}

web.Worker? _worker;
int _nextId = 0;
final Map<int, Completer<List<String>>> _pending = {};

web.Worker _ensureWorker() {
  final existing = _worker;
  if (existing != null) return existing;
  // Relative URL so it resolves against the document's <base href> (sub-path
  // deploys keep working). A classic worker: it `importScripts` the
  // self-contained zxing-wasm IIFE bundle, so no module options are needed.
  final w = web.Worker('zxing/qr_worker.js'.toJS);
  w.onmessage = (web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final id = data.getProperty<JSNumber>('id'.toJS).toDartInt;
    final completer = _pending.remove(id);
    if (completer == null) return;
    completer.complete(_codesFromMessage(data));
  }.toJS;
  // A worker load/runtime error fails every in-flight decode (empty → fall
  // back) and drops the handle so the next call rebuilds it.
  w.onerror = (web.Event _) {
    _worker = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(const []);
    }
    _pending.clear();
  }.toJS;
  _worker = w;
  return w;
}

List<String> _codesFromMessage(JSObject data) {
  final error = data.getProperty<JSAny?>('error'.toJS);
  if (error != null) return const []; // worker-side decode failure
  final payloads = data.getProperty<JSArray<JSObject>?>('payloads'.toJS);
  if (payloads == null) return const [];
  final codes = <String>[];
  for (final p in payloads.toDart) {
    final raw = p.getProperty<JSUint8Array?>('bytes'.toJS)?.toDart;
    final text = p.getProperty<JSString?>('text'.toJS)?.toDart;
    final recovered =
        (raw != null ? recoverEinvoiceText(raw) : null) ?? text ?? '';
    if (recovered.isNotEmpty) codes.add(recovered);
  }
  return codes;
}
