import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../core/supabase.dart';
import '../features/auth/login_screen.dart';
import '../features/budget/budget_management_screen.dart';
import '../features/carrier_sync/carrier_sync_screen.dart';
import '../features/categories/category_management_screen.dart';
import '../features/history/invoice_detail_screen.dart';
import '../features/manual_entry/manual_entry_screen.dart';
import '../features/shell/shell_scaffold.dart';
import '../models/invoice.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  // Re-evaluate `redirect` whenever the Supabase auth state changes.
  refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),
  redirect: (context, state) {
    final signedIn = supabase.auth.currentSession != null;
    final loggingIn = state.matchedLocation == '/login';
    if (!signedIn) return loggingIn ? null : '/login';
    if (loggingIn) return '/';
    // Demo (anonymous) users have no carrier credentials and can't sync; keep
    // them out of /carrier even via deep link / hot-reload landing.
    final isDemo = supabase.auth.currentUser?.isAnonymous ?? false;
    if (isDemo && state.matchedLocation == '/carrier') return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
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
      path: '/categories',
      builder: (context, state) => const CategoryManagementScreen(),
    ),
    GoRoute(
      path: '/budgets',
      builder: (context, state) => const BudgetManagementScreen(),
    ),
    GoRoute(
      path: '/invoice/:id',
      builder: (context, state) =>
          InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
    ),
    GoRoute(
      // Full edit of a user-originated invoice. The invoice to edit is passed
      // via `extra` (the detail screen already has it loaded).
      path: '/invoice/:id/edit',
      builder: (context, state) =>
          ManualEntryScreen(existing: state.extra as Invoice),
    ),
  ],
);

/// Adapts a [Stream] to a [Listenable] so GoRouter re-runs `redirect` on each
/// emission. Standard go_router recipe for auth-driven redirects.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription =
        stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
