import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth_providers.dart';
import '../../core/settings_provider.dart';
import '../../core/theme.dart';
import '../../widgets/mascots.dart';
import 'google_web_button.dart';

/// Sign-in gate. The only route reachable while signed out; the router redirect
/// in `app_router.dart` sends the user here and whisks them to `/` once a
/// Supabase session exists.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  StreamSubscription<Object>? _errSub;

  @override
  void initState() {
    super.initState();
    _errSub = ref.read(authServiceProvider).errors.listen((err) {
      if (!mounted) return;
      setState(() => _loading = false);
      // In debug builds surface the real error so config issues (Supabase
      // provider / client id / nonce) are diagnosable; release stays generic.
      final message = kDebugMode
          ? '${ref.read(stringsProvider).signInFailed}\n$err'
          : ref.read(stringsProvider).signInFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
      );
    });
  }

  @override
  void dispose() {
    _errSub?.cancel();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    await ref.read(authServiceProvider).signInWithGoogle();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    // On web this is Google's rendered GIS button; elsewhere it's null.
    final Widget? webButton = googleWebButton();

    return Scaffold(
      backgroundColor: PocketColors.board,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
              decoration: BoxDecoration(
                color: PocketColors.card,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CoinMascot(size: 84),
                  const SizedBox(height: 28),
                  _Wordmark(),
                  const SizedBox(height: 14),
                  Text(
                    s.signInTitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: PocketColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.signInSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: PocketColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (webButton != null)
                    SizedBox(height: 44, child: webButton)
                  else
                    _GoogleButton(
                      label: s.signInWithGoogle,
                      loading: _loading,
                      onPressed: _loading ? null : _signIn,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextStyle base(Color c) => GoogleFonts.spaceGrotesk(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: c,
          letterSpacing: -0.5,
        );
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: 'pocket', style: base(PocketColors.ink)),
          TextSpan(text: 'Pilot', style: base(PocketColors.persimmon)),
        ],
      ),
    );
  }
}

/// Native "Continue with Google" button (mobile/desktop). Web uses the GIS
/// rendered button instead.
class _GoogleButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _GoogleButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: PocketColors.ink,
          side: const BorderSide(color: PocketColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleGlyph(),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Minimal multicolour Google "G" so the mobile button reads as Google sign-in
/// without bundling an image asset.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Text(
      'G',
      style: GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: PocketColors.pine,
      ),
    );
  }
}
