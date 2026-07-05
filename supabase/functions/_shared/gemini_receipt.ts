// Reads a receipt / invoice photo with Google Gemini (vision) and returns the
// structured fields PocketPilot stores. Runs server-side (Edge Function) so the
// GOOGLE_AI_API_KEY never ships in the Flutter client, mirroring how merchant-lookup
// keeps the upstream calls off the browser.
//
// Unlike the e-invoice QR path (deterministic local decode), an arbitrary paper
// receipt has no machine-readable payload — so the image goes to the model and
// it returns JSON. Output is forced to a fixed shape via responseSchema so the
// Dart side can parse it without guesswork. Amounts are read in the receipt's own
// printed currency (whole New Taiwan Dollars for TWD — the dollars-not-cents
// convention the QR/CSV pipeline uses before `dollarsToCents`; decimals kept for
// any foreign currency). This currency detection runs on every scan so a foreign
// receipt is recognized even when it isn't tied to an active trip.
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

/// Optional travel hints. Currency detection is unconditional (see buildPrompt),
/// so these only tune the scan: `targetLang` turns on merchant/item translation
/// and `currencyHint` nudges the model toward the destination currency.
export interface ExtractOpts {
  /// The user's app language. When set, the model fills the *Translated fields
  /// with the merchant + item names translated into this language.
  targetLang?: "zh" | "en";
  /// ISO 4217 currency of the travel destination — a hint only; the model still
  /// reports whatever currency is actually printed on the receipt.
  currencyHint?: string;
}

/// One line item. Amounts are in the receipt's own printed currency (whole
/// numbers for TWD; the printed foreign amount, decimals kept, otherwise).
export interface ExtractedItem {
  name: string;
  nameTranslated: string | null; // translated name in travel mode, else null
  quantity: number;
  unitPrice: number;
  amount: number;
}

/// The structured receipt the model returns. Optional fields are null when the
/// receipt doesn't show them.
export interface ExtractedReceipt {
  merchantName: string | null;
  merchantNameTranslated: string | null; // travel mode, else null
  date: string | null; // YYYY-MM-DD
  total: number; // amount in `currency`
  salesAmount: number | null; // pre-tax subtotal, in `currency`
  sellerTaxId: string | null; // 8-digit 統一編號
  invoiceNumber: string | null; // e-invoice number if printed
  kind: "expense" | "income";
  currency: string; // ISO 4217 as printed on the receipt (TWD when none is shown)
  items: ExtractedItem[];
}

// Gemini's OpenAPI-subset schema dialect (uppercase types). Forces the model to
// answer with exactly these fields so parsing is deterministic.
//
// When translating (targetLang set) the *Translated fields are marked **required**
// — on the item objects too — so the model can't skip per-item translations the
// way it does when they're optional (that was the "items not translated" bug).
// `nullable: true` stays so `merchantNameTranslated` can still be null when a
// receipt has no merchant name.
function buildResponseSchema(opts: ExtractOpts) {
  const translating = !!opts.targetLang;
  return {
    type: "OBJECT",
    properties: {
      merchantName: { type: "STRING", nullable: true },
      merchantNameTranslated: { type: "STRING", nullable: true },
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
            nameTranslated: { type: "STRING", nullable: true },
            quantity: { type: "NUMBER" },
            unitPrice: { type: "NUMBER" },
            amount: { type: "NUMBER" },
          },
          required: translating
            ? ["name", "amount", "nameTranslated"]
            : ["name", "amount"],
        },
      },
    },
    required: translating
      ? ["total", "kind", "currency", "items", "merchantNameTranslated"]
      : ["total", "kind", "currency", "items"],
  };
}

const langLabel = (lang: "zh" | "en") =>
  lang === "zh" ? "Traditional Chinese (繁體中文)" : "English";

// One prompt for every scan. Currency detection is unconditional (read the printed
// ISO 4217 code, whole numbers for TWD, decimals kept for any foreign currency) so
// a foreign receipt is recognized even outside an active trip. `currencyHint` only
// nudges the guess and `targetLang` is the sole travel-only behaviour — it appends
// the merchant/item translation rule.
function buildPrompt(opts: ExtractOpts): string {
  const hint = opts.currencyHint
    ? ` This receipt is most likely in ${opts.currencyHint}, but always trust what is printed.`
    : "";
  const translateRule = opts.targetLang
    ? `\n- "merchantNameTranslated": the merchant name translated into ${
      langLabel(opts.targetLang)
    }, or null when there is no merchant name.
- "nameTranslated" on EVERY item: that line item's name translated into ${
      langLabel(opts.targetLang)
    } — include it for every item, never omit it. If the text is already in ${
      langLabel(opts.targetLang)
    }, repeat it unchanged.`
    : "";

  return `You are a receipt and invoice data extractor for a Taiwan expense tracker.
Read the attached photo — it may be a paper receipt, an itemised invoice, a
Taiwan 電子發票, or a foreign receipt, in any language — and return the structured
fields.

Rules:
- Read every money amount in the receipt's own printed currency — do NOT convert
  it. Use whole numbers for New Taiwan Dollars (TWD); for any other currency keep
  the decimals exactly as printed (e.g. 12.50). No currency symbols or thousands
  separators.${hint}
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
- "currency" is the ISO 4217 code of the currency actually printed on the receipt
  (e.g. JPY, USD, EUR, TWD), defaulting to "TWD" when none is shown.
- "items": one entry per line item with name, quantity (default 1), unitPrice and
  amount in the receipt's currency. If the line items are not legible, return an
  empty array — do not invent items.${translateRule}`;
}

// Gemma models can't be constrained with responseSchema, so we instruct them to
// emit bare JSON and parse it leniently (parseJson strips any code fences).
function buildJsonInstruction(opts: ExtractOpts): string {
  const base =
    `Return ONLY a single JSON object and nothing else — no markdown, no code
fences, no commentary. Keys: merchantName (string|null), date (string|null,
YYYY-MM-DD), total (number), salesAmount (number|null), sellerTaxId
(string|null), invoiceNumber (string|null), kind ("expense"|"income"), currency
(string, ISO 4217 as printed), items (array of {name, quantity, unitPrice, amount}).`;
  return opts.targetLang
    ? `${base} Also include merchantNameTranslated (string|null) and, in each item, nameTranslated (string|null).`
    : base;
}

/// Extracts the structured receipt from a base64-encoded image. Throws on a hard
/// failure (no key, transport error, the model returning no parseable JSON) so
/// the handler can surface it; the Flutter side treats any failure as a failed
/// scan job.
export async function extractReceipt(
  imageBase64: string,
  mimeType: string,
  apiKey: string | undefined,
  fetchFn: FetchFn = defaultFetch,
  opts: ExtractOpts = {},
): Promise<ExtractedReceipt> {
  if (!apiKey) throw new Error("GOOGLE_AI_API_KEY is not configured");
  if (!imageBase64) throw new Error("no image provided");

  return runWithModelFallback((model) =>
    callModel(model, imageBase64, mimeType, apiKey, fetchFn, opts)
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
  opts: ExtractOpts,
): Promise<ExtractedReceipt> {
  const gemma = isGemma(model);
  const prompt = gemma
    ? `${buildPrompt(opts)}\n\n${buildJsonInstruction(opts)}`
    : buildPrompt(opts);
  const generationConfig = gemma
    ? { temperature: 0 }
    : {
        responseMimeType: "application/json",
        responseSchema: buildResponseSchema(opts),
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
    merchantNameTranslated: str(raw.merchantNameTranslated),
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
  return { name, nameTranslated: str(r.nameTranslated), quantity, unitPrice, amount };
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
