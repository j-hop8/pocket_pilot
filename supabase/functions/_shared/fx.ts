// Fetches a foreign→home currency exchange rate for converting travel receipts.
//
// Provider: open.er-api.com — free, no API key, and (unlike the ECB-based
// frankfurter/ECB feeds) it includes TWD, which is required since TWD is the
// home currency every dashboard sums. Latest rates only; the caller caches per
// calendar day (see the exchange-rate function's fx_rates upsert).
//
// Dependency-free with an injectable fetch so it's deno-testable in isolation,
// mirroring gemini_receipt.ts / merchant_lookup.ts.

export type FetchFn = (url: string, init?: RequestInit) => Promise<Response>;

const defaultFetch: FetchFn = (url, init) =>
  fetch(url, { ...init, signal: AbortSignal.timeout(10000) });

const endpoint = (base: string) =>
  `https://open.er-api.com/v6/latest/${encodeURIComponent(base)}`;

/// Returns the `base`→`quote` rate (units of `quote` per 1 `base`), or null when
/// the pair isn't available upstream. Identical codes short-circuit to 1 without
/// a network call. Throws on a non-OK upstream response so the handler can fall
/// back to an uncached/null rate.
export async function fetchFxRate(
  base: string,
  quote: string,
  fetchFn: FetchFn = defaultFetch,
): Promise<number | null> {
  const b = base.trim().toUpperCase();
  const q = quote.trim().toUpperCase();
  if (!b || !q) return null;
  if (b === q) return 1;

  const res = await fetchFn(endpoint(b), { method: "GET" });
  if (!res.ok) {
    throw new Error(`exchange-rate upstream failed (${res.status})`);
  }
  const body = await res.json();
  const rate = body?.rates?.[q];
  return typeof rate === "number" && Number.isFinite(rate) && rate > 0
    ? rate
    : null;
}
