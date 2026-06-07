// carrier-sync Edge Function.
//
// Two trigger modes, one ingestion path:
//   • User "Sync now": the Flutter app calls supabase.functions.invoke('carrier-sync')
//     with the user's JWT → sync that single user.
//   • Scheduled: pg_cron posts here hourly with the `x-cron-secret` header →
//     sync every user whose auto_sync_enabled is on and whose interval elapsed.
//
// For each user: read phone + decrypt the Vault password (service role), drive a
// remote headless browser to download the 消費明細 CSV, then ingest it. Per-user
// status is written back to carrier_config so the app can surface failures.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ingestCsv, type SyncResult } from "../_shared/ingest.ts";
import { downloadCarrierCsv } from "../_shared/scrape.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  try {
    const cronSecret = req.headers.get("x-cron-secret");

    // ── Scheduled (cron) mode ────────────────────────────────────────────────
    if (cronSecret) {
      if (!CRON_SECRET || cronSecret !== CRON_SECRET) {
        return json({ error: "forbidden" }, 403);
      }
      const userIds = await dueUserIds(admin);
      let totalInserted = 0;
      const errors: string[] = [];
      for (const uid of userIds) {
        try {
          totalInserted += (await syncUser(admin, uid)).inserted;
        } catch (e) {
          errors.push(`${uid}: ${(e as Error).message}`);
        }
      }
      return json({ users: userIds.length, inserted: totalInserted, errors });
    }

    // ── User "Sync now" mode ─────────────────────────────────────────────────
    const userId = await userIdFromJwt(req);
    if (!userId) return json({ error: "unauthorized" }, 401);

    const result = await syncUser(admin, userId);
    return json(result);
  } catch (e) {
    console.error("carrier-sync error:", (e as Error).message, (e as Error).stack);
    return json({ error: (e as Error).message }, 500);
  }
});

/// Reads the JWT from the Authorization header and returns its user id (or null).
async function userIdFromJwt(req: Request): Promise<string | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return null;
  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}

/// Users whose scheduled sync is due (enabled, credentials stored, interval up).
async function dueUserIds(admin: SupabaseClient): Promise<string[]> {
  const { data, error } = await admin
    .from("carrier_config")
    .select("user_id, sync_interval_minutes, last_sync_attempt_at, password_secret_id")
    .eq("auto_sync_enabled", true)
    .not("password_secret_id", "is", null);
  if (error) throw error;
  const now = Date.now();
  return (data ?? [])
    .filter((c) => {
      if (!c.last_sync_attempt_at) return true;
      const elapsed = now - new Date(c.last_sync_attempt_at as string).getTime();
      return elapsed >= (c.sync_interval_minutes as number) * 60_000;
    })
    .map((c) => c.user_id as string);
}

/// Full sync for one user: status running → scrape → ingest → status ok/error.
async function syncUser(admin: SupabaseClient, userId: string): Promise<SyncResult> {
  await setStatus(admin, userId, "running", null);
  try {
    const { data: cfg, error } = await admin
      .from("carrier_config")
      .select("phone")
      .eq("user_id", userId)
      .single();
    if (error) throw error;
    const phone = (cfg?.phone as string | null) ?? "";

    const { data: password, error: secErr } = await admin.rpc("get_carrier_secret", {
      p_user_id: userId,
    });
    if (secErr) throw secErr;
    if (!phone || !password) {
      throw new Error("carrier credentials are not set");
    }

    const csv = await downloadCarrierCsv({ phone, password: password as string });
    const result = await ingestCsv(admin, userId, csv);

    const now = new Date().toISOString();
    await admin
      .from("carrier_config")
      .update({
        last_synced_at: now,
        last_sync_count: result.inserted,
        last_sync_status: "ok",
        last_sync_error: null,
        last_sync_attempt_at: now,
        updated_at: now,
      })
      .eq("user_id", userId);

    return result;
  } catch (e) {
    await setStatus(admin, userId, "error", (e as Error).message);
    throw e;
  }
}

async function setStatus(
  admin: SupabaseClient,
  userId: string,
  status: string,
  error: string | null,
): Promise<void> {
  await admin
    .from("carrier_config")
    .update({
      last_sync_status: status,
      last_sync_error: error,
      last_sync_attempt_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
