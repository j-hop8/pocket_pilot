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
// (check_extraction_quota, read-only) and answer 429 once it's spent. A hard
// failure (missing key, model/transport error, unparseable output) answers 502
// so the client marks just that scan job failed — and because we only
// record_extraction() *after* a success, a failed scan doesn't spend a slot.
//
// Demo accounts (anonymous sign-in, `is_anonymous` in the JWT) get a *tighter*
// per-user cap (ANON_DAILY_LIMIT) and additionally count against an app-wide
// daily ceiling (GLOBAL_DAILY_LIMIT) so total Gemini spend doesn't scale with
// the number of throwaway visitors. The global counter lives in
// global_extraction_usage and is only ever touched here with the service role.

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
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DAILY_LIMIT = 30; // Gemini extractions per (real) user per day.
const ANON_DAILY_LIMIT = 5; // Tighter per-visitor cap for demo accounts.
const GLOBAL_DAILY_LIMIT = 200; // App-wide ceiling for all demo accounts/day.

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

  // ── Daily quota (success-only) ─────────────────────────────────────────────
  // Run the per-user RPCs as the caller (their JWT) so they read auth.uid(). We
  // check read-only first (the over-limit request is rejected with 429 before we
  // spend any Gemini money), then record a slot only after a successful
  // extraction below — so a failed scan never burns a slot. Demo (anonymous)
  // callers get the tighter ANON_DAILY_LIMIT and also count against a global
  // ceiling.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);
  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const isAnon = isAnonymousJwt(authHeader);
  const perUserLimit = isAnon ? ANON_DAILY_LIMIT : DAILY_LIMIT;
  // Asia/Taipei calendar day — matches check_extraction_quota / record_extraction.
  const today = new Date().toLocaleDateString("en-CA", {
    timeZone: "Asia/Taipei",
  });

  const { data: allowed, error: quotaErr } = await client.rpc(
    "check_extraction_quota",
    { p_limit: perUserLimit },
  );
  if (quotaErr) return json({ error: quotaErr.message }, 502);
  if (allowed === false) {
    return json(
      { error: "daily extraction limit reached", code: "rate_limited", limit: perUserLimit },
      429,
    );
  }

  // Service-role client for the global ceiling (bypasses RLS; the table/RPC are
  // not reachable by client roles). Only demo accounts touch it.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  if (isAnon) {
    const { data: row, error: gErr } = await admin
      .from("global_extraction_usage")
      .select("count")
      .eq("usage_date", today)
      .maybeSingle();
    if (gErr) return json({ error: gErr.message }, 502);
    if ((row?.count ?? 0) >= GLOBAL_DAILY_LIMIT) {
      return json(
        { error: "demo daily limit reached", code: "rate_limited", limit: GLOBAL_DAILY_LIMIT },
        429,
      );
    }
  }

  let receipt: ExtractedReceipt;
  try {
    receipt = await extractReceipt(
      image,
      mimeType,
      Deno.env.get("GOOGLE_AI_API_KEY"),
    );
  } catch (e) {
    // A failed extraction spends no slot — we never reach the record calls.
    return json({ error: e instanceof Error ? e.message : String(e) }, 502);
  }

  // The extraction succeeded — now spend the slot(s). If a counter write fails,
  // don't punish the user (the receipt is good): log it and return the receipt,
  // leaving this one uncounted.
  const { error: recordErr } = await client.rpc("record_extraction");
  if (recordErr) console.error("record_extraction failed:", recordErr.message);

  if (isAnon) {
    const { error: gRecErr } = await admin.rpc("record_global_extraction", {
      p_day: today,
    });
    if (gRecErr) console.error("record_global_extraction failed:", gRecErr.message);
  }

  return json(receipt);
});

// Reads the `is_anonymous` claim from a `Bearer <jwt>` header without verifying
// the signature — the gateway already verified the JWT before we run, so this is
// only a claim read (the worst a forged claim could do is opt *into* the tighter
// demo limits). Returns false on any parse failure.
function isAnonymousJwt(authHeader: string): boolean {
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const payload = token.split(".")[1];
    if (!payload) return false;
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(json).is_anonymous === true;
  } catch {
    return false;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
