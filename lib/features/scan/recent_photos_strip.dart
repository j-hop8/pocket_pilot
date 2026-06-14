import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// An iPhone-camera-style strip of the most recent photos, pinned to the corner
/// of the scanner. Tapping a thumbnail hands a downsized JPEG to [onBytes]
/// (decoded by the panel like any picked photo); a trailing button opens the
/// full system picker.
///
/// On web — or when photo-library access is denied — there are no thumbnails, so
/// it degrades to just the picker button (which uses `file_picker`, the path
/// that already works everywhere).
///
/// [onPickStart] fires *synchronously* the moment a **recent-photo thumbnail**
/// is tapped, before its bytes load — the panel uses it to flash up the
/// "analyzing…" mascot immediately instead of waiting for the (~hundreds-of-ms)
/// thumbnail load. It is deliberately *not* fired for the system folder picker,
/// whose OS panel takes over the screen until the user has chosen a file.
class RecentPhotosStrip extends StatefulWidget {
  final ValueChanged<Uint8List> onBytes;
  final VoidCallback? onPickStart;
  final String galleryTooltip;

  const RecentPhotosStrip({
    super.key,
    required this.onBytes,
    required this.galleryTooltip,
    this.onPickStart,
  });

  @override
  State<RecentPhotosStrip> createState() => _RecentPhotosStripState();
}

class _RecentPhotosStripState extends State<RecentPhotosStrip> {
  static const _count = 5;
  static const _thumbSize = 52.0;

  List<AssetEntity> _assets = const [];
  bool _busy = false; // guards against a double-tap while bytes load

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) return; // strip stays picker-only
      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
      );
      if (paths.isEmpty) return;
      final assets =
          await paths.first.getAssetListPaged(page: 0, size: _count);
      if (!mounted) return;
      setState(() => _assets = assets);
    } catch (_) {
      // No access / unsupported — leave the picker button as the only option.
    }
  }

  Future<void> _pickFromAsset(AssetEntity asset) async {
    if (_busy) return;
    _busy = true;
    widget.onPickStart?.call();
    try {
      // 640 px is the smallest size that still reliably decodes a typical
      // receipt photograph: even with the dual QRs occupying just the lower
      // third of the frame, each QR ends up ~70 px wide → ~3 px per module,
      // which zxing2's tryHarder + the dual-binarizer fallback can read. iOS
      // hands the resize off to the Photos framework, so loading 640 px is
      // dramatically cheaper than 1024 px (and an order of magnitude faster
      // than the ~4K original we started with).
      final bytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize.square(640),
        quality: 75,
      );
      if (bytes != null) widget.onBytes(bytes);
    } finally {
      _busy = false;
    }
  }

  Future<void> _pickFromSystem() async {
    if (_busy) return;
    _busy = true;
    // NOTE: unlike the recent-photo thumbnails, we do *not* fire `onPickStart`
    // here — the OS folder picker owns the screen next, and flashing the reading
    // mascot behind it looks like the app is busy when it's really just waiting
    // on the user. The panel flips to the mascot in `_onPickedBytes`, the
    // instant bytes come back and real decoding starts.
    try {
      // withData so bytes are populated on every platform (web has no `path`).
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      final bytes = result?.files.single.bytes;
      if (bytes != null) widget.onBytes(bytes);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final asset in _assets) ...[
            _Thumb(asset: asset, size: _thumbSize, onTap: () => _pickFromAsset(asset)),
            const SizedBox(width: 6),
          ],
          _GalleryButton(size: _thumbSize, tooltip: widget.galleryTooltip, onTap: _pickFromSystem),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final AssetEntity asset;
  final double size;
  final VoidCallback onTap;

  const _Thumb({required this.asset, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize.square(160)),
            builder: (context, snap) {
              final bytes = snap.data;
              if (bytes == null) {
                return Container(color: Colors.white.withValues(alpha: 0.12));
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          ),
        ),
      ),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  final double size;
  final String tooltip;
  final VoidCallback onTap;

  const _GalleryButton({required this.size, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
