import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Non-web stub. The web capture flow ([WebCameraView]) is only constructed
/// behind `kIsWeb`, so this is never built on mobile — it exists so the import
/// resolves and the signatures match the web implementation.
class WebCameraView extends StatelessWidget {
  final Future<void> Function(Uint8List frame) onCapture;
  final bool busy;
  final String openingText;
  final String captureLabel;
  final String deniedText;
  final String unsupportedText;
  final String retryLabel;
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
