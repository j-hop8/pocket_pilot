// Unit tests for the FX-rate fetcher. Mocks `fetchFn` so no live call is made —
// covers parsing the quote out of the upstream `rates` map, the same-code
// short-circuit, an unknown quote, case-insensitivity, and a non-OK response.
//
// Run with: `deno test supabase/functions`.

import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchFxRate } from "./fx.ts";

/// open.er-api.com success shape (only the fields we read).
function okBody(rates: Record<string, number>): string {
  return JSON.stringify({ result: "success", base_code: "JPY", rates });
}

Deno.test("parses the quote currency from the upstream rates", async () => {
  const fetchFn = () => Promise.resolve(new Response(okBody({ TWD: 0.21, USD: 0.0064 })));
  assertEquals(await fetchFxRate("JPY", "TWD", fetchFn), 0.21);
});

Deno.test("same base and quote short-circuits to 1 with no fetch", async () => {
  let called = false;
  const fetchFn = () => {
    called = true;
    return Promise.resolve(new Response("{}"));
  };
  assertEquals(await fetchFxRate("TWD", "TWD", fetchFn), 1);
  assertEquals(called, false);
});

Deno.test("an unknown quote currency returns null", async () => {
  const fetchFn = () => Promise.resolve(new Response(okBody({ USD: 0.0064 })));
  assertEquals(await fetchFxRate("JPY", "TWD", fetchFn), null);
});

Deno.test("currency codes are case-insensitive", async () => {
  const fetchFn = () => Promise.resolve(new Response(okBody({ TWD: 0.21 })));
  assertEquals(await fetchFxRate("jpy", "twd", fetchFn), 0.21);
});

Deno.test("a non-OK upstream response throws", async () => {
  const fetchFn = () => Promise.resolve(new Response("nope", { status: 503 }));
  await assertRejects(() => fetchFxRate("JPY", "TWD", fetchFn), Error, "503");
});

Deno.test("a zero/negative rate is treated as unavailable", async () => {
  const fetchFn = () => Promise.resolve(new Response(okBody({ TWD: 0 })));
  assertEquals(await fetchFxRate("JPY", "TWD", fetchFn), null);
});
