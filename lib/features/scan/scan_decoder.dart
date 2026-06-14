import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pp_core/pp_core.dart';

import 'qr_barcode_detector.dart';
import 'qr_image_decoder.dart';
import 'qr_worker_client.dart';

/// Test hook: force the zxing-wasm Worker path on web even where `BarcodeDetector`
/// would win, so the fallback can be exercised in a Chromium-based browser.
/// Toggle with `--dart-define=FORCE_WORKER_SCAN=true`, or flip at runtime in a
/// debug build. No effect off web.
bool debugForceWorkerScan = const bool.fromEnvironment('FORCE_WORKER_SCAN');

/// Shared, UI-free e-invoice decode helpers. Both the live-camera panel and the
/// background scan queue go through these so there's a single decode/parse
/// implementation (previously this lived as private methods on the panel).

const _qrFormats = [BarcodeFormat.qrCode];

/// Classifies raw QR payloads into the header (left) and overflow (right) QR of
/// a 電子發票證明聯 and parses them. Returns null until a valid header is in hand.
ParsedQrInvoice? parseInvoiceFromCodes(Iterable<String> codes) {
  String? left;
  String? right;
  for (final v in codes) {
    if (v.startsWith('**')) {
      right ??= v;
    } else if (parseEinvoiceQr(left: v) != null) {
      left ??= v;
    }
  }
  if (left == null) return null;
  return parseEinvoiceQr(left: left, right: right);
}

/// Decodes receipt image [bytes] into a parsed e-invoice, or null if no valid
/// e-invoice QR could be read. Platform-aware:
/// - iOS/Android: try the hardware ML Kit reader first (an order of magnitude
///   faster), then fall back to the pure-Dart zxing2 pipeline (in a `compute`
///   isolate) to catch the second QR ML Kit often misses.
/// - Web: [_decodeInvoiceOnWeb] — strictly off the main thread so photo import
///   stays smooth (`compute` is a no-op on web, so the old path froze the UI).
Future<ParsedQrInvoice?> decodeInvoiceFromBytes(Uint8List bytes) async {
  final seen = <String>{};
  if (kIsWeb) return _decodeInvoiceOnWeb(seen, bytes);
  // Native iOS/Android gets the ML Kit fast path first.
  final parsed = await _tryAnalyzeImage(bytes, seen);
  if (parsed != null) return parsed;
  seen.addAll(await compute(decodeQrCodesFromImage, bytes));
  return parseInvoiceFromCodes(seen);
}

/// Web decode, kept off the main thread so the UI (and the reading mascot) never
/// freezes. Escalates through three tiers, returning as soon as one yields a
/// valid e-invoice:
///   1. `BarcodeDetector` — native, runs off-thread (Chromium / Chrome / Edge /
///      Android). One `detect()` returns both QRs of a receipt at once.
///   2. zxing-wasm in a Web Worker — off-thread on every other browser
///      (Firefox, desktop Safari) and the terminal tier wherever Workers exist.
///   3. pure-Dart zxing on the UI thread — last resort for the rare browser with
///      no Worker support; may briefly jank, but essentially never reached.
Future<ParsedQrInvoice?> _decodeInvoiceOnWeb(
  Set<String> seen,
  Uint8List bytes,
) async {
  // Tier 1: BarcodeDetector (skipped when forcing the worker path for testing).
  if (!debugForceWorkerScan) {
    final codes = await detectQrCodesWeb(bytes);
    if (codes != null) {
      seen.addAll(codes);
      final parsed = parseInvoiceFromCodes(seen);
      if (parsed != null) return parsed;
    }
  }
  // Tier 2: zxing-wasm Web Worker. When Workers exist this is the terminal tier
  // — a miss here means the photo simply has no readable QR, and we stop rather
  // than freeze the UI on the pure-Dart path.
  if (workerDecodeSupported()) {
    seen.addAll(await decodeQrCodesInWorker(bytes));
    return parseInvoiceFromCodes(seen);
  }
  // Tier 3: pure-Dart on the UI thread (no Worker support).
  seen.addAll(await decodeQrCodesFromImageWeb(bytes));
  return parseInvoiceFromCodes(seen);
}

/// iOS/Android fast path: writes [bytes] to a temp JPEG and asks mobile_scanner's
/// ML Kit reader to find the e-invoice QR(s). Returns a parsed invoice when ML
/// Kit found a header the parser accepts, else null (callers fall back to the
/// zxing2 pipeline). Any payloads it does find are added to [seen] so the
/// fallback can reuse them. Best-effort: any failure returns null.
Future<ParsedQrInvoice?> _tryAnalyzeImage(
  Uint8List bytes,
  Set<String> seen,
) async {
  File? tmp;
  MobileScannerController? scratch;
  try {
    tmp = File(
      '${Directory.systemTemp.path}/einvoice_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await tmp.writeAsBytes(bytes, flush: false);
    // A scratch controller used only for analyzeImage — never mounted in a
    // MobileScanner widget, so no camera is grabbed.
    scratch = MobileScannerController(formats: _qrFormats);
    final capture = await scratch.analyzeImage(tmp.path);
    if (capture == null) return null;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) seen.add(v);
    }
    return parseInvoiceFromCodes(seen);
  } catch (_) {
    return null;
  } finally {
    unawaited(scratch?.dispose() ?? Future.value());
    final f = tmp;
    if (f != null) unawaited(f.delete().catchError((_) => f));
  }
}
