// Unit tests for the merchant-name lookup. Mocks `fetchFn` so no live call is
// made — covers a GCIS company hit, the FIA 稅籍 fallback (sole proprietors /
// branches), the id guard, a FIA 404, and the way GCIS returns "200 but not a
// result" (Chinese error text / empty body), which is the exact bug that broke
// the old client.
//
// Run with: `deno test supabase/functions`.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lookupMerchantName } from "./merchant_lookup.ts";

const COMPANY = "5F64D864"; // GCIS 公司登記 dataset id fragment
const FIA = "businessRegistration"; // FIA 營業稅籍 path fragment

/// Returns a fetch that replies per the first URL fragment matched; anything
/// unmatched is an empty 200 (GCIS's "no match").
function mockFetch(routes: Record<string, { status?: number; body: string }>) {
  return (url: string): Promise<Response> => {
    for (const [frag, r] of Object.entries(routes)) {
      if (url.includes(frag)) {
        return Promise.resolve(new Response(r.body, { status: r.status ?? 200 }));
      }
    }
    return Promise.resolve(new Response("", { status: 200 }));
  };
}

Deno.test("resolves a company via GCIS Company_Name", async () => {
  const f = mockFetch({
    [COMPANY]: { body: JSON.stringify([{ Company_Name: "統一超商股份有限公司" }]) },
  });
  assertEquals(await lookupMerchantName("22555003", f), "統一超商股份有限公司");
});

Deno.test("falls back to FIA 稅籍 (businessNm) when GCIS misses", async () => {
  const f = mockFetch({
    [COMPANY]: { body: "[]" }, // no company match
    [FIA]: { body: JSON.stringify({ ban: "12345678", businessNm: "小吃商行" }) },
  });
  assertEquals(await lookupMerchantName("12345678", f), "小吃商行");
});

Deno.test("FIA 404 (unregistered tax id) is a miss", async () => {
  const f = mockFetch({
    [COMPANY]: { body: "[]" },
    [FIA]: { status: 404, body: "" },
  });
  assertEquals(await lookupMerchantName("99999999", f), null);
});

Deno.test("non-8-digit id is rejected without any fetch", async () => {
  let called = false;
  const f = (_url: string) => {
    called = true;
    return Promise.resolve(new Response("[]"));
  };
  assertEquals(await lookupMerchantName("1234", f), null);
  assertEquals(await lookupMerchantName(null, f), null);
  assertEquals(await lookupMerchantName("  ", f), null);
  assertEquals(called, false);
});

Deno.test("GCIS 200-but-error-text body is treated as a miss", async () => {
  const f = mockFetch({
    [COMPANY]: { body: "此API不存在，請查明後繼續。" },
    [FIA]: { status: 404, body: "" },
  });
  assertEquals(await lookupMerchantName("22555003", f), null);
});

Deno.test("empty bodies (no match anywhere) are a miss", async () => {
  const f = mockFetch({
    [COMPANY]: { body: "" },
    [FIA]: { status: 404, body: "" },
  });
  assertEquals(await lookupMerchantName("22555003", f), null);
});

Deno.test("blank name field is a miss, not an empty string", async () => {
  const f = mockFetch({
    [COMPANY]: { body: JSON.stringify([{ Company_Name: "   " }]) },
    [FIA]: { status: 404, body: "" },
  });
  assertEquals(await lookupMerchantName("22555003", f), null);
});
