import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/trip.dart';
import 'countries.dart';

/// Opens the create/edit-trip sheet. Pass [existing] to edit (adds a Delete
/// action). Saves through [tripRepositoryProvider] and refreshes the trip
/// providers, then pops.
Future<void> showTripForm(
  BuildContext context,
  WidgetRef ref, {
  Trip? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PocketColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _TripForm(existing: existing),
    ),
  );
}

class _TripForm extends ConsumerStatefulWidget {
  final Trip? existing;
  const _TripForm({this.existing});

  @override
  ConsumerState<_TripForm> createState() => _TripFormState();
}

class _TripFormState extends ConsumerState<_TripForm> {
  late final TextEditingController _name;
  TravelCountry? _country;
  DateTimeRange? _range;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _country = countryByCode(e?.countryCode);
    if (e != null) _range = DateTimeRange(start: e.startDate, end: e.endDate);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickCountry(AppLang lang) async {
    final picked = await showModalBottomSheet<TravelCountry>(
      context: context,
      backgroundColor: PocketColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in travelCountries)
              ListTile(
                leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                title: Text(c.name(lang)),
                trailing: Text(
                  c.currencyCode,
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: PocketColors.inkSoft,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _country = picked);
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _save(AppStrings s) async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack(s.enterTripName);
    final country = _country;
    if (country == null) return _snack(s.selectCountryFirst);
    final range = _range;
    if (range == null) return _snack(s.selectDatesFirst);

    setState(() => _saving = true);
    try {
      final trip = Trip(
        id: widget.existing?.id,
        name: name,
        countryCode: country.code,
        currencyCode: country.currencyCode,
        startDate: range.start,
        endDate: range.end,
      );
      final repo = ref.read(tripRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(trip);
      } else {
        await repo.update(trip);
      }
      ref.invalidate(tripsProvider);
      ref.invalidate(activeTripProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      _snack(s.tripSaveFailed(e));
    }
  }

  Future<void> _delete(AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTripTitle),
        content: Text(s.deleteTripBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tripRepositoryProvider).delete(widget.existing!.id!);
      ref.invalidate(tripsProvider);
      ref.invalidate(activeTripProvider);
      ref.invalidate(invoiceListProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(s.tripSaveFailed(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final country = _country;
    final range = _range;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? s.newTrip : s.editTrip,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: PocketColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: s.tripNameLabel,
              hintText: s.tripNameHint,
            ),
          ),
          const SizedBox(height: 14),
          _SelectorRow(
            icon: Icons.public,
            label: country == null
                ? s.chooseCountry
                : '${country.flag}  ${country.name(lang)} · ${country.currencyCode}',
            onTap: () => _pickCountry(lang),
          ),
          const SizedBox(height: 10),
          _SelectorRow(
            icon: Icons.date_range,
            label: range == null
                ? s.chooseDates
                : s.tripDateRange(
                    formatDate(range.start), formatDate(range.end)),
            onTap: _pickDates,
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : () => _save(s),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(s.saveTrip),
            ),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _delete(s),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(s.deleteTrip),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable field-like row (country / dates) styled like an input.
class _SelectorRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SelectorRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: PocketColors.paper2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PocketColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: PocketColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: PocketColors.ink),
              ),
            ),
            const Icon(Icons.chevron_right, color: PocketColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
