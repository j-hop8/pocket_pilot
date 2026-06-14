import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/mascots.dart';
import 'recent_photos_strip.dart';
import 'scan_decoder.dart';
import 'scan_queue.dart';
import 'web_camera_view.dart';

/// The e-invoice tab body. On entry it shows a chooser with two options —
/// **open the camera** or **pick from folder** — instead of grabbing the camera
/// the moment the tab appears.
///
/// Choosing the camera turns it on and continuously hunts for the QR, iPhone-
/// camera style: the instant a receipt is in hand it is **handed to the
/// background scan queue** (no blocking, no per-receipt sheet) and a brief "已加入"
/// flash confirms it — the camera keeps running so the user can capture receipts
/// one after another. Choosing "pick from folder" opens the system file picker,
/// which can select several receipts at once, and stays on the chooser.
/// Decoding + saving happen in the background; the global [ScanProgressOverlay]
/// shows the per-receipt progress.
///
/// While the camera is live a recent-photos strip sits in the bottom-left for
/// picking an existing photo, and a back button returns to the chooser.
///
/// The camera is released whenever the tab is left or the app is backgrounded —
/// the Add tab lives in an `IndexedStack`, so we must not hold it open offstage —
/// and the panel falls back to the chooser when the tab is left.
class EInvoiceScanPanel extends ConsumerStatefulWidget {
  /// True when this tab is the one the user is looking at (Add tab + e-invoice
  /// sub-tab). Drives whether the camera runs.
  final bool active;

  const EInvoiceScanPanel({super.key, required this.active});

  @override
  ConsumerState<EInvoiceScanPanel> createState() => _EInvoiceScanPanelState();
}

/// What the panel is currently showing: the entry chooser, or the live camera.
enum _ScanMode { chooser, camera }

class _EInvoiceScanPanelState extends ConsumerState<EInvoiceScanPanel>
    with WidgetsBindingObserver {
  static const _formats = [BarcodeFormat.qrCode];

  _ScanMode _mode = _ScanMode.chooser;
  MobileScannerController? _controller;
  final _seen = <String>{};
  // Invoice numbers already handed to the queue this camera session, so the
  // continuous detection stream doesn't enqueue the same receipt every frame.
  final _enqueued = <String>{};
  bool _appPaused = false;
  bool _flash = false; // brief "已加入" confirmation after queueing
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncCamera();
  }

  @override
  void didUpdateWidget(covariant EInvoiceScanPanel old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      setState(() {
        // Leaving the tab drops back to the chooser, so re-entering always
        // offers the choice again rather than silently re-opening the camera.
        if (!widget.active) _mode = _ScanMode.chooser;
        _syncCamera();
      });
    }
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
    _flashTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// Whether a live mobile camera should be running right now. The camera keeps
  /// running during processing too, so the user sees the preview behind the
  /// detection overlay instead of cutting to a black screen.
  bool get _wantCamera =>
      widget.active && _mode == _ScanMode.camera && !_appPaused && !kIsWeb;

  /// Reconciles the controller with [_wantCamera]: create one when the camera
  /// should run, dispose it the moment it shouldn't. Call inside `setState`.
  void _syncCamera() {
    if (_wantCamera && _controller == null) {
      _seen.clear();
      _enqueued.clear();
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
      _enqueued.clear();
      _controller = _newController();
    });
    unawaited(old?.dispose() ?? Future.value());
  }

  // ── Detection ──────────────────────────────────────────────────────────────

  /// Live-camera frame: accumulate QR payloads and, once a receipt parses, hand
  /// it to the background queue (skipping any receipt already queued this
  /// session) and keep scanning for the next one.
  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) _seen.add(v);
    }
    final parsed = parseInvoiceFromCodes(_seen);
    if (parsed == null) return;
    // Reset the buffer so the next receipt starts clean and we don't mix one
    // receipt's header with another's overflow QR.
    _seen.clear();
    if (!_enqueued.add(parsed.invoiceNumber)) return; // already queued
    ref.read(scanQueueProvider.notifier).enqueueParsed(parsed);
    _showFlash();
  }

  /// Queue picked / recent / web-capture photos for background decode + save.
  void _enqueueImages(List<Uint8List> images) {
    if (images.isEmpty) return;
    ref.read(scanQueueProvider.notifier).enqueueImages(images);
    _showFlash();
  }

  // ── Mode switching ─────────────────────────────────────────────────────────

  /// Chooser → live camera (acquires the controller via [_syncCamera]).
  void _openCamera() => setState(() {
        _mode = _ScanMode.camera;
        _syncCamera();
      });

  /// Live camera → chooser (releases the controller via [_syncCamera]).
  void _closeCamera() => setState(() {
        _mode = _ScanMode.chooser;
        _syncCamera();
      });

  /// "Pick from folder": open the system picker and queue whatever it returns,
  /// staying on the chooser. `allowMultiple` lets the user grab a stack of
  /// receipts at once; `withData` populates bytes on every platform (web has no
  /// file path).
  Future<void> _pickFromFolder() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result == null) return;
    _enqueueImages([
      for (final f in result.files)
        if (f.bytes != null) f.bytes!,
    ]);
  }

  /// Briefly show the "已加入" confirmation over the live preview.
  void _showFlash() {
    _flashTimer?.cancel();
    setState(() => _flash = true);
    _flashTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _flash = false);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: _mode == _ScanMode.chooser
            ? _ScanChooser(
                title: s.scanChooseTitle,
                cameraLabel: s.scanOpenCamera,
                folderLabel: s.scanPickFromFolder,
                hint: s.hintFor(1),
                onCamera: _openCamera,
                onPickFolder: _pickFromFolder,
              )
            : _cameraView(s),
      ),
    );
  }

  Widget _cameraView(AppStrings s) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _cameraLayer(s),
        // Alignment viewfinder + hint over the live preview, so the user
        // knows where to centre the QR.
        _ViewfinderFrame(hint: s.hintFor(1)),
        // Back to the chooser, iPhone-style in the top-left.
        Positioned(
          top: 12,
          left: 12,
          child: _BackButton(onTap: _closeCamera),
        ),
        // Recent photos / gallery picker, iPhone-style in the bottom-left.
        // The camera never blocks now, so the strip is always available.
        Positioned(
          left: 12,
          bottom: 12,
          child: RecentPhotosStrip(onImages: _enqueueImages),
        ),
        // Brief, non-blocking "已加入" confirmation after a receipt is queued.
        if (_flash) _AddedFlash(label: s.scanAdded),
      ],
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
        onCapture: (bytes) async => _enqueueImages([bytes]),
        // Briefly disable the capture button during the flash to debounce
        // double-taps; otherwise it stays ready for the next receipt.
        busy: _flash,
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

