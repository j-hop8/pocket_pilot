/// Pure category-resolution helpers shared by the ingest paths (carrier sync in
/// the app, and — mirrored by hand — server/src/lib/ingest.ts). Kept free of
/// Supabase/Flutter so the priority rules are unit-testable.
///
/// Auto-categorization consults the user's own history before the keyword
/// categorizer: an item or merchant categorized before keeps that category
/// (item wins over merchant), and the *most recent* past choice wins.
library;

String _norm(String s) => s.trim().toLowerCase();

/// One history row: a lookup [key] (item name or merchant), the [categoryId] the
/// user assigned (null → no signal, skipped), and an ISO recency [stamp] where a
/// lexicographically-larger string is more recent (e.g. 'invoice_date|created_at').
typedef HistoryRow = ({String? key, int? categoryId, String stamp});

/// Reduces history [rows] to one category id per normalized key, keeping the most
/// recent. Rows with a null key/category or blank key are ignored.
Map<String, int> foldMostRecentCategory(Iterable<HistoryRow> rows) {
  final best = <String, ({String stamp, int catId})>{};
  for (final r in rows) {
    final catId = r.categoryId;
    final rawKey = r.key;
    if (catId == null || rawKey == null) continue;
    final key = _norm(rawKey);
    if (key.isEmpty) continue;
    final cur = best[key];
    if (cur == null || r.stamp.compareTo(cur.stamp) > 0) {
      best[key] = (stamp: r.stamp, catId: catId);
    }
  }
  return {for (final e in best.entries) e.key: e.value.catId};
}

/// Category for a line item: its own history → merchant history → [keywordFallback].
int? resolveItemCategory({
  required String itemName,
  required String? merchant,
  required Map<String, int> itemHistory,
  required Map<String, int> merchantHistory,
  required int? keywordFallback,
}) =>
    itemHistory[_norm(itemName)] ??
    merchantHistory[_norm(merchant ?? '')] ??
    keywordFallback;

/// Category for an invoice header (the whole receipt): merchant history →
/// [keywordFallback]. Items may still differ via [resolveItemCategory].
int? resolveInvoiceCategory({
  required String? merchant,
  required Map<String, int> merchantHistory,
  required int? keywordFallback,
}) =>
    merchantHistory[_norm(merchant ?? '')] ?? keywordFallback;
