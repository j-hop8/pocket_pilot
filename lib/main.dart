import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth_providers.dart';
import 'core/auth_service.dart';

/// Entry point. Supabase credentials are injected at build time via
/// `--dart-define-from-file=dart_defines.json` (gitignored). The anon key is
/// publishable; the Gemini key is never bundled (Phase 3 Edge Function).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isEmpty || anonKey.isEmpty) {
    runApp(const NotConfiguredApp());
    return;
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  // Build + initialize the Google→Supabase auth bridge before the app renders,
  // so the login screen can show the web GIS button immediately. A bad/missing
  // client id must not crash startup — failures surface on the sign-in attempt.
  const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  final authService = AuthService(
    webClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    iosClientId: iosClientId.isEmpty ? null : iosClientId,
  );
  try {
    await authService.initialize();
  } catch (e) {
    debugPrint('Google sign-in init failed: $e');
  }

  runApp(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(authService)],
      child: const PocketPilotApp(),
    ),
  );
}

/// Shown when SUPABASE_URL / SUPABASE_ANON_KEY were not provided at build time.
class NotConfiguredApp extends StatelessWidget {
  const NotConfiguredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.settings_suggest, size: 48),
                SizedBox(height: 16),
                Text(
                  'Supabase not configured',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Run with:\nflutter run -d chrome '
                  '--dart-define-from-file=dart_defines.json\n\n'
                  'See dart_defines.example.json.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
