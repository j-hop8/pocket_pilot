import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Pocket palette — warm paper · persimmon · pine · butter · ink
// Colors derived from the HTML design directions (OKLCH → sRGB conversion).
class PocketColors {
  static const paper     = Color(0xFFFAF5EC); // oklch(0.972 0.013 84)
  static const paper2    = Color(0xFFF3ECE0); // oklch(0.945 0.018 82)
  static const ink       = Color(0xFF2E2421); // oklch(0.27 0.022 64)
  static const inkSoft   = Color(0xFF5D534A); // oklch(0.45 0.02 64)
  static const persimmon = Color(0xFFE7743F); // oklch(0.685 0.158 44) — primary
  static const pine      = Color(0xFF368076); // oklch(0.55 0.075 184) — secondary
  static const butter    = Color(0xFFE7CE7D); // oklch(0.855 0.105 92) — tertiary
  static const blush     = Color(0xFFF5D7C7); // oklch(0.90 0.04 50)
  static const board     = Color(0xFFE7E5E1); // background board
  static const card      = Color(0xFFFFFFFF);
  static const line      = Color(0x1F2E2421); // ink @ 12%
}

ThemeData buildTheme() {
  const cs = ColorScheme(
    brightness: Brightness.light,
    primary:              PocketColors.persimmon,
    onPrimary:            Colors.white,
    primaryContainer:     Color(0xFFFFDDC8),
    onPrimaryContainer:   PocketColors.ink,
    secondary:            PocketColors.pine,
    onSecondary:          Colors.white,
    secondaryContainer:   Color(0xFFC0DDD8),
    onSecondaryContainer: PocketColors.ink,
    tertiary:             PocketColors.butter,
    onTertiary:           PocketColors.ink,
    tertiaryContainer:    Color(0xFFFFF3C4),
    onTertiaryContainer:  PocketColors.ink,
    error:                Color(0xFFBA1A1A),
    onError:              Colors.white,
    errorContainer:       Color(0xFFFFDAD6),
    onErrorContainer:     Color(0xFF410002),
    surface:              PocketColors.paper,
    onSurface:            PocketColors.ink,
    surfaceContainerHighest: PocketColors.paper2,
    onSurfaceVariant:     PocketColors.inkSoft,
    outline:              PocketColors.line,
    outlineVariant:       PocketColors.line,
  );

  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    scaffoldBackgroundColor: PocketColors.board,
    textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.light().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: PocketColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: PocketColors.ink,
        letterSpacing: -0.4,
      ),
      iconTheme: const IconThemeData(color: PocketColors.ink),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      color: PocketColors.card,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PocketColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: Color(0x26E7743F), // persimmon @ 15%
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: PocketColors.persimmon, size: 24);
        }
        return const IconThemeData(color: PocketColors.inkSoft, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.spaceMono(
            fontSize: 10,
            letterSpacing: 0.04,
            color: PocketColors.persimmon,
            fontWeight: FontWeight.w700,
          );
        }
        return GoogleFonts.spaceMono(
          fontSize: 10,
          letterSpacing: 0.04,
          color: PocketColors.inkSoft,
        );
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: PocketColors.persimmon,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PocketColors.persimmon,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PocketColors.ink,
        side: const BorderSide(color: PocketColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PocketColors.paper2,
      labelStyle: const TextStyle(color: PocketColors.inkSoft),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PocketColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PocketColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PocketColors.persimmon, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: PocketColors.line, space: 0),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PocketColors.persimmon,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PocketColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: PocketColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
  );
}
