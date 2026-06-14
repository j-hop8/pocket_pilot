// Resolves a Taiwan business tax id (統一編號) to its registered name. Runs
// server-side (Edge Function) so there's no browser CORS restriction — the
// e-invoice QR carries only the tax id, and neither upstream API sends CORS
// headers, so the Flutter web client can't query them directly.
//
// Two approaches, tried in order (a tax id resolves in at least one):
//   1. 經濟部 GCIS 公司登記 — Business_Accounting_NO → Company_Name (companies).
//   2. 財政部 FIA 營業稅籍登記 — /businessRegistration/{id} → businessNm. The 稅籍
//      registry covers every e-invoice seller, incl. sole proprietors (商號) and
//      branches that the company registry alone misses.
//
// Dependency-free with an injectable fetch so it's deno-testable in isolation.
// Never throws: any network error, non-200, empty body, or 200-with-error-text
// (GCIS returns a Chinese error string with HTTP 200) is treated as a miss.

export type FetchFn = (url: string) => Promise<Response>;

const GCIS_API = "https://data.gcis.nat.gov.tw/od/data/api";
// 公司登記基本資料-應用一 (verified working 2026-06).
const COMPANY_API = `${GCIS_API}/5F64D864-61CB-4D0D-8AD9-492047CC1EA6`;
// 財政部財政資訊中心 營業（稅籍）登記資料 — one JSON object per tax id, 404 on miss.
const FIA_API = "https://eip.fia.gov.tw/OAI/api/businessRegistration";

const defaultFetch: FetchFn = (url) =>
  fetch(url, { signal: AbortSignal.timeout(6000) });

/// The registered business name for [taxId], or `null` if it can't be resolved.
export async function lookupMerchantName(
  taxId: string | null | undefined,
  fetchFn: FetchFn = defaultFetch,
): Promise<string | null> {
  const id = (taxId ?? "").trim();
  if (!/^\d{8}$/.test(id)) return null;

  return (
    (await queryGcisCompany(id, fetchFn)) ?? (await queryFia(id, fetchFn))
  );
}

/// 經濟部 GCIS 公司登記 — OData array; name in `Company_Name`.
async function queryGcisCompany(id: string, fetchFn: FetchFn): Promise<string | null> {
  try {
    const filter = encodeURIComponent(`Business_Accounting_NO eq '${id}'`);
    const res = await fetchFn(`${COMPANY_API}?$format=json&$filter=${filter}&$skip=0&$top=1`);
    if (!res.ok) return null;
    // GCIS answers a dead dataset / bad filter with a Chinese error string — and
    // an empty body for no match — both with HTTP 200, so only a JSON array is
    // a real result.
    const text = (await res.text()).trim();
    if (!text.startsWith("[")) return null;
    const body = JSON.parse(text);
    if (!Array.isArray(body) || body.length === 0) return null;
    const first = body[0];
    if (typeof first !== "object" || first === null) return null;
    return cleanName((first as Record<string, unknown>)["Company_Name"]);
  } catch {
    return null; // never let a lookup failure block the scan
  }
}

/// 財政部 FIA 營業稅籍 — a single JSON object; name in `businessNm`; HTTP 404 when
/// the tax id isn't registered.
async function queryFia(id: string, fetchFn: FetchFn): Promise<string | null> {
  try {
    const res = await fetchFn(`${FIA_API}/${id}`);
    if (!res.ok) return null; // 404 = no such tax id
    const text = (await res.text()).trim();
    if (!text.startsWith("{")) return null;
    const body = JSON.parse(text);
    if (typeof body !== "object" || body === null) return null;
    return cleanName((body as Record<string, unknown>)["businessNm"]);
  } catch {
    return null;
  }
}

function cleanName(value: unknown): string | null {
  const name = String(value ?? "").trim();
  return name === "" ? null : name;
}
