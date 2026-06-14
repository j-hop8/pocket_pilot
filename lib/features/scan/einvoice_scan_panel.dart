import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pp_core/pp_core.dart';

import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/mascots.dart';
import 'qr_image_decoder.dart';
import 'recent_photos_strip.dart';
import 'scan_review_sheet.dart';
import 'web_camera_view.dart';

/// The e-invoice tab body. Behaves like the iPhone camera: when the Add tab is
/// showing ([active]) the camera turns on automatically and continuously hunts
/// for the QR. The instant a QR is in hand the preview goes to a **solid black
/// mask** and the animated [ScanningMascot] takes centre stage with a "讀取中…"
/// label, so it's unambiguous that the app has moved from "looking" to
/// "reading" the receipt. After the user saves (or cancels) scanning resumes.
/// A recent-photos strip sits in the bottom-left for picking an existing photo.
///
/// The camera is released whenever the tab is left or the app is backgrounded —
/// the Add tab lives in an `IndexedStack`, so we must not hold it open offstage.
class EInvoiceScanPanel extends ConsumerStatefulWidget {
  /// True when this tab is the one the user is looking at (Add tab + e-invoice
  /// sub-tab). Drives whether the camera runs.
  final bool active;

  const EInvoiceScanPanel({super.key, required this.active});

  @override
  ConsumerState<EInvoiceScanPanel> createState() => _EInvoiceScanPanelState();
}

enum _Phase { scanning, processing }

