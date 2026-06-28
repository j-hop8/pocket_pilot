// Pure category-resolution helpers — the Deno mirror of
// lib/core/category_resolver.dart and server/src/lib/category_resolver.ts. Store
// and item categories are resolved independently: an item's category comes only
// from item-level signals (its own history, then the keyword rules on the item
// name) and never inherits the store/merchant category; the store (invoice
// header) category comes from the merchant's history, then the keyword rules on
// the merchant name, and finally the most common category among its line items.
// History consults the user's own past choices first; the most recent past
// choice wins.

export const norm = (s: string) => s.trim().toLowerCase();

/** One history row: a lookup key, the assigned category id (null → skipped), and
 * an ISO recency stamp where a lexicographically-larger string is more recent. */
export interface HistoryRow {
  key: string | null;
  categoryId: number | null;
  stamp: string;
}

/** Reduces history rows to one category id per normalized key, keeping the most
 * recent. Rows with a null key/category or blank key are ignored. */
export function foldMostRecentCategory(
  rows: Iterable<HistoryRow>,
): Map<string, number> {
  const best = new Map<string, { stamp: string; catId: number }>();
  for (const r of rows) {
    if (r.categoryId == null || r.key == null) continue;
    const key = norm(r.key);
    if (!key) continue;
    const cur = best.get(key);
    if (!cur || r.stamp > cur.stamp) best.set(key, { stamp: r.stamp, catId: r.categoryId });
  }
  const out = new Map<string, number>();
  for (const [k, v] of best) out.set(k, v.catId);
  return out;
}

/** Category for a line item: its own history → keyword fallback (the keyword
 * rules run against this item's name). Never falls back to the store/merchant
 * category — that signal is unreliable at the item level. */
export function resolveItemCategory(
  itemName: string,
  itemHistory: Map<string, number>,
  keywordFallback: number | null,
): number | null {
  return itemHistory.get(norm(itemName)) ?? keywordFallback;
}

/** Category for an invoice header (the whole receipt): merchant history →
 * keyword fallback (the keyword rules run against the merchant name) → the most
 * common category among its already-resolved line items. */
export function resolveInvoiceCategory(
  merchant: string | null,
  merchantHistory: Map<string, number>,
  keywordFallback: number | null,
  itemCategoryIds: Iterable<number | null>,
): number | null {
  return (
    merchantHistory.get(norm(merchant ?? "")) ??
    keywordFallback ??
    modeCategory(itemCategoryIds)
  );
}

/** The most frequent non-null id, or null when there are none. Ties are broken
 * by first appearance: `counts` iterates in first-insertion order (= the order
 * each id first appears in `ids`), so a strict `>` that never replaces on a tie
 * keeps the earliest-seen id — deterministic when `ids` is in sort_order. */
export function modeCategory(ids: Iterable<number | null>): number | null {
  const counts = new Map<number, number>();
  for (const id of ids) {
    if (id != null) counts.set(id, (counts.get(id) ?? 0) + 1);
  }
  let best: number | null = null;
  let bestCount = 0;
  for (const [id, count] of counts) {
    if (count > bestCount) {
      best = id;
      bestCount = count;
    }
  }
  return best;
}

export function distinctTrimmed(values: string[]): string[] {
  const out = new Set<string>();
  for (const v of values) {
    const t = v.trim();
    if (t) out.add(t);
  }
  return [...out];
}
