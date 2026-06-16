import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pocketpilot/features/scan/scan_source_chooser.dart';

/// The dark chooser card must be the same width on both Add sub-tabs (e-invoice
/// and receipt) — that was the bug: each tab's card shrink-wrapped its own
/// content, so the receipt card (longer hint, wider photo strip) came out wider
/// than the e-invoice card. [ScanSourceChooser] pins the width instead, so card
/// size no longer drifts with hint length or a footer.
void main() {
  // Keep layout deterministic and offline: fall back to a bundled font instead
  // of fetching Google Fonts during the test.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Width of the card's gradient panel — the only [DecoratedBox] with a
  /// gradient (the button pills use a solid colour / border, no gradient).
  Finder cardOf() => find.byWidgetPredicate((w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).gradient != null);

  Widget harness({
    required double width,
    required String hint,
    Widget? footer,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 800,
            child: ScanSourceChooser(
              mascot: const SizedBox(width: 84, height: 84),
              title: 'Title',
              hint: hint,
              // Short labels keep the pills within a narrow card regardless of
              // the test's fallback font (the real UI uses Space Mono).
              actions: [
                ScanChooserButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  filled: true,
                  onTap: () {},
                ),
                ScanChooserButton(
                  icon: Icons.folder_open_rounded,
                  label: 'Folder',
                  filled: false,
                  onTap: () {},
                ),
              ],
              footer: footer,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('card width is the same regardless of hint length', (t) async {
    await t.pumpWidget(harness(width: 600, hint: 'Short hint'));
    final short = t.getSize(cardOf()).width;

    await t.pumpWidget(harness(
      width: 600,
      hint: 'A much, much longer hint that on the old shrink-wrapped card would '
          'have stretched this panel noticeably wider than the other tab',
    ));
    final long = t.getSize(cardOf()).width;

    expect(short, long);
  });

  testWidgets('a footer adds height but does not widen the card', (t) async {
    await t.pumpWidget(harness(width: 600, hint: 'Short hint'));
    final withoutFooter = t.getSize(cardOf()).width;

    await t.pumpWidget(harness(
      width: 600,
      hint: 'Short hint',
      // A footer far wider than the card's content area.
      footer: const SizedBox(width: 2000, height: 60),
    ));
    final withFooter = t.getSize(cardOf()).width;

    expect(withFooter, withoutFooter);
  });

  testWidgets('card caps at 360 on a roomy tab but fills a narrow one',
      (t) async {
    await t.pumpWidget(harness(width: 600, hint: 'Short hint'));
    expect(t.getSize(cardOf()).width, 360);

    await t.pumpWidget(harness(width: 300, hint: 'Short hint'));
    expect(t.getSize(cardOf()).width, 300);
  });
}