class _EInvoiceScanPanelState extends ConsumerState<EInvoiceScanPanel>
    with WidgetsBindingObserver {
  static const _formats = [BarcodeFormat.qrCode];

  MobileScannerController? _controller;
  final _seen = <String>{};
  _Phase _phase = _Phase.scanning;
  bool _handled = false;
  bool _appPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncCamera();
  }

  @override
  void didUpdateWidget(covariant EInvoiceScanPanel old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) setState(_syncCamera);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state != AppLifecycleState.resumed;
    if (paused == _appPaused) return;
    _appPaused = paused;
    setState(_syncCamera);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// Whether a live mobile camera should be running right now. The camera keeps
  /// running during processing too, so the user sees the preview behind the
  /// detection overlay instead of cutting to a black screen.
  bool get _wantCamera => widget.active && !_appPaused && !kIsWeb;

  /// Reconciles the controller with [_wantCamera]: create one when the camera
  /// should run, dispose it the moment it shouldn't. Call inside `setState`.
  void _syncCamera() {
    if (_wantCamera && _controller == null) {
      _seen.clear();
      _handled = false;
      _controller = _newController();
    } else if (!_wantCamera && _controller != null) {
      final old = _controller;
      _controller = null;
      unawaited(old!.dispose());
    }
  }

  MobileScannerController _newController() => MobileScannerController(
        formats: _formats,
        detectionSpeed: DetectionSpeed.normal,
      );

  /// Re-acquire the camera after an error (e.g. the user granted a permission
  /// they had dismissed). `MobileScanner` only starts its controller in
  /// `initState`, so the fresh controller + `ValueKey(_controller)` forces a new
  /// element that auto-starts.
  void _retry() {
    final old = _controller;
    setState(() {
      _seen.clear();
      _handled = false;
      _controller = _newController();
    });
    unawaited(old?.dispose() ?? Future.value());
  }

  // ── Detection ──────────────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _phase != _Phase.scanning) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) _seen.add(v);
    }
    final parsed = _parseFromSeen();
    if (parsed != null) {
      _handled = true;
      setState(() => _phase = _Phase.processing);
      _finishProcessing(parsed);
    }
  }

  /// Flips the panel into the "analyzing…" state synchronously — fired by the
  /// recent-photos strip the *instant* the user taps, before bytes load. Without
  /// this the mascot doesn't appear until the (~hundreds of ms) thumbnail /
  /// file-picker round-trip completes, which is what felt like a UI freeze.
  void _startProcessing() {
    if (_phase == _Phase.processing) return;
    setState(() {
      _seen.clear();
      _handled = true;
      _phase = _Phase.processing;
    });
  }

  /// Decode a picked / recent photo (or a web capture frame) and process it.
  Future<void> _onPickedBytes(Uint8List bytes) async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    // Make sure the processing overlay is on screen before kicking off decode —
    // covers the camera-frame path where `_startProcessing` wasn't fired by the
    // strip (e.g. WebCameraView's capture button).
    if (_phase != _Phase.processing) _startProcessing();
    // Let Flutter paint the overlay before we start the heavy decode, so the
    // mascot animation actually appears (especially on web, where the decode
    // runs inline and would otherwise block the first frame).
    await Future<void>.delayed(Duration.zero);
    try {
      // Native iOS gets the hardware ML Kit decoder via `analyzeImage` (an
      // order of magnitude faster than the pure-Dart pipeline). If it can't
      // parse — typically because ML Kit only spots one of the dual QRs and
      // we need the overflow too — we fall through to zxing2 to catch the
      // missing half. Web has no `analyzeImage` (project memory), so it stays
      // on the pure-Dart path.
      var parsed = kIsWeb ? null : await _tryAnalyzeImage(bytes);
      if (parsed == null) {
        // Web uses the native browser JPEG decoder + zxing with yields between
        // regions (no real isolate available on web, so this keeps the mascot
        // ticking and the UI responsive instead of locking for ~1 s). Mobile
        // falls back to the sync pure-Dart pipeline inside compute().
        final codes = kIsWeb
            ? await decodeQrCodesFromImageWeb(bytes)
            : await compute(decodeQrCodesFromImage, bytes);
        if (!mounted) return;
        _seen.addAll(codes);
        parsed = _parseFromSeen();
      }
      if (parsed == null) {
        messenger.showSnackBar(SnackBar(content: Text(s.scanFailed)));
        _resumeScanning();
        return;
      }
      await _finishProcessing(parsed);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.scanSaveFailed(e))));
      _resumeScanning();
    }
  }

  /// Fast-path photo decode on iOS: writes [bytes] to a temp JPEG and asks
  /// mobile_scanner's ML Kit reader to find the e-invoice QR. Returns a parsed
  /// invoice when ML Kit found a header that the parser accepts, else null —
  /// callers fall back to the pure-Dart zxing2 pipeline. Best-effort: any
  /// failure (write error, ML Kit exception, missing header) returns null.
  Future<ParsedQrInvoice?> _tryAnalyzeImage(Uint8List bytes) async {
    File? tmp;
    MobileScannerController? scratch;
    try {
      tmp = File(
        '${Directory.systemTemp.path}/einvoice_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes(bytes, flush: false);
      // A scratch controller used only for analyzeImage — never mounted in a
      // MobileScanner widget, so no camera is grabbed.
      scratch = MobileScannerController(formats: _formats);
      final capture = await scratch.analyzeImage(tmp.path);
      if (capture == null) return null;
      for (final b in capture.barcodes) {
        final v = b.rawValue;
        if (v != null && v.isNotEmpty) _seen.add(v);
      }
      return _parseFromSeen();
    } catch (_) {
      return null;
    } finally {
      unawaited(scratch?.dispose() ?? Future.value());
      final f = tmp;
      if (f != null) unawaited(f.delete().catchError((_) => f));
    }
  }

  /// Classifies the values seen so far into the header (left) and overflow
  /// (right) QR, then parses. Returns null until a valid header is in hand.
  ParsedQrInvoice? _parseFromSeen() {
    String? left;
    String? right;
    for (final v in _seen) {
      if (v.startsWith('**')) {
        right ??= v;
      } else if (parseEinvoiceQr(left: v) != null) {
        left ??= v;
      }
    }
    if (left == null) return null;
    return parseEinvoiceQr(left: left, right: right);
  }

  /// Dedup-check, show the review sheet, then return to scanning. Wrapped so a
  /// backend hiccup surfaces as a toast instead of a stuck mascot.
  Future<void> _finishProcessing(ParsedQrInvoice qr) async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final exists = await ref
          .read(einvoiceQrServiceProvider)
          .alreadyExists(qr.invoiceNumber);
      if (!mounted) return;
      if (exists) {
        messenger.showSnackBar(SnackBar(content: Text(s.scanAlreadyAdded)));
        _resumeScanning();
        return;
      }
      final saved = await showScanReviewSheet(context, qr);
      if (!mounted) return;
      if (saved == true) {
        messenger.showSnackBar(SnackBar(content: Text(s.scanSaved)));
      }
      _resumeScanning();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.scanSaveFailed(e))));
      _resumeScanning();
    }
  }

  void _resumeScanning() {
    if (!mounted) return;
    setState(() {
      _seen.clear();
      _handled = false;
      _phase = _Phase.scanning;
    });
  }

  String _errorMessage(AppStrings s, MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => s.scanCameraDenied,
      MobileScannerErrorCode.unsupported => s.scanCameraUnsupported,
      _ => '${s.scanCameraError} (${error.errorCode.name})',
    };
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final processing = _phase == _Phase.processing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // While processing, the camera layer is replaced by a solid black
            // panel — no preview, no "正在開啟相機…" placeholder, no ambiguity
            // about whether the app is still scanning.
            if (processing)
              const ColoredBox(color: Colors.black)
            else
              _cameraLayer(s),
            // Alignment viewfinder + hint over the live preview, so the user
            // knows where to centre the QR. Removed in the processing phase
            // (the reading mascot owns the screen then).
            if (!processing) _ViewfinderFrame(hint: s.hintFor(1)),
            // Recent photos / gallery picker, iPhone-style in the bottom-left.
            // Hidden while reading so the mascot has the floor.
            if (!processing)
              Positioned(
                left: 12,
                bottom: 12,
                child: RecentPhotosStrip(
                  onBytes: _onPickedBytes,
                  onPickStart: _startProcessing,
                  galleryTooltip: s.scanPickPhoto,
                ),
              ),
            if (processing) _ReadingOverlay(label: s.scanReading),
          ],
        ),
      ),
    );
  }

  Widget _cameraLayer(AppStrings s) {
    if (kIsWeb) {
      // Web: mobile_scanner's reader can't read the dual-QR e-invoice, so use a
      // high-res preview with a capture button decoded in pure Dart.
      if (!widget.active || _appPaused) {
        return const ColoredBox(color: Colors.black87);
      }
      return WebCameraView(
        onCapture: _onPickedBytes,
        busy: _phase == _Phase.processing,
        openingText: s.scanCameraOpening,
        captureLabel: s.scanCapture,
        deniedText: s.scanCameraDenied,
        unsupportedText: s.scanCameraUnsupported,
        retryLabel: s.scanRetry,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return _CameraPlaceholder(s.scanCameraOpening);
    }
    return MobileScanner(
      key: ValueKey(controller),
      controller: controller,
      onDetect: _onDetect,
      fit: BoxFit.cover,
      placeholderBuilder: (_) => _CameraPlaceholder(s.scanCameraOpening),
      errorBuilder: (_, error) => _CameraError(
        message: _errorMessage(s, error),
        retryLabel: s.scanRetry,
        onRetry: _retry,
      ),
    );
  }
}

