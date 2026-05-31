import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/settings_provider.dart';
import '../../core/theme.dart';
import '../capture/capture_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';

class ShellScaffold extends ConsumerStatefulWidget {
  const ShellScaffold({super.key});

  @override
  ConsumerState<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<ShellScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);

    return Scaffold(
      backgroundColor: PocketColors.board,
      appBar: AppBar(
        toolbarHeight: 62,
        title: const _PocketWordmark(),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync_outlined),
            tooltip: 'Carrier sync',
            onPressed: () => context.push('/carrier'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: PocketColors.line),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          CaptureScreen(),
          HistoryScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: PocketColors.line),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: s.navHome,
              ),
              NavigationDestination(
                icon: const Icon(Icons.qr_code_scanner_outlined),
                selectedIcon: const Icon(Icons.qr_code_scanner),
                label: s.navCapture,
              ),
              NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long_rounded),
                label: s.navHistory,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings_rounded),
                label: s.navSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PocketWordmark extends StatelessWidget {
  const _PocketWordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'pocket',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: PocketColors.ink,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'Pilot',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: PocketColors.persimmon,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        CustomPaint(
          size: const Size(118, 7),
          painter: _SwooshPainter(),
        ),
      ],
    );
  }
}

// Replicates the SVG path from the design guide:
// M2 9 C40 2, 70 12, 110 7  c45 -6, 75 4, 116 -3
// Original viewBox 230×14, scaled down to 118×7.
class _SwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 230;
    final sy = size.height / 14;

    final path = Path()
      ..moveTo(2 * sx, 9 * sy)
      ..cubicTo(
        40 * sx,  2 * sy,
        70 * sx,  12 * sy,
        110 * sx, 7 * sy,
      )
      ..relativeCubicTo(
        45 * sx,  -6 * sy,
        75 * sx,  4 * sy,
        116 * sx, -3 * sy,
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = PocketColors.persimmon
        ..strokeWidth = 3.5 * sy / 1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
