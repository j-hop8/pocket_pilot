import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Google Identity Services rendered button. Clicking it emits a sign-in on
/// [GoogleSignIn.authenticationEvents], which [AuthService] exchanges for a
/// Supabase session.
Widget? googleWebButton() => web.renderButton(
      configuration: web.GSIButtonConfiguration(
        theme: web.GSIButtonTheme.outline,
        size: web.GSIButtonSize.large,
        shape: web.GSIButtonShape.pill,
        text: web.GSIButtonText.continueWith,
        logoAlignment: web.GSIButtonLogoAlignment.left,
      ),
    );
