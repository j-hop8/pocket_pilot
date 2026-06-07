import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

/// Bridges the native Google account picker (`google_sign_in`) to a Supabase
/// session.
///
/// `google_sign_in` is only the credential provider: it yields a Google **ID
/// token**, which we exchange for a real Supabase session via
/// [GoTrueClient.signInWithIdToken]. That session is what makes per-user RLS
/// (`auth.uid()`) work, and `supabase_flutter` persists it across restarts, so
/// returning users skip the login screen.
///
/// Every sign-in — the web GIS button *and* mobile [GoogleSignIn.authenticate] —
/// funnels through [GoogleSignIn.authenticationEvents], so the token exchange
/// lives in exactly one place ([_handleEvent]).
class AuthService {
  AuthService({required this.webClientId, this.iosClientId});

  /// Google Cloud **Web** OAuth client id. Used directly on web, and as the
  /// `serverClientId` (token audience) on Android/iOS.
  final String webClientId;

  /// Google Cloud **iOS** OAuth client id. Required only on iOS.
  final String? iosClientId;

  final GoogleSignIn _google = GoogleSignIn.instance;
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _eventSub;
  bool _initialized = false;

  /// Sign-in failures (Google SDK or Supabase token exchange). The login screen
  /// listens to surface them. User cancellations are intentionally not emitted.
  Stream<Object> get errors => _errors.stream;

  /// Initializes the Google SDK and starts listening for sign-in events. Safe to
  /// call repeatedly. Must complete before the login screen renders the web
  /// button.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    await _google.initialize(
      clientId: kIsWeb ? webClientId : (isIOS ? iosClientId : null),
      serverClientId: kIsWeb ? null : webClientId,
    );

    _eventSub = _google.authenticationEvents.listen(
      _handleEvent,
      onError: _errors.add,
    );
  }

  Future<void> _handleEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is! GoogleSignInAuthenticationEventSignIn) return;
    final String? idToken = event.user.authentication.idToken;
    if (idToken == null) {
      debugPrint('AuthService: Google returned no ID token.');
      _errors.add(StateError('Google did not return an ID token.'));
      return;
    }
    try {
      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } catch (e) {
      // The Supabase token exchange is the usual point of failure (provider not
      // enabled, client id not in the provider's authorized list, nonce check).
      // Log the real error — the login screen only shows a generic message.
      debugPrint('AuthService: signInWithIdToken failed: $e');
      _errors.add(e);
    }
  }

  /// Starts interactive sign-in where supported (mobile/desktop). On web the
  /// rendered GIS button drives sign-in instead, so this is a no-op there.
  Future<void> signInWithGoogle() async {
    await initialize();
    if (!_google.supportsAuthenticate()) return;
    try {
      await _google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        debugPrint('AuthService: Google sign-in failed: $e');
        _errors.add(e);
      }
    } catch (e) {
      debugPrint('AuthService: Google sign-in failed: $e');
      _errors.add(e);
    }
  }

  /// Clears the Google credential and the Supabase session. The router redirect
  /// (driven by the Supabase auth change) sends the user back to `/login`.
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Ignore Google sign-out hiccups; clearing the Supabase session is what
      // actually gates the app.
    }
    await supabase.auth.signOut();
  }

  void dispose() {
    _eventSub?.cancel();
    _errors.close();
  }
}
