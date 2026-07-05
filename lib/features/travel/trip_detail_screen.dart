import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/invoice.dart';
import '../../models/trip.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/mascots.dart';
import '../scan/scan_progress_overlay.dart';
import '../scan/trip_receipt_scan.dart';
import 'countries.dart';
import 'trip_form.dart';

/// One trip's expenses: a TWD total header + the linked receipts, each showing
/// the converted TWD amount with its original foreign amount underneath.
class TripDetailScreen extends ConsumerWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final tripsAsync = ref.watch(tripsProvider);
    final invoices = ref.watch(invoiceListProvider).asData?.value ?? const [];

    Trip? trip;
    for (final t in tripsAsync.asData?.value ?? const <Trip>[]) {
      if (t.id == tripId) {
        trip = t;
        break;
      }
    }

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.travelTitle)),
        body: tripsAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(child: Text(s.failedToLoad)),
      );
    }

    // Non-null capture so it can be used inside the FAB closure (a non-final
    // local isn't promoted when captured).
    final resolvedTrip = trip;
    final country = countryByCode(trip.countryCode);
    final tripInvoices = invoices.where((i) => i.tripId == tripId).toList();
    final spent = tripInvoices
        .where((i) => !i.isIncome)
        .fold<int>(0, (sum, i) => sum + i.totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: Text(trip.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: s.editTrip,
            onPressed: () => showTripForm(context, ref, existing: trip),
          ),
        ],
      ),
      // Scan-for-this-trip sits bottom-left, leaving the bottom-right corner
      // free for the scan progress card mounted in the body Stack below.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () => scanReceiptForTrip(context, ref, resolvedTrip, s),
        tooltip: s.scanReceipt,
        child: const Icon(Icons.add_a_photo_outlined),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _SummaryCard(
                  trip: trip, country: country, spent: spent, s: s, lang: lang),
              const SizedBox(height: 16),
              if (tripInvoices.isEmpty)
                SizedBox(
                  height: 240,
                  child: EmptyState(
                    title: s.tripExpensesEmpty,
                    subtitle: s.scanToStart,
                    mascot: const ReceiptMascot(size: 64),
                  ),
                )
              else
                ...tripInvoices.map((inv) => _TripExpenseTile(inv: inv, s: s)),
            ],
          ),
          // Background-scan progress, shown inside the trip too (not only on the
          // shell) so receipts scanned here report progress without leaving.
          const ScanProgressOverlay(),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Trip trip;
  final TravelCountry? country;
  final int spent;
  final AppStrings s;
  final AppLang lang;

  const _SummaryCard({
    required this.trip,
    required this.country,
    required this.spent,
    required this.s,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PocketColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(country?.flag ?? '✈️', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${country?.name(lang) ?? trip.countryCode} · ${trip.currencyCode}',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: PocketColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.tripDateRange(
                formatDate(trip.startDate), formatDate(trip.endDate)),
            style: GoogleFonts.spaceMono(
              fontSize: 11,
              color: PocketColors.inkSoft,
            ),
          ),
          const Divider(height: 28),
          Text(
            s.tripSpentLabel.toUpperCase(),
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.12,
              color: PocketColors.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatTwd(spent),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: PocketColors.ink,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripExpenseTile extends StatelessWidget {
  final Invoice inv;
  final AppStrings s;

  const _TripExpenseTile({required this.inv, required this.s});

  @override
  Widget build(BuildContext context) {
    // Prefer the translated merchant name (the user's language) with the
    // original underneath; fall back to the original alone.
    final primary = inv.merchantNameTranslated?.isNotEmpty == true
        ? inv.merchantNameTranslated!
        : (inv.merchantName?.isNotEmpty == true
            ? inv.merchantName!
            : s.unknownMerchant);
    final showOriginalName = inv.merchantNameTranslated?.isNotEmpty == true &&
        inv.merchantName?.isNotEmpty == true &&
        inv.merchantName != inv.merchantNameTranslated;

    return Card(
      child: ListTile(
        onTap: () => context.push('/invoice/${inv.id}'),
        title: Text(primary),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showOriginalName)
              Text(
                inv.merchantName!,
                style: GoogleFonts.spaceMono(
                    fontSize: 11, color: PocketColors.inkSoft),
              ),
            Text(
              formatDate(inv.invoiceDate),
              style: GoogleFonts.spaceMono(
                  fontSize: 11, color: PocketColors.inkSoft),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatTwd(inv.totalAmount),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (inv.isForeign && inv.originalAmount != null)
              Text(
                formatForeign(inv.originalAmount!, inv.originalCurrency!),
                style: GoogleFonts.spaceMono(
                    fontSize: 11, color: PocketColors.inkSoft),
              ),
          ],
        ),
      ),
    );
  }
}
