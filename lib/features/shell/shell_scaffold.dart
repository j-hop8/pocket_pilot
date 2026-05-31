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
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'pocket',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w500,
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
    );
  }
}
