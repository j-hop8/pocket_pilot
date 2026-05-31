import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import 'mascots.dart';

class EmptyState extends StatelessWidget {
  final IconData? icon; // unused visually — kept for call-site compat
  final String title;
  final String? subtitle;
  final Widget? mascot; // preferred over icon

  const EmptyState({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.mascot,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            mascot ?? const CoinMascot(size: 80),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: PocketColors.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceMono(
                  fontSize: 11,
                  color: PocketColors.inkSoft,
                  letterSpacing: 0.04,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
