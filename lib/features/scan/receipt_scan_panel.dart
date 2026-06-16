import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../widgets/mascots.dart';
import 'recent_photos_strip.dart';
import 'scan_queue.dart';
import 'scan_source_chooser.dart';
import 'web_camera_view.dart';

/// The receipt tab body. Mirrors the e-invoice tab's chooser layout (via the
/// shared [ScanSourceChooser]) so the two Add sub-tabs look identical: a mascot,
/// a title + hint, and two ways to hand a photo to the background OCR queue —
/// **take a photo** or **pick from folder** (one or more images). Each picked
/// image goes to [ScanQueue.enqueueReceiptImages], where it's sent to Gemini,
/// extracted and auto-saved as an editable `ocr` invoice; the global
/// [ScanProgressOverlay] shows per-receipt progress.
///
/// "Take photo" opens a real camera, not a file dialog:
///  * On **mobile** it uses the system camera ([ImagePicker], a single still).
///  * On the **web** `image_picker`'s camera source silently falls back to a
///    file picker — the same as "pick from folder" — so we instead open a live
///    [WebCameraView] with a capture button, exactly like the e-invoice tab.
///
/// On mobile a recent-photos strip under the buttons offers a one-tap shortcut
/// for a receipt just photographed.
class ReceiptScanPanel extends ConsumerStatefulWidget {
  /// True when this tab is the one the user is looking at (Add tab + receipt
  /// sub-tab). Gates the recent-photos strip so its permission prompt only fires
  /// while the tab is actually showing.
  final bool active;

  const ReceiptScanPanel({super.key, required this.active});

  @override
  ConsumerState<ReceiptScanPanel> createState() => _ReceiptScanPanelState();
}

class _ReceiptScanPanelState extends ConsumerState<ReceiptScanPanel> {
  final _picker = ImagePicker();
  bool _busy = false; // guards against a double-tap while the camera/picker opens
  bool _webCamera = false; // web only: showing the live capture view

  @override
  void didUpdateWidget(covariant ReceiptScanPanel old) {
    super.didUpdateWidget(old);
    // Leaving the tab drops the live capture view back to the chooser, which
    // unmounts WebCameraView and releases the webcam — we must not hold it open
    // while the Add tab is offstage in the bottom-nav IndexedStack.
    if (old.active && !widget.active && _webCamera) {
      setState(() => _webCamera = false);
    }
  }

  /// Hand picked images to the background queue and confirm briefly.
  void _enqueue(List<Uint8List> images) {
    if (images.isEmpty) return;
    ref.read(scanQueueProvider.notifier).enqueueReceiptImages(images);
    final s = ref.read(stringsProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s.scanAdded),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// "Take photo". On the web open the live capture view (a real camera);
  /// elsewhere open the system camera for a single still, downscaled enough to
  /// upload quickly while staying legible for OCR.
  Future<void> _takePhoto() async {
    if (kIsWeb) {
      setState(() => _webCamera = true);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      _enqueue([await file.readAsBytes()]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Pick from folder": the system picker, multi-select; `withData` populates
  /// bytes on every platform (web has no file path).
  Future<void> _pickFromFolder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: true,
      );
      if (result == null) return;
      _enqueue([
        for (final f in result.files)
          if (f.bytes != null) f.bytes!,
      ]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: _webCamera
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _cameraView(s),
            )
          : ScanSourceChooser(
              mascot: const ReceiptMascot(size: 84),
              title: s.scanReceiptChooseTitle,
              hint: s.scanReceiptHint,
              actions: [
                ScanChooserButton(
                  icon: Icons.photo_camera_rounded,
                  label: s.scanTakePhoto,
                  filled: true,
                  onTap: _busy ? null : _takePhoto,
                ),
                ScanChooserButton(
                  icon: Icons.folder_open_rounded,
                  label: s.scanPickFromFolder,
                  filled: false,
                  onTap: _busy ? null : _pickFromFolder,
                ),
              ],
              // Recent-photos quick-pick (mobile only; renders nothing on web or
              // when library access is denied). Scrollable so its row of
              // thumbnails never overflows the card on a narrow phone.
              footer: widget.active && !kIsWeb
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: RecentPhotosStrip(onImages: _enqueue),
                    )
                  : null,
            ),
    );
  }

  /// Web-only live capture: a `getUserMedia` preview with a capture button. A
  /// snapshot is queued for OCR and we drop back to the chooser. A back chip in
  /// the corner returns without capturing.
  Widget _cameraView(AppStrings s) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebCameraView(
          onCapture: (bytes) async {
            _enqueue([bytes]);
            if (mounted) setState(() => _webCamera = false);
          },
          busy: false,
          captureIcon: Icons.photo_camera_rounded,
          openingText: s.scanCameraOpening,
          captureLabel: s.scanCapture,
          deniedText: s.scanCameraDenied,
          unsupportedText: s.scanCameraUnsupported,
          retryLabel: s.scanRetry,
        ),
        Positioned(
          top: 12,
          left: 12,
          child: _BackButton(onTap: () => setState(() => _webCamera = false)),
        ),
      ],
    );
  }
}

/// Circular translucent back chip that returns the capture view to the chooser.
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
        child:
            const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
