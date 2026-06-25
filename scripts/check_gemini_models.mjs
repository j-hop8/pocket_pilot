// Live diagnostic for the extract-receipt model fallback chain.
//
// Answers two questions against the real Gemini API, using the same key the
// edge function uses:
//   1. Which models does this key expose for generateContent? (ListModels)
//   2. Does each model in our hardcoded chain actually work for an image call?
//      (one minimal generateContent probe per model — mirrors gemini_receipt.ts)
//
// Run it with the same key extract-receipt uses:
//   GOOGLE_AI_API_KEY=<key> node scripts/check_gemini_models.mjs
// (or `supabase secrets list` won't show values — copy the key from wherever you
// set it, e.g. Google AI Studio.)
//
// No dependencies; needs Node 18+ for global fetch. Exits non-zero if any chain
// model is unreachable so it's CI-friendly.

const API = "https://generativelanguage.googleapis.com/v1beta";

// Default mirrors MODELS in supabase/functions/_shared/gemini_receipt.ts. Pass
// model IDs as CLI args to probe an arbitrary set instead (e.g. to sweep older
// free-tier models and check whether a 429 is account-wide or model-specific).
const CHAIN = process.argv.slice(2).length
  ? process.argv.slice(2)
  : [
      "gemini-2.5-flash-lite",
      "gemini-3.1-flash-lite",
      "gemini-2.5-flash",
      "gemma-4-26b-a4b-it",
      "gemma-4-31b-it",
    ];

const isGemma = (m) => m.startsWith("gemma");

// 1x1 transparent PNG — enough to exercise the image (inline_data) path.
const PIXEL =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

const key = process.env.GOOGLE_AI_API_KEY;
if (!key) {
  console.error("Set GOOGLE_AI_API_KEY (the same key extract-receipt uses).");
  process.exit(2);
}

// ── 1. ListModels: everything this key can call generateContent on ──────────
async function listModels() {
  const names = [];
  let pageToken = "";
  do {
    const url =
      `${API}/models?key=${key}&pageSize=200` +
      (pageToken ? `&pageToken=${pageToken}` : "");
    const res = await fetch(url);
    if (!res.ok) {
      console.error(`ListModels failed (${res.status}): ${await res.text()}`);
      process.exit(1);
    }
    const body = await res.json();
    for (const m of body.models ?? []) {
      if ((m.supportedGenerationMethods ?? []).includes("generateContent")) {
        names.push(m.name.replace(/^models\//, ""));
      }
    }
    pageToken = body.nextPageToken ?? "";
  } while (pageToken);
  return names.sort();
}

// ── 2. Probe one model with a real (tiny) image generateContent call ────────
async function probe(model) {
  const generationConfig = isGemma(model)
    ? { temperature: 0, maxOutputTokens: 16 }
    : { responseMimeType: "application/json", temperature: 0, maxOutputTokens: 16 };
  const body = {
    contents: [
      {
        parts: [
          { inline_data: { mime_type: "image/png", data: PIXEL } },
          { text: isGemma(model) ? 'Reply with {"ok":1}' : "Reply with JSON {\"ok\":1}" },
        ],
      },
    ],
    generationConfig,
  };
  try {
    const res = await fetch(`${API}/models/${model}:generateContent?key=${key}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(30000),
    });
    if (res.ok) return { status: res.status, ok: true };
    const detail = (await res.text()).replace(/\s+/g, " ").slice(0, 160);
    return { status: res.status, ok: false, detail };
  } catch (e) {
    return { status: 0, ok: false, detail: String(e?.message ?? e) };
  }
}

const available = await listModels();
console.log(`\nModels this key exposes for generateContent (${available.length}):`);
for (const n of available) console.log(`  ${n}`);

console.log(`\nProbing the extract-receipt chain (one image call each):`);
let firstWorking = null;
let failures = 0;
for (const model of CHAIN) {
  const listed = available.includes(model) ? "listed" : "NOT in ListModels";
  const r = await probe(model);
  const mark = r.ok ? "✅" : r.status === 429 || r.status === 503 ? "⏳" : "❌";
  const note = r.ok ? "works" : `${r.status} ${r.detail ?? ""}`.trim();
  console.log(`  ${mark} ${model.padEnd(24)} [${listed}]  ${note}`);
  if (r.ok && !firstWorking) firstWorking = model;
  // 429/503 mean "busy", not "broken" — the chain handles those, don't count them.
  if (!r.ok && r.status !== 429 && r.status !== 503) failures++;
}

console.log(
  firstWorking
    ? `\nFirst working model: ${firstWorking} — scans will succeed.`
    : `\nNo chain model answered — scans will fail. Check the key / quota.`,
);
process.exit(failures > 0 && !firstWorking ? 1 : 0);
