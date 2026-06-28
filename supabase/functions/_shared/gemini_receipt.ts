// Reads a receipt / invoice photo with Google Gemini (vision) and returns the
// structured fields PocketPilot stores. Runs server-side (Edge Function) so the
// GOOGLE_AI_API_KEY never ships in the Flutter client, mirroring how merchant-lookup
// keeps the upstream calls off the browser.
//
// Unlike the e-invoice QR path (deterministic local decode), an arbitrary paper
// receipt has no machine-readable payload — so the image goes to the model and
// it returns JSON. Output is forced to a fixed shape via responseSchema so the
// Dart side can parse it without guesswork. Amounts are whole New Taiwan Dollars
// (the same dollars-not-cents convention the QR/CSV pipeline uses before
// `dollarsToCents`).
//
// Dependency-free with an injectable fetch so it's deno-testable in isolation.
// The model-fallback chain, skip policy, fetch and JSON parsing are shared with
// the text categorizer — see ./gemini.ts.

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

/// One line item, amounts in whole dollars.
export interface ExtractedItem {
  name: string;
  quantity: number;
  unitPrice: number;
  amount: number;
}

/// The structured receipt the model returns. Optional fields are null when the
/// receipt doesn't show them.
export interface ExtractedReceipt {
  merchantName: string | null;
  date: string | null; // YYYY-MM-DD
  total: number; // whole dollars
  salesAmount: number | null; // pre-tax subtotal, whole dollars
  sellerTaxId: string | null; // 8-digit 統一編號
  invoiceNumber: string | null; // e-invoice number if printed
  kind: "expense" | "income";
  currency: string;
  items: ExtractedItem[];
}

// Gemini's OpenAPI-subset schema dialect (uppercase types). Forces the model to
// answer with exactly these fields so parsing is deterministic.
const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    merchantName: { type: "STRING", nullable: true },
    date: { type: "STRING", nullable: true },
    total: { type: "NUMBER" },
    salesAmount: { type: "NUMBER", nullable: true },
    sellerTaxId: { type: "STRING", nullable: true },
    invoiceNumber: { type: "STRING", nullable: true },
    kind: { type: "STRING", enum: ["expense", "income"] },
    currency: { type: "STRING" },
    items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          name: { type: "STRING" },
          quantity: { type: "NUMBER" },
          unitPrice: { type: "NUMBER" },
          amount: { type: "NUMBER" },
        },
        required: ["name", "amount"],
      },
    },
  },
  required: ["total", "kind", "currency", "items"],
} as const;

const PROMPT =
  `You are a receipt and invoice data extractor for a Taiwan expense tracker.
Read the attached photo — it may be a paper receipt, an itemised invoice, a
Taiwan 電子發票, or a foreign receipt, in Traditional Chinese or English — and
return the structured fields.

Rules:
- All money amounts are whole New Taiwan Dollars as numbers (no currency symbol,
  no thousands separators, no decimals unless the receipt truly shows them).
- "total" is the final amount actually paid (after tax/discounts).
- "salesAmount" is the pre-tax subtotal if the receipt shows one, else null.
- "date" is the transaction date printed on the receipt as YYYY-MM-DD. Convert
  ROC/民國 years (year + 1911) to the Gregorian year. If no date is legible, null.
- "sellerTaxId" is the seller's 8-digit 統一編號 if printed, else null.
- "invoiceNumber" is the e-invoice number (two letters + 8 digits, e.g.
  AB12345678) if printed, else null.
- "merchantName" is the store / company name printed on the receipt, else null.
- "kind" is "income" only for money coming in (payslip, refund, payout);
  otherwise "expense".
- "currency" defaults to "TWD".
- "items": one entry per line item with name, quantity (default 1), unitPrice and
  amount in whole dollars. If the line items are not legible, return an empty
  array — do not invent items.`;

// Gemma models can't be constrained with responseSchema, so we instruct them to
// emit bare JSON and parse it leniently (parseJson strips any code fences).
const JSON_ONLY_INSTRUCTION =
  `Return ONLY a single JSON object and nothing else — no markdown, no code
fences, no commentary. Keys: merchantName (string|null), date (string|null,
YYYY-MM-DD), total (number), salesAmount (number|null), sellerTaxId
(string|null), invoiceNumber (string|null), kind ("expense"|"income"), currency
(string), items (array of {name, quantity, unitPrice, amount}).`;

/// Extracts the structured receipt from a base64-encoded image. Throws on a hard
/// failure (no key, transport error, the model returning no parseable JSON) so
/// the handler can surface it; the Flutter side treats any failure as a failed
/// scan job.
export async function extractReceipt(
  imageBase64: string,
  mimeType: string,
  apiKey: string | undefined,
  fetchFn: FetchFn = defaultFetch,
): Promise<ExtractedReceipt> {
  if (!apiKey) throw new Error("GOOGLE_AI_API_KEY is not configured");
  if (!imageBase64) throw new Error("no image provided");
  return runWithModelFallback((model) =>
    callModel(model, imageBase64, mimeType, apiKey, fetchFn)
  );
}

// Sends the image+prompt to one model and returns the normalized receipt. Gemini
// models are constrained to JSON via responseSchema; Gemma models get the bare
// PROMPT plus JSON_ONLY_INSTRUCTION and lenient parsing. Throws SkipModel on a
// SKIP_MODEL status so the caller can try the next model.
async function callModel(
  model: string,
  imageBase64: string,
  mimeType: string,
  apiKey: string,
  fetchFn: FetchFn,
): Promise<ExtractedReceipt> {
  const gemma = isGemma(model);
  const prompt = gemma ? `${PROMPT}\n\n${JSON_ONLY_INSTRUCTION}` : PROMPT;
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
      contents: [
        {
          parts: [
            { inline_data: { mime_type: mimeType || "image/jpeg", data: imageBase64 } },
            { text: prompt },
          ],
        },
      ],
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
    throw new Error(`${model} returned no content`);
  }
  return normalize(parseJson(text));
}

// Coerces the model's JSON into the typed shape with safe fallbacks, so a missing
// or odd field can never crash the handler.
function normalize(raw: Record<string, unknown>): ExtractedReceipt {
  const items = Array.isArray(raw.items)
    ? raw.items.map(normalizeItem).filter((i): i is ExtractedItem => i !== null)
    : [];
  return {
    merchantName: str(raw.merchantName),
    date: str(raw.date),
    total: num(raw.total) ?? 0,
    salesAmount: num(raw.salesAmount),
    sellerTaxId: str(raw.sellerTaxId),
    invoiceNumber: str(raw.invoiceNumber),
    kind: raw.kind === "income" ? "income" : "expense",
    currency: str(raw.currency) ?? "TWD",
    items,
  };
}

function normalizeItem(raw: unknown): ExtractedItem | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const name = str(r.name);
  if (name === null) return null;
  const amount = num(r.amount) ?? 0;
  const quantity = num(r.quantity) ?? 1;
  const unitPrice = num(r.unitPrice) ?? amount;
  return { name, quantity, unitPrice, amount };
}

function str(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function num(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const n = Number(value.replace(/[,\s]/g, ""));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}
