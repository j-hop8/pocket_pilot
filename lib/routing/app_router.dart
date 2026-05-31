import 'package:go_router/go_router.dart';

import '../features/carrier_sync/carrier_sync_screen.dart';
import '../features/history/invoice_detail_screen.dart';
import '../features/manual_entry/manual_entry_screen.dart';
import '../features/shell/shell_scaffold.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ShellScaffold(),
    ),
    GoRoute(
      path: '/add',
      builder: (context, state) => const ManualEntryScreen(),
    ),
    GoRoute(
      path: '/carrier',
      builder: (context, state) => const CarrierSyncScreen(),
    ),
    GoRoute(
      path: '/invoice/:id',
      builder: (context, state) =>
          InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
    ),
  ],
);
