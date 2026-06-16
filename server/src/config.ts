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
  // Hard deadline for a whole sync job (scrape + ingest). Large accounts with
  // many pages legitimately need more than the original 5 min.
  syncJobExpireSeconds: optionalInt("SYNC_JOB_EXPIRE_SECONDS", 600),

  // Rate limiting
  // Minimum gap between manual /sync/now requests for the same user (429 below).
  syncCooldownSeconds: optionalInt("SYNC_COOLDOWN_SECONDS", 60),
  // Minimum gap between portal logins across ALL users (politeness / anti-bot).
  portalMinGapMs: optionalInt("PORTAL_MIN_GAP_MS", 3_000),
  // Generic per-IP HTTP ceiling (@fastify/rate-limit).
  httpRateMax: optionalInt("HTTP_RATE_MAX", 60),
  httpRateWindowMs: optionalInt("HTTP_RATE_WINDOW_MS", 60_000),

  // Sync window (incremental date-range scrape)
  // Re-fetch this many days before the last successful sync (dedupe makes the
  // overlap a safe no-op; covers late-arriving invoices).
  syncOverlapDays: optionalInt("SYNC_OVERLAP_DAYS", 3),
  // First-ever sync (no last_synced_at) looks back this many days.
  syncLookbackDays: optionalInt("SYNC_LOOKBACK_DAYS", 60),
} as const;
