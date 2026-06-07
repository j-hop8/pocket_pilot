// Supabase clients. `admin` uses the service-role key (bypasses RLS) to read the
// Vault password via get_carrier_secret and to write invoices / status — exactly
// the privilege the old Edge Function ran with.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import ws from "ws";
import { config } from "./config";

// supabase-js constructs a RealtimeClient at createClient() time, which needs a
// WebSocket. Node <22 has no native WebSocket, so supply the `ws` implementation.
// (This server never opens a realtime channel; it just keeps the constructor happy.)
const realtime = { transport: ws as unknown as typeof WebSocket };

export const admin: SupabaseClient = createClient(
  config.supabaseUrl,
  config.serviceRoleKey,
  { auth: { persistSession: false, autoRefreshToken: false }, realtime },
);

/// A client scoped to a user's access token — used only to resolve the user id
/// from their JWT (mirrors the Edge Function's userIdFromJwt). It carries no
/// service-role privilege.
export function clientForToken(token: string): SupabaseClient {
  return createClient(config.supabaseUrl, config.anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
    realtime,
  });
}
