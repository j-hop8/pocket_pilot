import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../../core/supabase.dart';

/// Looks up a foreign→TWD exchange rate via the `exchange-rate` Edge Function
/// (which caches results in fx_rates). Mirrors [MerchantLookupService]'s shape:
/// the Supabase singleton is touched lazily so test fakes that override
/// [rateToTwd] never reach the network.
///
/// Best-effort: any failure resolves to null so a travel receipt still saves —
/// just unconverted (its original foreign amount is kept and stays editable).
class ExchangeRateService {
  ExchangeRateService();

  static const home = 'TWD';

  /// Units of TWD per 1 [base] (e.g. JPY→TWD ≈ 0.21), or null when unavailable.
  Future<double?> rateToTwd(String base) async {
    final code = base.toUpperCase();
    if (code == home) return 1;
    try {
      final res = await supabase.functions.invoke(
        'exchange-rate',
        body: {'base': code, 'quote': home},
      );
      final data = res.data;
      if (data is Map && data['rate'] is num) {
        final rate = (data['rate'] as num).toDouble();
        if (rate > 0) return rate;
      }
    } on FunctionException catch (_) {
      // Edge Function returned non-2xx — treat as a miss.
    }
    return null;
  }
}
