// Unit tests for the categorize classifier's model-fallback chain. Mocks
// `fetchFn` so no live Gemini call is made — covers the happy path, falling
// through on a 429, the Gemma bare-JSON branch, ```json fence parsing, dropping a
// hallucinated category, exhausting the chain, a fatal error short-circuiting,
// and the no-op guards (no key / nothing to classify) that skip fetch entirely.
//
// Run with: `deno test supabase/functions`.

import {
  assert,
  assertEquals,
  assertMatch,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { categorizeNames, type CategorizeInput } from "./gemini_categorize.ts";

const INPUT: CategorizeInput = {
  items: ["綠茶", "鉛筆"],
  merchants: ["佐亨"],
  categories: [
    { key: "dining", label: "Dining 餐飲" },
    { key: "education", label: "Education 教育" },
  ],
};

/// Wraps a model's text output in the Gemini generateContent response shape.
function geminiBody(text: string): string {
  return JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] });
}

const RESULT_JSON = JSON.stringify({
  items: [
    { name: "綠茶", key: "dining" },
    { name: "鉛筆", key: "education" },
  ],
  merchants: [{ name: "佐亨", key: "dining" }],
});

interface Recorded {
  url: string;
  body: Record<string, unknown>;
}

function sequencedFetch(responses: Array<{ status?: number; body: string }>) {
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

Deno.test("primary model success — maps every name, one call", async () => {
  const { fetchFn, calls } = sequencedFetch([{ body: geminiBody(RESULT_JSON) }]);

  const out = await categorizeNames(INPUT, "key", fetchFn);

  assertEquals(out.items["綠茶"], "dining");
  assertEquals(out.items["鉛筆"], "education");
  assertEquals(out.merchants["佐亨"], "dining");
  assertEquals(calls.length, 1);
  assertMatch(calls[0].url, /gemini-2\.5-flash-lite/);
  // Text-only request — no inline image part.
  const parts = (calls[0].body.contents as Array<{ parts: unknown[] }>)[0].parts;
  assertEquals(parts.length, 1);
});

Deno.test("429 on the primary falls through to the next model", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 429, body: "rate limited" },
    { body: geminiBody(RESULT_JSON) },
  ]);

  const out = await categorizeNames(INPUT, "key", fetchFn);

  assertEquals(out.merchants["佐亨"], "dining");
  assertEquals(calls.length, 2);
  assertMatch(calls[1].url, /gemini-3\.1-flash-lite/);
});

Deno.test("a key outside the allowed set is dropped to null", async () => {
  const stray = JSON.stringify({
    items: [
      { name: "綠茶", key: "groceries" }, // not in the allowed set
      { name: "鉛筆", key: "education" },
    ],
    merchants: [{ name: "佐亨", key: null }],
  });
  const { fetchFn } = sequencedFetch([{ body: geminiBody(stray) }]);

  const out = await categorizeNames(INPUT, "key", fetchFn);

  assertEquals(out.items["綠茶"], null); // hallucinated category rejected
  assertEquals(out.items["鉛筆"], "education");
  assertEquals(out.merchants["佐亨"], null);
});

Deno.test("Gemma fallback sends bare-JSON config, no responseSchema", async () => {
  const { fetchFn, calls } = sequencedFetch([
    { status: 429, body: "busy" }, // gemini-2.5-flash-lite
    { status: 429, body: "busy" }, // gemini-3.1-flash-lite
    { status: 429, body: "busy" }, // gemini-2.5-flash
    { body: geminiBody(RESULT_JSON) }, // gemma-4-26b-a4b-it
  ]);

  const out = await categorizeNames(INPUT, "key", fetchFn);

  assertEquals(out.items["綠茶"], "dining");
  assertEquals(calls.length, 4);
  assertMatch(calls[3].url, /gemma-4-26b-a4b-it/);

  const gen = (calls[3].body.generationConfig ?? {}) as Record<string, unknown>;
  assertEquals(gen.responseSchema, undefined);
  assertEquals(gen.responseMimeType, undefined);
  const parts =
    (calls[3].body.contents as Array<{ parts: Array<{ text?: string }> }>)[0].parts;
  const promptText = parts.map((p) => p.text ?? "").join("");
  assertMatch(promptText, /Return ONLY a single JSON object/);
});

