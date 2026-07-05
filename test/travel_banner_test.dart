import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocketpilot/core/providers.dart';
import 'package:pocketpilot/features/travel/travel_screen.dart';
import 'package:pocketpilot/models/invoice.dart';
import 'package:pocketpilot/models/trip.dart';

/// The active-trip banner shows a currency block per trip covering today, each
/// with today's rate and a live foreign→TWD converter.
void main() {
  // Keep layout offline: fall back to a bundled font instead of fetching.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Trip active(String id, String currency, String country) {
    final today = DateTime.now();
    return Trip(
      id: id,
      name: '$country trip',
      countryCode: country,
      currencyCode: currency,
      startDate: today.subtract(const Duration(days: 1)),
      endDate: today.add(const Duration(days: 1)),
    );
  }

  Future<void> pumpTravel(WidgetTester t, List<Trip> trips) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          tripsProvider.overrideWith((ref) async => trips),
          invoiceListProvider.overrideWith((ref) async => <Invoice>[]),
          twdRateProvider('JPY').overrideWith((ref) async => 0.21),
          twdRateProvider('KRW').overrideWith((ref) async => 0.023),
        ],
        child: const MaterialApp(home: TravelScreen()),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('two trips active today → a rate line + converter for each',
      (t) async {
    await pumpTravel(t, [active('jp', 'JPY', 'JP'), active('kr', 'KRW', 'KR')]);

    // Both destinations' rate lines are shown (not just the first trip's).
    expect(find.textContaining('JPY ≈'), findsOneWidget);
    expect(find.textContaining('KRW ≈'), findsOneWidget);
    // One converter input per active trip.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('typing a foreign amount converts to TWD live', (t) async {
    await pumpTravel(t, [active('jp', 'JPY', 'JP')]);

    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), '1000');
    await t.pump();

    // 1000 JPY × 0.21 = NT$210.
    expect(find.text('NT\$210'), findsOneWidget);
  });
}
