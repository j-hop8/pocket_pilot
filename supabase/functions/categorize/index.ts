// categorize Edge Function — step 3 of the categorize flow (history → keyword
// rules → Gemini). The client gathers the names the cheaper steps couldn't place
// (distinct uncategorized merchant + item names) plus the user's category
// vocabulary and posts them here; we classify them with Google Gemini and return
// a name → category-key map. Running it server-side keeps GOOGLE_AI_API_KEY off
// the client (set it with `supabase secrets set GOOGLE_AI_API_KEY=…`) and adds
// CORS for the Flutter web client — same shape as extract-receipt.
//
// POST { items: string[], merchants: string[], categories: {key,label}[] }
//   → { items: {<name>: <key|null>}, merchants: {<name>: <key|null>} }
//
// Gateway JWT verification is left on, so only signed-in callers reach it. Each
// Gemini call costs money/quota, so before classifying we atomically reserve the
// caller's daily slot (reserve_categorize) and answer 429 once it's spent; if the
// classification then fails we refund the slot (refund_categorize) and answer 502,
// so a failure never burns quota. Demo accounts (anonymous sign-in) are blocked with 403 — they have
// negligible data and the demo budget is reserved for receipt scans, mirroring the
// demo carrier-sync block.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  type CategorizeResult,
  categorizeNames,
} from "../_shared/gemini_categorize.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const DAILY_LIMIT = 20; // Gemini categorize batches per user per day.

interface CategoryOption {
  key: string;
  label: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  // ── Parse + validate the request body ───────────────────────────────────────
  let items: string[] = [];
  let merchants: string[] = [];
  let categories: CategoryOption[] = [];
  try {
    const body = await req.json();
    items = strings(body?.items);
    merchants = strings(body?.merchants);
    categories = categoryOptions(body?.categories);
  } catch {
    return json({ error: "malformed body" }, 400);
  }

  if (categories.length === 0) return json({ error: "no categories" }, 400);
  if (items.length === 0 && merchants.length === 0) {
    return json({ items: {}, merchants: {} }); // nothing to do — no Gemini call
  }

  // ── Auth: signed-in, non-anonymous callers only ─────────────────────────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);
  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  // Resolve the caller authoritatively — getUser validates the JWT against the
  // auth server, so we read a verified `is_anonymous` rather than parsing the
  // token ourselves. Demo (anonymous) accounts are blocked, mirroring the demo
  // carrier-sync block: they have negligible data and the budget is reserved for
  // receipt scans.
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const { data: { user }, error: userErr } = await client.auth.getUser(token);
  if (userErr || !user) return json({ error: "unauthorized" }, 401);
  if (user.is_anonymous === true) {
    return json({ error: "demo accounts cannot auto-categorize", code: "anon_forbidden" }, 403);
  }

  // ── Daily quota (atomic reserve, refund on failure) ─────────────────────────
  // Atomically reserve a slot before spending Gemini money: a single row-locked
  // statement, so concurrent batches can't both pass and overshoot the cap. If
  // the classification then fails we refund the slot, so a failure never burns
  // quota.
  const { data: reserved, error: quotaErr } = await client.rpc(
    "reserve_categorize",
    { p_limit: DAILY_LIMIT },
  );
  if (quotaErr) return json({ error: quotaErr.message }, 502);
  if (reserved !== true) {
    return json(
      { error: "daily categorize limit reached", code: "rate_limited", limit: DAILY_LIMIT },
      429,
    );
  }

  let result: CategorizeResult;
  try {
    result = await categorizeNames(
      { items, merchants, categories },
      Deno.env.get("GOOGLE_AI_API_KEY"),
    );
  } catch (e) {
    // Give the reserved slot back — a failed classification must not cost quota.
    const { error: refundErr } = await client.rpc("refund_categorize");
    if (refundErr) console.error("refund_categorize failed:", refundErr.message);
    return json({ error: e instanceof Error ? e.message : String(e) }, 502);
  }

  return json(result);
});

// Distinct, trimmed, non-empty strings from an untrusted array.
function strings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out = new Set<string>();
  for (const v of value) {
    if (typeof v === "string") {
      const t = v.trim();
      if (t) out.add(t);
    }
  }
  return [...out];
}

function categoryOptions(value: unknown): CategoryOption[] {
  if (!Array.isArray(value)) return [];
  const out: CategoryOption[] = [];
  for (const v of value) {
    if (typeof v !== "object" || v === null) continue;
    const r = v as Record<string, unknown>;
    const key = typeof r.key === "string" ? r.key.trim() : "";
    if (!key) continue;
    const label = typeof r.label === "string" ? r.label.trim() : key;
    out.push({ key, label });
  }
  return out;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
