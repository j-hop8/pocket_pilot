import 'dart:convert';

import 'package:http/http.dart' as http;

/// Resolves a seller tax id (統一編號) to a business name, since the e-invoice QR
/// carries only the tax id — not the Chinese merchant name printed on the
/// receipt.
///
/// Best-effort: queries the 經濟部 GCIS open-data platform (company registry
/// first, then the business/商業 registry for sole proprietors). Any failure —
/// network, CORS on web, or a vendor not in either dataset — returns `null`, and
/// the invoice still saves with the tax id alone. Results are cached in-memory
/// for the session so re-scanning the same store is free.
class MerchantLookupService {
  MerchantLookupService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _cache = <String, String?>{};

  static const _host = 'data.gcis.nat.gov.tw';
  // 公司登記 (company) and 商業登記 (sole proprietor / partnership) datasets.
  static const _companyApi = '/od/data/api/5F64D864-61CB-4D0D-8AD9-492047CC1EA6';
  static const _businessApi = '/od/data/api/426D5542-65F1-4F9B-AFA0-3E7607D4F360';

  /// The registered name for [taxId], or `null` if it can't be resolved.
  Future<String?> nameForTaxId(String? taxId) async {
    final id = taxId?.trim();
    if (id == null || id.length != 8) return null;
    if (_cache.containsKey(id)) return _cache[id];

    // GCIS is slow (often 1-3 s per call) and a small vendor lives in one or
    // the other dataset, never both, so racing the two queries halves the
    // typical wait. Prefer the company answer when present.
    final results = await Future.wait([
      _query(_companyApi, id, 'Company_Name'),
      _query(_businessApi, id, 'Business_Name'),
    ]);
    final name = results[0] ?? results[1];
    _cache[id] = name;
    return name;
  }

  Future<String?> _query(String path, String id, String nameField) async {
    try {
      final uri = Uri.https(_host, path, {
        '\$format': 'json',
        '\$filter': "Business_Accounting_NO eq '$id'",
        '\$skip': '0',
        '\$top': '1',
      });
      final res = await _client
          .get(uri)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! List || body.isEmpty) return null;
      final first = body.first;
      if (first is! Map) return null;
      final name = (first[nameField] as String?)?.trim();
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null; // never let a lookup failure block the scan
    }
  }
}
