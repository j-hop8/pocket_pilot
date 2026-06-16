// Per-user cooldown for manual /sync/now. Keeps a user from spamming the button
// (each tap hits Supabase auth, flips status, and re-logs into the gov portal).
// pg-boss's singletonKey already prevents *duplicate jobs*; this adds a polite
// minimum gap and a clear 429 the client can act on. Pure + side-effect free so
// it's trivially testable.

export interface SyncState {
  /// carrier_config.last_sync_status — 'ok' | 'error' | 'running' | null.
  status: string | null;
  /// carrier_config.last_sync_attempt_at as ms since epoch, or null if never.
  attemptAtMs: number | null;
}

export type SyncThrottleDecision =
  | { allowed: true }
  | { allowed: false; reason: string; retryAfterSec: number };

/// Decides whether a manual sync may start now.
/// - A sync still "running" within `runningTtlMs` (the job-expiry window) blocks,
///   so a crashed job that left status='running' eventually frees up.
/// - Otherwise an attempt within `cooldownMs` blocks (too soon since the last).
export function syncThrottleDecision(
  state: SyncState,
  nowMs: number,
  cooldownMs: number,
  runningTtlMs: number,
): SyncThrottleDecision {
  const { status, attemptAtMs } = state;
  if (attemptAtMs == null) return { allowed: true };
  const elapsed = nowMs - attemptAtMs;

  if (status === "running" && elapsed < runningTtlMs) {
    return {
      allowed: false,
      reason: "a sync is already running",
      retryAfterSec: retryAfter(runningTtlMs - elapsed),
    };
  }

  if (elapsed < cooldownMs) {
    return {
      allowed: false,
      reason: "synced too recently",
      retryAfterSec: retryAfter(cooldownMs - elapsed),
    };
  }

  return { allowed: true };
}

function retryAfter(remainingMs: number): number {
  return Math.max(1, Math.ceil(remainingMs / 1000));
}
