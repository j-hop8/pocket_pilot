import 'package:flutter/material.dart';

/// Distinguishes how an invoice was captured (spec D1-05).
class SourceIcon extends StatelessWidget {
  final String source;
  final double size;

  const SourceIcon({super.key, required this.source, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final (icon, tooltip) = switch (source) {
      'carrier' => (Icons.sync, 'Carrier sync'),
      'qr_scan' => (Icons.qr_code_2, 'QR scan'),
      'ocr' => (Icons.document_scanner, 'OCR scan'),
      'manual' => (Icons.edit_note, 'Manual entry'),
      _ => (Icons.receipt_long, source),
    };
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: size, color: Colors.grey.shade600),
    );
  }
}
