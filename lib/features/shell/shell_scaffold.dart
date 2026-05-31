import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../dashboard/dashboard_screen.dart';
import '../history/history_screen.dart';

/// Top-level scaffold: bottom nav between Dashboard and History, plus a FAB to
/// add a manual invoice.
class ShellScaffold extends StatefulWidget {
  const ShellScaffold({super.key});

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  int _index = 0;
  static const _titles = ['Dashboard', 'History'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync_outlined),
            tooltip: 'Carrier sync',
            onPressed: () => context.push('/carrier'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [DashboardScreen(), HistoryScreen()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
