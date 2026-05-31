import 'package:flutter/material.dart';

import '../core/theme.dart';

// Geometric mascots inspired by Galas — each has two eyes.
// Coin (阿錢) · Receipt (發票君) · Note (鈔鈔) · QR (掃掃)

// ---------------------------------------------------------------------------
// Shared eye widget
// ---------------------------------------------------------------------------

class _Eye extends StatelessWidget {
  final bool lookAway; // offset pupil diagonally
  final double parentSize;

  const _Eye({this.lookAway = false, required this.parentSize});

  double get _eyeSize  => parentSize * 0.219; // ~21/96
  double get _pupilSize => _eyeSize * 0.381;  // ~8/21

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _eyeSize,
      height: _eyeSize,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Transform.translate(
          offset: lookAway
              ? Offset(_eyeSize * 0.095, _eyeSize * 0.095)
              : Offset.zero,
          child: Container(
            width: _pupilSize,
            height: _pupilSize,
            decoration: const BoxDecoration(
              color: PocketColors.ink,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CoinMascot — circle, persimmon
// ---------------------------------------------------------------------------

class CoinMascot extends StatelessWidget {
  final double size;
  const CoinMascot({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: PocketColors.persimmon,
              shape: BoxShape.circle,
            ),
          ),
          Positioned(
            top: size * 0.354,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Eye(parentSize: size),
                SizedBox(width: size * 0.073),
                _Eye(lookAway: true, parentSize: size),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ReceiptMascot — zigzag-bottom rectangle, pine
// ---------------------------------------------------------------------------

class ReceiptMascot extends StatelessWidget {
  final double size; // height
  const ReceiptMascot({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final w = size * 0.75; // width ≈ 78/104 ratio from design
    return SizedBox(
      width: w,
      height: size,
      child: Stack(
        children: [
          ClipPath(
            clipper: _ReceiptClipper(),
            child: Container(
              width: w,
              height: size,
              color: PocketColors.pine,
            ),
          ),
          Positioned(
            top: size * 0.288,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Eye(lookAway: true, parentSize: size * 0.85),
                SizedBox(width: size * 0.062),
                _Eye(parentSize: size * 0.85),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const r = 10.0;
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, size.height * 0.92);
    // Zigzag bottom — 8 teeth
    final step = size.width / 8;
    for (int i = 8; i >= 1; i--) {
      path.lineTo(i * step - step / 2, size.height);
      path.lineTo((i - 1) * step, size.height * 0.92);
    }
    path
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// ---------------------------------------------------------------------------
// NoteMascot — organic blob, butter
// ---------------------------------------------------------------------------

class NoteMascot extends StatelessWidget {
  final double size; // height
  const NoteMascot({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final w = size * 1.083; // 104/96 ratio
    return SizedBox(
      width: w,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: PocketColors.butter,
              borderRadius: BorderRadius.only(
                topLeft:     Radius.elliptical(w * 0.55, size * 0.52),
                topRight:    Radius.elliptical(w * 0.40, size * 0.48),
                bottomLeft:  Radius.elliptical(w * 0.42, size * 0.50),
                bottomRight: Radius.elliptical(w * 0.52, size * 0.45),
              ),
            ),
          ),
          Positioned(
            top: size * 0.396,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Eye(parentSize: size),
                SizedBox(width: size * 0.073),
                _Eye(parentSize: size),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QRMascot — rounded square, ink
// ---------------------------------------------------------------------------

class QRMascot extends StatelessWidget {
  final double size;
  const QRMascot({super.key, this.size = 92});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: PocketColors.ink,
              borderRadius: BorderRadius.circular(size * 0.196),
            ),
          ),
          Positioned(
            top: size * 0.359,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Eye(lookAway: true, parentSize: size),
                SizedBox(width: size * 0.076),
                _Eye(lookAway: true, parentSize: size),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
