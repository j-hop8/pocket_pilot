import 'package:flutter/widgets.dart';

/// Non-web platforms have no rendered Google button; the caller falls back to
/// its own button + [AuthService.signInWithGoogle].
Widget? googleWebButton() => null;
