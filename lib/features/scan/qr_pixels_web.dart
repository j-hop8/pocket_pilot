import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Decoded image pixels: straight (un-premultiplied) RGBA, row-major.
class ImagePixels {
  final Uint8List rgba;
  final int width;
  final int height;
  const ImagePixels(this.rgba, this.width, this.height);
}

/// Decodes [bytes] (JPEG/PNG/…) in the browser and returns its RGBA pixels via a
/// 2D canvas, scaled so the longest edge is at most [maxEdge].
///
/// This deliberately avoids `ui.Image.toByteData`, which on Flutter web returns
/// an all-zero buffer on the HTML/headless renderers (the GPU image can't be
/// read back) — that silently fed zxing a black image and broke photo-import
/// scanning. `createImageBitmap` + `drawImage` + `getImageData` is renderer-
/// independent and offloads the JPEG decode to the browser. Returns null on any
/// failure so the caller can fall back to the pure-Dart pipeline.
Future<ImagePixels?> decodeImagePixelsWeb(Uint8List bytes,
    {int maxEdge = 1600}) async {
  try {
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS);
    // `imageOrientation: 'from-image'` bakes in EXIF rotation (iPhone photos are
    // usually rotated), so the canvas is upright for the QR detector.
    final bitmap = await web.window
        .createImageBitmap(
          blob,
          web.ImageBitmapOptions(imageOrientation: 'from-image'),
        )
        .toDart;
    var w = bitmap.width;
    var h = bitmap.height;
    final longest = w >= h ? w : h;
    if (longest > maxEdge) {
      final scale = maxEdge / longest;
      w = (w * scale).round();
      h = (h * scale).round();
    }
    final canvas = web.HTMLCanvasElement()
      ..width = w
      ..height = h;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, 0, 0, w, h);
    bitmap.close();
    final data = ctx.getImageData(0, 0, w, h).data.toDart;
    return ImagePixels(Uint8List.fromList(data), w, h);
  } catch (_) {
    return null;
  }
}
