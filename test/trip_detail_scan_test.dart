import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocketpilot/core/providers.dart';
import 'package:pocketpilot/features/scan/scan_progress_overlay.dart';
import 'package:pocketpilot/features/travel/trip_detail_screen.dart';
import 'package:pocketpilot/models/invoice.dart';
import 'package:pocketpilot/models/trip.dart';

/// The trip page has a scan-for-this-trip button pinned bottom-left and mounts
/// the background-scan progress overlay itself (so progress shows without
/// leaving the trip — the bottom-right "tab").
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Trip jp() => Trip(
        id: 'jp',
        name: 'Japan trip',
        countryCode: 'JP',
        currencyCode: 'JPY',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 10),
      );

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          tripsProvider.overrideWith((ref) async => [jp()]),
          invoiceListProvider.overrideWith((ref) async => <Invoice>[]),
        ],
        child: const MaterialApp(home: TripDetailScreen(tripId: 'jp')),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('scan button is pinned to the bottom-left', (t) async {
    await pump(t);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    final scaffold = t.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.floatingActionButtonLocation,
        FloatingActionButtonLocation.startFloat);
  });

  testWidgets('the scan progress overlay is mounted inside the trip page',
      (t) async {
    await pump(t);
    expect(find.byType(ScanProgressOverlay), findsOneWidget);
  });
}
