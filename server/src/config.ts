// Central env config. Throws on startup if a required secret is missing so we
// fail fast rather than mid-sync. (The spike script reads env directly and does
// NOT import this, so it can run with only PHONE/PASSWORD set.)

function required(name: string): string {
  const v = process.env[name];
  if (!v || v.trim() === "") {
    throw new Error(`Missing required env var ${name}`);
  }
  return v;
}

function optionalInt(name: string, fallback: number): number {
  const v = process.env[name];
  if (!v) return fallback;
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

export const config = {
  port: optionalInt("PORT", 8080),

  supabaseUrl: required("SUPABASE_URL"),
  anonKey: required("SUPABASE_ANON_KEY"),
  serviceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
  // Session-mode connection string for pg-boss (LISTEN/NOTIFY + advisory locks).
  dbUrl: required("SUPABASE_DB_URL"),

  // Scraper
  headless: process.env.HEADLESS !== "false",
  proxyUrl: process.env.PROXY_URL || undefined,

  // Queue / scheduler
  syncConcurrency: optionalInt("SYNC_CONCURRENCY", 2),
  schedulerIntervalMs: optionalInt("SCHEDULER_INTERVAL_MS", 60_000),
} as const;
