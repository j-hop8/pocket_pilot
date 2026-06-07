import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/settings_provider.dart';
import '../../core/theme.dart';
import '../../widgets/mascots.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  int _sourceIndex = 1; // 0 = manual, 1 = e-invoice QR, 2 = receipt

  Widget get _mascot => switch (_sourceIndex) {
    2 => const ReceiptMascot(size: 80),
    _ => const QRMascot(size: 80),
  };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final isManual = _sourceIndex == 0;

    return Column(
      children: [
        _SourceTabs(
          selected: _sourceIndex,
          labels: [s.tabManual, s.tabEInvoice, s.tabReceipt],
          onSelect: (i) => setState(() => _sourceIndex = i),
        ),
        if (isManual)
          Expanded(
            child: _ManualPanel(
              title: s.manualPanelTitle,
              hint: s.manualPanelHint,
              addLabel: s.addInvoice,
              onAdd: () => context.push('/add'),
            ),
          )
        else ...[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: _Viewfinder(
                mascot: _mascot,
                hint: s.hintFor(_sourceIndex),
              ),
            ),
          ),
          const _BottomSheet(),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ManualPanel extends StatelessWidget {
  final String title;
  final String hint;
  final String addLabel;
  final VoidCallback onAdd;

  const _ManualPanel({
    required this.title,
    required this.hint,
    required this.addLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          decoration: BoxDecoration(
            color: PocketColors.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NoteMascot(size: 88),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: PocketColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceMono(
                  fontSize: 12,
                  color: PocketColors.inkSoft,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: PocketColors.persimmon,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: PocketColors.persimmon.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    '✏️  $addLabel',
                    style: GoogleFonts.spaceMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: PocketColors.paper,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SourceTabs extends StatelessWidget {
  final int selected;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  const _SourceTabs({
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? PocketColors.ink : PocketColors.paper2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labels[i],
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: active ? PocketColors.paper : PocketColors.inkSoft,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  final Widget mascot;
  final String hint;

  const _Viewfinder({required this.mascot, required this.hint});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF23211D), Color(0xFF33302A)],
              ),
            ),
          ),
          const _CornerBracket(corner: _Corner.tl),
          const _CornerBracket(corner: _Corner.tr),
          const _CornerBracket(corner: _Corner.bl),
          const _CornerBracket(corner: _Corner.br),
          Center(child: mascot),
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xAAFAF5EC),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Corner { tl, tr, bl, br }

class _CornerBracket extends StatelessWidget {
  final _Corner corner;
  const _CornerBracket({required this.corner});

  @override
  Widget build(BuildContext context) {
    const pad = 20.0;
    const size = 28.0;
    double? top, bottom, left, right;
    switch (corner) {
      case _Corner.tl: top    = pad; left  = pad; break;
      case _Corner.tr: top    = pad; right = pad; break;
      case _Corner.bl: bottom = pad; left  = pad; break;
      case _Corner.br: bottom = pad; right = pad; break;
    }
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: CustomPaint(
        size: const Size(size, size),
        painter: _BracketPainter(corner: corner),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final _Corner corner;
  const _BracketPainter({required this.corner});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PocketColors.butter
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const r = 8.0;
    final w = size.width;
    final h = size.height;

    final path = Path();
    switch (corner) {
      case _Corner.tl:
        path
          ..moveTo(w, 0)
          ..lineTo(r, 0)
          ..arcToPoint(Offset(0, r), radius: const Radius.circular(r), clockwise: true)
          ..lineTo(0, h);
      case _Corner.tr:
        path
          ..moveTo(0, 0)
          ..lineTo(w - r, 0)
          ..arcToPoint(Offset(w, r), radius: const Radius.circular(r), clockwise: false)
          ..lineTo(w, h);
      case _Corner.bl:
        path
          ..moveTo(0, 0)
          ..lineTo(0, h - r)
          ..arcToPoint(Offset(r, h), radius: const Radius.circular(r), clockwise: false)
          ..lineTo(w, h);
      case _Corner.br:
        path
          ..moveTo(w, 0)
          ..lineTo(w, h - r)
          ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r), clockwise: true)
          ..lineTo(0, h);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: PocketColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: PocketColors.persimmon,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: PocketColors.persimmon.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
