// Shared Google Gemini plumbing for the Edge Functions that call it
// (gemini_receipt.ts for vision, gemini_categorize.ts for text): the ordered
// model-fallback chain, the "skip this model" status policy, the injectable
// fetch, and lenient JSON parsing. Keeping it in one place stops the model list
// and skip policy from drifting between callers (the gemma-3-vs-4 class of bug).
// Each caller supplies its own prompt / schema / normalize via the per-model
// callback passed to runWithModelFallback.

export type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

// Ordered fallback chain. The free Gemini tier rate-limits easily, so when a
// model is busy OR unavailable (see SKIP_MODEL) we move to the next one rather
// than failing. Lead with confirmed Gemini models so a rate-limit cascade stays
// on known-good models; the Gemma entries are deep fallbacks for extra capacity.
// Gemma can't use Gemini's responseSchema JSON mode, so callers send those models
// a bare-JSON instruction instead. Verified against the key's live ListModels —
// note it exposes Gemma *4*, not Gemma 3. An entry not enabled for the key just
// 404s and is skipped, so the chain degrades gracefully.
export const MODELS = [
  "gemini-2.5-flash-lite",
  "gemini-3.1-flash-lite",
  "gemini-2.5-flash",
  "gemma-4-26b-a4b-it",
  "gemma-4-31b-it",
] as const;

export const endpoint = (model: string) =>
  `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

export const isGemma = (model: string) => model.startsWith("gemma");

// HTTP statuses that mean "skip this model, try the next one in the chain":
//  - 429 / 503: the model is busy (the free tier hits these constantly).
//  - 400 / 404: the model isn't available for this key / version.
//  - 500 / 502 / 504: a transient server-side error on this model.
// Auth failures (401/403) are the one thing surfaced immediately — they're
// key-level and would fail identically on every model, so burning the rest of the
// chain is pointless.
export const SKIP_MODEL = new Set([400, 404, 429, 500, 502, 503, 504]);

// Thrown for a SKIP_MODEL status (or a content-less 200) so runWithModelFallback
// knows to fall through to the next model instead of surfacing the error.
export class SkipModel extends Error {}

export const defaultFetch: FetchFn = (url, init) =>
  fetch(url, { ...init, signal: AbortSignal.timeout(30000) });

// Parses the model's text into an object, tolerating the ```json … ``` code
// fences Gemma sometimes wraps its output in.
export function parseJson(text: string): Record<string, unknown> {
  let t = text.trim();
  const fence = t.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  if (fence) t = fence[1].trim();
  try {
    return JSON.parse(t);
  } catch {
    throw new Error("model returned non-JSON content");
  }
}

// Tries each model in MODELS until one returns a result. [callOnce] runs one
// model and throws SkipModel to fall through to the next; any other error
// surfaces immediately (a real failure that would repeat on every model). Throws
// once the whole chain is exhausted.
export async function runWithModelFallback<T>(
  callOnce: (model: string) => Promise<T>,
): Promise<T> {
  let lastErr: Error | null = null;
  for (const model of MODELS) {
    try {
      return await callOnce(model);
    } catch (e) {
      const err = e instanceof Error ? e : new Error(String(e));
      if (err instanceof SkipModel) {
        lastErr = err; // model busy or unavailable — fall through to the next one
        continue;
      }
      throw err; // a real failure — surface it now, don't burn the chain
    }
  }
  throw new Error(
    `All ${MODELS.length} models unavailable; last: ${lastErr?.message ?? "unknown"}`,
  );
}
