// Classifies merchant names and item names into the user's expense categories
// with Google Gemini — the text-only counterpart of gemini_receipt.ts and step 3
// of the categorize flow (history → keyword rules → Gemini). It only ever sees
// the rows the cheaper steps couldn't categorize, runs server-side (Edge
// Function) so GOOGLE_AI_API_KEY never ships in the client, and returns a plain
// name → category-key map the client maps to ids and writes back.
//
// Dependency-free with an injectable fetch so it's deno-testable in isolation.
// The model-fallback chain, skip policy, fetch and JSON parsing are shared with
// the vision receipt extractor — see ./gemini.ts.

import {
  defaultFetch,
  endpoint,
  type FetchFn,
  isGemma,
  parseJson,
  runWithModelFallback,
  SKIP_MODEL,
  SkipModel,
} from "./gemini.ts";

/// A category the model may pick from, mirroring a row of the user's `categories`.
export interface CategoryOption {
  key: string;
  label: string;
}

export interface CategorizeInput {
  items: string[];
  merchants: string[];
  categories: CategoryOption[];
}

/// Each input name mapped to a chosen category key (one of the allowed keys) or
/// null when the model couldn't place it. Names absent from the model's answer
/// are simply missing (treated as null by the caller).
export interface CategorizeResult {
  items: Record<string, string | null>;
  merchants: Record<string, string | null>;
}

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    items: namedKeyArray(),
    merchants: namedKeyArray(),
  },
  required: ["items", "merchants"],
} as const;

// One array of {name, key}. `key` is a bare nullable STRING (not an enum) — the
// allowed set is dynamic per user and validated in normalize() instead, which
// also keeps the schema valid when the model wants to answer null.
function namedKeyArray() {
  return {
    type: "ARRAY",
    items: {
      type: "OBJECT",
      properties: {
        name: { type: "STRING" },
        key: { type: "STRING", nullable: true },
      },
      required: ["name"],
    },
  };
}

function buildPrompt(input: CategorizeInput): string {
  const allowed = input.categories
    .map((c) => `- ${c.key} — ${c.label}`)
    .join("\n");
  const list = (names: string[]) =>
    names.length ? names.map((n) => `- ${n}`).join("\n") : "(none)";
  return `You categorize merchant names and item names from Taiwan receipts into
expense categories for an expense tracker. Names may be in Traditional Chinese or
English.

Choose the single best category KEY for each name from the allowed list below, or
null when none clearly fits — do not guess. Use exactly the keys as written.

Allowed categories (key — label):
${allowed}

Merchant names:
${list(input.merchants)}

Item names:
${list(input.items)}

Return, for every name above, an object {name, key}: put merchant results in
"merchants" and item results in "items". Echo each name exactly as given; set key
to one of the allowed keys or null.`;
}

const JSON_ONLY_INSTRUCTION =
  `Return ONLY a single JSON object and nothing else — no markdown, no code
fences, no commentary. Shape: {"merchants": [{"name": string, "key": string|null}],
"items": [{"name": string, "key": string|null}]}.`;

/// Classifies [input.merchants] and [input.items] against [input.categories].
/// Returns empty maps without calling Gemini when there is nothing to classify
/// or no categories to choose from. Throws on a hard failure (no key, transport
/// error, no parseable JSON) so the handler can surface it.
export async function categorizeNames(
  input: CategorizeInput,
  apiKey: string | undefined,
  fetchFn: FetchFn = defaultFetch,
): Promise<CategorizeResult> {
  if (!apiKey) throw new Error("GOOGLE_AI_API_KEY is not configured");
  const nothingToDo = input.items.length === 0 && input.merchants.length === 0;
  if (nothingToDo || input.categories.length === 0) {
    return { items: {}, merchants: {} };
  }
  return runWithModelFallback((model) => callModel(model, input, apiKey, fetchFn));
}

async function callModel(
  model: string,
  input: CategorizeInput,
  apiKey: string,
  fetchFn: FetchFn,
): Promise<CategorizeResult> {
  const gemma = isGemma(model);
  const prompt = gemma
    ? `${buildPrompt(input)}\n\n${JSON_ONLY_INSTRUCTION}`
    : buildPrompt(input);
  const generationConfig = gemma
    ? { temperature: 0 }
    : {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
      temperature: 0,
    };

  const res = await fetchFn(`${endpoint(model)}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig,
    }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    const message = `Gemini request failed (${res.status}) on ${model}: ${detail.slice(0, 300)}`;
    if (SKIP_MODEL.has(res.status)) throw new SkipModel(message);
    throw new Error(message);
  }

  const body = await res.json();
  const text: unknown = body?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string" || text.trim() === "") {
    // A 200 with no content (safety block / MAX_TOKENS / promptFeedback only) is
    // a model-level miss, not a fatal error — skip to the next model in the chain
    // rather than failing the whole batch.
    throw new SkipModel(`${model} returned no content`);
  }
  const allowed = new Set(input.categories.map((c) => c.key));
  return normalize(parseJson(text), allowed, input);
}

// Coerces the model's JSON into name → key maps, dropping any key not in the
// allowed set (→ null) so a hallucinated category can never reach the database.
// Results are keyed by the REQUESTED names ([input]), not the names the model
// echoed: the client writes back by the exact name it asked about, so any
// trimming/casing drift in the model's echo would otherwise silently drop the
// mapping. Every requested name is present (null when the model didn't place it).
function normalize(
  raw: Record<string, unknown>,
  allowed: Set<string>,
  input: CategorizeInput,
): CategorizeResult {
  return {
    items: toMap(raw.items, allowed, input.items),
    merchants: toMap(raw.merchants, allowed, input.merchants),
  };
}

function toMap(
  value: unknown,
  allowed: Set<string>,
  requested: string[],
): Record<string, string | null> {
  // Index the model's answers by a normalized name (trim + lowercase) so we can
  // match them back to the requested names tolerant of echo drift.
  const byNorm = new Map<string, string | null>();
  if (Array.isArray(value)) {
    for (const entry of value) {
      if (typeof entry !== "object" || entry === null) continue;
      const r = entry as Record<string, unknown>;
      const name = typeof r.name === "string" ? r.name.trim() : "";
      if (!name) continue;
      const key = typeof r.key === "string" ? r.key.trim() : "";
      byNorm.set(name.toLowerCase(), key && allowed.has(key) ? key : null);
    }
  }
  const out: Record<string, string | null> = {};
  for (const name of requested) {
    out[name] = byNorm.get(name.trim().toLowerCase()) ?? null;
  }
  return out;
}