Deno.test("a reply wrapped in ```json fences is parsed", async () => {
  const fenced = "```json\n" + RESULT_JSON + "\n```";
  const { fetchFn } = sequencedFetch([
    { status: 429, body: "busy" }, // skip the primary
    { body: geminiBody(fenced) },
  ]);

  const out = await categorizeNames(INPUT, "key", fetchFn);
  assertEquals(out.items["鉛筆"], "education");
});

Deno.test("a content-less 200 skips to the next model", async () => {
  // 200 OK but no candidate (safety block / MAX_TOKENS / promptFeedback only).
  const noContent = JSON.stringify({ candidates: [] });
  const { fetchFn, calls } = sequencedFetch([
    { body: noContent }, // primary answers 200 with nothing usable
    { body: geminiBody(RESULT_JSON) }, // next model in the chain answers
  ]);

  const out = await categorizeNames(INPUT, "key", fetchFn);

  assertEquals(out.items["綠茶"], "dining");
  assertEquals(calls.length, 2);
  assertMatch(calls[1].url, /gemini-3\.1-flash-lite/);
});

Deno.test("result is keyed by the requested name despite model echo drift", async () => {
  const input: CategorizeInput = {
    items: ["Latte", "綠茶"],
    merchants: [],
    categories: [{ key: "dining", label: "Dining 餐飲" }],
  };
  // The model echoes names with different casing / extra whitespace than asked.
  const drifted = JSON.stringify({
    items: [
      { name: "  latte ", key: "dining" },
      { name: "綠茶", key: "dining" },
    ],
    merchants: [],
  });
  const { fetchFn } = sequencedFetch([{ body: geminiBody(drifted) }]);

  const out = await categorizeNames(input, "key", fetchFn);

  // Keyed by the EXACT requested names, so the client can write them back.
  assertEquals(out.items["Latte"], "dining");
  assertEquals(out.items["綠茶"], "dining");
  // Names the model never echoed are present as null, never missing.
  assertEquals(Object.keys(out.items).sort(), ["Latte", "綠茶"]);
});

Deno.test("every model unavailable throws after exhausting the chain", async () => {
  const { fetchFn, calls } = sequencedFetch([{ status: 429, body: "nope" }]);

  await assertRejects(
    () => categorizeNames(INPUT, "key", fetchFn),
    Error,
    "unavailable",
  );
  assert(calls.length >= 5); // one call per model in the chain
});

Deno.test("a fatal (401) error surfaces immediately, no fallthrough", async () => {
  const { fetchFn, calls } = sequencedFetch([{ status: 401, body: "bad key" }]);

  await assertRejects(
    () => categorizeNames(INPUT, "key", fetchFn),
    Error,
    "(401)",
  );
  assertEquals(calls.length, 1);
});

Deno.test("guards run before any fetch: no key, nothing to do, no categories", async () => {
  let called = false;
  const fetchFn = (_u: string, _i: RequestInit) => {
    called = true;
    return Promise.resolve(new Response("{}"));
  };

  // Missing key throws without fetching.
  await assertRejects(() => categorizeNames(INPUT, undefined, fetchFn));

  // Nothing to classify → empty maps, no fetch.
  const empty = await categorizeNames(
    { items: [], merchants: [], categories: INPUT.categories },
    "key",
    fetchFn,
  );
  assertEquals(empty, { items: {}, merchants: {} });

  // No categories to choose from → empty maps, no fetch.
  const noCats = await categorizeNames(
    { items: ["x"], merchants: [], categories: [] },
    "key",
    fetchFn,
  );
  assertEquals(noCats, { items: {}, merchants: {} });

  assertEquals(called, false);
});
