// extract-receipt Edge Function.
//
// A paper receipt / invoice has no machine-readable payload, so the image is
// sent to Google Gemini (vision), which returns the structured fields the app
// stores. Running it here keeps GOOGLE_AI_API_KEY server-side (set it with
// `supabase secrets set GOOGLE_AI_API_KEY=…`) and adds CORS so the Flutter web
// client works too — same shape as the merchant-lookup function.
//
// POST { image: <base64>, mimeType?: string } → ExtractedReceipt JSON.
// Gateway JWT verification is left on (the app always invokes with the user's
// session JWT), so only signed-in callers reach it. Each Gemini call costs
// money/quota, so before extracting we check the caller's daily quota
// (check_extraction_quota, DAILY_LIMIT/day, read-only) and answer 429 once it's
// spent. A hard failure (missing key, model/transport error, unparseable output)
// answers 502 so the client marks just that scan job failed — and because we only
// record_extraction() *after* a success, a failed scan doesn't spend a slot.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type ExtractedReceipt, extractReceipt } from "../_shared/gemini_receipt.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const DAILY_LIMIT = 30; // Gemini extractions per user per day.

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  let image: string | null = null;
  let mimeType = "image/jpeg";
  try {
    const body = await req.json();
    if (body && typeof body.image === "string") image = body.image;
    if (body && typeof body.mimeType === "string") mimeType = body.mimeType;
  } catch {
    image = null; // malformed body
  }

  if (!image) return json({ error: "missing image" }, 400);

  // ── Daily per-user quota (success-only) ────────────────────────────────────
  // Run the RPCs as the caller (their JWT) so they read auth.uid(). We check the
  // quota read-only first (the 31st call of the day is rejected with 429 before
  // we spend any Gemini money), then record a slot only after a successful
  // extraction below — so a failed scan never burns a slot.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);
  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: allowed, error: quotaErr } = await client.rpc(
    "check_extraction_quota",
    { p_limit: DAILY_LIMIT },
  );
  if (quotaErr) return json({ error: quotaErr.message }, 502);
  if (allowed === false) {
    return json(
      { error: "daily extraction limit reached", code: "rate_limited", limit: DAILY_LIMIT },
      429,
    );
  }

  let receipt: ExtractedReceipt;
  try {
    receipt = await extractReceipt(
      image,
      mimeType,
      Deno.env.get("GOOGLE_AI_API_KEY"),
    );
  } catch (e) {
    // A failed extraction spends no slot — we never reach record_extraction().
    return json({ error: e instanceof Error ? e.message : String(e) }, 502);
  }

  // The extraction succeeded — now spend the slot. If the counter write fails,
  // don't punish the user (the receipt is good): log it and return the receipt,
  // leaving this one uncounted.
  const { error: recordErr } = await client.rpc("record_extraction");
  if (recordErr) console.error("record_extraction failed:", recordErr.message);

  return json(receipt);
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
