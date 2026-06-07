import 'package:flutter/widgets.dart';

import 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart' as impl;

/// On web, returns Google's official GIS-rendered sign-in button, which drives
/// the credential flow through [GoogleSignIn.authenticationEvents]. On every
/// other platform returns `null` so the caller renders its own button and calls
/// [AuthService.signInWithGoogle] instead.
Widget? googleWebButton() => impl.googleWebButton();
