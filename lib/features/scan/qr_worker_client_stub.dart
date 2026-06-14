import 'dart:typed_data';

/// Non-web stub — the Worker decoder only exists on web (and is only ever called
/// behind `kIsWeb`).
bool workerDecodeSupported() => false;

/// Returns an empty list so any off-web caller escalates to the next decode tier
/// rather than crashing.
Future<List<String>> decodeQrCodesInWorker(Uint8List bytes) async => const [];
