import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

/// The shared entry card for the two camera-style Add sub-tabs (e-invoice and
/// receipt): a dark, rounded panel with a mascot, a title + hint, and one or
/// more action pills. Both tabs render this identically so the Add tab feels of
/// a piece.
///
/// The card's width is **pinned** (filling the available width up to
/// [_maxWidth]) rather than shrink-wrapped to its content. That's deliberate:
/// the old per-tab cards each hugged their own content, so the receipt card —
/// with a longer hint and a wide recent-photos strip — came out noticeably
/// wider than the e-invoice card. Pinning the width keeps the two cards exactly
/// the same size regardless of how long each tab's hint is or whether a [footer]
/// is present.
class ScanSourceChooser extends StatelessWidget {
  /// The tab's mascot, drawn at the top of the card.
  final Widget mascot;
  final String title;
  final String hint;

  /// The action pills (typically [ScanChooserButton]s), stacked with 12 px gaps.
  final List<Widget> actions;

  /// Optional extra below the actions (e.g. the receipt tab's recent-photos
  /// strip). Adds height only — it never widens the card.
  final Widget? footer;

  const ScanSourceChooser({
    super.key,
    required this.mascot,
    required this.title,
    required this.hint,
    required this.actions,
    this.footer,
  });

  /// The widest the card grows on roomy screens; below this it fills the
  /// available width. Shared by both tabs, so their cards always match.
  static const _maxWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite
            ? math.min(constraints.maxWidth, _maxWidth)
            : _maxWidth;
        return Center(
          child: SizedBox(
            width: w,
            height: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
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
                    mascot,
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
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      actions[i],
                    ],
                    if (footer != null) ...[
                      const SizedBox(height: 24),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One option pill in a [ScanSourceChooser]. The primary action ([filled]) is
/// the persimmon CTA; the secondary is an outlined butter pill. A null [onTap]
/// renders it disabled (dimmed and non-interactive).
class ScanChooserButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  const ScanChooserButton({
    super.key,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? PocketColors.paper : PocketColors.butter;
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: GestureDetector(
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
      ),
    );
  }
}
