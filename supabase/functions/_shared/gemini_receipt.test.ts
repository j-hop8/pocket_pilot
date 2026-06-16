// Unit tests for the receipt extractor's model-fallback chain. Mocks `fetchFn`
// so no live Gemini call is made — covers the happy path on the primary model,
// falling through to the next model on a 429, lenient parsing of a Gemma reply
// wrapped in ```json fences, exhausting the whole chain, and a non-retryable
// error short-circuiting immediately.
//
// Run with: `deno test supabase/functions`.

import {
  assert,
  assertEquals,
  assertMatch,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { extractReceipt } from "./gemini_receipt.ts";

const IMG = "aGVsbG8="; // base64, contents don't matter to the mock

/// Wraps a model's text output in the Gemini generateContent response shape.
function geminiBody(text: string): string {
  return JSON.stringify({
    candidates: [{ content: { parts: [{ text }] } }],
  });
}

/// A canned receipt the model would return.
const RECEIPT_JSON = JSON.stringify({
  merchantName: "Corner Cafe",
  date: "2026-06-01",
  total: 120,
  kind: "expense",
  currency: "TWD",
  items: [],
});

interface Recorded {
  url: string;
  body: Record<string, unknown>;
}

/// A fetch that replies from `responses` in order and records every request, so
/// a test can assert which model URLs were hit and what body was sent.
function sequencedFetch(
  responses: Array<{ status?: number; body: string }>,
) {
  const calls: Recorded[] = [];
  let i = 0;
  const fetchFn = (url: string, init: RequestInit): Promise<Response> => {
    calls.push({ url, body: JSON.parse(String(init.body)) });
    const r = responses[Math.min(i, responses.length - 1)];
    i++;
    return Promise.resolve(new Response(r.body, { status: r.status ?? 200 }));
  };
  return { fetchFn, calls };
}

Deno.test("primary model success — one call, no fallback", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { body: geminiBody(RECEIPT_JSON) },
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);

  assertEquals(receipt.merchantName, "Corner Cafe");
  assertEquals(receipt.total, 120);
  assertEquals(calls.length, 1);
  assertMatch(calls[0].url, /gemini-3\.1-flash-lite/);
});

Deno.test("429 on the primary falls through to the next (Gemma) model", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 429, body: "rate limited" },
    { body: geminiBody(RECEIPT_JSON) },
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);

  assertEquals(receipt.merchantName, "Corner Cafe");
  assertEquals(calls.length, 2);
  assertMatch(calls[1].url, /gemma-3-12b-it/);

  // Gemma can't use responseSchema; it must get bare-JSON instructions instead.
  const gen = (calls[1].body.generationConfig ?? {}) as Record<string, unknown>;
  assertEquals(gen.responseSchema, undefined);
  assertEquals(gen.responseMimeType, undefined);
  const parts = (calls[1].body.contents as Array<{ parts: Array<{ text?: string }> }>)[0].parts;
  const promptText = parts.map((p) => p.text ?? "").join("");
  assertMatch(promptText, /Return ONLY a single JSON object/);
});

Deno.test("Gemma reply wrapped in ```json fences is parsed", async () => {
  const fenced = "```json\n" + RECEIPT_JSON + "\n```";
  const { fetchFn } = sequencedFetch([
    { status: 429, body: "busy" }, // skip the Gemini primary
    { body: geminiBody(fenced) }, // gemma-3-12b-it replies with fences
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);
  assertEquals(receipt.merchantName, "Corner Cafe");
  assertEquals(receipt.total, 120);
});

Deno.test("503 is retryable too", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 503, body: "overloaded" },
    { body: geminiBody(RECEIPT_JSON) },
  ]);

  await extractReceipt(IMG, "image/jpeg", "key", fetchFn);
  assertEquals(calls.length, 2);
});

Deno.test("every model rate-limited throws after exhausting the chain", async () => {
  const { fetchFn, calls } = sequencedFetch([{ status: 429, body: "nope" }]);

  await assertRejects(
    () => extractReceipt(IMG, "image/jpeg", "key", fetchFn),
    Error,
    "rate-limited",
  );
  // One call per model in the chain (currently 5).
  assert(calls.length >= 5);
});

Deno.test("a non-retryable error surfaces immediately, no fallthrough", async () => {
  const { fetchFn, calls } = sequencedFetch([{ status: 400, body: "bad request" }]);

  await assertRejects(
    () => extractReceipt(IMG, "image/jpeg", "key", fetchFn),
    Error,
    "(400)",
  );
  assertEquals(calls.length, 1);
});

Deno.test("missing api key / image are guarded before any fetch", async () => {
  let called = false;
  const fetchFn = (_u: string, _i: RequestInit) => {
    called = true;
    return Promise.resolve(new Response("{}"));
  };
  await assertRejects(() => extractReceipt(IMG, "image/jpeg", undefined, fetchFn));
  await assertRejects(() => extractReceipt("", "image/jpeg", "key", fetchFn));
  assertEquals(called, false);
});
