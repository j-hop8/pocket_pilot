import 'dart:typed_data';

/// Non-web stub — the browser `BarcodeDetector` only exists on web (and is only
/// ever called behind `kIsWeb`). Returns null so any off-web caller escalates to
/// the next decode tier rather than crashing.
Future<List<String>?> detectQrCodesWeb(Uint8List bytes) async => null;
