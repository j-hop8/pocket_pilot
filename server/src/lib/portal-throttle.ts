// A process-wide gap throttle used to space out logins to the MOF gov portal,
// so concurrent syncs don't hammer it (politeness / anti-bot). Reserving the
// next slot up front means it spaces successive acquisitions by `gapMs` even
// when several workers call it at once.
//
// Kept config-free (a plain factory) so it stays unit-testable without env; the
// process singleton is built in sync.ts where `config` is already imported.

export function createGapThrottle(gapMs: number): () => Promise<void> {
  let nextAllowedAt = 0;
  return async function acquire(): Promise<void> {
    const now = Date.now();
    const startAt = Math.max(now, nextAllowedAt);
    nextAllowedAt = startAt + gapMs;
    const wait = startAt - now;
    if (wait > 0) await delay(wait);
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
