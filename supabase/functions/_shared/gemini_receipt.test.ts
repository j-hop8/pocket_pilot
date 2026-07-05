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
  assertMatch(calls[0].url, /gemini-2\.5-flash-lite/);
});

Deno.test("429 on the primary falls through to the next model", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 429, body: "rate limited" },
    { body: geminiBody(RECEIPT_JSON) },
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);

  assertEquals(receipt.merchantName, "Corner Cafe");
  assertEquals(calls.length, 2);
  assertMatch(calls[1].url, /gemini-3\.1-flash-lite/);
});

// Regression test for the reported failure: a busy primary (429) followed by an
// unavailable model (404 "is not found ... or is not supported for
// generateContent") must NOT sink the scan — the chain keeps going until a
// working model answers.
Deno.test("a busy model then a 404 model both fall through to a working one", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 429, body: "rate limited" }, // gemini-2.5-flash-lite busy
    { status: 404, body: "model not found" }, // gemini-3.1-flash-lite unavailable
    { body: geminiBody(RECEIPT_JSON) }, // gemini-2.5-flash answers
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);

  assertEquals(receipt.total, 120);
  assertEquals(calls.length, 3);
});

// Reaching the Gemma fallbacks needs every Gemini model in front of them to be
// skipped first (3 here). The Gemma branch must send no responseSchema and the
// bare-JSON instruction instead.
Deno.test("Gemma fallback sends bare-JSON config, no responseSchema", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 429, body: "busy" }, // gemini-2.5-flash-lite
    { status: 429, body: "busy" }, // gemini-3.1-flash-lite
    { status: 429, body: "busy" }, // gemini-2.5-flash
    { body: geminiBody(RECEIPT_JSON) }, // gemma-4-26b-a4b-it
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);

  assertEquals(receipt.merchantName, "Corner Cafe");
  assertEquals(calls.length, 4);
  assertMatch(calls[3].url, /gemma-4-26b-a4b-it/);

  const gen = (calls[3].body.generationConfig ?? {}) as Record<string, unknown>;
  assertEquals(gen.responseSchema, undefined);
  assertEquals(gen.responseMimeType, undefined);
  const parts = (calls[3].body.contents as Array<{ parts: Array<{ text?: string }> }>)[0].parts;
  const promptText = parts.map((p) => p.text ?? "").join("");
  assertMatch(promptText, /Return ONLY a single JSON object/);
});

Deno.test("a reply wrapped in ```json fences is parsed", async () => {
  const fenced = "```json\n" + RECEIPT_JSON + "\n```";
  const { fetchFn } = sequencedFetch([
    { status: 429, body: "busy" }, // skip the primary
    { body: geminiBody(fenced) }, // next model replies with fences
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);
  assertEquals(receipt.merchantName, "Corner Cafe");
  assertEquals(receipt.total, 120);
});

// A flaky model (Gemma sometimes 500s "Internal error") must not break the chain
// when a later model would succeed.
Deno.test("a transient 500 on a model falls through to the next", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 500, body: "Internal error" },
    { body: geminiBody(RECEIPT_JSON) },
  ]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn);

  assertEquals(receipt.total, 120);
  assertEquals(calls.length, 2);
});

Deno.test("503 is retryable too", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 503, body: "overloaded" },
    { body: geminiBody(RECEIPT_JSON) },
  ]);

  await extractReceipt(IMG, "image/jpeg", "key", fetchFn);
  assertEquals(calls.length, 2);
});

Deno.test("every model unavailable throws after exhausting the chain", async () => {
  const { fetchFn, calls } = sequencedFetch([{ status: 429, body: "nope" }]);

  await assertRejects(
    () => extractReceipt(IMG, "image/jpeg", "key", fetchFn),
    Error,
    "unavailable",
  );
  // One call per model in the chain (currently 5).
  assert(calls.length >= 5);
});

