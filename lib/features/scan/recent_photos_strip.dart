import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// An iPhone-camera-style strip of the most recent photos, pinned to the corner
/// of the scanner. Tapping a thumbnail hands a downsized JPEG to [onImages]
/// (queued for background decode like any picked photo) — a quick one-tap for a
/// receipt you just photographed. Browsing the full library lives on the scan
/// chooser's "pick from folder", so the strip doesn't repeat it.
///
/// On web — or when photo-library access is denied — there are no thumbnails, so
/// the strip renders nothing.
class RecentPhotosStrip extends StatefulWidget {
  /// Receives the single image picked by a thumbnail tap. The panel enqueues it
  /// on the background queue.
  final ValueChanged<List<Uint8List>> onImages;

  const RecentPhotosStrip({
    super.key,
    required this.onImages,
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
      if (bytes != null) widget.onImages([bytes]);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // No recent thumbnails (web, denied access, or empty library) → no strip.
    if (_assets.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _assets.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _Thumb(
              asset: _assets[i],
              size: _thumbSize,
              onTap: () => _pickFromAsset(_assets[i]),
            ),
          ],
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

