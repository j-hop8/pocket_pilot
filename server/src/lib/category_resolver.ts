// Pure category-resolution helpers — the TS mirror of
// lib/core/category_resolver.dart. Auto-categorization consults the user's own
// history before the keyword categorizer: an item or merchant categorized before
// keeps that category (item wins over merchant); the most recent past choice wins.

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

/** Category for a line item: its own history → merchant history → keyword fallback. */
export function resolveItemCategory(
  itemName: string,
  merchant: string | null,
  itemHistory: Map<string, number>,
  merchantHistory: Map<string, number>,
  keywordFallback: number | null,
): number | null {
  return (
    itemHistory.get(norm(itemName)) ??
    merchantHistory.get(norm(merchant ?? "")) ??
    keywordFallback
  );
}

/** Category for an invoice header (the whole receipt): merchant history → keyword. */
export function resolveInvoiceCategory(
  merchant: string | null,
  merchantHistory: Map<string, number>,
  keywordFallback: number | null,
): number | null {
  return merchantHistory.get(norm(merchant ?? "")) ?? keywordFallback;
}

export function distinctTrimmed(values: string[]): string[] {
  const out = new Set<string>();
  for (const v of values) {
    const t = v.trim();
    if (t) out.add(t);
  }
  return [...out];
}