Deno.test("a fatal (non-skippable) error surfaces immediately, no fallthrough", async () => {
  // 401/403 are key-level: they'd fail identically on every model, so we surface
  // them at once rather than burning the whole chain. (404/400, by contrast, are
  // per-model and DO fall through — see the 404 regression test above.)
  const { fetchFn, calls } = sequencedFetch([{ status: 401, body: "bad key" }]);

  await assertRejects(
    () => extractReceipt(IMG, "image/jpeg", "key", fetchFn),
    Error,
    "(401)",
  );
  assertEquals(calls.length, 1);
});

/// Pulls the joined prompt text out of a recorded request body.
function promptOf(call: Recorded): string {
  const parts =
    (call.body.contents as Array<{ parts: Array<{ text?: string }> }>)[0].parts;
  return parts.map((p) => p.text ?? "").join("");
}

Deno.test("default (no opts) still reads the printed currency, whole-TWD, no translation", async () => {
  const { fetchFn, calls } = sequencedFetch([{ body: geminiBody(RECEIPT_JSON) }]);
  await extractReceipt(IMG, "image/jpeg", "key", fetchFn);
  const prompt = promptOf(calls[0]);
  // Currency detection is now unconditional — foreign receipts are recognized even
  // with no travel opts — while TWD still uses whole numbers.
  assertMatch(prompt, /whole numbers for New Taiwan Dollars/);
  assertMatch(prompt, /ISO 4217 code of the currency actually printed/);
  assertEquals(/translated into/.test(prompt), false);
});

Deno.test("travel opts switch in foreign-currency + translation rules", async () => {
  const TRAVEL_JSON = JSON.stringify({
    merchantName: "セブンイレブン",
    merchantNameTranslated: "7-Eleven",
    date: "2026-06-20",
    total: 1500,
    kind: "expense",
    currency: "JPY",
    items: [
      { name: "おにぎり", nameTranslated: "Rice ball", quantity: 2, unitPrice: 150, amount: 300 },
    ],
  });
  const { fetchFn, calls } = sequencedFetch([{ body: geminiBody(TRAVEL_JSON) }]);

  const receipt = await extractReceipt(IMG, "image/jpeg", "key", fetchFn, {
    targetLang: "en",
    currencyHint: "JPY",
  });

  // The foreign currency + translations survive normalization.
  assertEquals(receipt.currency, "JPY");
  assertEquals(receipt.total, 1500);
  assertEquals(receipt.merchantNameTranslated, "7-Eleven");
  assertEquals(receipt.items[0].nameTranslated, "Rice ball");

  // The prompt carried the travel rules + the currency hint.
  const prompt = promptOf(calls[0]);
  assertMatch(prompt, /receipt's own printed currency/);
  assertMatch(prompt, /most likely in JPY/);
  assertMatch(prompt, /translated into English/);
});

/// Reads the responseSchema out of a recorded Gemini (non-Gemma) request.
function schemaOf(call: Recorded): {
  required: string[];
  properties: { items: { items: { required: string[] } } };
} {
  // deno-lint-ignore no-explicit-any
  return (call.body.generationConfig as any).responseSchema;
}

Deno.test("translating marks the translated fields required, per item too", async () => {
  const { fetchFn, calls } = sequencedFetch([{ body: geminiBody(RECEIPT_JSON) }]);
  await extractReceipt(IMG, "image/jpeg", "key", fetchFn, { targetLang: "en" });

  const schema = schemaOf(calls[0]);
  // Forcing these into `required` is what stops the model skipping the per-item
  // translations (the "items not translated" bug).
  assert(schema.required.includes("merchantNameTranslated"));
  assert(schema.properties.items.items.required.includes("nameTranslated"));
});

Deno.test("without targetLang the translated fields stay optional", async () => {
  const { fetchFn, calls } = sequencedFetch([{ body: geminiBody(RECEIPT_JSON) }]);
  await extractReceipt(IMG, "image/jpeg", "key", fetchFn);

  const schema = schemaOf(calls[0]);
  assertEquals(schema.required.includes("merchantNameTranslated"), false);
  assertEquals(
    schema.properties.items.items.required.includes("nameTranslated"),
    false,
  );
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
