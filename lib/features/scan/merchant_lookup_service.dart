import '../../core/supabase.dart';

/// Resolves a seller tax id (統一編號) to a business name, since the e-invoice QR
/// carries only the tax id — not the Chinese merchant name printed on the
/// receipt.
///
/// The lookup runs server-side in the `merchant-lookup` Edge Function: the
/// official 經濟部 GCIS registry API sends no CORS headers, so the browser can't
/// query it directly. Best-effort — any failure (network, not found, the
/// function being unavailable) returns `null` and the invoice still saves with
/// the tax id alone. Results are cached in-memory for the session so re-scanning
/// the same store is free.
class MerchantLookupService {
  MerchantLookupService();

  final _cache = <String, String?>{};

  /// The registered name for [taxId], or `null` if it can't be resolved.
  Future<String?> nameForTaxId(String? taxId) async {
    final id = taxId?.trim();
    if (id == null || id.length != 8) return null;
    if (_cache.containsKey(id)) return _cache[id];

    String? name;
    try {
      // Accessed lazily (not in the constructor) so test fakes that override
      // this method never touch the Supabase singleton.
      final res = await supabase.functions.invoke(
        'merchant-lookup',
        body: {'taxId': id},
      );
      final data = res.data;
      if (data is Map && data['name'] is String) {
        final trimmed = (data['name'] as String).trim();
        name = trimmed.isEmpty ? null : trimmed;
      }
    } catch (_) {
      name = null; // never let a lookup failure block the scan
    }
    _cache[id] = name;
    return name;
  }
}
