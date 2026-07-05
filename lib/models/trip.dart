import 'package:intl/intl.dart';

final _dateOnly = DateFormat('yyyy-MM-dd');

/// A travel period: a date range + destination. While today falls within
/// [startDate]..[endDate] the trip is "active": scanned receipts auto-link to it
/// and convert from [currencyCode] to TWD. Dates are stored as DATE (no time).
class Trip {
  final String? id;
  final String name;
  final String countryCode; // ISO 3166-1 alpha-2, e.g. 'JP'
  final String currencyCode; // ISO 4217, e.g. 'JPY'
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? createdAt;

  const Trip({
    this.id,
    required this.name,
    required this.countryCode,
    required this.currencyCode,
    required this.startDate,
    required this.endDate,
    this.createdAt,
  });

  /// Whether [day] falls within the trip (inclusive, date-only comparison).
  bool covers(DateTime day) {
    final d = _dateOnlyOf(day);
    return !d.isBefore(_dateOnlyOf(startDate)) && !d.isAfter(_dateOnlyOf(endDate));
  }

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String?,
        name: json['name'] as String,
        countryCode: json['country_code'] as String,
        currencyCode: json['currency_code'] as String,
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: DateTime.parse(json['end_date'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  /// For insert. `id`, `user_id`, `created_at`, `updated_at` are DB-managed
  /// (`user_id` self-fills from auth.uid()).
  Map<String, dynamic> toInsertJson() => {
        'name': name,
        'country_code': countryCode,
        'currency_code': currencyCode,
        'start_date': _dateOnly.format(startDate),
        'end_date': _dateOnly.format(endDate),
      };

  /// For a full update; bumps `updated_at` (no DB trigger does it for us).
  Map<String, dynamic> toUpdateJson() => {
        ...toInsertJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// Date-only [DateTime] for inclusive range comparisons.
DateTime _dateOnlyOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// The trip a receipt belongs to, decided by the receipt's own printed [date]
/// (more reliable than the upload/scan date), or null when it can't be decided
/// ("to be decided" — left for the user to assign).
///
/// - No trip covers [date] → null.
/// - Exactly one trip covers it → that trip.
/// - Several trips cover it (overlapping trips, or a travel day between two) →
///   disambiguate by the receipt's own [currency]: the single trip whose currency
///   matches wins; if that still can't decide (no match, or several) → null.
Trip? tripForReceipt(List<Trip> trips, DateTime date, String currency) {
  final covering = trips.where((t) => t.covers(date)).toList();
  if (covering.isEmpty) return null;
  if (covering.length == 1) return covering.first;
  final cur = currency.toUpperCase();
  final byCurrency =
      covering.where((t) => t.currencyCode.toUpperCase() == cur).toList();
  return byCurrency.length == 1 ? byCurrency.first : null;
}