/// The entry screen for the e-invoice tab: a dark viewfinder-style backdrop with
/// the QR mascot and the two ways in — open the live camera, or pick image files
/// from the device. Mirrors the receipt tab's [_Viewfinder] look so the Add tab
/// feels of a piece.
class _ScanChooser extends StatelessWidget {
  final String title;
  final String cameraLabel;
  final String folderLabel;
  final String hint;
  final VoidCallback onCamera;
  final VoidCallback onPickFolder;

  const _ScanChooser({
    required this.title,
    required this.cameraLabel,
    required this.folderLabel,
    required this.hint,
    required this.onCamera,
    required this.onPickFolder,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF23211D), Color(0xFF33302A)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const QRMascot(size: 84),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: PocketColors.paper,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceMono(
                fontSize: 12,
                color: const Color(0xAAFAF5EC),
              ),
            ),
            const SizedBox(height: 28),
            _ChooserButton(
              icon: Icons.photo_camera_rounded,
              label: cameraLabel,
              filled: true,
              onTap: onCamera,
            ),
            const SizedBox(height: 12),
            _ChooserButton(
              icon: Icons.folder_open_rounded,
              label: folderLabel,
              filled: false,
              onTap: onPickFolder,
            ),
          ],
        ),
      ),
    );
  }
}

/// One option pill in the [_ScanChooser]. The primary action ([filled]) is the
/// persimmon CTA; the secondary is an outlined butter pill.
class _ChooserButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ChooserButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? PocketColors.paper : PocketColors.butter;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: filled ? PocketColors.persimmon : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: filled
              ? null
              : Border.all(color: PocketColors.butter.withValues(alpha: 0.7)),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: PocketColors.persimmon.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.spaceMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular translucent back chip that returns the camera view to the chooser.
class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
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

/// Brief, non-blocking confirmation badge shown over the live preview the moment
/// a receipt is handed to the background queue. Unlike the old reading overlay it
/// does not mask the camera — scanning continues underneath so the user can line
/// up the next receipt immediately. The actual decode/save progress lives in the
/// global [ScanProgressOverlay].
class _AddedFlash extends StatelessWidget {
  final String label;

  const _AddedFlash({required this.label});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
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
