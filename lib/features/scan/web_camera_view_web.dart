import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Live camera preview with a capture button, for the **web** only.
///
/// `mobile_scanner`'s web reader can't reliably read the dense, side-by-side
/// dual-QR 電子發票證明聯: it runs ZXing at a low default resolution, with no
/// try-harder hint, and returns a single barcode per frame. So on web we open a
/// high-resolution `getUserMedia` stream ourselves and, on capture, snapshot the
/// frame to PNG bytes and hand them to the same pure-Dart decoder that photo
/// import uses (`decodeQrCodesFromImage`) — which also handles both QR halves.
class WebCameraView extends StatefulWidget {
  /// Called with a PNG snapshot of the current frame when the user taps capture.
  final Future<void> Function(Uint8List frame) onCapture;

  /// True while the parent is decoding/processing a previous capture; disables
  /// the capture button so frames can't pile up.
  final bool busy;

  final String openingText;
  final String captureLabel;
  final String deniedText;
  final String unsupportedText;
  final String retryLabel;

  /// Glyph on the capture button. Defaults to the QR-scanner icon the e-invoice
  /// tab wants; the receipt tab passes a plain camera icon.
  final IconData captureIcon;

  const WebCameraView({
    super.key,
    required this.onCapture,
    required this.busy,
    required this.openingText,
    required this.captureLabel,
    required this.deniedText,
    required this.unsupportedText,
    required this.retryLabel,
    this.captureIcon = Icons.qr_code_scanner,
  });

  @override
  State<WebCameraView> createState() => _WebCameraViewState();
}

class _WebCameraViewState extends State<WebCameraView> {
  static int _seq = 0;
  late final String _viewType = 'pp-web-camera-${_seq++}';

  web.HTMLVideoElement? _video;
  web.MediaStream? _stream;
  bool _ready = false;
  String? _error;
  bool _canRetry = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final stream = await _openStream();
      final video = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..srcObject = stream;
      video.setAttribute('playsinline', 'true');
      video.style
        ..setProperty('width', '100%')
        ..setProperty('height', '100%')
        ..setProperty('object-fit', 'cover');
      ui_web.platformViewRegistry
          .registerViewFactory(_viewType, (int _) => video);
      await video.play().toDart;
      if (!mounted) {
        _stopStream(stream);
        return;
      }
      setState(() {
        _stream = stream;
        _video = video;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final denied =
          msg.contains('NotAllowedError') || msg.contains('Permission');
      final noCamera = msg.contains('NotFoundError') ||
          msg.contains('NotSupportedError') ||
          msg.contains('undefined') ||
          msg.contains('null');
      setState(() {
        // A denied permission can be granted then retried; a missing camera or
        // insecure context can't be fixed from here.
        _canRetry = denied;
        _error = denied
            ? widget.deniedText
            : noCamera
                ? widget.unsupportedText
                : widget.deniedText;
      });
    }
  }

  /// Opens a back-facing, high-resolution stream. Constraints are built as a
  /// plain JS object (the typed `MediaTrackConstraints` is awkward) and passed
  /// to `getUserMedia` via a dynamic call.
  Future<web.MediaStream> _openStream() {
    final video = JSObject()
      ..['facingMode'] = 'environment'.toJS
      ..['width'] = (JSObject()..['ideal'] = 1920.toJS)
      ..['height'] = (JSObject()..['ideal'] = 1080.toJS);
    final constraints = JSObject()
      ..['audio'] = false.toJS
      ..['video'] = video;
    final mediaDevices = web.window.navigator.mediaDevices as JSObject;
    final promise = mediaDevices.callMethod<JSPromise<web.MediaStream>>(
        'getUserMedia'.toJS, constraints);
    return promise.toDart;
  }

  Future<void> _retry() async {
    _disposeStream();
    setState(() {
      _ready = false;
      _error = null;
    });
    await _start();
  }

  void _capture() {
    final video = _video;
    if (video == null || !_ready || widget.busy) return;
    final w = video.videoWidth;
    final h = video.videoHeight;
    if (w == 0 || h == 0) return;
    final canvas = web.HTMLCanvasElement()
      ..width = w
      ..height = h;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(video, 0, 0);
    final dataUrl = canvas.toDataURL('image/png');
    final bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
    widget.onCapture(bytes);
  }

  void _stopStream(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  void _disposeStream() {
    final s = _stream;
    if (s != null) _stopStream(s);
    _video?.srcObject = null;
    _stream = null;
    _video = null;
  }

  @override
  void dispose() {
    _disposeStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _Overlay(
        icon: Icons.videocam_off_outlined,
        text: _error!,
        action: _canRetry
            ? FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: Text(widget.retryLabel),
              )
            : null,
      );
    }
    if (!_ready) {
      return _Overlay(spinner: true, text: widget.openingText);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: FilledButton.icon(
              onPressed: widget.busy ? null : _capture,
              icon: Icon(widget.captureIcon),
              label: Text(widget.captureLabel),
            ),
          ),
        ),
      ],
    );
  }
}

class _Overlay extends StatelessWidget {
  final String text;
  final bool spinner;
  final IconData? icon;
  final Widget? action;

  const _Overlay({
    required this.text,
    this.spinner = false,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spinner)
                const CircularProgressIndicator(color: Colors.white70)
              else if (icon != null)
                Icon(icon, color: Colors.white70, size: 36),
              const SizedBox(height: 14),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
