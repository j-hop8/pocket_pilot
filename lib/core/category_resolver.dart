/// Pure category-resolution helpers shared by the ingest paths (carrier sync in
/// the app, and — mirrored by hand — server/src/lib/category_resolver.ts and
/// supabase/functions/_shared/category_resolver.ts). Kept free of
/// Supabase/Flutter so the priority rules are unit-testable.
///
/// Store and item categories are resolved independently:
///   * An item's category comes only from item-level signals — its own history,
///     then the keyword rules run against the item name. It never inherits the
///     store/merchant category (that signal is unreliable at the item level).
///   * The store (invoice header) category comes from the merchant's history,
///     then the keyword rules run against the merchant name, and finally — when
///     neither matches — the most common category among its line items.
/// History always consults the user's own past choices first, and the *most
/// recent* past choice wins.
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

/// Category for a line item: its own history → [keywordFallback] (the keyword
/// rules run against this item's name). Never falls back to the store/merchant
/// category — that signal is unreliable at the item level.
int? resolveItemCategory({
  required String itemName,
  required Map<String, int> itemHistory,
  required int? keywordFallback,
}) =>
    itemHistory[_norm(itemName)] ?? keywordFallback;

/// Category for an invoice header (the whole receipt): merchant history →
/// [keywordFallback] (the keyword rules run against the merchant name) → the
/// most common category among [itemCategoryIds] (its already-resolved line
/// items). The item-mode fallback covers stores the rules don't recognise by
/// name but whose items are categorizable.
int? resolveInvoiceCategory({
  required String? merchant,
  required Map<String, int> merchantHistory,
  required int? keywordFallback,
  required Iterable<int?> itemCategoryIds,
}) =>
    merchantHistory[_norm(merchant ?? '')] ??
    keywordFallback ??
    modeCategory(itemCategoryIds);

/// The most frequent non-null id in [ids], or null when there are none. Ties are
/// broken by first appearance: [counts] iterates in first-insertion order (= the
/// order each id first appears in [ids]), so a strict `>` that never replaces on
/// a tie keeps the earliest-seen id — deterministic when [ids] is in `sort_order`.
int? modeCategory(Iterable<int?> ids) {
  final counts = <int, int>{};
  for (final id in ids) {
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  int? best;
  var bestCount = 0;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      best = entry.key;
      bestCount = entry.value;
    }
  }
  return best;
}
