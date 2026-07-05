import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/strings.dart';
import '../../models/trip.dart';
import 'scan_queue.dart';

enum _Source { camera, folder }

/// Bottom-sheet entry point to scan a receipt straight into [trip]: take a photo
/// or pick one/more image files, then hand them to the background OCR queue with
/// the trip forced on (so the saved receipt lands under this trip regardless of
/// its date). Mirrors [ReceiptScanPanel]'s picking; progress shows in the global
/// ScanProgressOverlay and the trip list refreshes when each receipt is saved.
Future<void> scanReceiptForTrip(
  BuildContext context,
  WidgetRef ref,
  Trip trip,
  AppStrings s,
) async {
  final source = await showModalBottomSheet<_Source>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                s.scanReceiptChooseTitle,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: Text(s.scanTakePhoto),
            onTap: () => Navigator.pop(ctx, _Source.camera),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(s.scanPickFromFolder),
            onTap: () => Navigator.pop(ctx, _Source.folder),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return;

  final images = <Uint8List>[];
  if (source == _Source.camera) {
    // On web image_picker's camera source falls back to a file dialog — fine for
    // this secondary entry point (the Add tab has the full live web camera).
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file != null) images.add(await file.readAsBytes());
  } else {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result != null) {
      for (final f in result.files) {
        if (f.bytes != null) images.add(f.bytes!);
      }
    }
  }
  if (images.isEmpty) return;

  ref.read(scanQueueProvider.notifier).enqueueReceiptImages(images, trip: trip);
  if (context.mounted) {
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
}
