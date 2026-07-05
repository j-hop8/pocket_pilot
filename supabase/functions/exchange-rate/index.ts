// exchange-rate Edge Function.
//
// Returns a foreign→TWD exchange rate for converting travel receipts, cached in
// the fx_rates table so we don't hit the upstream API on every scan. The upstream
// (open.er-api.com) is keyless and — unlike ECB/frankfurter — includes TWD.
//
// POST { base, quote?, date? } → { rate: number|null, rate_date: string }.
// `quote` defaults to TWD (the home currency); `date` defaults to today
// (Asia/Taipei). Gateway JWT verification is left on (the app always invokes
// with the user's session JWT), so only signed-in callers reach it. Best-effort:
// any upstream failure resolves to { rate: null } so the scan still saves the
// receipt (unconverted, still editable) — same shape as merchant-lookup.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { fetchFxRate } from "../_shared/fx.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const HOME = "TWD"; // home currency every dashboard/budget sums

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  // Asia/Taipei calendar day — matches the rest of the app's day boundaries.
  const today = new Date().toLocaleDateString("en-CA", {
    timeZone: "Asia/Taipei",
  });

  let base = "";
  let quote = HOME;
  let date = today;
  try {
    const body = await req.json();
    if (body && typeof body.base === "string") base = body.base.toUpperCase();
    if (body && typeof body.quote === "string") quote = body.quote.toUpperCase();
    if (body && typeof body.date === "string") date = body.date;
  } catch {
    base = ""; // malformed body → just a miss
  }

  if (!base) return json({ rate: null, rate_date: date });
  if (base === quote) return json({ rate: 1, rate_date: date });

  // Service-role client: the fx_rates cache is shared reference data, written
  // only here (bypassing RLS), and read by any signed-in user.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // 1. Cache hit?
  const { data: cached } = await admin
    .from("fx_rates")
    .select("rate")
    .eq("base", base)
    .eq("quote", quote)
    .eq("rate_date", date)
    .maybeSingle();
  if (cached?.rate != null) {
    return json({ rate: Number(cached.rate), rate_date: date });
  }

  // 2. Miss — fetch upstream (best-effort) and cache on success.
  let rate: number | null = null;
  try {
    rate = await fetchFxRate(base, quote);
  } catch (e) {
    console.error("fetchFxRate failed:", e instanceof Error ? e.message : e);
  }

  if (rate != null) {
    const { error } = await admin
      .from("fx_rates")
      .upsert({ base, quote, rate_date: date, rate });
    if (error) console.error("fx_rates upsert failed:", error.message);
  }

  return json({ rate, rate_date: date });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
