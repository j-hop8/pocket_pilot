import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../capture/capture_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../history/history_screen.dart';

class ShellScaffold extends StatefulWidget {
  const ShellScaffold({super.key});

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PocketColors.board,
      appBar: AppBar(
        toolbarHeight: 62,
        title: _PocketWordmark(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: PocketColors.line,
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          CaptureScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: PocketColors.line),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首頁',
              ),
              NavigationDestination(
                icon: Icon(Icons.qr_code_scanner_outlined),
                selectedIcon: Icon(Icons.qr_code_scanner),
                label: '掃描',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: '帳本',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PocketWordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Logo from the design guide:
    //   <div class="logo">pocket<b>Pilot</b></div>
    //   <svg class="swoosh" viewBox="0 0 230 14">
    //     <path d="M2 9C40 2 70 12 110 7c45-6 75 4 116-3" stroke="persimmon" …/>
    //   </svg>
    // Both "pocket" and "Pilot" are font-weight 700; only colour differs.
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
        40 * sx,  2 * sy,   // cp1
        70 * sx,  12 * sy,  // cp2
        110 * sx, 7 * sy,   // end
      )
      ..relativeCubicTo(
        45 * sx,  -6 * sy,  // cp1
        75 * sx,  4 * sy,   // cp2
        116 * sx, -3 * sy,  // end
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = PocketColors.persimmon
        ..strokeWidth = 3.5 * sy / 1 // maintain stroke weight ratio
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
