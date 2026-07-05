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
import 'countries.dart';
import 'trip_form.dart';

/// Trip list + the active-trip FX banner. The entry point for the Travel
/// feature (pushed from the shell app-bar luggage icon).
class TravelScreen extends ConsumerWidget {
  const TravelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final tripsAsync = ref.watch(tripsProvider);
    final invoices = ref.watch(invoiceListProvider).asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.travelTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: s.newTrip,
            onPressed: () => showTripForm(context, ref),
          ),
        ],
      ),
      body: tripsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: PocketColors.persimmon),
        ),
        error: (e, _) => Center(child: Text(s.failedToLoadError(e))),
        data: (trips) {
          // Foreign receipts whose trip couldn't be decided (date in no trip, or
          // an ambiguous overlap) — surfaced here so the user can assign them.
          final undecided = invoices
              .where((i) => i.isForeign && i.tripId == null)
              .toList();
          if (trips.isEmpty && undecided.isEmpty) {
            return EmptyState(
              title: s.noTrips,
              subtitle: s.noTripsHint,
              mascot: const QRMascot(size: 72),
            );
          }
          final today = DateTime.now();
          // Every trip covering today — overlapping trips each get their own
          // currency block so both destinations' rates + converters are shown.
          final activeTrips = trips.where((t) => t.covers(today)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: [
              if (activeTrips.isNotEmpty) ...[
                _ActiveTripBanner(trips: activeTrips, s: s),
                const SizedBox(height: 20),
              ],
              if (undecided.isNotEmpty) ...[
                _UnassignedForeignSection(invoices: undecided, s: s),
                const SizedBox(height: 20),
              ],
              ...trips.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TripCard(
                      trip: t,
                      invoices: invoices,
                      s: s,
                      lang: lang,
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

/// Sums the TWD `total_amount` of expense invoices linked to [tripId].
int _tripSpentTwd(List<Invoice> invoices, String? tripId) {
  if (tripId == null) return 0;
  var sum = 0;
  for (final i in invoices) {
    if (i.tripId == tripId && !i.isIncome) sum += i.totalAmount;
  }
  return sum;
}

/// The "current trip" card. Shows a currency block per trip covering today, so
/// overlapping trips each display their own rate + converter.
class _ActiveTripBanner extends StatelessWidget {
  final List<Trip> trips;
  final AppStrings s;

  const _ActiveTripBanner({required this.trips, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PocketColors.pine,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.activeTripLabel.toUpperCase(),
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < trips.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            _TripRateBlock(trip: trips[i], s: s),
          ],
        ],
      ),
    );
  }
}

/// One trip's currency block: flag + name, today's rate, and a live converter
/// (type a foreign amount → instant TWD).
class _TripRateBlock extends ConsumerStatefulWidget {
  final Trip trip;
  final AppStrings s;

  const _TripRateBlock({required this.trip, required this.s});

  @override
  ConsumerState<_TripRateBlock> createState() => _TripRateBlockState();
}

class _TripRateBlockState extends ConsumerState<_TripRateBlock> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final trip = widget.trip;
    final country = countryByCode(trip.countryCode);
    final rateAsync = ref.watch(twdRateProvider(trip.currencyCode));
    final rate = rateAsync.asData?.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(country?.flag ?? '✈️', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                trip.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          s.todaysRate.toUpperCase(),
          style: GoogleFonts.spaceMono(
            fontSize: 9,
            letterSpacing: 0.1,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 4),
        rateAsync.when(
          loading: () => Text(
            '…',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          error: (_, __) => _muted(s.rateUnavailable),
          data: (r) => r == null
              ? _muted(s.rateUnavailable)
              : Text(
                  s.rateText(trip.currencyCode, formatRate(r)),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        _converter(rate, trip.currencyCode),
      ],
    );
  }

  /// Type a foreign amount → instant TWD (uses today's rate; disabled when the
  /// rate is unavailable).
  Widget _converter(double? rate, String code) {
    final input = double.tryParse(_controller.text.trim());
    final twdCents = (rate != null && input != null && input > 0)
        ? (input * rate * 100).round()
        : null;

    OutlineInputBorder border(double alpha) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: alpha == 0
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: alpha)),
        );

    return Row(
      children: [
        SizedBox(
          width: 148,
          child: TextField(
            controller: _controller,
            enabled: rate != null,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            cursorColor: Colors.white,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              hintText: widget.s.converterHint,
              hintStyle: GoogleFonts.spaceMono(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
              suffixText: code,
              suffixStyle: GoogleFonts.spaceMono(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.12),
              border: border(0),
              enabledBorder: border(0),
              disabledBorder: border(0),
              focusedBorder: border(0.5),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('≈',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16, color: Colors.white.withValues(alpha: 0.8))),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            twdCents != null ? formatTwd(twdCents) : '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _muted(String text) => Text(
        text,
        style: GoogleFonts.spaceMono(
          fontSize: 12,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      );
}

/// Lists foreign receipts that aren't linked to any trip yet ("to be decided").
/// Each row opens the receipt, where a trip can be assigned.
class _UnassignedForeignSection extends StatelessWidget {
  final List<Invoice> invoices;
  final AppStrings s;

  const _UnassignedForeignSection({required this.invoices, required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            s.unassignedForeignTitle,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: PocketColors.ink,
            ),
          ),
        ),
        ...invoices.map((inv) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _UnassignedTile(inv: inv, s: s),
            )),
      ],
    );
  }
}

class _UnassignedTile extends StatelessWidget {
  final Invoice inv;
  final AppStrings s;

  const _UnassignedTile({required this.inv, required this.s});

  @override
  Widget build(BuildContext context) {
    final name = inv.merchantNameTranslated?.isNotEmpty == true
        ? inv.merchantNameTranslated!
        : (inv.merchantName?.isNotEmpty == true
            ? inv.merchantName!
            : s.unknownMerchantLong);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/invoice/${inv.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PocketColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: PocketColors.persimmon.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PocketColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatDate(inv.invoiceDate),
                    style: GoogleFonts.spaceMono(
                      fontSize: 11,
                      color: PocketColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatTwd(inv.totalAmount),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: PocketColors.ink,
                  ),
                ),
                if (inv.isForeign && inv.originalAmount != null)
                  Text(
                    formatForeign(inv.originalAmount!, inv.originalCurrency!),
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      color: PocketColors.inkSoft,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: PocketColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final List<Invoice> invoices;
  final AppStrings s;
  final AppLang lang;

  const _TripCard({
    required this.trip,
    required this.invoices,
    required this.s,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final country = countryByCode(trip.countryCode);
    final spent = _tripSpentTwd(invoices, trip.id);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/travel/${trip.id}'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: PocketColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(country?.flag ?? '✈️', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: PocketColors.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${s.tripDateRange(formatDate(trip.startDate), formatDate(trip.endDate))} · ${trip.currencyCode}',
                    style: GoogleFonts.spaceMono(
                      fontSize: 11,
                      color: PocketColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatTwd(spent),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PocketColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  s.tripSpentLabel,
                  style: GoogleFonts.spaceMono(
                    fontSize: 9,
                    color: PocketColors.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
