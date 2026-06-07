import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase.dart';

/// Singleton auth bridge. Client ids are injected at build time via
/// `--dart-define-from-file=dart_defines.json`. In [main] this provider is
/// overridden with an already-[AuthService.initialize]d instance.
final authServiceProvider = Provider<AuthService>((ref) {
  const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  final svc = AuthService(
    webClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    iosClientId: iosClientId.isEmpty ? null : iosClientId,
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Emits on every Supabase auth change (sign-in, sign-out, token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// The currently signed-in user, or null. Recomputed on each auth change.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return supabase.auth.currentUser;
});
