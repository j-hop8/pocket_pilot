import 'dart:typed_data';

/// Decoded image pixels: straight (un-premultiplied) RGBA, row-major.
class ImagePixels {
  final Uint8List rgba;
  final int width;
  final int height;
  const ImagePixels(this.rgba, this.width, this.height);
}

/// Non-web stub — the canvas-based reader only exists on web (and is only ever
/// called behind `kIsWeb`). Returns null so any off-web caller falls back to the
/// pure-Dart `image` decoder rather than crashing.
Future<ImagePixels?> decodeImagePixelsWeb(Uint8List bytes,
        {int maxEdge = 1600}) async =>
    null;
