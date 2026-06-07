// Replaces pg_cron. On an interval, scans carrier_config for users whose
// scheduled sync is due and enqueues one job each. The same predicate the Edge
// Function used (dueUserIds), but feeding a concurrency-limited queue instead of
// a single sequential invocation.
//
// NOTE: assumes a single backend instance. If you scale to multiple instances,
// move this to a leader/locked job so ticks don't overlap (singletonKey already
// prevents duplicate per-user jobs, but the scan would run N times).

import { admin } from "./supabase";
import { config } from "./config";
import { enqueueSync } from "./queue";

interface DueRow {
  user_id: string;
  sync_interval_minutes: number;
  last_sync_attempt_at: string | null;
  password_secret_id: string | null;
}

export function startScheduler(): void {
  setInterval(tick, config.schedulerIntervalMs);
  setTimeout(tick, 10_000); // first scan shortly after boot
  console.log(`[scheduler] scanning every ${config.schedulerIntervalMs}ms`);
}

async function tick(): Promise<void> {
  try {
    const ids = await dueUserIds();
    if (ids.length) console.log(`[scheduler] enqueueing ${ids.length} due user(s)`);
    for (const id of ids) await enqueueSync(id);
  } catch (e) {
    console.error("[scheduler] tick failed:", (e as Error).message);
  }
}

/// Users whose scheduled sync is due (enabled, credentials stored, interval up).
async function dueUserIds(): Promise<string[]> {
  const { data, error } = await admin
    .from("carrier_config")
    .select("user_id, sync_interval_minutes, last_sync_attempt_at, password_secret_id")
    .eq("auto_sync_enabled", true)
    .not("password_secret_id", "is", null);
  if (error) throw error;
  const now = Date.now();
  return ((data ?? []) as DueRow[])
    .filter((c) => {
      if (!c.last_sync_attempt_at) return true;
      const elapsed = now - new Date(c.last_sync_attempt_at).getTime();
      return elapsed >= c.sync_interval_minutes * 60_000;
    })
    .map((c) => c.user_id);
}
