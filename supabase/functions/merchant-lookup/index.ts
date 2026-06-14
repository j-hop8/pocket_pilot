// merchant-lookup Edge Function.
//
// The e-invoice QR carries the seller's 統一編號 but not the merchant name, and
// the official GCIS registry API has no CORS headers — so the Flutter web client
// can't call it from the browser. This function proxies the lookup server-side
// (no CORS limit) and returns the name with CORS headers so web works too.
//
// POST { taxId } → { name: string | null }. Gateway JWT verification is left on
// (the app always invokes with the user's session JWT), so only signed-in
// callers reach it. Best-effort: any failure resolves to { name: null }.

import { lookupMerchantName } from "../_shared/merchant_lookup.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  let taxId: string | null = null;
  try {
    const body = await req.json();
    if (body && typeof body.taxId === "string") taxId = body.taxId;
  } catch {
    taxId = null; // missing / malformed body → just a miss
  }

  const name = await lookupMerchantName(taxId);
  return new Response(JSON.stringify({ name }), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