/// Scanning-state alignment overlay: a centred rounded rectangle traced by
/// four butter L-brackets, with the hint string captioned just under it. Gives
/// the user a clear target for the dual e-invoice QRs (~78 % wide, ~52 % tall
/// of the shortest side — wider than tall so the side-by-side codes fit).
class _ViewfinderFrame extends StatelessWidget {
  final String hint;

  const _ViewfinderFrame({required this.hint});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortest = constraints.biggest.shortestSide;
          final w = (shortest * 0.78).clamp(180.0, 360.0);
          final h = (shortest * 0.52).clamp(120.0, 240.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: CustomPaint(
                    painter: _FrameBracketsPainter(),
                  ),
                ),
              ),
              // Hint pinned just below the frame so it reads as a caption.
              Center(
                child: Padding(
                  padding: EdgeInsets.only(top: h + 28),
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xEEFAF5EC),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FrameBracketsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PocketColors.butter
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // L-bracket arms run ~22 % of the side they live on — long enough to read
    // as a frame, short enough to feel like brackets, not a full rectangle.
    final armX = size.width * 0.22;
    final armY = size.height * 0.22;
    const r = 14.0;
    final w = size.width;
    final h = size.height;
    final path = Path()
      // Top-left
      ..moveTo(armX, 0)
      ..lineTo(r, 0)
      ..arcToPoint(Offset(0, r), radius: const Radius.circular(r), clockwise: false)
      ..lineTo(0, armY)
      // Top-right
      ..moveTo(w - armX, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r), clockwise: true)
      ..lineTo(w, armY)
      // Bottom-right
      ..moveTo(w, h - armY)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r), clockwise: true)
      ..lineTo(w - armX, h)
      // Bottom-left
      ..moveTo(armX, h)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r), clockwise: true)
      ..lineTo(0, h - armY);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Reading-state overlay: a centred [ScanningMascot] with a "讀取中…" label.
/// Sits on top of the solid black mask the panel paints during processing — so
/// nothing from the camera layer (preview frames, the "正在開啟相機…"
/// placeholder) shows through, and it's unambiguous that the app has moved on
/// from scanning.
///
/// The mascot is the *only* liveness cue on purpose. An earlier version put a
/// [LinearProgressIndicator] underneath as a backup, but both it and the mascot
/// ride the same frame pipeline, so a single dropped frame froze them together —
/// the bar visibly stalling mid-sweep made the pair read as "synced and stuck".
/// The mascot's own repeating ticker (breathe + wobble + blink + darting eyes)
/// keeps moving for as long as we're processing and hides a brief hitch far
/// better than a bar that stops dead, so it now stands alone.
class _ReadingOverlay extends StatelessWidget {
  final String label;

  const _ReadingOverlay({required this.label});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ScanningMascot(size: 112),
            const SizedBox(height: 24),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown over the viewfinder while the camera is being acquired (loading the
/// barcode library, prompting for permission, opening the stream).
class _CameraPlaceholder extends StatelessWidget {
  final String label;
  const _CameraPlaceholder(this.label);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the camera fails to start, with a retry that re-acquires it —
/// the common path on web after the user grants a previously-denied permission.
class _CameraError extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const _CameraError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
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
              const Icon(Icons.videocam_off_outlined,
                  color: Colors.white70, size: 36),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
